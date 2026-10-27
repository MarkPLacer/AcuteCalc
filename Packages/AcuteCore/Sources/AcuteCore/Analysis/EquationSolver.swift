import Foundation

public struct EquationSolution: Sendable, Hashable {
    public var value: Double
    public var exact: ExactReal?
    /// Closed form that is not an `ExactReal` (e.g. log₇ 2).
    public var closedForm: Expr?

    public init(value: Double, exact: ExactReal? = nil, closedForm: Expr? = nil) {
        self.value = value
        self.exact = exact
        self.closedForm = closedForm
    }

    /// Best exact expression for display, if any.
    public var exactExpr: Expr? { exact?.expr ?? closedForm }
}

public struct EquationResult: Sendable {
    public var variable: String
    public var solutions: [EquationSolution]
    /// When the equation is periodic, `solutions` cover one period and all solutions are `x + k·period`.
    public var period: Double?
    public var isIdentity = false
    public var complexSolutions: [Complex] = []
    public var searchedRange: ClosedRange<Double>?
}

/// Solves `lhs = rhs` for one unknown: exactly for polynomials (rational roots and
/// surds), numerically otherwise, with periodicity detection for trigonometric equations.
public enum EquationSolver {
    public static func solve(lhs: Expr, rhs: Expr, variable: String = "x", context: EvaluationContext, range: ClosedRange<Double>? = nil) throws(MathError) -> EquationResult {
        let difference = Simplifier.simplify(.sum([lhs, .negation(rhs)]))
        var result = EquationResult(variable: variable, solutions: [])
        guard difference.dependsOn(variable) else {
            // No unknown left: either always true or never.
            let value = try RealEvaluator.evaluate(difference, context: context)
            result.isIdentity = abs(value) < 1e-12
            return result
        }

        if let polynomial = Polynomial.extract(from: difference, variable: variable), polynomial.degree >= 1 {
            // Repeated roots (x² − 5)² are solved once, from the square-free part p / gcd(p, p′).
            let distinct = polynomial.squareFreePart()
            if let exact = polynomial.exactRealRoots() ?? distinct?.exactRealRoots() {
                result.solutions = exact.map { EquationSolution(value: $0.doubleValue, exact: $0) }
            } else {
                result.solutions = polynomial.realRoots().map { x in
                    EquationSolution(value: x, exact: FunctionAnalyzer.exactValue(x) { abs(polynomial.evaluate($0.doubleValue)) < 1e-9 })
                }
            }
            result.complexSolutions = (distinct ?? polynomial).complexRoots().filter { $0.im != 0 }.sorted { ($0.re, $0.im) < ($1.re, $1.im) }
            return result
        }

        // Exponential equations via t = aˣ (exact solutions like log₇ 2).
        if let substituted = ExponentialSubstitution.solve(lhs: lhs, rhs: rhs, variable: variable), !substituted.isEmpty {
            result.solutions = substituted.map { solution in
                let rational = ExactRecognizer.recognize(solution.value).flatMap { $0.isRational ? $0 : nil }
                return EquationSolution(value: solution.value, exact: rational, closedForm: solution.expr)
            }.sorted { $0.value < $1.value }
            return result
        }

        let f = FunctionAnalyzer.makeFunction(difference, variable: variable, context: context)

        // Identity check (e.g. sin²x + cos²x = 1)
        let probes = [-3.7, -1.3, 0.4, 1.9, 5.3, 11.1]
        let probeValues = probes.map(f).filter(\.isFinite)
        if probeValues.count >= 4, probeValues.allSatisfy({ abs($0) < 1e-11 }) {
            result.isIdentity = true
            return result
        }

        if range == nil, let period = FunctionAnalyzer.detectPeriod(f, angleUnit: context.angleUnit) {
            var roots = RootFinder.roots(f, in: 0...period, samples: 4000).filter { $0 < period - 1e-12 * period }
            // A solution at x ≡ 0 can come out a few ulps below 0 (2cos(x − π/3) = 1: f(0) = 2·10⁻¹⁶,
            // root at −1.3·10⁻¹⁶) with its copy beyond the grid near `period`, so 0 is judged on its own.
            if roots.first.map({ $0 > 1e-12 * period }) ?? true, isRootAtZero(f, step: period / 4000, period: period) {
                roots.insert(0, at: 0)
            }
            result.period = period
            result.searchedRange = 0...period
            result.solutions = roots.map { x in
                EquationSolution(value: x, exact: FunctionAnalyzer.exactValue(x) { abs(f($0.doubleValue)) < 1e-9 })
            }
            return result
        }

        let searchRange = range ?? -1000...1000
        result.searchedRange = searchRange
        var roots = RootFinder.roots(f, in: max(searchRange.lowerBound, -20)...min(searchRange.upperBound, 20), samples: 8000)
        if range == nil {
            for r in RootFinder.roots(f, in: searchRange, samples: 20000) where !roots.contains(where: { abs($0 - r) < 1e-6 * max(1, abs(r)) }) {
                roots.append(r)
            }
            // Nothing in the windows: the solution may lie beyond them (log x = 4 → x = 10⁴).
            if roots.isEmpty { roots = rootsBeyondWindow(f) }
        }
        result.solutions = roots.sorted().map { x in
            EquationSolution(value: x, exact: FunctionAnalyzer.exactValue(x) { abs(f($0.doubleValue)) < 1e-9 })
        }
        return result
    }

    /// Whether x = 0 solves a periodic equation although the scan of [0, period] missed it: f(0) is
    /// tiny next to f(±step) and f changes sign within 10⁻¹² periods left of 0, or f keeps its sign
    /// and |f| is smallest at 0 (sin²(x − π) = 0). A pole at 0 has a huge f(0) and is rejected, and so
    /// is a jump (fpart(x + 1) = 10⁻¹⁰ jumps from 1 to 0 at x = 0): f must stay small on both sides.
    static func isRootAtZero(_ f: (Double) -> Double, step: Double, period: Double) -> Bool {
        let y = f(0), left = f(-step), right = f(step)
        let tolerance = 1e-9 * max(1, min(max(abs(left), abs(right)), 1e6))
        guard y != 0, y.isFinite, left.isFinite, right.isFinite, left != 0, right != 0, abs(y) <= tolerance else { return false }
        func continuous(at r: Double) -> Bool {
            let d = 4 * (2 * Double.ulpOfOne * abs(r) + 0.5e-15)
            return abs(f(r - d)) <= tolerance && abs(f(r + d)) <= tolerance
        }
        if (left < 0) != (y < 0) {
            guard let r = RootFinder.brent(f, -step, 0), r >= -1e-12 * period else { return false }
            return continuous(at: r) || RootFinder.isSteepRoot(f, at: r, width: step)
        }
        return (right < 0) == (y < 0) && abs(y) <= abs(left) && abs(y) <= abs(right) && continuous(at: 0)
    }

    /// Roots on the logarithmic grid x = ±10ᵘ, u ∈ [3, 15] (2000 steps per side, both ends included):
    /// sign changes refined with Brent (true zeros or steep roots, so poles are rejected), samples that
    /// are exactly 0, and minima of |f| that reach 0 ((√x − 1000)² = 0 at 10⁶) with RootFinder's local
    /// tolerance. Far out, rounding alone makes f vanish or change sign ((1 + 1/x)ˣ − e beyond 10⁷), so
    /// a root must also look like one, and roots that crowd together are dropped as rounding noise.
    static func rootsBeyondWindow(_ f: (Double) -> Double, samples: Int = 2000) -> [Double] {
        var roots: [Double] = []
        func add(_ r: Double) {
            if !roots.contains(where: { abs($0 - r) < 1e-6 * max(1, abs(r)) }) { roots.append(r) }
        }
        // At six distances h/4⁵ … h, |f| grows away from r (by 1.3 per step) with the same signs on each
        // side every time: opposite for a crossing, equal for a touching root. Noise keeps neither.
        func looksLikeRoot(_ r: Double, _ h: Double, crossing: Bool?) -> Bool {
            var previous = 0.0
            var signs: (Bool, Bool)?
            for k in stride(from: 5, through: 0, by: -1) {
                let d = h / pow(4, Double(k))
                let a = f(r - d), b = f(r + d)
                guard a.isFinite, b.isFinite, a != 0, b != 0, max(abs(a), abs(b)) >= 1.3 * previous else { return false }
                if let s = signs {
                    guard s == (a < 0, b < 0) else { return false }
                } else {
                    if let crossing, crossing != ((a < 0) != (b < 0)) { return false }
                    signs = (a < 0, b < 0)
                }
                previous = max(abs(a), abs(b))
            }
            return true
        }
        for side in [-1.0, 1.0] {
            let xs = (0...samples).map { k -> Double in
                let u = 3 + 12 * Double(k) / Double(samples)
                // Whole decades exactly (10³, 10⁶ … 10¹⁵): pow(10, 15) need not be 10¹⁵ in every libm,
                // and ∛(x − 10¹⁵) = 0 has its root on the last sample.
                let x = u == u.rounded() ? (0..<Int(u)).reduce(1.0, { power, _ in power * 10 }) : pow(10, u)
                return side * x
            }
            let ys = xs.map(f)
            for i in 0...samples {
                let y = ys[i]
                guard y.isFinite else { continue }
                let neighbours = [i > 0 ? ys[i - 1] : .nan, i < samples ? ys[i + 1] : .nan].filter(\.isFinite)
                // Next to values under 1e-250 a zero or a minimum is underflow, not a root.
                let scale = neighbours.map { abs($0) }.max() ?? 0
                guard scale >= 1e-250 else { continue }
                let h = abs(xs[min(i + 1, samples)] - xs[max(i - 1, 0)]) / 2
                if y == 0 {
                    // ±1000 itself belongs to the window.
                    if i > 0, looksLikeRoot(xs[i], h, crossing: nil) { add(xs[i]) }
                    continue
                }
                if i < samples, ys[i + 1].isFinite, ys[i + 1] != 0, (y < 0) != (ys[i + 1] < 0) {
                    let lower = min(xs[i], xs[i + 1]), upper = max(xs[i], xs[i + 1])
                    if let r = RootFinder.brent(f, lower, upper) {
                        let v = f(r)
                        if v.isFinite, abs(v) <= 1e-9 * max(1, abs(y), abs(ys[i + 1])) || RootFinder.isSteepRoot(f, at: r, width: upper - lower),
                           looksLikeRoot(r, upper - lower, crossing: true) {
                            add(r)
                        }
                    }
                    continue
                }
                if i > 0, i < samples, ys[i - 1].isFinite, ys[i + 1].isFinite, abs(y) <= abs(ys[i - 1]), abs(y) <= abs(ys[i + 1]) {
                    let r = RootFinder.minimize({ abs(f($0)) }, min(xs[i - 1], xs[i + 1]), max(xs[i - 1], xs[i + 1]))
                    let v = f(r)
                    if v.isFinite, abs(v) <= 1e-9 * max(1, min(scale, 1e6)), looksLikeRoot(r, h, crossing: false) { add(r) }
                }
            }
        }
        // A real solution this far out stands alone; more than 3 within a factor of 10 is noise.
        let alone = roots.filter { r in
            roots.filter { ($0 > 0) == (r > 0) && abs(log10(abs($0) / abs(r))) <= 1 }.count <= 3
        }
        return alone.sorted()
    }
}
