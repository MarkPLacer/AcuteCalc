import AcuteCore
import Metal
import os
import QuartzCore

/// Hardware ray-traced shadows and reflections for height fields z = f(x, y).
///
/// Only on GPUs with the ray tracing unit (Apple9 and later: A17 Pro, M3, M4, M5) that can trace rays
/// from fragment functions (`supportsRaytracingFromRender`); elsewhere, including the simulator, the
/// surface is shaded without them. The triangle mesh is evaluated on the CPU on the grid the surface is drawn
/// with (the shader evaluates the display mesh itself), so shadow and mirror rays start on the traced
/// triangles, and built into a primitive acceleration structure with a Metal 3 acceleration structure encoder
/// on its own queue. Two structures of the maximum size alternate; a build writes the inactive one only
/// after the GPU has completed every frame that read it (`RenderBackend.completedFrame`).
/// The structures and the buffers they are built from are allocated once; only the structures are resident,
/// because a built structure keeps no reference to its vertex and index buffers (see `vertexBuffers`).
@MainActor
final class SurfaceRayTracing {
    /// The finest grid Nastavitve › Ločljivost 3D ploskev offers (SettingsView.surfaceResolutions): the
    /// structures and buffers are sized for it once, and coarser grids build into the same ones.
    nonisolated static let maxResolution = 320

    let structures: [MTLAccelerationStructure]
    /// Upload buffers for the mesh of each structure, reused by every build. Only the build reads them, on
    /// its own Metal 3 command buffer; traced frames never do. A built structure "contains references to
    /// any other acceleration structures referenced by the descriptor, but not any other underlying buffer
    /// data" (MTLAccelerationStructureCommandEncoder, build(accelerationStructure:descriptor:…)), and the
    /// Metal 4 build "doesn't retain any references to the input buffers of the descriptor, such as the
    /// vertex buffer" (MTL4ComputeCommandEncoder, build(destinationAccelerationStructure:descriptor:…)).
    private let vertexBuffers: [MTLBuffer]
    private let indexBuffers: [MTLBuffer]
    /// What a traced frame reads: the structures alone (Metal 4 residency set). Metal 3 binds the current one
    /// to the fragment stage, which needs no `useResources` (MTLRenderCommandEncoder useResources(_:usage:stages:)).
    var resources: [MTLResource] { structures.map { $0 as MTLResource } }
    private let device: MTLDevice
    private let queue: MTLCommandQueue
    private let scratch: MTLBuffer
    private var active: Int?
    private var building = false
    private var builtSignature: Signature?
    private var pendingSignature: Signature?
    /// A surface whose build failed, how often in a row, and whether its delayed retry is still to come.
    private var failure: Failure?
    /// Per structure, the last frame that traced against it.
    private var lastUse: [UInt64] = [0, 0]
    private let log = Logger(subsystem: "com.markplacer.acutecalc", category: "Metal")

    /// The structure to trace against: the last one built for a height field. While a slider moves
    /// it may lag the surface by one build (a few milliseconds), which keeps the shadows steady.
    var current: MTLAccelerationStructure? {
        guard let active, pendingSignature != nil, builtSignature != nil else { return nil }
        return structures[active]
    }

    /// Records that `frame` traces against the current structure.
    func noteUse(frame: UInt64) {
        if let active { lastUse[active] = frame }
    }

    static func isSupported(_ device: MTLDevice) -> Bool {
        device.supportsRaytracing && device.supportsRaytracingFromRender && device.supportsFamily(.apple9)
    }

    init?(device: MTLDevice) {
        guard Self.isSupported(device), let queue = device.makeCommandQueue() else { return nil }
        let n = Self.maxResolution
        let maxTriangles = (n - 1) * (n - 1) * 2
        // Size for the finest mesh; coarser meshes build into the same structures.
        let descriptor = Self.descriptor(vertices: nil, indices: nil, triangles: maxTriangles, vertexCount: n * n)
        let sizes = device.accelerationStructureSizes(descriptor: descriptor)
        guard let a = device.makeAccelerationStructure(size: sizes.accelerationStructureSize),
              let b = device.makeAccelerationStructure(size: sizes.accelerationStructureSize),
              let scratch = device.makeBuffer(length: max(sizes.buildScratchBufferSize, 16), options: .storageModePrivate) else { return nil }
        var vertexBuffers: [MTLBuffer] = [], indexBuffers: [MTLBuffer] = []
        for _ in 0..<2 {
            guard let vertices = device.makeBuffer(length: n * n * 3 * MemoryLayout<Float>.stride, options: .storageModeShared),
                  let indices = device.makeBuffer(length: (n - 1) * (n - 1) * 2 * 3 * MemoryLayout<UInt32>.stride, options: .storageModeShared) else { return nil }
            vertexBuffers.append(vertices)
            indexBuffers.append(indices)
        }
        self.vertexBuffers = vertexBuffers
        self.indexBuffers = indexBuffers
        a.label = "Surface BVH A"
        b.label = "Surface BVH B"
        queue.label = "Surface BVH builds"
        self.device = device
        self.queue = queue
        self.scratch = scratch
        self.structures = [a, b]
    }

    private static func descriptor(vertices: MTLBuffer?, indices: MTLBuffer?, triangles: Int, vertexCount: Int) -> MTLPrimitiveAccelerationStructureDescriptor {
        let geometry = MTLAccelerationStructureTriangleGeometryDescriptor()
        geometry.vertexBuffer = vertices
        geometry.vertexFormat = .float3
        geometry.vertexStride = MemoryLayout<Float>.stride * 3
        geometry.indexBuffer = indices
        geometry.indexType = .uint32
        geometry.triangleCount = triangles
        geometry.opaque = true
        let descriptor = MTLPrimitiveAccelerationStructureDescriptor()
        descriptor.geometryDescriptors = [geometry]
        return descriptor
    }

    struct Signature: Equatable, Sendable {
        var instructions: [Instruction]
        var parameters: [Double]
        var domain: SIMD4<Double>
        var zRange: SIMD2<Double>
        var zScale: Double
        /// The grid of n × n vertices the surface is drawn with (SurfaceEncoder.gridResolution).
        var resolution: Int
    }

    private struct Failure {
        let signature: Signature
        let count: Int
        var waiting: Bool
    }

    /// Rebuilds the structure when the surface changed; `redraw` runs once a new one is ready.
    func update(model: SurfaceModel, backend: RenderBackend, redraw: @escaping @MainActor () -> Void) {
        guard model.kind == .heightField, let program = model.program else {
            pendingSignature = nil
            return
        }
        // Trace the drawn grid: on a coarser one, rays could start under the traced triangles (false shadows
        // and mirror hits). The settings offer no grid finer than the structures hold.
        let resolution = min(SurfaceEncoder.gridResolution(model), Self.maxResolution)
        let signature = Signature(instructions: program.instructions, parameters: model.parameterNames.map { model.parameters[$0] ?? 0 },
                                  domain: model.domain, zRange: model.zRange, zScale: model.zScale, resolution: resolution)
        pendingSignature = signature
        guard signature != builtSignature, !building else { return }
        // A failed build is tried again by its delayed retry (`buildFailed`), not by the next redraw.
        if let failure, failure.signature == signature, failure.waiting { return }
        // The inactive structure may still be read by frames in flight: wait until the GPU completed them.
        let target = active.map { 1 - $0 } ?? 0
        guard backend.completedFrame >= lastUse[target] else {
            Task { @MainActor [weak self, weak backend] in
                try? await Task.sleep(for: .milliseconds(8))
                guard let backend else { return }
                self?.update(model: model, backend: backend, redraw: redraw)
            }
            return
        }
        build(signature, program: program, redraw: redraw)
    }

    /// Samples the height field off the main thread, then builds on the main actor.
    private func build(_ signature: Signature, program: Program, redraw: @escaping @MainActor () -> Void) {
        building = true
        Task.detached(priority: .userInitiated) {
            let (positions, indices) = Self.mesh(signature, program: program)
            await self.encode(signature, positions: positions, indices: indices, redraw: redraw)
        }
    }

    /// The triangle mesh in world coordinates on the signature's grid and the triangles inside the box.
    nonisolated static func mesh(_ signature: Signature, program: Program) -> ([Float], [UInt32]) {
        let n = signature.resolution
        let vm = RealVM(program: program, parameters: signature.parameters)
        let d = signature.domain
        let zHalf = max((signature.zRange.y - signature.zRange.x) / 2, 1e-6)
        let zMid = (signature.zRange.y + signature.zRange.x) / 2
        let h = signature.zScale
        // World coordinates exactly as surface_vertex maps them: x → X, z → Y (up), y → −Z.
        var positions = [Float](repeating: 0, count: n * n * 3)
        var inside = [Bool](repeating: false, count: n * n)
        for j in 0..<n {
            for i in 0..<n {
                let u = Double(i) / Double(n - 1), v = Double(j) / Double(n - 1)
                let z = vm.evaluate(x: d.x + (d.y - d.x) * u, y: d.z + (d.w - d.z) * v)
                let Y = (z - zMid) / zHalf * h
                let k = j * n + i
                positions[3 * k] = Float(u * 2 - 1)
                positions[3 * k + 1] = Y.isFinite ? Float(Y) : 0
                positions[3 * k + 2] = Float(-(v * 2 - 1))
                // The fragment shader clips the surface to the box; clipped parts cast no shadow.
                inside[k] = Y.isFinite && abs(Y) <= h
            }
        }
        var indices: [UInt32] = []
        indices.reserveCapacity((n - 1) * (n - 1) * 6)
        for j in 0..<(n - 1) {
            for i in 0..<(n - 1) {
                let a = j * n + i, b = a + 1, c = a + n, e = c + 1
                if inside[a] && inside[b] && inside[c] { indices += [UInt32(a), UInt32(b), UInt32(c)] }
                if inside[b] && inside[e] && inside[c] { indices += [UInt32(b), UInt32(e), UInt32(c)] }
            }
        }
        return (positions, indices)
    }

    private func encode(_ signature: Signature, positions: [Float], indices: [UInt32], redraw: @escaping @MainActor () -> Void) {
        let n = signature.resolution
        let target = active.map { 1 - $0 } ?? 0
        let vertexBuffer = vertexBuffers[target], indexBuffer = indexBuffers[target]
        // Builds run one at a time (`building`) and no frame reads the upload buffers; no frame in flight
        // reads the target structure (see `update`).
        positions.withUnsafeBytes { vertexBuffer.contents().copyMemory(from: $0.baseAddress!, byteCount: $0.count) }
        indices.withUnsafeBytes { if let base = $0.baseAddress { indexBuffer.contents().copyMemory(from: base, byteCount: $0.count) } }
        guard !indices.isEmpty else {
            building = false
            // Handled: nothing to trace for this surface (no rebuild until it changes).
            builtSignature = signature
            active = nil
            redraw()
            return
        }
        guard let commandBuffer = queue.makeCommandBuffer(),
              let encoder = commandBuffer.makeAccelerationStructureCommandEncoder() else {
            building = false
            buildFailed(signature, "Acceleration structure build not encoded: no command buffer or encoder", redraw: redraw)
            return
        }
        let descriptor = Self.descriptor(vertices: vertexBuffer, indices: indexBuffer, triangles: indices.count / 3, vertexCount: n * n)
        encoder.build(accelerationStructure: structures[target], descriptor: descriptor, scratchBuffer: scratch, scratchBufferOffset: 0)
        encoder.endEncoding()
        commandBuffer.addCompletedHandler { [weak self] buffer in
            let failed = buffer.status != .completed
            let error = buffer.error as NSError?
            // Nastavitve shows it (GPUDiagnostics). Once the system has revoked the app's GPU access, ray tracing
            // stays off until the app restarts.
            if failed, let error { GPUDiagnostics.report(error, stopsRayTracing: Self.isAccessRevoked(error)) }
            // Committed as the app moved to the background: not counted, and no retry until a frame, drawn once
            // the app is active again, builds it (Preparing your Metal app to run in the background).
            let notPermitted = error.map { GPUDiagnostics.isNotPermitted($0) } ?? false
            let message = "Acceleration structure build failed (\(error?.domain ?? "no domain") \(error?.code ?? 0)): \(error?.localizedDescription ?? "unknown error")"
            Task { @MainActor in
                guard let self else { return }
                self.building = false
                if !failed {
                    self.failure = nil
                    self.active = target
                    self.builtSignature = signature
                    redraw()
                } else if !notPermitted {
                    self.buildFailed(signature, message, redraw: redraw)
                }
            }
        }
        commandBuffer.commit()
    }

    /// A build of `signature` failed. Nothing visible changed, so there is no redraw, and the next one does not
    /// build it again: a delayed retry does, after 0.25, 0.5 and 1 s (`retryDelay`). After that the surface is
    /// drawn without ray tracing until it changes. Only its first failure is logged.
    private func buildFailed(_ signature: Signature, _ message: String, redraw: @escaping @MainActor () -> Void) {
        var count = 1
        if let failure, failure.signature == signature { count = failure.count + 1 }
        if count == 1 { log.error("\(message, privacy: .public)") }
        guard let delay = Self.retryDelay(afterFailures: count) else {
            // Given up, like a surface with nothing to trace: no rebuild until the surface changes. Without
            // `active`, `current` is nil, so frames stop tracing the structure of an earlier surface.
            failure = nil
            builtSignature = signature
            if active != nil {
                active = nil
                redraw()
            }
            return
        }
        failure = Failure(signature: signature, count: count, waiting: true)
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: delay)
            guard let self, self.failure?.signature == signature else { return }
            self.failure?.waiting = false
            // The frame this asks for builds it again (`update`).
            redraw()
        }
    }

    /// The wait before trying a failed build again after its `failures`-th failure in a row, or nil once the
    /// three retries are used up (a failure that persists would otherwise rebuild on every frame).
    nonisolated static func retryDelay(afterFailures failures: Int) -> Duration? {
        let delays: [Duration] = [.milliseconds(250), .milliseconds(500), .seconds(1)]
        return delays.indices.contains(failures - 1) ? delays[failures - 1] : nil
    }

    /// Whether the system has revoked the app's GPU access for causing too many timeouts or hangs.
    nonisolated private static func isAccessRevoked(_ error: NSError) -> Bool {
        error.domain == MTLCommandBufferError.errorDomain && error.code == Int(MTLCommandBufferError.accessRevoked.rawValue)
    }
}
