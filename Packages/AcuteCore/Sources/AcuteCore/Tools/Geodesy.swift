import Foundation

/// Plane surveying computations (Geodezija at FGG) in the convention of the national grid:
/// y points east, x north, and direction angles ν are measured clockwise from north
/// (0 ≤ ν < 2π). Angles are in radians; `gon(fromRadians:)` and `degrees(fromDMS:)` convert.
public enum Geodesy {
    public struct Point: Sendable, Hashable {
        public var y: Double
        public var x: Double

        public init(y: Double, x: Double) {
            self.y = y
            self.x = x
        }
    }

    // MARK: Angles

    /// The angle in [0, 2π).
    public static func normalized(_ angle: Double) -> Double {
        let r = angle.truncatingRemainder(dividingBy: 2 * .pi)
        let v = r < 0 ? r + 2 * .pi : r
        return v >= 2 * .pi ? 0 : v
    }

    public static func gon(fromRadians r: Double) -> Double { r * 200 / .pi }

    public static func radians(fromGon g: Double) -> Double { g * .pi / 200 }

    /// Degrees from "123 45 12,5", "123°45′12.5″", "−12°30'" or "45,25".
    public static func degrees(fromDMS text: String) -> Double? {
        var t = text.trimmingCharacters(in: .whitespaces)
        var negative = false
        if let first = t.first, first == "-" || first == "−" {
            negative = true
            t.removeFirst()
        }
        let parts = t.replacingOccurrences(of: ",", with: ".").split(whereSeparator: { "°'′\"″: ".contains($0) })
        guard (1...3).contains(parts.count) else { return nil }
        var values: [Double] = []
        for part in parts {
            guard let v = Double(part), v.isFinite, v >= 0 else { return nil }
            values.append(v)
        }
        guard values.dropFirst().allSatisfy({ $0 < 60 }) else { return nil }
        let minutes = values.count > 1 ? values[1] : 0, seconds = values.count > 2 ? values[2] : 0
        let d = values[0] + minutes / 60 + seconds / 3600
        return negative ? -d : d
    }

    // MARK: Basic tasks

    /// The direction angle ν_AB and the distance d_AB (the inverse task).
    public static func inverse(_ a: Point, _ b: Point) -> (direction: Double, distance: Double)? {
        let dy = b.y - a.y, dx = b.x - a.x
        let d = (dy * dy + dx * dx).squareRoot()
        guard d > 0 else { return nil }
        return (normalized(atan2(dy, dx)), d)
    }

    /// The point at distance d in the direction ν from A (the polar method).
    public static func polar(from a: Point, direction nu: Double, distance d: Double) -> Point {
        Point(y: NumericCalculus.clean(a.y + d * sin(nu)), x: NumericCalculus.clean(a.x + d * cos(nu)))
    }

    /// Where the rays from A in the direction ν_A and from B in the direction ν_B meet; nil for
    /// parallel rays or when they would meet behind A or B.
    public static func intersection(_ a: Point, direction nuA: Double, _ b: Point, direction nuB: Double) -> Point? {
        // (y, x) components of the unit directions.
        let sa = SIMD2(sin(nuA), cos(nuA)), sb = SIMD2(sin(nuB), cos(nuB))
        let ab = SIMD2(b.y - a.y, b.x - a.x)
        let denominator = cross(sa, sb)
        guard Swift.abs(denominator) > 1e-12 else { return nil }
        let t = cross(ab, sb) / denominator, u = cross(ab, sa) / denominator
        guard t > 0, u > 0 else { return nil }
        return polar(from: a, direction: nuA, distance: t)
    }

    /// Forward intersection (urez naprej) from the angle α at A between AB and AP and the angle β
    /// at B between BA and BP, with P to the left or to the right of AB seen from A.
    public static func forwardIntersection(_ a: Point, _ b: Point, alpha: Double, beta: Double, left: Bool) -> Point? {
        guard let ab = inverse(a, b) else { return nil }
        let nuAP = left ? ab.direction - alpha : ab.direction + alpha
        let nuBP = left ? ab.direction + .pi + beta : ab.direction + .pi - beta
        return intersection(a, direction: normalized(nuAP), b, direction: normalized(nuBP))
    }

    /// Arc intersection (ločni presek): P at the distance d_A from A and d_B from B, to the left
    /// or to the right of AB seen from A.
    public static func arcIntersection(_ a: Point, _ b: Point, distanceA da: Double, distanceB db: Double, left: Bool) -> Point? {
        guard let ab = inverse(a, b), da > 0, db > 0 else { return nil }
        let cosine = (da * da + ab.distance * ab.distance - db * db) / (2 * da * ab.distance)
        guard Swift.abs(cosine) <= 1 + 1e-12 else { return nil }
        let alpha = acos(Swift.min(1, Swift.max(-1, cosine)))
        return polar(from: a, direction: normalized(left ? ab.direction - alpha : ab.direction + alpha), distance: da)
    }

    /// Resection (urez nazaj, Snellius–Pothenot): P from the angle α from A to B and β from B to C,
    /// both measured at P clockwise as on the horizontal circle. Nil on the danger circle, when
    /// P lies on the circle through A, B and C.
    public static func resection(_ a: Point, _ b: Point, _ c: Point, alpha: Double, beta: Double) -> Point? {
        // In the (east, north) plane P sees AB under the counterclockwise angle −α, so the circle
        // through A, B and P is centred at the midpoint of AB moved by −½·cot α·(B − A) turned by 90°.
        func center(_ p: SIMD2<Double>, _ q: SIMD2<Double>, _ angle: Double) -> SIMD2<Double>? {
            let s = sin(angle)
            guard Swift.abs(s) > 1e-12 else { return nil }
            let d = q - p
            let shift = 0.5 * cos(angle) / s
            return (p + q) / 2 - shift * SIMD2(-d.y, d.x)
        }
        let pa = SIMD2(a.y, a.x), pb = SIMD2(b.y, b.x), pc = SIMD2(c.y, c.x)
        guard let m1 = center(pa, pb, alpha), let m2 = center(pb, pc, beta) else { return nil }
        let d = m2 - m1
        let dd = (d * d).sum()
        let size = Swift.max(((pb - pa) * (pb - pa)).sum(), ((pc - pb) * (pc - pb)).sum())
        guard dd > 1e-16 * size else { return nil }
        // Both circles pass through B and P, so P is B mirrored across the line of the centres.
        let foot = m1 + (((pb - m1) * d).sum() / dd) * d
        let p = 2 * foot - pb
        guard ((p - pb) * (p - pb)).sum() > 1e-16 * size else { return nil }
        return Point(y: NumericCalculus.clean(p.x), x: NumericCalculus.clean(p.y))
    }

    static func cross(_ p: SIMD2<Double>, _ q: SIMD2<Double>) -> Double { p.x * q.y - p.y * q.x }

    // MARK: Areas

    /// Gauss's formula 2P = Σ yᵢ(xᵢ₊₁ − xᵢ₋₁) for the area enclosed by the points in order.
    public static func area(_ points: [Point]) -> Double {
        guard points.count >= 3 else { return 0 }
        // Coordinates relative to the first point keep large national grid values exact.
        let y0 = points[0].y, x0 = points[0].x
        var twice = 0.0
        for i in points.indices {
            let next = points[(i + 1) % points.count], previous = points[(i + points.count - 1) % points.count]
            twice += (points[i].y - y0) * ((next.x - x0) - (previous.x - x0))
        }
        return NumericCalculus.clean(Swift.abs(twice) / 2)
    }

    public static func perimeter(_ points: [Point]) -> Double {
        guard points.count >= 2 else { return 0 }
        var total = 0.0
        for i in points.indices {
            let p = points[i], q = points[(i + 1) % points.count]
            total += ((q.y - p.y) * (q.y - p.y) + (q.x - p.x) * (q.x - p.x)).squareRoot()
        }
        return NumericCalculus.clean(total)
    }

    // MARK: Similarity transformation

    /// The plane similarity (Helmert) transformation y′ = a·y − b·x + t_y, x′ = b·y + a·x + t_x.
    public struct Helmert: Sendable, Hashable {
        public var a: Double
        public var b: Double
        public var ty: Double
        public var tx: Double
        /// Transformed minus given coordinates at the identical points.
        public var residuals: [Point]

        /// The scale m = √(a² + b²).
        public var scale: Double { (a * a + b * b).squareRoot() }
        /// The change of every direction angle (clockwise positive).
        public var rotation: Double { Geodesy.normalized(-atan2(b, a)) }
        /// σ₀ = √(Σv²/(2n − 4)) with more than two identical points.
        public var sigma: Double? {
            guard residuals.count > 2 else { return nil }
            let sum = residuals.reduce(0) { $0 + $1.y * $1.y + $1.x * $1.x }
            return (sum / Double(2 * residuals.count - 4)).squareRoot()
        }

        public func apply(_ p: Point) -> Point {
            Point(y: NumericCalculus.clean(a * p.y - b * p.x + ty), x: NumericCalculus.clean(b * p.y + a * p.x + tx))
        }
    }

    /// The transformation fitted by least squares to identical points (source → target).
    public static func helmert(_ pairs: [(source: Point, target: Point)]) throws(MathError) -> Helmert {
        guard pairs.count >= 2 else { throw .domain("potrebni sta vsaj dve identični točki") }
        let n = Double(pairs.count)
        let sy = pairs.reduce(0) { $0 + $1.source.y } / n, sx = pairs.reduce(0) { $0 + $1.source.x } / n
        let ty = pairs.reduce(0) { $0 + $1.target.y } / n, tx = pairs.reduce(0) { $0 + $1.target.x } / n
        var squares = 0.0, alongA = 0.0, alongB = 0.0
        for pair in pairs {
            let u = pair.source.y - sy, v = pair.source.x - sx
            let up = pair.target.y - ty, vp = pair.target.x - tx
            squares += u * u + v * v
            alongA += u * up + v * vp
            alongB += u * vp - v * up
        }
        guard squares > 0 else { throw .domain("identične točke morajo biti različne") }
        let a = alongA / squares, b = alongB / squares
        var fit = Helmert(a: a, b: b, ty: ty - a * sy + b * sx, tx: tx - b * sy - a * sx, residuals: [])
        let transform = fit
        fit.residuals = pairs.map { pair in
            let p = transform.apply(pair.source)
            return Point(y: NumericCalculus.clean(p.y - pair.target.y), x: NumericCalculus.clean(p.x - pair.target.x))
        }
        return fit
    }

    // MARK: Sphere

    /// The great circle (ortodroma) between two points given by latitude φ and longitude λ: its
    /// length on a sphere of radius R and the azimuths at the start and at the end (nil for
    /// coincident or antipodal points, which no single great circle joins); nil when a latitude
    /// is outside ±90°.
    public static func greatCircle(latitude1 phi1: Double, longitude1 lambda1: Double, latitude2 phi2: Double, longitude2 lambda2: Double,
                                   radius: Double) -> (distance: Double, initialAzimuth: Double?, finalAzimuth: Double?)? {
        guard Swift.abs(phi1) <= .pi / 2, Swift.abs(phi2) <= .pi / 2, radius > 0 else { return nil }
        let dPhi = phi2 - phi1, dLambda = lambda2 - lambda1
        let h = sin(dPhi / 2) * sin(dPhi / 2) + cos(phi1) * cos(phi2) * sin(dLambda / 2) * sin(dLambda / 2)
        let sigma = 2 * atan2(h.squareRoot(), Swift.max(0, 1 - h).squareRoot())
        func azimuth(_ from: Double, _ to: Double, _ dl: Double) -> Double {
            normalized(atan2(sin(dl) * cos(to), cos(from) * sin(to) - sin(from) * cos(to) * cos(dl)))
        }
        guard sigma > 1e-12, sigma < .pi - 1e-12 else { return (radius * sigma, nil, nil) }
        return (radius * sigma, azimuth(phi1, phi2, dLambda), normalized(azimuth(phi2, phi1, -dLambda) + .pi))
    }

    /// The rhumb line (loksodroma) with a constant azimuth, the shorter way round; nil at a pole.
    public static func rhumbLine(latitude1 phi1: Double, longitude1 lambda1: Double, latitude2 phi2: Double, longitude2 lambda2: Double,
                                 radius: Double) -> (distance: Double, azimuth: Double)? {
        guard Swift.abs(phi1) < .pi / 2, Swift.abs(phi2) < .pi / 2 else { return nil }
        let dPhi = phi2 - phi1
        var dLambda = (lambda2 - lambda1).truncatingRemainder(dividingBy: 2 * .pi)
        if dLambda > .pi { dLambda -= 2 * .pi } else if dLambda < -.pi { dLambda += 2 * .pi }
        let dPsi = log(tan(.pi / 4 + phi2 / 2) / tan(.pi / 4 + phi1 / 2))
        let q = Swift.abs(dPsi) > 1e-12 ? dPhi / dPsi : cos(phi1)
        return (radius * (dPhi * dPhi + q * q * dLambda * dLambda).squareRoot(), normalized(atan2(dLambda, dPsi)))
    }
}
