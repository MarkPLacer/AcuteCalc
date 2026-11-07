import Testing
@testable import AcuteCalc

/// Audit metal:6: from outside the box an implicit surface marches only on the entry face, and where the near
/// plane (0.05) clipped that face the pixel stayed empty. The exit-face pipeline now also runs within a margin of
/// the box: the distance from the camera to the near plane's corners, which grows with the view's aspect.
@MainActor
@Suite struct ImplicitSurfaceNearPlaneTests {
    private func camera(distance: Double, yaw: Double, pitch: Double) -> SurfaceModel {
        let model = SurfaceModel()
        model.distance = distance
        model.yaw = yaw
        model.pitch = pitch
        return model
    }

    /// Pinched all the way in (distance 1.4) at yaw 0.75: at pitch 0.57 the eye is 0.0055 above the top face, and
    /// with a level camera 0.024 outside the face z = 1. Both left most of the box empty; the exact box test said
    /// "outside" for both.
    @Test func justOutsideTheBoxMarchesFromTheExitFace() {
        #expect(camera(distance: 1.4, yaw: 0.75, pitch: 0.57).cameraInsideBox(aspect: 1.38))
        #expect(camera(distance: 1.4, yaw: 0.75, pitch: 0).cameraInsideBox(aspect: 1.38))
    }

    /// At distance 1.43, yaw 0.65 and pitch 0.36 the eye is 0.065 outside the face z = 1: beyond the near plane's
    /// corners in a square view (0.057), but not on an iPhone in landscape (aspect 2.17: 0.067), where a fixed
    /// margin of 0.06 still left a corner of the screen empty.
    @Test func theMarginGrowsWithTheAspect() {
        let model = camera(distance: 1.43, yaw: 0.65, pitch: 0.36)
        #expect(model.cameraInsideBox(aspect: 2.17))
        #expect(!model.cameraInsideBox(aspect: 1))
    }

    @Test func aCameraAwayFromTheBoxStaysOutside() {
        #expect(!SurfaceModel().cameraInsideBox(aspect: 2.17))
        #expect(!camera(distance: 1.6, yaw: 0.75, pitch: 0).cameraInsideBox(aspect: 2.17))
    }
}
