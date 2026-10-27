import Metal
import MetalKit
import OSLog

/// Which Metal API generation renders the graphs.
enum RendererBackendKind: String, CaseIterable, Identifiable, Codable {
    case metal4
    case metal3

    var id: String { rawValue }

    var title: String {
        switch self {
        case .metal4: "Metal 4"
        case .metal3: "Metal 3 (združljivost)"
        }
    }
}

/// Description of a render pipeline; both backends compile from the same functions.
nonisolated struct PipelineSpec: Hashable, Sendable {
    var vertex: String
    var fragment: String
    var blending = true
    var sampleCount = 1
    var depth = false
    var colorFormat: MTLPixelFormat = .bgra8Unorm

    /// Pipeline name in Metal debugger.
    var label: String {
        var name = "\(vertex) \(fragment)"
        if blending { name += " blended" }
        if sampleCount > 1 { name += " \(sampleCount)x" }
        return name
    }
}

/// Shared device, shader library and pipeline cache.
final class MetalContext {
    static let shared = MetalContext()

    let device: MTLDevice?
    let library: MTLLibrary?
    let supportsMetal4: Bool
    #if !targetEnvironment(simulator)
    private var compiler: MTL4Compiler?
    #endif
    private var metal4Pipelines: [PipelineSpec: MTLRenderPipelineState] = [:]
    private var classicPipelines: [PipelineSpec: MTLRenderPipelineState] = [:]
    private var depthStates: [Bool: MTLDepthStencilState] = [:]
    /// Backends whose known pipelines are compiled (or being compiled) in the background.
    private var warmedUp: Set<RendererBackendKind> = []
    private let log = Logger(subsystem: "com.markplacer.acutecalc", category: "Metal")

    private init() {
        let device = MTLCreateSystemDefaultDevice()
        self.device = device
        self.library = device?.makeDefaultLibrary()
        #if targetEnvironment(simulator)
        // The simulator SDK has no Metal 4 API; the Metal 3 backend draws there.
        self.supportsMetal4 = false
        #else
        var compiler: MTL4Compiler?
        var compilerError: (any Error)?
        if let device, device.supportsFamily(.metal4) {
            do {
                compiler = try device.makeCompiler(descriptor: MTL4CompilerDescriptor())
            } catch {
                compilerError = error
            }
        }
        self.compiler = compiler
        // Without a compiler no Metal 4 pipeline can be built: the Metal 3 backend draws instead.
        self.supportsMetal4 = compiler != nil
        if let compilerError {
            log.error("Metal 4 compiler failed: \(compilerError.localizedDescription, privacy: .public)")
        }
        #endif
    }

    func pipeline(_ spec: PipelineSpec, backend: RendererBackendKind) -> MTLRenderPipelineState? {
        switch backend {
        case .metal4:
            #if targetEnvironment(simulator)
            return nil
            #else
            if let cached = metal4Pipelines[spec] { return cached }
            guard let compiler, let library else { return nil }
            let descriptor = MetalContext.metal4Descriptor(for: spec, library: library)
            do {
                let state = try Signposts.interval("Compile pipeline") {
                    try compiler.makeRenderPipelineState(descriptor: descriptor)
                }
                metal4Pipelines[spec] = state
                return state
            } catch {
                log.error("Metal 4 pipeline \(spec.fragment, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
                return nil
            }
            #endif
        case .metal3:
            if let cached = classicPipelines[spec] { return cached }
            guard let device, let library else { return nil }
            let descriptor = MetalContext.classicDescriptor(for: spec, library: library)
            do {
                let state = try Signposts.interval("Compile pipeline") {
                    try device.makeRenderPipelineState(descriptor: descriptor)
                }
                classicPipelines[spec] = state
                return state
            } catch {
                log.error("Metal pipeline \(spec.fragment, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
                return nil
            }
        }
    }

    #if !targetEnvironment(simulator)
    /// Built from Sendable values only, so the background warm-up can hand it to the compiler.
    nonisolated private static func metal4Descriptor(for spec: PipelineSpec, library: MTLLibrary) -> MTL4RenderPipelineDescriptor {
        let descriptor = MTL4RenderPipelineDescriptor()
        descriptor.label = spec.label
        let vertex = MTL4LibraryFunctionDescriptor()
        vertex.library = library
        vertex.name = spec.vertex
        let fragment = MTL4LibraryFunctionDescriptor()
        fragment.library = library
        fragment.name = spec.fragment
        descriptor.vertexFunctionDescriptor = vertex
        descriptor.fragmentFunctionDescriptor = fragment
        descriptor.rasterSampleCount = spec.sampleCount
        let attachment = descriptor.colorAttachments[0]
        attachment?.pixelFormat = spec.colorFormat
        if spec.blending {
            attachment?.blendingState = .enabled
            attachment?.rgbBlendOperation = .add
            attachment?.alphaBlendOperation = .add
            attachment?.sourceRGBBlendFactor = .one
            attachment?.sourceAlphaBlendFactor = .one
            attachment?.destinationRGBBlendFactor = .oneMinusSourceAlpha
            attachment?.destinationAlphaBlendFactor = .oneMinusSourceAlpha
        } else {
            attachment?.blendingState = .disabled
        }
        return descriptor
    }
    #endif

    /// Built from Sendable values only, so the background warm-up can hand it to Metal.
    nonisolated private static func classicDescriptor(for spec: PipelineSpec, library: MTLLibrary) -> MTLRenderPipelineDescriptor {
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.label = spec.label
        descriptor.vertexFunction = library.makeFunction(name: spec.vertex)
        descriptor.fragmentFunction = library.makeFunction(name: spec.fragment)
        descriptor.rasterSampleCount = spec.sampleCount
        if spec.depth { descriptor.depthAttachmentPixelFormat = .depth32Float }
        let attachment = descriptor.colorAttachments[0]
        attachment?.pixelFormat = spec.colorFormat
        if spec.blending {
            attachment?.isBlendingEnabled = true
            attachment?.rgbBlendOperation = .add
            attachment?.alphaBlendOperation = .add
            attachment?.sourceRGBBlendFactor = .one
            attachment?.sourceAlphaBlendFactor = .one
            attachment?.destinationRGBBlendFactor = .oneMinusSourceAlpha
            attachment?.destinationAlphaBlendFactor = .oneMinusSourceAlpha
        }
        return descriptor
    }

    // MARK: Warm-up

    /// The pipelines the views request: the 2D graph, the 3D surface (4× MSAA, depth) and the
    /// complex plot. The big bytecode interpreters come first; a view's first frame compiles what
    /// it needs itself, so the warm-up usually finds those already cached.
    static let knownPipelines: [PipelineSpec] = [
        PipelineSpec(vertex: "grid_vertex", fragment: "implicit_fragment"),
        PipelineSpec(vertex: "surface_vertex", fragment: "surface_fragment", blending: false, sampleCount: 4, depth: true),
        PipelineSpec(vertex: "complex_vertex", fragment: "complex_fragment", blending: false),
        PipelineSpec(vertex: "axis_vertex", fragment: "axis_fragment", blending: true, sampleCount: 4, depth: true),
        PipelineSpec(vertex: "fill_vertex", fragment: "fill_fragment"),
        PipelineSpec(vertex: "grid_vertex", fragment: "grid_fragment"),
        PipelineSpec(vertex: "grid_vertex", fragment: "grid_fragment", blending: false),
        PipelineSpec(vertex: "line_vertex", fragment: "line_fragment"),
    ]

    /// Compiles `knownPipelines` for `backend` once, with Metal's asynchronous API, so the first
    /// implicit relation, surface or complex plot does not block the main thread while its
    /// shaders compile (MTLRenderPipelineState: create pipeline states at a noncritical time).
    /// Metal compiles on its own threads; the results are stored here on the main actor, and
    /// `pipeline(_:backend:)` still compiles synchronously whatever is not ready yet.
    func warmUpPipelines(for backend: RendererBackendKind) {
        guard device != nil, library != nil, warmedUp.insert(backend).inserted else { return }
        Task(priority: .medium) {
            for spec in MetalContext.knownPipelines {
                await self.warmUp(spec, backend: backend)
            }
        }
    }

    private func warmUp(_ spec: PipelineSpec, backend: RendererBackendKind) async {
        guard let device, let library else { return }
        switch backend {
        case .metal4:
            #if targetEnvironment(simulator)
            return
            #else
            guard metal4Pipelines[spec] == nil, let compiler else { return }
            let descriptor = MetalContext.metal4Descriptor(for: spec, library: library)
            do {
                let state = try await compiler.makeRenderPipelineState(descriptor: descriptor)
                // The synchronous path may have built it meanwhile; keep that one.
                if metal4Pipelines[spec] == nil { metal4Pipelines[spec] = state }
            } catch {
                log.error("Metal 4 pipeline \(spec.fragment, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            }
            #endif
        case .metal3:
            guard classicPipelines[spec] == nil else { return }
            let descriptor = MetalContext.classicDescriptor(for: spec, library: library)
            do {
                let state = try await device.makeRenderPipelineState(descriptor: descriptor)
                if classicPipelines[spec] == nil { classicPipelines[spec] = state }
            } catch {
                log.error("Metal pipeline \(spec.fragment, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    func depthState(writes: Bool) -> MTLDepthStencilState? {
        if let cached = depthStates[writes] { return cached }
        let descriptor = MTLDepthStencilDescriptor()
        descriptor.depthCompareFunction = .lessEqual
        descriptor.isDepthWriteEnabled = writes
        let state = device?.makeDepthStencilState(descriptor: descriptor)
        depthStates[writes] = state
        return state
    }

    /// Picks the backend to use for new views.
    func resolvedBackend(preferred: RendererBackendKind) -> RendererBackendKind {
        preferred == .metal4 && supportsMetal4 ? .metal4 : .metal3
    }
}
