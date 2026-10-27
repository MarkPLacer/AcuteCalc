import CoreGraphics
import Testing
@testable import AcuteCalc

/// The 3D surface switches its MTKView to timed (120 Hz) drawing for a spin and must switch it
/// back off once the spin has stopped, also when a grab stopped it (Audit: MTL-01).
@MainActor
@Suite struct SurfaceInertiaTests {
    @Test func grabbingASpinAndReleasingWithoutVelocityStopsContinuousRendering() {
        let model = SurfaceModel()
        var continuous = false
        model.setContinuousRendering = { continuous = $0 }
        model.startInertia(CGPoint(x: 1000, y: 0))   // a flick: |ω| = 1000 · 0.008 = 8 > 0.2
        #expect(continuous)
        model.stopInertia()                          // pan .began catches the spinning surface
        model.startInertia(.zero)                    // pan .ended after the finger came to rest
        model.stepAnimation()                        // the next display-link frame
        // Before the fix the velocity was already zero here, so timed drawing was never switched off.
        #expect(continuous == false)
    }

    @Test func cancelledGrabStopsContinuousRendering() {
        let model = SurfaceModel()
        var continuous = false
        model.setContinuousRendering = { continuous = $0 }
        model.startInertia(CGPoint(x: 1000, y: 0))
        #expect(continuous)
        model.stopInertia()                          // pan .began, then .cancelled (no .ended)
        model.stepAnimation()
        #expect(continuous == false)
    }

    /// Guards the fix against stopping a real spin (passes before and after it).
    @Test func aSpinKeepsContinuousRenderingWhileItCoasts() {
        let model = SurfaceModel()
        var continuous = false
        model.setContinuousRendering = { continuous = $0 }
        model.startInertia(CGPoint(x: 1000, y: 0))
        let yaw = model.yaw
        model.stepAnimation()
        // The first step may see dt = 0 (same media time); the spin keeps continuous rendering on.
        #expect(continuous)
        #expect(model.yaw <= yaw)
    }
}
