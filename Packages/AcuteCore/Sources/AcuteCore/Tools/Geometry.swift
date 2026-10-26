import Foundation

/// A solved triangle: sides a, b, c opposite the angles α, β, γ (radians).
public struct Triangle: Hashable, Sendable {
    public var a: Double, b: Double, c: Double
    public var alpha: Double, beta: Double, gamma: Double

    public var perimeter: Double { a + b + c }
    /// Heron's formula.
    public var area: Double {
        let s = perimeter / 2
        return Swift.max(0, s * (s - a) * (s - b) * (s - c)).squareRoot()
    }
    /// Radius of the circumscribed circle R = a / (2 sin α).
    public var circumradius: Double { a / (2 * sin(alpha)) }
    /// Radius of the inscribed circle r = S / s.
    public var inradius: Double { area / (perimeter / 2) }
    public var heightA: Double { 2 * area / a }
    public var heightB: Double { 2 * area / b }
    public var heightC: Double { 2 * area / c }
    public var medianA: Double { 0.5 * (2 * b * b + 2 * c * c - a * a).squareRoot() }
    public var medianB: Double { 0.5 * (2 * a * a + 2 * c * c - b * b).squareRoot() }
    public var medianC: Double { 0.5 * (2 * a * a + 2 * b * b - c * c).squareRoot() }

    public var isRight: Bool { [alpha, beta, gamma].contains { Swift.abs($0 - .pi / 2) < 1e-9 } }
}

/// Known parts of a triangle (angles in radians).
public struct TriangleInput: Hashable, Sendable {
    public var a: Double?, b: Double?, c: Double?
    public var alpha: Double?, beta: Double?, gamma: Double?

    public init(a: Double? = nil, b: Double? = nil, c: Double? = nil, alpha: Double? = nil, beta: Double? = nil, gamma: Double? = nil) {
        self.a = a; self.b = b; self.c = c
        self.alpha = alpha; self.beta = beta; self.gamma = gamma
    }
}

/// Solves a triangle from three known parts (SSS, SAS, ASA, AAS, SSA with both solutions).
public enum TriangleSolver {
    public static func solve(_ input: TriangleInput) throws(MathError) -> [Triangle] {
        let sides = [input.a, input.b, input.c]
        let angles = [input.alpha, input.beta, input.gamma]
        for s in sides.compactMap({ $0 }) where !(s > 0) { throw .domain("stranice morajo biti pozitivne") }
        for t in angles.compactMap({ $0 }) where !(t > 0 && t < .pi) { throw .domain("koti morajo biti med 0° in 180°") }
        let knownSides = sides.compactMap { $0 }.count
        let knownAngles = angles.compactMap { $0 }.count
        guard knownSides + knownAngles >= 3 else { throw .domain("vnesi tri podatke, vsaj eno stranico") }
        guard knownSides >= 1 else { throw .domain("iz samih kotov velikosti ni mogoče določiti") }

        // Two angles → the third.
        var A = angles
        if knownAngles >= 2 {
            let sum = A.compactMap { $0 }.reduce(0, +)
            if knownAngles == 3 {
                guard Swift.abs(sum - .pi) < 1e-9 else { throw .domain("vsota kotov mora biti 180°") }
            } else {
                guard sum < .pi else { throw .domain("vsota kotov mora biti manjša od 180°") }
                if let i = A.firstIndex(where: { $0 == nil }) { A[i] = .pi - sum }
            }
        }
        var S = sides

        if knownSides == 3 {
            let (a, b, c) = (S[0]!, S[1]!, S[2]!)
            guard a + b > c, a + c > b, b + c > a else { throw .domain("stranice ne zadoščajo trikotniški neenakosti") }
            return [fromSides(a, b, c)]
        }

        if A.allSatisfy({ $0 != nil }) {
            // ASA / AAS: law of sines from the known side.
            guard let k = S.firstIndex(where: { $0 != nil }) else { throw .domain("manjka stranica") }
            let ratio = S[k]! / sin(A[k]!)
            for i in 0..<3 where S[i] == nil { S[i] = ratio * sin(A[i]!) }
            return [Triangle(a: S[0]!, b: S[1]!, c: S[2]!, alpha: A[0]!, beta: A[1]!, gamma: A[2]!)]
        }

        // Two sides and one angle.
        guard knownSides == 2, let angleIndex = A.firstIndex(where: { $0 != nil }) else { throw .domain("premalo podatkov") }
        let angle = A[angleIndex]!
        if S[angleIndex] == nil {
            // SAS: the angle lies between the known sides → law of cosines.
            let others = (0..<3).filter { $0 != angleIndex }
            let x = S[others[0]]!, y = S[others[1]]!
            S[angleIndex] = (x * x + y * y - 2 * x * y * cos(angle)).squareRoot()
            return [fromSides(S[0]!, S[1]!, S[2]!)]
        }
        // SSA: the angle is opposite a known side → law of sines, possibly two triangles.
        let opposite = S[angleIndex]!
        guard let other = (0..<3).first(where: { $0 != angleIndex && S[$0] != nil }) else { throw .domain("premalo podatkov") }
        let sine = S[other]! * sin(angle) / opposite
        guard sine <= 1 + 1e-12 else { return [] }
        // sin β = 1 up to rounding (a = b·sin α, e.g. 5, 10, 30°): a single right triangle, not two
        // copies with β = 90° ± 10⁻⁶°.
        let first = sine >= 1 - 1e-12 ? Double.pi / 2 : asin(sine)
        var solutions: [Triangle] = []
        for candidate in Set([first, .pi - first]) where candidate > 0 && angle + candidate < .pi - 1e-12 {
            var angles = [Double?](repeating: nil, count: 3)
            angles[angleIndex] = angle
            angles[other] = candidate
            let third = (0..<3).first { angles[$0] == nil }!
            angles[third] = .pi - angle - candidate
            var sidesCopy = S
            sidesCopy[third] = opposite / sin(angle) * sin(angles[third]!)
            solutions.append(Triangle(a: sidesCopy[0]!, b: sidesCopy[1]!, c: sidesCopy[2]!, alpha: angles[0]!, beta: angles[1]!, gamma: angles[2]!))
        }
        return solutions.sorted { $0.gamma < $1.gamma }
    }

    static func fromSides(_ a: Double, _ b: Double, _ c: Double) -> Triangle {
        func angle(_ opposite: Double, _ x: Double, _ y: Double) -> Double {
            acos(Swift.max(-1, Swift.min(1, (x * x + y * y - opposite * opposite) / (2 * x * y))))
        }
        let alpha = angle(a, b, c)
        let beta = angle(b, a, c)
        return Triangle(a: a, b: b, c: c, alpha: alpha, beta: beta, gamma: .pi - alpha - beta)
    }
}

/// Vectors in the plane and space (school notation a⃗ = (x, y, z)).
public enum VectorGeometry {
    public static func length(_ v: [Double]) -> Double { v.reduce(0) { $0 + $1 * $1 }.squareRoot() }

    public static func dot(_ a: [Double], _ b: [Double]) -> Double { zip(a, b).reduce(0) { $0 + $1.0 * $1.1 } }

    public static func cross(_ a: [Double], _ b: [Double]) -> [Double] {
        let x = a + Array(repeating: 0, count: Swift.max(0, 3 - a.count))
        let y = b + Array(repeating: 0, count: Swift.max(0, 3 - b.count))
        return [x[1] * y[2] - x[2] * y[1], x[2] * y[0] - x[0] * y[2], x[0] * y[1] - x[1] * y[0]]
    }

    /// Angle between two vectors in radians.
    public static func angle(_ a: [Double], _ b: [Double]) -> Double? {
        let l = length(a) * length(b)
        guard l > 0 else { return nil }
        return acos(Swift.max(-1, Swift.min(1, dot(a, b) / l)))
    }

    /// Area of the parallelogram spanned by a and b (twice the triangle area).
    public static func parallelogramArea(_ a: [Double], _ b: [Double]) -> Double { length(cross(a, b)) }

    /// Mixed product (a × b)·c: signed volume of the parallelepiped.
    public static func mixedProduct(_ a: [Double], _ b: [Double], _ c: [Double]) -> Double { dot(cross(a, b), c + Array(repeating: 0, count: Swift.max(0, 3 - c.count))) }

    /// Projection of a onto b.
    public static func projection(_ a: [Double], onto b: [Double]) -> [Double]? {
        let bb = dot(b, b)
        guard bb > 0 else { return nil }
        let k = dot(a, b) / bb
        return b.map { $0 * k }
    }
}
