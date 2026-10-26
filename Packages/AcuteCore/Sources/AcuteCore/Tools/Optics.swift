import Foundation

/// Thin lenses and spherical mirrors (geometric optics at the matura): the image from the lens
/// equation 1/f = 1/a + 1/b, the magnification and the nature of the image. The object distance
/// a is positive; the image distance b is positive for a real image (behind a lens, in front of
/// a mirror) and negative for a virtual one. A diverging lens and a convex mirror have f < 0.
public enum Optics {
    public enum Kind: String, CaseIterable, Sendable {
        case convergingLens, divergingLens, concaveMirror, convexMirror

        public var isMirror: Bool { self == .concaveMirror || self == .convexMirror }

        /// A converging lens and a concave mirror gather parallel light (f > 0).
        public var converges: Bool { self == .convergingLens || self == .concaveMirror }
    }

    public struct Image: Sendable, Hashable {
        /// The image distance b; infinite when the object is in the focal point.
        public var distance: Double
        /// m = −b/a, negative for an inverted image.
        public var magnification: Double
        /// The image height m·h.
        public var height: Double

        public var isAtInfinity: Bool { !distance.isFinite }
        public var isReal: Bool { distance.isFinite && distance > 0 }
        public var isUpright: Bool { magnification > 0 }
    }

    /// The signed focal length of the kind from the length typed (its sign is ignored).
    public static func focalLength(_ kind: Kind, _ f: Double) -> Double {
        kind.converges ? Swift.abs(f) : -Swift.abs(f)
    }

    /// The image of an object at the distance a > 0 with the height h; f may be typed without
    /// its sign, which follows from the kind.
    public static func image(kind: Kind, focalLength f: Double, objectDistance a: Double, objectHeight h: Double) throws(MathError) -> Image {
        guard f.isFinite, f != 0 else { throw .domain("goriščna razdalja mora biti različna od 0") }
        guard a > 0, a.isFinite else { throw .domain("predmet mora biti pred lečo oziroma zrcalom (a > 0)") }
        guard h.isFinite, h != 0 else { throw .domain("velikost predmeta mora biti različna od 0") }
        let focal = focalLength(kind, f)
        guard a != focal else { return Image(distance: .infinity, magnification: .infinity, height: .infinity) }
        let b = a * focal / (a - focal)
        let m = -b / a
        return Image(distance: b, magnification: m, height: m * h)
    }
}
