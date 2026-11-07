import Metal
import OSLog

// The simulator accepts only private depth, stencil and MSAA textures ("Developing Metal apps that run in
// Simulator"), so there the 3D view keeps MetalKit's.
#if !targetEnvironment(simulator)
/// The 4× multisample colour and depth attachments of the 3D view, as memoryless textures.
///
/// The pass resolves the colour into the drawable and discards depth, so neither needs memory: "most render passes
/// don't store depth attachments and multisample attachments to memory. You can significantly reduce your memory
/// usage by creating these attachments as memoryless resources" (MTLStorageMode.memoryless). MetalKit's own
/// (MTKView.sampleCount 4 and a depth format) are private, about 55–63 MB each for a 3D view beside the controls on
/// an iPad Pro 13, and MetalKit keeps them in the view's residency set, so the view asks MetalKit for neither and
/// its backend points each pass at these instead.
@MainActor
final class MemorylessTargets {
    static let sampleCount = 4

    /// The textures a resize made, and the ones they replace (both empty when the size stayed).
    struct Replacement {
        var added: [MTLTexture] = []
        var removed: [MTLTexture] = []
    }

    private let device: MTLDevice
    private var colorTexture: MTLTexture?
    private var depthTexture: MTLTexture?
    private var reportedFailure = false
    private let log = Logger(subsystem: "com.markplacer.acutecalc", category: "Metal")

    init(device: MTLDevice) {
        self.device = device
    }

    /// Points colour attachment 0 at the multisample texture, resolved into `drawable`, and the depth attachment at
    /// the depth texture, cleared to 1 and discarded. Both are made anew when the drawable's size changed. Returns
    /// what that replaced, or nil (and leaves the pass alone) when Metal could not make them.
    func attach(color: MTLRenderPassColorAttachmentDescriptor, depth: MTLRenderPassDepthAttachmentDescriptor,
                resolvingInto drawable: MTLTexture) -> Replacement? {
        var replacement = Replacement()
        if colorTexture?.width != drawable.width || colorTexture?.height != drawable.height || depthTexture == nil {
            guard let newColor = makeTexture(.bgra8Unorm, like: drawable),
                  let newDepth = makeTexture(.depth32Float, like: drawable) else {
                if !reportedFailure {
                    reportedFailure = true
                    log.error("Memoryless attachments of \(drawable.width) × \(drawable.height) could not be made")
                }
                return nil
            }
            replacement.added = [newColor, newDepth]
            replacement.removed = [colorTexture, depthTexture].compactMap { $0 }
            colorTexture = newColor
            depthTexture = newDepth
        }
        color.texture = colorTexture
        color.resolveTexture = drawable
        color.loadAction = .clear
        color.storeAction = .multisampleResolve
        depth.texture = depthTexture
        depth.loadAction = .clear
        depth.storeAction = .dontCare
        depth.clearDepth = 1
        return replacement
    }

    private func makeTexture(_ format: MTLPixelFormat, like drawable: MTLTexture) -> MTLTexture? {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: format, width: drawable.width,
                                                                  height: drawable.height, mipmapped: false)
        descriptor.textureType = .type2DMultisample
        descriptor.sampleCount = Self.sampleCount
        descriptor.storageMode = .memoryless
        descriptor.usage = .renderTarget
        return device.makeTexture(descriptor: descriptor)
    }
}
#endif
