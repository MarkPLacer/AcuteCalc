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
struct PipelineSpec: Hashable {
    var vertex: String
    var fragment: String
    var blending = true
    var sampleCount = 1
    var depth = false
    var colorFormat: MTLPixelFormat = .bgra8Unorm
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
            let descriptor = MTL4RenderPipelineDescriptor()
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
            let descriptor = MTLRenderPipelineDescriptor()
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
