import Metal
import MetalKit
import Testing
@testable import AcuteCalc

/// Metal 4 command buffers keep nothing alive, so a coordinator has to let the GPU finish its
/// backend's frames (RenderBackend.waitUntilIdle) before it drops the backend: when the view goes
/// away and when attach() replaces the backend after the renderer setting changed (Audit: MTL-05).
/// A stand-in backend records the wait. The simulator only has the Metal 3 path; the Metal 4 wait
/// itself needs a device.
@MainActor
@Suite(.enabled(if: MTLCreateSystemDefaultDevice() != nil, "needs a Metal device"))
struct ComplexBackendLifetimeTests {
    @Test func switchingTheRendererWaitsForTheOldBackend() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let coordinator = ComplexCoordinator(model: ComplexPlotModel())
        let view = MTKView(frame: .zero, device: device)
        var waits = 0
        weak var old: StandInBackend?
        do {
            let ring = try #require(FrameRing(device: device))
            let standIn = StandInBackend(ring: ring) { waits += 1 }
            coordinator.backend = standIn    // the Metal 4 backend attached first
            old = standIn
        }
        coordinator.attach(to: view, backendKind: .metal3)    // the renderer setting changed
        let released = old == nil
        let fallback = coordinator.backend is ClassicBackend
        // Before the fix attach() dropped the old backend without waiting (waits == 0).
        #expect(waits == 1)
        #expect(released)
        #expect(fallback)
    }

    /// dismantleUIView already waited before this fix; guards it.
    @Test func removingThePlotWaitsForItsBackend() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let coordinator = ComplexCoordinator(model: ComplexPlotModel())
        let view = MTKView(frame: .zero, device: device)
        var waits = 0
        let ring = try #require(FrameRing(device: device))
        coordinator.backend = StandInBackend(ring: ring) { waits += 1 }
        ComplexMetalView.dismantleUIView(view, coordinator: coordinator)
        #expect(waits == 1)
    }
}

/// Counts waitUntilIdle() calls; draws nothing.
@MainActor
private final class StandInBackend: RenderBackend {
    let kind = RendererBackendKind.metal4
    let ring: FrameRing
    private let onWait: () -> Void

    init(ring: FrameRing, onWait: @escaping () -> Void) {
        self.ring = ring
        self.onWait = onWait
    }

    func makeResident(_ resources: [MTLAllocation]) {}

    var submittedFrame: UInt64 { 0 }
    var completedFrame: UInt64 { 0 }

    func render(in view: MTKView, encode: (GPUEncoder, RenderPassInfo) -> Void) {}

    func waitUntilIdle() { onWait() }
}
