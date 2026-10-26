import Metal
import MetalKit
import QuartzCore

/// Submits one frame: begins the pass on the view's drawable, lets the scene encode its
/// draws through `GPUEncoder`, commits and presents.
@MainActor
protocol RenderBackend: AnyObject {
    var kind: RendererBackendKind { get }
    var ring: FrameRing { get }
    func makeResident(_ resources: [MTLAllocation])
    func render(in view: MTKView, encode: (GPUEncoder, RenderPassInfo) -> Void)
}

/// Pass information independent of the API generation.
struct RenderPassInfo {
    var drawableSize: CGSize
    var sampleCount: Int
    var hasDepth: Bool
}

// MARK: - Metal 4

// The simulator SDK has no Metal 4 types; there the Metal 3 backend draws (CI smoke test).
#if !targetEnvironment(simulator)
/// Metal 4 submission following Apple's “Drawing a triangle with Metal 4” pattern:
/// one reusable MTL4CommandBuffer, a command allocator per frame in flight, a shared
/// event for CPU/GPU pacing, an argument table for bindings and residency sets.
@MainActor
final class Metal4Backend: RenderBackend {
    let kind = RendererBackendKind.metal4
    let ring: FrameRing
    private let device: MTLDevice
    private let queue: MTL4CommandQueue
    private let commandBuffer: MTL4CommandBuffer
    private let allocators: [MTL4CommandAllocator]
    private let argumentTable: MTL4ArgumentTable
    private let residency: MTLResidencySet
    private let frameEvent: MTLSharedEvent
    private var frameNumber: UInt64 = 0

    init?(device: MTLDevice, view: MTKView) {
        guard device.supportsFamily(.metal4),
              let queue = device.makeMTL4CommandQueue(),
              let commandBuffer = device.makeCommandBuffer(),
              let event = device.makeSharedEvent(),
              let ring = FrameRing(device: device) else { return nil }
        let allocators = (0..<FrameRing.framesInFlight).compactMap { _ in device.makeCommandAllocator() }
        guard allocators.count == FrameRing.framesInFlight else { return nil }
        let tableDescriptor = MTL4ArgumentTableDescriptor()
        tableDescriptor.maxBufferBindCount = 8
        tableDescriptor.maxTextureBindCount = 4
        guard let table = try? device.makeArgumentTable(descriptor: tableDescriptor) else { return nil }
        let residencyDescriptor = MTLResidencySetDescriptor()
        residencyDescriptor.initialCapacity = 16
        guard let residency = try? device.makeResidencySet(descriptor: residencyDescriptor) else { return nil }

        self.device = device
        self.queue = queue
        self.commandBuffer = commandBuffer
        self.allocators = allocators
        self.argumentTable = table
        self.residency = residency
        self.frameEvent = event
        self.ring = ring
        event.signaledValue = 0

        residency.addAllocations(ring.buffers.map { $0 as MTLAllocation })
        residency.commit()
        queue.addResidencySet(residency)
        // MetalKit keeps the drawables, depth and multisample textures in the view's set.
        queue.addResidencySet(view.residencySet)
        ring.onBuffersChanged = { [weak self] old, new in
            guard let self else { return }
            self.residency.removeAllocations(old.map { $0 as MTLAllocation })
            self.residency.addAllocations(new.map { $0 as MTLAllocation })
            self.residency.commit()
        }
    }

    func makeResident(_ resources: [MTLAllocation]) {
        residency.addAllocations(resources)
        residency.commit()
    }

    func render(in view: MTKView, encode: (GPUEncoder, RenderPassInfo) -> Void) {
        guard let drawable = view.currentDrawable, let pass = view.currentMTL4RenderPassDescriptor else { return }
        frameNumber += 1
        // Wait until the GPU is done with the frame that last used this allocator and ring slot.
        if frameNumber > UInt64(FrameRing.framesInFlight) {
            _ = frameEvent.wait(untilSignaledValue: frameNumber - UInt64(FrameRing.framesInFlight), timeoutMS: 32)
        }
        let allocator = allocators[Int(frameNumber % UInt64(FrameRing.framesInFlight))]
        allocator.reset()
        ring.beginFrame(frameNumber)

        commandBuffer.beginCommandBuffer(allocator: allocator)
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else {
            commandBuffer.endCommandBuffer()
            return
        }
        encoder.label = "Graph"
        encoder.setArgumentTable(argumentTable, stages: [.vertex, .fragment])
        let info = RenderPassInfo(drawableSize: view.drawableSize, sampleCount: view.sampleCount, hasDepth: view.depthStencilPixelFormat != .invalid)
        encode(Metal4Encoder(encoder: encoder, table: argumentTable), info)
        encoder.endEncoding()
        commandBuffer.endCommandBuffer()

        queue.waitForDrawable(drawable)
        queue.commit([commandBuffer])
        queue.signalDrawable(drawable)
        drawable.present()
        queue.signalEvent(frameEvent, value: frameNumber)
        ring.endFrame()
    }
}
#endif

// MARK: - Metal 3 fallback

@MainActor
final class ClassicBackend: RenderBackend {
    let kind = RendererBackendKind.metal3
    let ring: FrameRing
    private let queue: MTLCommandQueue
    private let inFlight = DispatchSemaphore(value: FrameRing.framesInFlight)
    private var frameNumber: UInt64 = 0

    init?(device: MTLDevice) {
        guard let queue = device.makeCommandQueue(), let ring = FrameRing(device: device) else { return nil }
        self.queue = queue
        self.ring = ring
    }

    func makeResident(_ resources: [MTLAllocation]) {}

    func render(in view: MTKView, encode: (GPUEncoder, RenderPassInfo) -> Void) {
        guard let drawable = view.currentDrawable, let pass = view.currentRenderPassDescriptor else { return }
        inFlight.wait()
        frameNumber += 1
        ring.beginFrame(frameNumber)
        guard let commandBuffer = queue.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else {
            inFlight.signal()
            return
        }
        let semaphore = inFlight
        commandBuffer.addCompletedHandler { _ in semaphore.signal() }
        encoder.label = "Graph"
        let info = RenderPassInfo(drawableSize: view.drawableSize, sampleCount: view.sampleCount, hasDepth: view.depthStencilPixelFormat != .invalid)
        encode(ClassicEncoder(encoder: encoder), info)
        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
        ring.endFrame()
    }
}

@MainActor
func makeRenderBackend(preferred: RendererBackendKind, view: MTKView) -> RenderBackend? {
    let context = MetalContext.shared
    guard let device = context.device else { return nil }
    #if !targetEnvironment(simulator)
    if context.resolvedBackend(preferred: preferred) == .metal4, let backend = Metal4Backend(device: device, view: view) {
        return backend
    }
    #endif
    return ClassicBackend(device: device)
}
