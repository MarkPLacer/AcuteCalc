import Foundation

/// A notable point on a graph.
public struct SpecialPoint: Sendable, Hashable, Identifiable {
    public enum Kind: String, Sendable, Hashable, CaseIterable {
        case zero, maximum, minimum, inflection, yIntercept, intersection, hole
        /// Ends of the pieces of a piecewise function (bound included / excluded).
        case closedEnd, openEnd

        public var title: String {
            switch self {
            case .zero: "Ničla"
            case .maximum: "Maksimum"
            case .minimum: "Minimum"
            case .inflection: "Prevoj"
            case .yIntercept: "Začetna vrednost"
            case .intersection: "Presečišče"
            case .hole: "Luknja"
            case .closedEnd: "Krajišče"
            case .openEnd: "Krajišče (ni vključeno)"
            }
        }
    }

    public var kind: Kind
    public var x: Double
    public var y: Double
    public var exactX: ExactReal?
    public var exactY: ExactReal?
    /// Index of the second curve for intersections.
    public var otherCurve: Int?
    /// Angle between the two curves at an intersection (radians, 0…π/2).
    public var angle: Double?

    public var id: String { "\(kind.rawValue)|\(x)|\(y)|\(otherCurve ?? -1)" }

    public init(kind: Kind, x: Double, y: Double, exactX: ExactReal? = nil, exactY: ExactReal? = nil, otherCurve: Int? = nil, angle: Double? = nil) {
        self.kind = kind
        self.x = x
        self.y = y
        self.exactX = exactX
        self.exactY = exactY
        self.otherCurve = otherCurve
        self.angle = angle
    }

    /// The angle between two curves with slopes `k1` and `k2` (vertical tangents allowed).
    public static func intersectionAngle(slope k1: Double, slope k2: Double) -> Double? {
        var angle = Swift.abs(atan(k1) - atan(k2))
        if angle > .pi / 2 { angle = .pi - angle }
        return angle.isFinite ? angle : nil
    }
}

public struct Line2D: Sendable, Hashable {
    public var slope: Double
    public var intercept: Double
}

/// Full analysis of y = f(x) on an interval ("analiza funkcije").
public struct FunctionAnalysis: Sendable {
    public var range: ClosedRange<Double>
    public var zeros: [SpecialPoint] = []
    public var extrema: [SpecialPoint] = []
    public var inflections: [SpecialPoint] = []
    public var yIntercept: SpecialPoint?
    public var poles: [Double] = []
    public var horizontalAsymptoteLeft: Double?
    public var horizontalAsymptoteRight: Double?
    public var obliqueAsymptote: Line2D?
    public var increasing: [ClosedRange<Double>] = []
    public var decreasing: [ClosedRange<Double>] = []
    public var convex: [ClosedRange<Double>] = []
    public var concave: [ClosedRange<Double>] = []
    public var derivative: Expr?
    public var secondDerivative: Expr?
    public var isEven = false
    public var isOdd = false
    public var period: Double?

    public var allPoints: [SpecialPoint] {
        zeros + extrema + inflections + (yIntercept.map { [$0] } ?? [])
    }
}

public enum FunctionAnalyzer {
    /// Builds a fast evaluator for `expr` in `variable` (bytecode, falling back to the tree walker).
    public static func makeFunction(_ expr: Expr, variable: String, context: EvaluationContext) -> (Double) -> Double {
        let compiler = BytecodeCompiler(slots: [variable: .x], angleUnit: context.angleUnit, constants: context.variables)
        if let program = try? compiler.compile(expr) {
            let vm = RealVM(program: program)
            return { vm.evaluate(x: $0) }
        }
        return NumericCalculus.sampler(expr, variable: variable, context: context)
    }

    static func exactValue(_ x: Double, verify f: ((ExactReal) -> Bool)? = nil) -> ExactReal? {
        guard let candidate = ExactRecognizer.recognize(x) else { return nil }
        if let f, !f(candidate) { return nil }
        return candidate
    }

    public static func analyze(_ expr: Expr, variable: String = "x", range: ClosedRange<Double>, context: EvaluationContext, includeAsymptotes: Bool = true) -> FunctionAnalysis {
        var analysis = FunctionAnalysis(range: range)
        let f = makeFunction(expr, variable: variable, context: context)
        let derivative = try? Differentiator.derivative(of: expr, withRespectTo: variable, angleUnit: context.angleUnit)
        let second = derivative.flatMap { try? Differentiator.derivative(of: $0, withRespectTo: variable, angleUnit: context.angleUnit) }
        analysis.derivative = derivative
        analysis.secondDerivative = second
        let df: (Double) -> Double = derivative.map { makeFunction($0, variable: variable, context: context) } ?? { NumericCalculus.derivative(of: f, at: $0) }
        let d2f: (Double) -> Double = second.map { makeFunction($0, variable: variable, context: context) } ?? { NumericCalculus.secondDerivative(of: f, at: $0) }

        let polynomial = Polynomial.extract(from: expr, variable: variable)
        let exactPolynomialRoots = polynomial?.exactRealRoots()

        // Zeros
        let zeroXs = RootFinder.roots(f, in: range)
        analysis.zeros = zeroXs.map { x in
            var exact: ExactReal?
            if let roots = exactPolynomialRoots {
                exact = roots.min { abs($0.doubleValue - x) < abs($1.doubleValue - x) }.flatMap { abs($0.doubleValue - x) < 1e-7 * max(1, abs(x)) ? $0 : nil }
            } else {
                exact = exactValue(x) { candidate in abs(f(candidate.doubleValue)) <= max(1e-10, abs(f(x)) * 10) }
            }
            return SpecialPoint(kind: .zero, x: exact?.doubleValue ?? x, y: 0, exactX: exact, exactY: .zero)
        }

        // Extrema from sign changes of f′
        for (x, risingAfter) in RootFinder.signChanges(df, in: range) {
            let y = f(x)
            guard y.isFinite else { continue }
            let exactX = exactValue(x) { candidate in abs(df(candidate.doubleValue)) <= max(1e-9, abs(df(x)) * 10) }
            let yValue = exactX.map { f($0.doubleValue) } ?? y
            let exactY = exactX.flatMap { ex in ExactEvaluator.value(expr, angleUnit: context.angleUnit, variables: [variable: ex]) }
            analysis.extrema.append(SpecialPoint(kind: risingAfter ? .minimum : .maximum, x: exactX?.doubleValue ?? x, y: NumericCalculus.clean(yValue), exactX: exactX, exactY: exactY))
        }

        // Inflection points from sign changes of f″
        for (x, _) in RootFinder.signChanges(d2f, in: range) {
            let y = f(x)
            guard y.isFinite else { continue }
            let exactX = exactValue(x) { candidate in abs(d2f(candidate.doubleValue)) <= max(1e-8, abs(d2f(x)) * 10) }
            let exactY = exactX.flatMap { ex in ExactEvaluator.value(expr, angleUnit: context.angleUnit, variables: [variable: ex]) }
            analysis.inflections.append(SpecialPoint(kind: .inflection, x: exactX?.doubleValue ?? x, y: NumericCalculus.clean(y), exactX: exactX, exactY: exactY))
        }

        // y-intercept
        if range.contains(0) {
            let y0 = f(0)
            if y0.isFinite {
                let exactY = ExactEvaluator.value(expr, angleUnit: context.angleUnit, variables: [variable: .zero])
                analysis.yIntercept = SpecialPoint(kind: .yIntercept, x: 0, y: NumericCalculus.clean(y0), exactX: .zero, exactY: exactY)
            }
        }

        // Poles: zeros of 1/f where |f| blows up. The VM gives NaN where a denominator is exactly 0,
        // so a sample or a Brent step that lands on the pole (x = 2 of 1/(x − 2) on −10…10) looks
        // 10⁻¹² of the interval beside it (not at x.nextUp: the square of 0.nextUp is 0 again, 1/x²).
        let width = range.upperBound - range.lowerBound
        let reciprocal: (Double) -> Double = { x in
            var v = f(x)
            if v.isNaN { v = f(x + width * 1e-12) }
            if v.isInfinite { return 0 }
            return v.isNaN ? .nan : 1 / v
        }
        analysis.poles = RootFinder.roots(reciprocal, in: range).filter { p in
            let d = width * 1e-6
            let l = abs(f(p - d)), r = abs(f(p + d))
            if (l.isFinite && l > 1e5) || (r.isFinite && r > 1e5) || l.isInfinite || r.isInfinite { return true }
            // Scale-free as well: beside a pole |f| grows over 10× from 100·d to d (100ᵐ for order m),
            // so a small residue is kept too (|f(2 ± d)| = 5·10⁴ for 1/(x − 2) on −10…10, tan x).
            return [-1.0, 1.0].contains { side in
                let near = abs(f(p + side * d)), far = abs(f(p + side * 100 * d))
                return near.isInfinite || (near.isFinite && far.isFinite && near > 10 * far)
            }
        }.map(NumericCalculus.clean)  // Brent stops ~10⁻¹⁵ beside the pole (1/x: "x = −9,3·10⁻¹⁶").

        if includeAsymptotes {
            analysis.horizontalAsymptoteLeft = NumericCalculus.limit(of: f, at: -.infinity).flatMap { $0.isFinite ? $0 : nil }
            analysis.horizontalAsymptoteRight = NumericCalculus.limit(of: f, at: .infinity).flatMap { $0.isFinite ? $0 : nil }
            if analysis.horizontalAsymptoteRight == nil,
               let k = NumericCalculus.limit(of: { f($0) / $0 }, at: .infinity), k.isFinite, k != 0,
               let n = NumericCalculus.limit(of: { f($0) - k * $0 }, at: .infinity), n.isFinite,
               approaches(f, slope: k, intercept: n) {
                analysis.obliqueAsymptote = Line2D(slope: k, intercept: n)
            }
        }

        // Monotonicity and convexity between critical points.
        let breaks = (analysis.extrema.map(\.x) + analysis.poles + [range.lowerBound, range.upperBound]).sorted()
        for (a, b) in zip(breaks, breaks.dropFirst()) where b - a > width * 1e-9 {
            let slope = df(0.5 * (a + b))
            guard slope.isFinite, slope != 0 else { continue }
            if slope > 0 { analysis.increasing.append(a...b) } else { analysis.decreasing.append(a...b) }
        }
        let curvatureBreaks = (analysis.inflections.map(\.x) + analysis.poles + [range.lowerBound, range.upperBound]).sorted()
        for (a, b) in zip(curvatureBreaks, curvatureBreaks.dropFirst()) where b - a > width * 1e-9 {
            let curvature = d2f(0.5 * (a + b))
            guard curvature.isFinite, curvature != 0 else { continue }
            if curvature > 0 { analysis.convex.append(a...b) } else { analysis.concave.append(a...b) }
        }

        // Parity
        let probes = [0.37, 1.13, 2.71, 4.4, 7.9]
        var even = true, odd = true, any = false
        for p in probes {
            let a = f(p), b = f(-p)
            guard a.isFinite, b.isFinite else { continue }
            any = true
            if abs(a - b) > 1e-9 * max(1, abs(a)) { even = false }
            if abs(a + b) > 1e-9 * max(1, abs(a)) { odd = false }
        }
        analysis.isEven = any && even
        analysis.isOdd = any && odd && !even
        analysis.period = detectPeriod(f, angleUnit: context.angleUnit)
        return analysis
    }

    /// Whether f really comes close to y = kx + n for large x. The extrapolated limits of an
    /// oscillating f (sin x) give a tiny slope and an arbitrary intercept: a stray line. The gap
    /// just past x = 10⁵, 10⁶ and 10⁷ must end small without having grown (x + sin(x)/x), or
    /// shrink steadily by a factor of 3 or more per decade (x + c/x, even for c = 10⁸ whose gap is
    /// still 10 at 10⁷). The limits sample whole numbers, where x + sin(πx) and x + cos(2πx) look
    /// like lines, so the probes are not whole numbers.
    static func approaches(_ f: (Double) -> Double, slope k: Double, intercept n: Double) -> Bool {
        // 0.618… (the golden ratio) is far from every fraction with a small denominator.
        let probes = [1e5, 1e6, 1e7].map { $0 + 0.6180339887498949 }
        let gaps = probes.map { x in abs(f(x) - (k * x + n)) }
        guard gaps.allSatisfy(\.isFinite) else { return false }
        // The rounding of f(x) and of k·x at x = 10⁷.
        let noise = 1e-12 * Swift.max(1, abs(k) * 1e7, abs(n))
        if gaps[2] <= 1e-3 * Swift.max(1, abs(n)), gaps[2] <= gaps[0] + noise { return true }
        return gaps[1] <= gaps[0] / 3 + noise && gaps[2] <= gaps[1] / 3 + noise
    }

    /// Detects common periods (2π, π, π/2 and their degree equivalents, or 1 for frac/floor shapes).
    public static func detectPeriod(_ f: (Double) -> Double, angleUnit: AngleUnit) -> Double? {
        let turn = angleUnit.fullTurn
        let candidates = [turn / 4, turn / 2, turn, turn * 2, 1, 2]
        let probes = [0.123, 0.789, 1.456, 2.345, 3.21, 5.67]
        for p in candidates.sorted() {
            var ok = true
            var tested = 0
            for x in probes {
                let a = f(x), b = f(x + p), c = f(x + 3 * p)
                guard a.isFinite, b.isFinite, c.isFinite else { continue }
                tested += 1
                if abs(a - b) > 1e-9 * max(1, abs(a)) || abs(a - c) > 1e-9 * max(1, abs(a)) { ok = false; break }
            }
            if ok && tested >= 3 {
                // Reject constants.
                let values = probes.map(f).filter(\.isFinite)
                if let mn = values.min(), let mx = values.max(), mx - mn > 1e-12 { return p }
                return nil
            }
        }
        return nil
    }

    /// Intersections of y = f(x) and y = g(x) on the range.
    public static func intersections(_ f: Expr, _ g: Expr, variable: String = "x", range: ClosedRange<Double>, context: EvaluationContext, otherCurve: Int? = nil) -> [SpecialPoint] {
        let difference = Expr.sum([f, .negation(g)])
        let h = makeFunction(difference, variable: variable, context: context)
        let fy = makeFunction(f, variable: variable, context: context)
        let exactRoots = Polynomial.extract(from: difference, variable: variable)?.exactRealRoots()
        return RootFinder.roots(h, in: range).compactMap { x in
            let y = fy(x)
            guard y.isFinite else { return nil }
            var exactX: ExactReal?
            if let roots = exactRoots {
                exactX = roots.first { abs($0.doubleValue - x) < 1e-7 * max(1, abs(x)) }
            } else {
                exactX = exactValue(x) { candidate in abs(h(candidate.doubleValue)) <= max(1e-10, abs(h(x)) * 10) }
            }
            let exactY = exactX.flatMap { ex in ExactEvaluator.value(f, angleUnit: context.angleUnit, variables: [variable: ex]) }
            return SpecialPoint(kind: .intersection, x: exactX?.doubleValue ?? x, y: NumericCalculus.clean(exactY?.doubleValue ?? y), exactX: exactX, exactY: exactY, otherCurve: otherCurve)
        }
    }
}
