import Foundation
import Testing
@testable import AcuteCore

// MARK: Lenses and mirrors

@Suite struct OpticsTests {
    @Test func convergingLens() throws {
        // f = 10, a = 30: b = 15, the image real, inverted and half as large.
        let far = try Optics.image(kind: .convergingLens, focalLength: 10, objectDistance: 30, objectHeight: 4)
        #expect(approx(far.distance, 15) && approx(far.magnification, -0.5) && approx(far.height, -2))
        #expect(far.isReal && !far.isUpright)
        // a = 2f: b = 2f and the image as large as the object.
        let twice = try Optics.image(kind: .convergingLens, focalLength: 10, objectDistance: 20, objectHeight: 1)
        #expect(approx(twice.distance, 20) && approx(twice.magnification, -1))
        // Inside the focal length the lens is a magnifier: b = −10, m = 2, virtual and upright.
        let near = try Optics.image(kind: .convergingLens, focalLength: 10, objectDistance: 5, objectHeight: 1)
        #expect(approx(near.distance, -10) && approx(near.magnification, 2) && !near.isReal && near.isUpright)
        // In the focal point the image is at infinity.
        #expect(try Optics.image(kind: .convergingLens, focalLength: 10, objectDistance: 10, objectHeight: 1).isAtInfinity)
    }

    @Test func divergingLensAndMirrors() throws {
        // A diverging lens with |f| = 10 always gives a virtual, upright, smaller image.
        let lens = try Optics.image(kind: .divergingLens, focalLength: 10, objectDistance: 30, objectHeight: 4)
        #expect(approx(lens.distance, -7.5) && approx(lens.magnification, 0.25) && !lens.isReal && lens.isUpright)
        // A concave mirror behaves like a converging lens, a convex one like a diverging lens.
        let concave = try Optics.image(kind: .concaveMirror, focalLength: 10, objectDistance: 30, objectHeight: 1)
        #expect(approx(concave.distance, 15) && concave.isReal)
        let convex = try Optics.image(kind: .convexMirror, focalLength: -10, objectDistance: 10, objectHeight: 1)
        #expect(approx(convex.distance, -5) && approx(convex.magnification, 0.5))
        #expect(Optics.focalLength(.convexMirror, 10) == -10 && Optics.focalLength(.concaveMirror, -10) == 10)
        #expect(throws: MathError.self) { try Optics.image(kind: .convergingLens, focalLength: 0, objectDistance: 1, objectHeight: 1) }
        #expect(throws: MathError.self) { try Optics.image(kind: .convergingLens, focalLength: 5, objectDistance: -1, objectHeight: 1) }
    }
}
