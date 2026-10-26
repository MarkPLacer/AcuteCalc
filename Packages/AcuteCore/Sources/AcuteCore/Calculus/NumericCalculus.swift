import Foundation

/// Numeric differentiation and simple limits.
public enum NumericCalculus {
    /// Evaluates `body` at `variable = x` with the tree evaluator, returning NaN instead of throwing.
    static func sampler(_ body: Expr, variable: String, context: EvaluationContext) -> (Double) -> Double {
        var base = context
        base.variables[variable] = 0
        return { x in
            var ctx = base
            ctx.variables[variable] = x
            var evaluator = RealEvaluator(context: ctx)
            return (try? evaluator.eval(body)) ?? .nan
        }
    }

    /// Central differences with Richardson extrapolation (error ~h⁶).
    public static func derivative(_ body: Expr, variable: String, at x: Double, context: EvaluationContext) throws(MathError) -> Double {
        let f = sampler(body, variable: variable, context: context)
        let value = derivative(of: f, at: x)
        guard value.isFinite else { throw .domain("odvod v tej točki ne obstaja") }
        return value
    }

    public static func derivative(of f: (Double) -> Double, at x: Double) -> Double {
        let h = 1e-3 * Swift.max(1, abs(x))
        func d(_ step: Double) -> Double { (f(x + step) - f(x - step)) / (2 * step) }
        let d1 = d(h)
        let d2 = d(h / 2)
        let d3 = d(h / 4)
        let r1 = (4 * d2 - d1) / 3
        let r2 = (4 * d3 - d2) / 3
        return (16 * r2 - r1) / 15
    }

    public static func secondDerivative(of f: (Double) -> Double, at x: Double) -> Double {
        let h = 1e-3 * Swift.max(1, abs(x))
        func d(_ step: Double) -> Double { (f(x + step) - 2 * f(x) + f(x - step)) / (step * step) }
        let d1 = d(h)
        let d2 = d(h / 2)
        return (4 * d2 - d1) / 3
    }

    public enum LimitSide: Sendable { case left, right, both }

    /// Numeric limit `x → point` (point may be ±∞). Returns `nil` when the values don't settle.
    public static func limit(of f: (Double) -> Double, at point: Double, side: LimitSide = .both) -> Double? {
        if point.isInfinite {
            // x → ±∞ becomes t → 0⁺ with x = ±1/t, so the same extrapolation applies and
            // we never evaluate at huge x where (1 + 1/x)ˣ loses all precision.
            let sign: Double = point > 0 ? 1 : -1
            return LimitEvaluator.oneSided({ t in f(sign / t) }, 0, 1)
        }
        switch side {
        case .left: return LimitEvaluator.oneSided(f, point, -1)
        case .right: return LimitEvaluator.oneSided(f, point, 1)
        case .both:
            guard let l = LimitEvaluator.oneSided(f, point, -1), let r = LimitEvaluator.oneSided(f, point, 1) else { return nil }
            if l.isInfinite || r.isInfinite { return l == r ? l : nil }
            return abs(l - r) <= 1e-6 * Swift.max(1, abs(l)) ? clean((l + r) / 2) : nil
        }
    }

    /// Rounds away floating point noise (0.30000000000000004 → 0.3) while keeping 13 significant digits.
    public static func clean(_ x: Double) -> Double {
        guard x.isFinite, x != 0 else { return x }
        if abs(x) < 1e-14 { return 0 }
        let digits = 13 - Int(Foundation.floor(Foundation.log10(abs(x))))
        guard digits > 0, digits < 300 else { return x }
        let scale = pow(10, Double(digits))
        guard scale.isFinite else { return x }
        return (x * scale).rounded() / scale
    }
}

/// Adaptive Gauss–Kronrod (G7/K15) quadrature. Infinite ranges use a variable
/// substitution; slowly decaying oscillatory tails (∫ sin x / x dx) fall back to
/// summing the integral over consecutive half-periods with Wynn ε-extrapolation
/// (the idea behind QUADPACK's QAWF).
public enum Integrator {
    private static let xgk: [Double] = [
        0.991455371120812639206854697526329, 0.949107912342758524526189684047851,
        0.864864423359769072789712788640926, 0.741531185599394439863864773280788,
        0.586087235467691130294144845693013, 0.405845151377397166906606412076961,
        0.207784955007898467600689403773245, 0.0,
    ]
    private static let wgk: [Double] = [
        0.022935322010529224963732008058970, 0.063092092629978553290700663189204,
        0.104790010322250183839876322541518, 0.140653259715525918745189590510238,
        0.169004726639267902826583426598550, 0.190350578064785409913256402421014,
        0.204432940075298892414161999234649, 0.209482141084727828012999174891714,
    ]
    private static let wg: [Double] = [
        0.129484966168869693270611432679082, 0.279705391489276667901467771423780,
        0.381830050505118944950369775488975, 0.417959183673469387755102040816327,
    ]

    public static func integrate(_ body: Expr, variable: String, from a: Double, to b: Double, context: EvaluationContext) throws(MathError) -> Double {
        let f = FunctionAnalyzer.makeFunction(body, variable: variable, context: context)
        return try integrate(f, from: a, to: b)
    }

    public static func integrate(_ f: (Double) -> Double, from a: Double, to b: Double, tolerance: Double = 1e-11) throws(MathError) -> Double {
        if a.isNaN || b.isNaN { throw .domain("meje integrala") }
        if a == b { return 0 }
        if a > b { return -(try integrate(f, from: b, to: a, tolerance: tolerance)) }

        switch (a.isInfinite, b.isInfinite) {
        case (true, true):
            let left = try integrate(f, from: -.infinity, to: 0, tolerance: tolerance / 2)
            let right = try integrate(f, from: 0, to: .infinity, tolerance: tolerance / 2)
            return NumericCalculus.clean(left + right)
        case (true, false):
            // ∫ from −∞ to b of f(x) dx = ∫ from −b to ∞ of f(−u) du
            return try integrate({ f(-$0) }, from: -b, to: .infinity, tolerance: tolerance)
        case (false, true):
            return try integrateToInfinity(f, from: a, tolerance: tolerance)
        case (false, false):
            var budget = 80_000
            let (value, _) = adaptive(f, a, b, tolerance: tolerance, depth: 0, budget: &budget)
            guard value.isFinite else {
                throw value.isInfinite ? .domain("integral divergira") : .domain("integrand na intervalu ni definiran")
            }
            return NumericCalculus.clean(value)
        }
    }

    private static func integrateToInfinity(_ f: (Double) -> Double, from a: Double, tolerance: Double) throws(MathError) -> Double {
        // 1) Substitution x = a + t/(1−t) on [0, 1): accurate for integrands that decay fast.
        let g: (Double) -> Double = { t in
            let x = a + t / (1 - t)
            return f(x) / ((1 - t) * (1 - t))
        }
        var budget = 60_000
        let (mapped, error) = adaptive(g, 0, 1, tolerance: tolerance, depth: 0, budget: &budget)
        if mapped.isFinite, tailDecays(f, from: a), error <= 1e-8 * Swift.max(1, abs(mapped)) {
            return NumericCalculus.clean(mapped)
        }

        // 2) Oscillatory or slowly decaying tail: integrate lobe by lobe and extrapolate.
        let spacing = zeroSpacing(f, from: a) ?? 1.0
        var partialSums: [Double] = []
        var total = 0.0
        var lower = a
        if let firstZero = RootFinder.roots(f, in: a...(a + 2 * spacing), samples: 400).first(where: { $0 > a + 1e-12 }) {
            var initialBudget = 120_000
            total = adaptive(f, a, firstZero, tolerance: tolerance, depth: 0, budget: &initialBudget).0
            lower = firstZero
        }
        for _ in 0..<80 {
            var chunkBudget = 20_000
            let upper = lower + spacing
            let (chunk, _) = adaptive(f, lower, upper, tolerance: tolerance * 0.01, depth: 0, budget: &chunkBudget)
            guard chunk.isFinite else { break }
            total += chunk
            partialSums.append(total)
            lower = upper
        }
        guard partialSums.count >= 12 else { throw .domain("integral divergira") }
        // Divergence check: the contribution of each lobe must shrink.
        let n = partialSums.count
        let lateSize = (n - 6..<n).map { abs(partialSums[$0] - partialSums[$0 - 1]) }.max() ?? 0
        let earlySize = (1..<7).map { abs(partialSums[$0] - partialSums[$0 - 1]) }.max() ?? 1
        if lateSize > earlySize * 0.9 && lateSize > 1e-9 { throw .domain("integral divergira") }
        guard let value = SeriesAccelerator.wynnEpsilon(partialSums), value.isFinite else {
            throw .domain("integral ne konvergira")
        }
        return NumericCalculus.clean(value)
    }

    /// True when |x·f(x)| shrinks quickly (non-oscillating, integrable tail).
    private static func tailDecays(_ f: (Double) -> Double, from a: Double) -> Bool {
        let values = [1e2, 1e3, 1e4, 1e5].map { offset -> Double in
            let x = a + offset
            return abs(f(x)) * x
        }
        guard values.allSatisfy({ $0.isFinite }), let last = values.last else { return false }
        if last < 1e-6 { return true }
        return zip(values, values.dropFirst()).allSatisfy { pair in pair.1 < pair.0 * 0.2 }
    }

    /// Typical distance between consecutive sign changes away from the origin.
    private static func zeroSpacing(_ f: (Double) -> Double, from a: Double) -> Double? {
        let start = a + 10
        let zeros = RootFinder.roots(f, in: start...(start + 60), samples: 6000)
        guard zeros.count >= 4 else { return nil }
        let gaps = zip(zeros, zeros.dropFirst()).map { pair in pair.1 - pair.0 }
        let mean = gaps.reduce(0, +) / Double(gaps.count)
        return gaps.allSatisfy({ abs($0 - mean) < 0.05 * mean }) ? mean : nil
    }

    private static func adaptive(_ f: (Double) -> Double, _ a: Double, _ b: Double, tolerance: Double, depth: Int, budget: inout Int) -> (Double, Double) {
        let (value, error) = kronrod(f, a, b)
        budget -= 15
        if error <= Swift.max(tolerance, 1e-15 * abs(value)) || depth >= 40 || budget <= 0 || !value.isFinite {
            return (value, error)
        }
        let m = 0.5 * (a + b)
        let left = adaptive(f, a, m, tolerance: tolerance / 2, depth: depth + 1, budget: &budget)
        let right = adaptive(f, m, b, tolerance: tolerance / 2, depth: depth + 1, budget: &budget)
        return (left.0 + right.0, left.1 + right.1)
    }

    private static func kronrod(_ f: (Double) -> Double, _ a: Double, _ b: Double) -> (Double, Double) {
        let center = 0.5 * (a + b)
        let half = 0.5 * (b - a)
        func safe(_ x: Double) -> Double {
            let v = f(x)
            if v.isNaN {
                // Removable singularity (e.g. sin x / x at 0): nudge the node.
                return f(x + 1e-9 * Swift.max(abs(half), 1e-12))
            }
            return v
        }
        let fc = safe(center)
        var resultK = fc * wgk[7]
        var resultG = fc * wg[3]
        for j in 0..<7 {
            let dx = half * xgk[j]
            let f1 = safe(center - dx)
            let f2 = safe(center + dx)
            resultK += wgk[j] * (f1 + f2)
            if j % 2 == 1 { resultG += wg[j / 2] * (f1 + f2) }
        }
        return (resultK * half, abs((resultK - resultG) * half))
    }
}
