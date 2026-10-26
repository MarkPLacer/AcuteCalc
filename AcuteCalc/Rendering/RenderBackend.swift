import Metal
import MetalKit
import OSLog
import QuartzCore

/// Submits one frame: begins the pass on the view's drawable, lets the scene encode its
/// draws through `GPUEncoder`, commits and presents.
@MainActor
protocol RenderBackend: AnyObject {
    var kind: RendererBackendKind { get }
    var ring: FrameRing { get }
    func makeResident(_ resources: [MTLAllocation])
    func render(in view: MTKView, encode: (GPUEncoder, RenderPassInfo) -> Void)
    /// Waits (bounded) until the GPU has finished the submitted frames, so the backend and its
    /// resources can go away with the view or when the renderer changes.
    func waitUntilIdle()
}

/// Pass information independent of the API generation.
struct RenderPassInfo {
    var drawableSize: CGSize
    var sampleCount: Int
    var hasDepth: Bool
}

/// Ring buffers a `FrameRing` growth replaced, kept until the GPU has completed the last frame
/// that used them: Metal 4 command buffers and argument tables hold no references to resources,
/// and a residency set may only drop what the GPU no longer reads.
struct RetiredBuffers<Buffer> {
    private var batches: [(buffers: [Buffer], lastFrame: UInt64)] = []

    var isEmpty: Bool { batches.isEmpty }

    /// Keeps `buffers`, which frames up to `lastFrame` read.
    mutating func retire(_ buffers: [Buffer], lastFrame: UInt64) {
        guard !buffers.isEmpty else { return }
        batches.append((buffers: buffers, lastFrame: lastFrame))
    }

    /// Hands back, and forgets, the buffers whose last frame the GPU has completed.
    mutating func release(completedThrough completed: UInt64) -> [Buffer] {
        let done = batches.filter { $0.lastFrame <= completed }
        batches.removeAll { $0.lastFrame <= completed }
        return done.flatMap { $0.buffers }
    }
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
    /// Old ring buffers that frames in flight may still read (see `RetiredBuffers`).
    private var retired = RetiredBuffers<MTLBuffer>()
    private let log = Logger(subsystem: "com.markplacer.acutecalc", category: "Metal")
    private var reportedSkippedFrame = false

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
        // The view's set holds the depth and multisample textures MetalKit creates; the drawables
        // are in the set of its CAMetalLayer, which has to be added as well (MTKView.residencySet).
        queue.addResidencySet(view.residencySet)
        if let layer = view.layer as? CAMetalLayer {
            queue.addResidencySet(layer.residencySet)
        }
        ring.onBuffersChanged = { [weak self] old, new in
            guard let self else { return }
            // The ring grows right after a commit, so this frame and up to two before it still read
            // the old buffers: they stay alive and resident until the GPU has completed this frame.
            self.retired.retire(old, lastFrame: self.frameNumber)
            self.residency.addAllocations(new.map { $0 as MTLAllocation })
            self.residency.commit()
        }
    }

    func makeResident(_ resources: [MTLAllocation]) {
        residency.addAllocations(resources)
        residency.commit()
    }

    /// Metal 4 keeps nothing alive for the GPU: the queue, allocators, residency set and ring
    /// buffers must outlive the frames in flight. Bounded, so a stuck GPU cannot hang the main
    /// thread; normally the last frame needs a few milliseconds at most.
    func waitUntilIdle() {
        let last = frameNumber
        guard frameEvent.wait(untilSignaledValue: last, timeoutMS: 1000) else {
            log.error("GPU did not finish frame \(last) within 1 s")
            return
        }
        releaseRetiredBuffers()
    }

    /// Drops the ring buffers a growth replaced once the GPU has completed their last frame.
    private func releaseRetiredBuffers() {
        guard !retired.isEmpty else { return }
        let done = retired.release(completedThrough: frameEvent.signaledValue)
        guard !done.isEmpty else { return }
        residency.removeAllocations(done.map { $0 as MTLAllocation })
        residency.commit()
    }

    func render(in view: MTKView, encode: (GPUEncoder, RenderPassInfo) -> Void) {
        guard let drawable = view.currentDrawable, let pass = view.currentMTL4RenderPassDescriptor else { return }
        let frame = frameNumber + 1
        // Wait until the GPU is done with the frame that last used this allocator and ring slot.
        if frame > UInt64(FrameRing.framesInFlight) {
            let previous = frame - UInt64(FrameRing.framesInFlight)
            guard frameEvent.wait(untilSignaledValue: previous, timeoutMS: 32) else {
                // Resetting the allocator or rewriting the ring slot now would race the GPU, and
                // waiting on without a limit could hang the main thread: skip this frame (its
                // drawable goes back unpresented) and ask for another one.
                if !reportedSkippedFrame {
                    reportedSkippedFrame = true
                    log.notice("GPU still busy with frame \(previous) after 32 ms; frame skipped")
                }
                Task { [weak view] in view?.setNeedsDisplay() }
                return
            }
        }
        frameNumber = frame
        releaseRetiredBuffers()
        let allocator = allocators[Int(frameNumber % UInt64(FrameRing.framesInFlight))]
        allocator.reset()
        ring.beginFrame(frameNumber)

        commandBuffer.beginCommandBuffer(allocator: allocator)
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else {
            commandBuffer.endCommandBuffer()
            // Signal the frame anyway, so the wait for it three frames later does not time out.
            queue.signalEvent(frameEvent, value: frameNumber)
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

    /// Nothing to wait for: Metal 3 command buffers retain the resources they use.
    func waitUntilIdle() {}

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
