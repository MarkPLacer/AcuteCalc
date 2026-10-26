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
            let roots = RootFinder.roots(f, in: 0...period, samples: 4000).filter { $0 < period - 1e-12 * period }
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

    /// Sign changes on the logarithmic grid x = ±10ᵘ, u ∈ [3, 15], refined with Brent. Only true
    /// zeros are kept (|f| tiny next to the neighbouring samples), so poles are rejected.
    static func rootsBeyondWindow(_ f: (Double) -> Double, samples: Int = 2000) -> [Double] {
        var roots: [Double] = []
        for side in [-1.0, 1.0] {
            let xs = (0...samples).map { side * pow(10, 3 + 12 * Double($0) / Double(samples)) }
            let ys = xs.map(f)
            var i = 0
            while i < samples {
                // A sample that lands exactly on a root is bridged by its neighbours.
                let j = ys[i + 1] == 0 && i + 1 < samples ? i + 2 : i + 1
                let ya = ys[i], yb = ys[j]
                if ya.isFinite, yb.isFinite, ya != 0, yb != 0, (ya < 0) != (yb < 0),
                   let r = RootFinder.brent(f, min(xs[i], xs[j]), max(xs[i], xs[j])) {
                    let v = f(r)
                    if v.isFinite, abs(v) <= 1e-9 * max(1, abs(ya), abs(yb))
                        || RootFinder.isSteepRoot(f, at: r, width: abs(xs[j] - xs[i])) {
                        roots.append(r)
                    }
                }
                i = j
            }
        }
        return roots.sorted()
    }
}
