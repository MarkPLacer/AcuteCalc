import Foundation

/// Lines and planes in space (Matematika I and II): distances, mutual position, intersections,
/// angles, projections and mirror images. A line is A + t·s⃗, a plane n⃗·r⃗ + d = 0.
public enum SpatialGeometry {
    public struct Line: Sendable, Hashable {
        public var point: [Double]
        public var direction: [Double]

        public init(point: [Double], direction: [Double]) {
            self.point = point
            self.direction = direction
        }

        /// The line through two points; nil when they coincide.
        public init?(through a: [Double], _ b: [Double]) {
            let s = SpatialGeometry.minus(b, a)
            guard VectorGeometry.length(s) > 0 else { return nil }
            self.init(point: a, direction: s)
        }

        public func at(_ t: Double) -> [Double] { zip(point, direction).map { $0 + t * $1 } }
    }

    public struct Plane: Sendable, Hashable {
        public var normal: [Double]
        public var d: Double

        /// ax + by + cz + d = 0
        public init(normal: [Double], d: Double) {
            self.normal = normal
            self.d = d
        }

        /// The plane through a point with the given normal.
        public init(normal: [Double], point: [Double]) {
            self.normal = normal
            d = -VectorGeometry.dot(normal, point)
        }

        /// The plane through three points; nil when they lie on one line.
        public init?(through a: [Double], _ b: [Double], _ c: [Double]) {
            let u = SpatialGeometry.minus(b, a), v = SpatialGeometry.minus(c, a)
            let n = VectorGeometry.cross(u, v)
            guard VectorGeometry.length(n) > 1e-12 * Swift.max(1e-300, VectorGeometry.length(u) * VectorGeometry.length(v)) else { return nil }
            self.init(normal: n, point: a)
        }

        /// Signed value n⃗·r⃗ + d.
        func value(_ p: [Double]) -> Double { VectorGeometry.dot(normal, p) + d }
    }

    public enum LinePosition: Sendable, Hashable {
        case intersecting([Double])
        case parallel
        case identical
        case skew
    }

    // MARK: Distances

    public static func distance(_ p: [Double], _ plane: Plane) -> Double {
        Swift.abs(plane.value(p)) / VectorGeometry.length(plane.normal)
    }

    public static func distance(_ p: [Double], _ line: Line) -> Double {
        VectorGeometry.length(VectorGeometry.cross(minus(p, line.point), line.direction)) / VectorGeometry.length(line.direction)
    }

    /// The shortest distance between two lines (zero when they meet): |AB⃗·(s⃗ × r⃗)|/|s⃗ × r⃗|, or
    /// the distance of B from the first line when they are parallel.
    public static func distance(_ a: Line, _ b: Line) -> Double {
        guard !parallel(a.direction, b.direction) else { return distance(b.point, a) }
        let n = VectorGeometry.cross(a.direction, b.direction)
        return Swift.abs(VectorGeometry.dot(minus(b.point, a.point), n)) / VectorGeometry.length(n)
    }

    /// Distance between two parallel planes (zero when they intersect).
    public static func distance(_ a: Plane, _ b: Plane) -> Double {
        guard parallel(a.normal, b.normal) else { return 0 }
        // A point of b, then its distance from a.
        let k = -b.d / VectorGeometry.dot(b.normal, b.normal)
        return distance(b.normal.map { $0 * k }, a)
    }

    // MARK: Position and intersections

    /// The feet of the common perpendicular of two lines that are not parallel.
    public static func closestPoints(_ a: Line, _ b: Line) -> ([Double], [Double])? {
        guard !parallel(a.direction, b.direction) else { return nil }
        let w = minus(a.point, b.point)
        let aa = VectorGeometry.dot(a.direction, a.direction), ab = VectorGeometry.dot(a.direction, b.direction)
        let bb = VectorGeometry.dot(b.direction, b.direction)
        let aw = VectorGeometry.dot(a.direction, w), bw = VectorGeometry.dot(b.direction, w)
        let denominator = aa * bb - ab * ab
        let t = (ab * bw - bb * aw) / denominator, u = (aa * bw - ab * aw) / denominator
        return (clean(a.at(t)), clean(b.at(u)))
    }

    public static func position(_ a: Line, _ b: Line) -> LinePosition {
        // The gap is computed from AB⃗, so it is compared with |AB⃗|: moving both lines together
        // does not change the answer.
        let tolerance = 1e-12 * VectorGeometry.length(minus(b.point, a.point))
        let gap = distance(a, b)
        guard let feet = closestPoints(a, b) else { return gap <= tolerance ? .identical : .parallel }
        return gap <= tolerance ? .intersecting(feet.0) : .skew
    }

    /// The common point of a line and a plane; nil when the line is parallel to it (or lies in it).
    public static func intersection(_ line: Line, _ plane: Plane) -> [Double]? {
        let denominator = VectorGeometry.dot(plane.normal, line.direction)
        guard Swift.abs(denominator) > 1e-12 * VectorGeometry.length(plane.normal) * VectorGeometry.length(line.direction) else { return nil }
        return clean(line.at(-plane.value(line.point) / denominator))
    }

    /// The line where two planes meet; nil when they are parallel.
    public static func intersection(_ a: Plane, _ b: Plane) -> Line? {
        guard !parallel(a.normal, b.normal) else { return nil }
        let direction = VectorGeometry.cross(a.normal, b.normal)
        let determinant = VectorGeometry.dot(direction, direction)
        // The point c₁n⃗₁ + c₂n⃗₂ lies in both planes.
        let n11 = VectorGeometry.dot(a.normal, a.normal), n22 = VectorGeometry.dot(b.normal, b.normal)
        let n12 = VectorGeometry.dot(a.normal, b.normal)
        let h1 = -a.d, h2 = -b.d
        let c1 = (h1 * n22 - h2 * n12) / determinant, c2 = (h2 * n11 - h1 * n12) / determinant
        let point = zip(a.normal, b.normal).map { c1 * $0 + c2 * $1 }
        return Line(point: clean(point), direction: clean(direction))
    }

    // MARK: Angles (0 … π/2)

    public static func angle(_ a: Line, _ b: Line) -> Double {
        acute(VectorGeometry.dot(a.direction, b.direction) / (VectorGeometry.length(a.direction) * VectorGeometry.length(b.direction)))
    }

    public static func angle(_ a: Plane, _ b: Plane) -> Double {
        acute(VectorGeometry.dot(a.normal, b.normal) / (VectorGeometry.length(a.normal) * VectorGeometry.length(b.normal)))
    }

    /// The angle between a line and a plane: sin φ = |n⃗·s⃗|/(|n⃗||s⃗|).
    public static func angle(_ line: Line, _ plane: Plane) -> Double {
        let s = Swift.abs(VectorGeometry.dot(plane.normal, line.direction)) / (VectorGeometry.length(plane.normal) * VectorGeometry.length(line.direction))
        return asin(Swift.min(1, s))
    }

    // MARK: Projections and mirror images

    public static func projection(_ p: [Double], onto plane: Plane) -> [Double] {
        let k = plane.value(p) / VectorGeometry.dot(plane.normal, plane.normal)
        return clean(zip(p, plane.normal).map { $0 - k * $1 })
    }

    public static func projection(_ p: [Double], onto line: Line) -> [Double] {
        let t = VectorGeometry.dot(minus(p, line.point), line.direction) / VectorGeometry.dot(line.direction, line.direction)
        return clean(line.at(t))
    }

    public static func mirror(_ p: [Double], in plane: Plane) -> [Double] {
        clean(zip(projection(p, onto: plane), p).map { 2 * $0 - $1 })
    }

    public static func mirror(_ p: [Double], in line: Line) -> [Double] {
        clean(zip(projection(p, onto: line), p).map { 2 * $0 - $1 })
    }

    // MARK: Helpers

    static func minus(_ a: [Double], _ b: [Double]) -> [Double] { zip(a, b).map(-) }

    static func parallel(_ u: [Double], _ v: [Double]) -> Bool {
        VectorGeometry.length(VectorGeometry.cross(u, v)) <= 1e-12 * Swift.max(1e-300, VectorGeometry.length(u) * VectorGeometry.length(v))
    }

    static func acute(_ cosine: Double) -> Double {
        acos(Swift.min(1, Swift.abs(cosine)))
    }

    static func clean(_ v: [Double]) -> [Double] { v.map(NumericCalculus.clean) }
}

/// Geometric properties of plane cross-sections (Osnove statike, Trdnost at FGG): area, centroid,
/// second moments of area about the centroidal axes (Steiner's theorem), the product of inertia,
/// the principal moments with their direction and the elastic section moduli.
public enum CrossSection {
    public enum Part: Sendable, Hashable {
        /// Corners in order (either orientation).
        case polygon([SIMD2<Double>])
        /// Lower left corner (x, y), width and height.
        case rectangle(x: Double, y: Double, width: Double, height: Double)
        case circle(center: SIMD2<Double>, radius: Double)
        /// A circular sector between two angles in radians, counterclockwise from the x axis:
        /// a half disc from 0 to π, a quarter disc from 0 to π/2.
        case sector(center: SIMD2<Double>, radius: Double, from: Double, to: Double)
    }

    public struct Properties: Sendable, Hashable {
        public var area: Double
        public var centroid: SIMD2<Double>
        /// About the axes through the centroid parallel to x and y: I_x = ∫y² dA, I_y = ∫x² dA, I_xy = ∫xy dA.
        public var ix: Double
        public var iy: Double
        public var ixy: Double
        /// Principal moments I₁ ≥ I₂ and the angle of the I₁ axis from x (radians, counterclockwise).
        public var i1: Double
        public var i2: Double
        public var principalAngle: Double
        /// The bounding box of the solid parts.
        public var lowerLeft: SIMD2<Double>
        public var upperRight: SIMD2<Double>

        public var radiusX: Double { (ix / area).squareRoot() }
        public var radiusY: Double { (iy / area).squareRoot() }
        /// I_p = I_x + I_y about the centroid.
        public var polar: Double { ix + iy }
        /// W_x = I_x / e_y with the largest distance e_y of the section from the x axis through the centroid.
        public var sectionModulusX: Double { ix / Swift.max(upperRight.y - centroid.y, centroid.y - lowerLeft.y) }
        public var sectionModulusY: Double { iy / Swift.max(upperRight.x - centroid.x, centroid.x - lowerLeft.x) }
    }

    /// A, Sₓ = ∫y dA, S_y = ∫x dA and the second moments about the coordinate axes.
    struct Moments {
        var area = 0.0, sx = 0.0, sy = 0.0, ixx = 0.0, iyy = 0.0, ixy = 0.0

        static func + (a: Moments, b: Moments) -> Moments {
            Moments(area: a.area + b.area, sx: a.sx + b.sx, sy: a.sy + b.sy, ixx: a.ixx + b.ixx, iyy: a.iyy + b.iyy, ixy: a.ixy + b.ixy)
        }

        func scaled(_ k: Double) -> Moments {
            Moments(area: k * area, sx: k * sx, sy: k * sy, ixx: k * ixx, iyy: k * iyy, ixy: k * ixy)
        }

        /// The same moments about axes moved so that the old origin sits at c.
        func shifted(by c: SIMD2<Double>) -> Moments {
            Moments(area: area, sx: sx + c.y * area, sy: sy + c.x * area,
                    ixx: ixx + 2 * c.y * sx + c.y * c.y * area, iyy: iyy + 2 * c.x * sy + c.x * c.x * area,
                    ixy: ixy + c.x * sx + c.y * sy + c.x * c.y * area)
        }
    }

    /// Parts marked `hole` are subtracted (openings, hollow sections).
    public static func properties(_ parts: [(part: Part, hole: Bool)]) throws(MathError) -> Properties {
        var total = Moments()
        var solids: [SIMD2<Double>] = []
        for (part, hole) in parts {
            total = total + (try moments(part)).scaled(hole ? -1 : 1)
            if !hole {
                let corners = bounds(part)
                solids += [corners.0, corners.1]
            }
        }
        let (low, high) = box(solids)
        guard !solids.isEmpty, total.area > 1e-12 * Swift.max(1e-300, (high.x - low.x) * (high.y - low.y)) else {
            throw .domain("ploščina prereza mora biti pozitivna")
        }
        let xT = total.sy / total.area, yT = total.sx / total.area
        let ix = total.ixx - total.area * yT * yT
        let iy = total.iyy - total.area * xT * xT
        let ixy = total.ixy - total.area * xT * yT
        let mean = (ix + iy) / 2
        let radius = (((ix - iy) / 2) * ((ix - iy) / 2) + ixy * ixy).squareRoot()
        let clean = NumericCalculus.clean
        return Properties(area: clean(total.area), centroid: SIMD2(clean(xT), clean(yT)), ix: clean(ix), iy: clean(iy), ixy: clean(ixy),
                          i1: clean(mean + radius), i2: clean(mean - radius), principalAngle: clean(0.5 * atan2(-2 * ixy, ix - iy)),
                          lowerLeft: low, upperRight: high)
    }

    static func moments(_ part: Part) throws(MathError) -> Moments {
        switch part {
        case .rectangle(let x, let y, let b, let h):
            guard b > 0, h > 0 else { throw .domain("širina in višina pravokotnika morata biti pozitivni") }
            return Moments(area: b * h, ixx: b * h * h * h / 12, iyy: h * b * b * b / 12).shifted(by: SIMD2(x + b / 2, y + h / 2))
        case .circle(let c, let r):
            return try moments(.sector(center: c, radius: r, from: 0, to: 2 * .pi))
        case .sector(let c, let r, let from, let to):
            let span = to - from
            guard r > 0 else { throw .domain("polmer mora biti pozitiven") }
            guard span > 0, span <= 2 * .pi + 1e-12 else { throw .domain("kot izseka mora biti med 0° in 360°") }
            let r3 = r * r * r / 3, r4 = r * r * r * r
            let local = Moments(area: r * r * span / 2, sx: r3 * (cos(from) - cos(to)), sy: r3 * (sin(to) - sin(from)),
                                ixx: r4 / 8 * (span - (sin(2 * to) - sin(2 * from)) / 2),
                                iyy: r4 / 8 * (span + (sin(2 * to) - sin(2 * from)) / 2),
                                ixy: r4 / 16 * (cos(2 * from) - cos(2 * to)))
            return local.shifted(by: c)
        case .polygon(let p):
            guard p.count >= 3 else { throw .domain("mnogokotnik potrebuje vsaj tri oglišča") }
            var m = Moments()
            for i in p.indices {
                let a = p[i], b = p[(i + 1) % p.count]
                let cross = a.x * b.y - b.x * a.y
                m.area += cross / 2
                m.sy += (a.x + b.x) * cross / 6
                m.sx += (a.y + b.y) * cross / 6
                m.ixx += (a.y * a.y + a.y * b.y + b.y * b.y) * cross / 12
                m.iyy += (a.x * a.x + a.x * b.x + b.x * b.x) * cross / 12
                m.ixy += (a.x * b.y + 2 * a.x * a.y + 2 * b.x * b.y + b.x * a.y) * cross / 24
            }
            guard m.area != 0 else { throw .domain("oglišča mnogokotnika ležijo na premici") }
            return m.area < 0 ? m.scaled(-1) : m
        }
    }

    /// The smallest axis-parallel box around a part (lower left, upper right).
    public static func bounds(_ part: Part) -> (SIMD2<Double>, SIMD2<Double>) {
        switch part {
        case .rectangle(let x, let y, let b, let h):
            return (SIMD2(x, y), SIMD2(x + b, y + h))
        case .circle(let c, let r):
            return (c - SIMD2(r, r), c + SIMD2(r, r))
        case .sector(let c, let r, let from, let to):
            // The centre, both ends of the arc and the arc's points at multiples of 90° (at most
            // five, with the angles first brought to one turn).
            let turn = (from / (2 * Double.pi)).rounded(.down) * 2 * Double.pi
            let start = from - turn, end = Swift.min(to - turn, start + 2 * Double.pi)
            var points: [SIMD2<Double>] = [c, c + r * SIMD2(cos(start), sin(start)), c + r * SIMD2(cos(end), sin(end))]
            var k = (start / (Double.pi / 2)).rounded(.up)
            while k * Double.pi / 2 <= end, points.count < 9 {
                points.append(c + r * SIMD2(cos(k * Double.pi / 2), sin(k * Double.pi / 2)))
                k += 1
            }
            return box(points)
        case .polygon(let p):
            return box(p)
        }
    }

    static func box(_ points: [SIMD2<Double>]) -> (SIMD2<Double>, SIMD2<Double>) {
        var low = SIMD2(Double.infinity, Double.infinity)
        var high = SIMD2(-Double.infinity, -Double.infinity)
        for p in points {
            low = SIMD2(Swift.min(low.x, p.x), Swift.min(low.y, p.y))
            high = SIMD2(Swift.max(high.x, p.x), Swift.max(high.y, p.y))
        }
        return (low, high)
    }
}
