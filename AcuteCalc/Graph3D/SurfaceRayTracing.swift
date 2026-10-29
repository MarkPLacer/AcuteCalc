import AcuteCore
import Metal
import os
import QuartzCore

/// Hardware ray-traced shadows and reflections for height fields z = f(x, y).
///
/// Only on GPUs with the ray tracing unit (Apple9 and later: A17 Pro, M3, M4, M5) that can trace rays
/// from fragment functions (`supportsRaytracingFromRender`); elsewhere, including the simulator, the
/// surface is shaded without them. The triangle mesh is evaluated on the CPU (the shader evaluates the
/// display mesh itself) and built into a primitive acceleration structure with a Metal 3 acceleration
/// structure encoder on its own queue. Two structures of the maximum size alternate; a build writes the
/// inactive one only after the GPU has completed every frame that read it (`RenderBackend.completedFrame`),
/// and both are made resident once.
@MainActor
final class SurfaceRayTracing {
    nonisolated static let resolution = 96

    let structures: [MTLAccelerationStructure]
    private let device: MTLDevice
    private let queue: MTLCommandQueue
    private let scratch: MTLBuffer
    private let maxTriangles: Int
    private var active: Int?
    private var building = false
    private var builtSignature: Signature?
    private var pendingSignature: Signature?
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
        let n = Self.resolution
        maxTriangles = (n - 1) * (n - 1) * 2
        // Size for the full mesh; smaller meshes build into the same structures.
        let descriptor = Self.descriptor(vertices: nil, indices: nil, triangles: maxTriangles, vertexCount: n * n)
        let sizes = device.accelerationStructureSizes(descriptor: descriptor)
        guard let a = device.makeAccelerationStructure(size: sizes.accelerationStructureSize),
              let b = device.makeAccelerationStructure(size: sizes.accelerationStructureSize),
              let scratch = device.makeBuffer(length: max(sizes.buildScratchBufferSize, 16), options: .storageModePrivate) else { return nil }
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
    }

    /// Rebuilds the structure when the surface changed; `redraw` runs once a new one is ready.
    func update(model: SurfaceModel, backend: RenderBackend, redraw: @escaping @MainActor () -> Void) {
        guard model.kind == .heightField, let program = model.program else {
            pendingSignature = nil
            return
        }
        let signature = Signature(instructions: program.instructions, parameters: model.parameterNames.map { model.parameters[$0] ?? 0 },
                                  domain: model.domain, zRange: model.zRange, zScale: model.zScale)
        pendingSignature = signature
        guard signature != builtSignature, !building else { return }
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
        let maxTriangles = self.maxTriangles
        Task.detached(priority: .userInitiated) {
            let (positions, indices) = Self.mesh(signature, program: program, maxTriangles: maxTriangles)
            await self.encode(signature, positions: positions, indices: indices, redraw: redraw)
        }
    }

    /// The triangle mesh in world coordinates and the triangles inside the box.
    nonisolated private static func mesh(_ signature: Signature, program: Program, maxTriangles: Int) -> ([Float], [UInt32]) {
        let n = Self.resolution
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
        indices.reserveCapacity(maxTriangles * 3)
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
        let n = Self.resolution
        let target = active.map { 1 - $0 } ?? 0
        guard !indices.isEmpty,
              let vertexBuffer = device.makeBuffer(bytes: positions, length: positions.count * MemoryLayout<Float>.stride, options: .storageModeShared),
              let indexBuffer = device.makeBuffer(bytes: indices, length: indices.count * MemoryLayout<UInt32>.stride, options: .storageModeShared),
              let commandBuffer = queue.makeCommandBuffer(),
              let encoder = commandBuffer.makeAccelerationStructureCommandEncoder() else {
            building = false
            builtSignature = nil
            active = nil
            return
        }
        let descriptor = Self.descriptor(vertices: vertexBuffer, indices: indexBuffer, triangles: indices.count / 3, vertexCount: n * n)
        encoder.build(accelerationStructure: structures[target], descriptor: descriptor, scratchBuffer: scratch, scratchBufferOffset: 0)
        encoder.endEncoding()
        let log = self.log
        commandBuffer.addCompletedHandler { [weak self] buffer in
            let failed = buffer.status != .completed
            if failed { log.error("Acceleration structure build failed: \(buffer.error?.localizedDescription ?? "unknown", privacy: .public)") }
            Task { @MainActor in
                guard let self else { return }
                self.building = false
                if !failed {
                    self.active = target
                    self.builtSignature = signature
                }
                redraw()
            }
        }
        commandBuffer.commit()
    }
}
