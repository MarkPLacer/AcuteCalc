import Foundation

/// Exponential equations that become polynomial after `t = aˣ`
/// (7ˣ + 7²ˣ + 7³ˣ = 14 → t + t² + t³ = 14 → t = 2 → x = log₇ 2).
public enum ExponentialSubstitution {
    public struct Solution: Sendable {
        /// Exact closed form, e.g. `log₇ 2`.
        public var expr: Expr
        public var value: Double
    }

    /// Returns the base a and multiplier k when `e` is a^(k·x) (or e^(k·x)).
    static func exponential(_ e: Expr, variable: String) -> (base: Expr, k: Rational)? {
        let base: Expr
        let exponent: Expr
        switch e {
        case .power(let b, let x):
            base = b; exponent = x
        case .function(.exp, let args) where args.count == 1:
            base = .constant(.e); exponent = args[0]
        default:
            return nil
        }
        guard !base.dependsOn(variable) else { return nil }
        // exponent must be k·x with rational k
        guard let poly = Polynomial.extract(from: exponent, variable: variable), poly.degree == 1,
              let exact = poly.exactCoefficients, exact[0].isZero else { return nil }
        return (base, exact[1])
    }

    /// Tries to solve `lhs = rhs` exactly via t = aˣ. Returns `nil` if the equation doesn't have that shape.
    public static func solve(lhs: Expr, rhs: Expr, variable: String = "x") -> [Solution]? {
        let difference = Simplifier.simplify(.sum([lhs, .negation(rhs)]))
        // Find all exponentials a^(k x) and check they share the base.
        var bases: [Expr] = []
        var multipliers: [Rational] = []
        func collect(_ e: Expr) {
            if let (b, k) = exponential(e, variable: variable) {
                bases.append(b)
                multipliers.append(k)
                return
            }
            for c in e.children { collect(c) }
        }
        collect(difference)
        guard let base = bases.first, bases.allSatisfy({ $0 == base }) else { return nil }
        // Common unit: t = a^(g·x) with g = gcd of the multipliers.
        var g = multipliers[0].magnitude
        for m in multipliers.dropFirst() {
            // gcd of rationals p/q: gcd(p)/lcm(q)
            let num = Rational.gcd(g.numerator, m.numerator)
            guard let den = Rational.lcm(g.denominator, m.denominator), let r = Rational(num, den) else { return nil }
            g = r
        }
        guard !g.isZero else { return nil }
        let t = Expr.variable("__t")
        // Replace a^(k x) by t^(k/g)
        func replace(_ e: Expr) -> Expr {
            if let (_, k) = exponential(e, variable: variable), let power = k.divided(by: g) {
                return power == .one ? t : .power(t, .number(power))
            }
            return e.mapChildren(replace)
        }
        let substituted = replace(difference)
        guard !substituted.dependsOn(variable),
              let polynomial = Polynomial.extract(from: substituted, variable: "__t"), polynomial.degree >= 1 else { return nil }
        let roots: [(ExactReal?, Double)]
        if let exact = polynomial.exactRealRoots() {
            roots = exact.map { ($0, $0.doubleValue) }
        } else {
            roots = polynomial.realRoots().map { (nil, $0) }
        }
        let baseValue = (try? RealEvaluator.evaluate(base)) ?? .nan
        guard baseValue > 0, baseValue != 1 else { return nil }
        var solutions: [Solution] = []
        for (exact, value) in roots where value > 0 {
            // a^(g x) = t  →  x = log_a(t) / g
            let x = Foundation.log(value) / Foundation.log(baseValue) / g.doubleValue
            let argument: Expr = exact.map { $0.expr } ?? .decimal(value)
            var expr: Expr
            if case .constant(.e) = base {
                expr = .function(.ln, [argument])
            } else if case .number(let r) = base, r == Rational(10) {
                expr = .function(.log10, [argument])
            } else {
                expr = .function(.log, [base, argument])
            }
            // log_a(1) = 0, log_a(a^k) = k: prefer exact numbers when possible.
            if let exactX = ExactRecognizer.recognize(x), exactX.isRational {
                expr = exactX.expr
            } else if g != .one {
                expr = .quotient(expr, .number(g))
            }
            solutions.append(Solution(expr: expr, value: x))
        }
        return solutions
    }
}

/// Taylor polynomials around a point, built from symbolic derivatives.
public enum TaylorSeries {
    /// Tₙ(x) = Σ_{k=0}^{n} f⁽ᵏ⁾(a)/k! · (x − a)ᵏ, as an expression in `variable`.
    public static func polynomial(of expr: Expr, variable: String = "x", around a: Double, order: Int, context: EvaluationContext) -> Expr? {
        var current = expr
        return polynomial(variable: variable, around: a, order: order, context: context) { k in
            if k > 0 {
                guard let next = try? Differentiator.derivative(of: current, withRespectTo: variable, angleUnit: context.angleUnit) else { return nil }
                current = next
            }
            return current
        }
    }

    /// Tₙ from given derivatives: `derivative(k)` is f⁽ᵏ⁾ in `variable` (f for k = 0, nil when it cannot be
    /// formed), asked for k = 0, 1, 2 … in turn. They depend on neither `a` nor the values in `context` (only
    /// on its angle unit), so a caller that draws Tₙ for changing parameters can keep them.
    public static func polynomial(variable: String = "x", around a: Double, order: Int, context: EvaluationContext, derivative: (Int) -> Expr?) -> Expr? {
        var terms: [Expr] = []
        var factorial = 1.0
        let x = Expr.variable(variable)
        let shift: Expr = a == 0 ? x : .sum([x, .decimal(-a)])
        for k in 0...max(0, min(order, 30)) {
            guard let current = derivative(k) else { return nil }
            if k > 0 { factorial *= Double(k) }
            var ctx = context
            ctx.variables[variable] = a
            guard let value = try? RealEvaluator.evaluate(current, context: ctx) else { return nil }
            // Noise is judged on f⁽ᵏ⁾(a) against the terms it was computed from (sin x at 0 has exact zeros);
            // f⁽ᵏ⁾(a)/k! itself may be tiny but genuine (1/16! = 4,8·10⁻¹⁴ for eˣ), which clean() dropped.
            if value == 0 { continue }
            if Swift.abs(value / factorial) < 1e-6 {
                let scale = CalculationEngine.noiseScale(current) { e in (try? RealEvaluator.evaluate(e, context: ctx)).map { Complex($0, 0) } }
                if CalculationEngine.withoutNoise(value, scale: scale.re) == 0 { continue }
            }
            let coefficient = NumericCalculus.roundNoise(value / factorial)
            // Below 1 the tolerance of `approximating` is absolute, so a tiny coefficient would become the fraction 0.
            let fraction = Rational.approximating(coefficient, maxDenominator: 100_000, tolerance: 1e-13).flatMap { $0.isZero ? nil : $0 }
            let coefficientExpr: Expr = fraction.map(Expr.number) ?? .decimal(coefficient)
            switch k {
            case 0: terms.append(coefficientExpr)
            case 1: terms.append(.product([coefficientExpr, shift]))
            default: terms.append(.product([coefficientExpr, .power(shift, .int(k))]))
            }
        }
        if terms.isEmpty { return .number(.zero) }
        return Simplifier.simplify(.sum(terms))
    }
}

/// Removable discontinuities ("luknje"): points where f is undefined but the limit exists.
public enum HoleFinder {
    public static func holes(_ expr: Expr, variable: String = "x", range: ClosedRange<Double>, context: EvaluationContext) -> [SpecialPoint] {
        // Candidates: zeros of every denominator in the expression.
        var denominators: [Expr] = []
        func collect(_ e: Expr) {
            switch e {
            case .quotient(_, let d): denominators.append(d)
            case .power(let b, let x):
                if let r = x.rationalValue, r.isNegative { denominators.append(b) }
            case .function(.cot, let args), .function(.csc, let args): denominators.append(.function(.sin, args))
            case .function(.tan, let args), .function(.sec, let args): denominators.append(.function(.cos, args))
            default: break
            }
            for c in e.children { collect(c) }
        }
        collect(expr)
        guard !denominators.isEmpty else { return [] }
        let f = FunctionAnalyzer.makeFunction(expr, variable: variable, context: context)
        var result: [SpecialPoint] = []
        for d in denominators where d.dependsOn(variable) {
            let g = FunctionAnalyzer.makeFunction(d, variable: variable, context: context)
            for root in RootFinder.roots(g, in: range, samples: 2000) {
                // Snap to the exact point (0 instead of 8.9e−16) so 0/0 is actually hit.
                let c = ExactRecognizer.recognize(root)?.doubleValue ?? root
                let value = f(c)
                guard !value.isFinite else { continue }
                if let l = try? LimitEvaluator.limit(f, at: c, direction: .both), l.isFinite,
                   !result.contains(where: { abs($0.x - c) < 1e-9 * max(1, abs(c)) }) {
                    let exactX = ExactRecognizer.recognize(c)
                    let exactY = ExactRecognizer.recognize(l)
                    result.append(SpecialPoint(kind: .hole, x: exactX?.doubleValue ?? c, y: l, exactX: exactX, exactY: exactY))
                }
            }
        }
        return result
    }
}
