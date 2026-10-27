import Foundation

/// Convergence acceleration for sequences of partial sums.
public enum SeriesAccelerator {
    /// Wynn's ε-algorithm. Works for alternating and many oscillatory sequences
    /// (∑(−1)ⁿ/(n+1) → ln 2, partial integrals of sin x / x → π/2).
    public static func wynnEpsilon(_ sums: [Double]) -> Double? {
        let n = sums.count
        guard n >= 3 else { return sums.last }
        var e0 = [Double](repeating: 0, count: n + 1) // ε_{-1} column
        var e1 = sums                                  // ε_0 column
        var best = sums.last!
        var bestDelta = Double.infinity
        var column = 1
        while e1.count > 1 {
            var next: [Double] = []
            next.reserveCapacity(e1.count - 1)
            for j in 0..<(e1.count - 1) {
                let diff = e1[j + 1] - e1[j]
                if diff == 0 || !diff.isFinite {
                    next.append(.infinity)
                } else {
                    next.append(e0[j + 1] + 1 / diff)
                }
            }
            // Even columns hold the extrapolated estimates.
            if column % 2 == 0, next.count >= 2 {
                let a = next[next.count - 1], b = next[next.count - 2]
                if a.isFinite, b.isFinite, abs(a - b) < bestDelta {
                    bestDelta = abs(a - b)
                    best = a
                }
            }
            e0 = e1
            e1 = next
            column += 1
        }
        return best.isFinite ? best : sums.last
    }
}

/// Infinite series ∑ aₙ: direct summation for fast convergence, Richardson
/// extrapolation in 1/N for slow tails (∑ 1/n² → π²/6), divergence detection (∑ 1/n).
public enum SeriesSummation {
    public static func sum(from start: Int, term: (Int) -> Double) throws(MathError) -> Double {
        // Fast path: geometric-like decay.
        var total = 0.0
        var small = 0
        var n = start
        while n < start + 4000 {
            let a = term(n)
            guard a.isFinite else { throw .domain("člen vrste ni definiran (n = \(n))") }
            total += a
            if abs(a) <= 1e-17 * max(1, abs(total)) { small += 1 } else { small = 0 }
            if small >= 12 { return total }
            n += 1
        }
        // Slow tail: partial sums at N = 2ᵏ and polynomial extrapolation in h = 1/N.
        var partial = 0.0
        var index = start
        var hs: [Double] = []
        var sums: [Double] = []
        for k in 6...19 {
            let limit = start + (1 << k)
            while index < limit {
                let a = term(index)
                guard a.isFinite else { throw .domain("člen vrste ni definiran (n = \(index))") }
                partial += a
                index += 1
            }
            hs.append(1 / Double(limit - start))
            sums.append(partial)
        }
        let count = min(6, sums.count)
        let x = Array(hs.suffix(count))
        let y = Array(sums.suffix(count))
        var p = y
        var estimates: [Double] = []
        for m in 1..<count {
            for i in 0..<(count - m) {
                p[i] = (x[i + m] * p[i] - x[i] * p[i + 1]) / (x[i + m] - x[i])
            }
            estimates.append(p[0])
        }
        guard let best = estimates.last, best.isFinite, estimates.count >= 2 else { throw .domain("vrsta divergira") }
        let previous = estimates[estimates.count - 2]
        // Divergent series (∑ 1/n ~ ln N) never settle.
        guard abs(best - previous) <= 1e-7 * max(1, abs(best)) else { throw .domain("vrsta divergira") }
        return best
    }
}

/// Numeric limits with Richardson extrapolation (handles removable singularities such
/// as sin x / x at 0 to full double precision) and detection of infinite limits.
public enum LimitEvaluator {
    public static func limit(_ body: Expr, variable: String, at point: Double, direction: LimitDirection, context: EvaluationContext) throws(MathError) -> Double {
        let f = FunctionAnalyzer.makeFunction(body, variable: variable, context: context)
        return try limit(f, at: point, direction: direction, elementary: isElementary(body, variable: variable),
                         cancels: { x in losesDigits(body, variable: variable, at: x, context: context) })
    }

    /// Only where `oneSided` finds no limit, `divergence` may give ±∞ (1/(x − 2) at 2⁺, ln x at 0⁺, x at ∞);
    /// `elementary`: f is built as `isElementary` says, so an overflow inside it shows growth;
    /// `cancels(x)`: f(x) is rounding there, not f (see `losesDigits`), so no ±∞ is read from it.
    public static func limit(_ f: (Double) -> Double, at point: Double, direction: LimitDirection, elementary: Bool = false,
                             cancels: (Double) -> Bool = { _ in false }) throws(MathError) -> Double {
        if point.isInfinite {
            guard let v = NumericCalculus.limit(of: f, at: point) else {
                let sign: Double = point > 0 ? 1 : -1
                if let v = divergence({ t in f(sign / t) }, 0, 1, deep: true, elementary: elementary, cancels: { t in cancels(sign / t) }).infinity { return v }
                throw .domain("limita ne obstaja")
            }
            return v
        }
        switch direction {
        case .left:
            guard let v = oneSided(f, point, -1) else {
                if let v = divergence(f, point, -1, deep: false, elementary: elementary, cancels: cancels).infinity { return v }
                throw .domain("limita ne obstaja")
            }
            return v
        case .right:
            guard let v = oneSided(f, point, 1) else {
                if let v = divergence(f, point, 1, deep: false, elementary: elementary, cancels: cancels).infinity { return v }
                throw .domain("limita ne obstaja")
            }
            return v
        case .both:
            let l = oneSided(f, point, -1)
            let r = oneSided(f, point, 1)
            switch (l, r) {
            case (let l?, let r?):
                if l.isInfinite || r.isInfinite {
                    guard l == r else { throw .domain("leva in desna limita se razlikujeta") }
                    return l
                }
                guard abs(l - r) <= 1e-7 * max(1, abs(l)) else { throw .domain("leva (\(l)) in desna (\(r)) limita se razlikujeta") }
                return NumericCalculus.clean(0.5 * (l + r))
            case (let v?, nil), (nil, let v?):
                // Only one side exists (e.g. √x at 0): use it, like most textbooks.
                return v
            default:
                // ±∞ when both sides grow to the same infinity (1/x² + ln|x| at 0), or one side does and
                // the other has no defined value at all (ln x at 0, as √x at 0 above).
                let left = divergence(f, point, -1, deep: false, elementary: elementary, cancels: cancels)
                let right = divergence(f, point, 1, deep: false, elementary: elementary, cancels: cancels)
                if let v = left.infinity, right.infinity == v || right.undefined { return v }
                if let v = right.infinity, left.undefined { return v }
                throw .domain("limita ne obstaja")
            }
        }
    }

    /// x → ±∞ typed on its own (the calculator's top-level lim; inside an expression, `limit` above).
    /// ±∞ only as `divergence` confirms it. A number only when two grids shallower than `oneSided`'s
    /// (x = 1,25·2ᵏ up to 10 240 and 0,88·2ᵏ up to 7 240, where rounding inside f is smaller than at
    /// x = 81 920) give the same digits in the default display with a margin, agree with that grid to
    /// 10⁻⁹, and their samples from x = 10 on approach the value monotonically with shrinking steps.
    /// Otherwise "limita ne obstaja": x^(1/x), ln x/x and sin x/x converge too slowly for the samples.
    public static func limitAtInfinity(_ body: Expr, variable: String, at point: Double, context: EvaluationContext) throws(MathError) -> Double {
        let f = FunctionAnalyzer.makeFunction(body, variable: variable, context: context)
        return try limitAtInfinity(f, at: point, elementary: isElementary(body, variable: variable),
                                   cancels: { x in losesDigits(body, variable: variable, at: x, context: context) })
    }

    static func limitAtInfinity(_ f: (Double) -> Double, at point: Double, elementary: Bool = false,
                                cancels: (Double) -> Bool = { _ in false }) throws(MathError) -> Double {
        let sign: Double = point > 0 ? 1 : -1
        let main = NumericCalculus.limit(of: f, at: point)
        guard let v = main, v.isFinite else {
            // oneSided's ±∞ (|f| > 10⁶ and growing on its last five samples) also holds for x²·sin x.
            guard let d = divergence({ t in f(sign / t) }, 0, 1, deep: true, elementary: elementary, cancels: { t in cancels(sign / t) }).infinity,
                  main == nil || main == d else { throw .domain("limita ne obstaja") }
            return d
        }
        var estimates: [Double] = []
        for s in [8, 8 * 2.0.squareRoot()] {
            guard let e = oneSided({ t in f(sign / (s * t)) }, 0, 1), e.isFinite else { throw .domain("limita ne obstaja") }
            // oneSided's samples, and those from x = 10 on with the first and the last of these x.
            var samples: [Double] = []
            var tail: [Double] = []
            var ends: [Double] = []
            for k in 0..<14 {
                let t = 0.1 / pow(2, Double(k))
                let value = f(sign / (s * t))
                samples.append(value)
                guard 1 / (s * t) >= 10 else { continue }
                ends.append(sign / (s * t))
                if value.isFinite { tail.append(value) }
            }
            guard let first = ends.first, let last = ends.last, !cancels(first), !cancels(last),
                  tail.count >= 7, approachesMonotonically(tail) else { throw .domain("limita ne obstaja") }
            // A constant from x = 10 on only if it is that constant from the first sample on: 1 + e^(−x²)
            // rounds to 1, so (1 + e^(−x²))^(e^(x²)) is 1 there, not e.
            if tail.allSatisfy({ $0 == tail[0] }), samples.contains(where: { $0.isFinite && $0 != tail[0] }) {
                throw .domain("limita ne obstaja")
            }
            estimates.append(e)
        }
        let a = estimates[0], b = estimates[1]
        if a == 0 && b == 0 && v == 0 { return 0 }
        let scale = max(1, abs(a))
        guard abs(a - b) <= 1e-11 * scale, abs(a - v) <= 1e-9 * scale else { throw .domain("limita ne obstaja") }
        // The digits the calculator shows by default must not change within the grids' spread (plus 10⁻¹²
        // for an error they share): (1 + 0,6451/x)^x = 1,906177637 5051… is not shown as …637.
        let margin = abs(a - b) + 1e-12 * scale
        guard NumberFormatting.format(a - margin) == NumberFormatting.format(a + margin) else { throw .domain("limita ne obstaja") }
        return a
    }

    /// Monotone, with steps that shrink by 0,9 at least (or stay 0): convergence, not slow growth (10²⁰ + x²)
    /// or a jump to the constant that an overflow inside f leaves (x/Γ(x + 1)^(1/x) = 0 from x = 171 on).
    static func approachesMonotonically(_ values: [Double]) -> Bool {
        let steps = zip(values, values.dropFirst()).map { $1 - $0 }
        guard steps.allSatisfy({ $0 >= 0 }) || steps.allSatisfy({ $0 <= 0 }) else { return false }
        return zip(steps, steps.dropFirst()).allSatisfy { abs($1) <= 0.9 * abs($0) }
    }

    /// `body` is built from the variable, numbers, + − · ÷, powers, roots, exp, ln, |·| and the hyperbolic functions,
    /// which keep growing past an overflow (eˣ): there every sample is ±∞ and shows only its sign, so a periodic
    /// or step factor is not seen. eˣ·sin²x is +∞ there from x = 710 on, but 0 at every multiple of π.
    static func isElementary(_ body: Expr, variable: String) -> Bool {
        let allowed: Set<MathFunction> = [.exp, .ln, .log10, .log2, .log, .sqrt, .cbrt, .root, .abs, .sinh, .cosh, .tanh,
                                          .coth, .sech, .csch, .asinh, .acosh, .atanh, .acoth, .asech, .acsch]
        return !body.contains { e in
            guard e.dependsOn(variable) else { return false }
            switch e {
            case .variable, .sum, .product, .negation, .quotient, .power: return false
            case .function(let f, _): return !allowed.contains(f)
            default: return true
            }
        }
    }

    /// A sum in `body` keeps less than 2⁻⁴⁰ of its largest term at x, so f(x) is rounding there, not f:
    /// cosh u − 1 − u²/2 with u = 10⁻⁸/x is computed as −u²/2 because cosh u rounds to 1.
    static func losesDigits(_ body: Expr, variable: String, at x: Double, context: EvaluationContext) -> Bool {
        var local = context
        local.variables[variable] = x
        var evaluator = RealEvaluator(context: local)
        return body.contains { e in
            guard case .sum(let terms) = e, let total = try? evaluator.eval(e), total.isFinite else { return false }
            var largest = 0.0
            for term in terms {
                guard let v = try? evaluator.eval(term), v.isFinite else { return false }
                largest = max(largest, abs(v))
            }
            return largest > 0 && abs(total) <= 0x1p-40 * largest
        }
    }

    /// Where `oneSided` finds no limit: ±∞ when the values grow without bound towards the point on two
    /// independent sequences of steps, h = max(1, |a|)/16 · 2⁻ᵏ and h = max(1, |a|)/16 · 3⁻ᵏ/√2, down to
    /// 2²⁴ ulps of max(1, |a|) (for x → ±∞ substituted as t → 0⁺, `deep`, down to t = 2⁻⁵⁰⁰).
    /// `undefined`: no sample is defined (ln x left of 0).
    static func divergence(_ f: (Double) -> Double, _ a: Double, _ side: Double, deep: Bool, elementary: Bool,
                           cancels: (Double) -> Bool) -> (infinity: Double?, undefined: Bool) {
        let scale = max(1, abs(a))
        let unit = scale.ulp
        let smallest = deep ? 0x1p-500 : unit * 0x1p24
        var signs: [Double?] = []
        var undefined = true
        for (ratio, factor) in [(2.0, 1.0), (3.0, 0.5.squareRoot())] {
            var values: [Double] = []
            var distances: [Double] = []
            var xs: [Double] = []
            var h = scale / 16 * factor
            while h >= smallest {
                let x = a + side * h
                let v = f(x)
                if !v.isNaN { undefined = false }
                values.append(v)
                distances.append(abs(x - a))
                xs.append(x)
                h /= ratio
            }
            guard let run = growth(values, distances, unit: unit, deep: deep, elementary: elementary),
                  !cancels(xs[run.start]), !cancels(xs[run.end - 1]) else {
                signs.append(nil)
                continue
            }
            signs.append(run.sign)
        }
        if undefined { return (nil, true) }
        guard let s = signs[0], signs[1] == s else { return (nil, false) }
        return (s > 0 ? Double.infinity : -Double.infinity, false)
    }

    /// The sign of the values when they grow without bound in the run of samples nearest to the point,
    /// values[start..<end] (`distances` from the point exactly): of one sign, strictly growing, at least
    /// 9 of them and twice as large at the end, reaching out to 2⁻⁸·max(1, |a|) (t = 2⁻¹⁶ at ∞), with a
    /// growth exponent (x⁻ᵖ) or a slope per unit of ln distance (ln x) that settles; or faster than any
    /// power up to an overflow that lasts to the last sample (eˣ at ∞), for an `elementary` body that reached 10⁶.
    /// What the samples cannot show stays unseen: a turn beyond x = 2⁵⁰⁰ (x − x²/10²⁰⁰ is +∞ here, not −∞) or a
    /// drift below about 10⁻⁷ of the growth measure over ln x ∈ [2,8; 346] (ln x − x^(10⁻⁹) is +∞ here, not −∞).
    static func growth(_ values: [Double], _ distances: [Double], unit: Double, deep: Bool, elementary: Bool) -> (sign: Double, start: Int, end: Int)? {
        guard let lastValue = values.last else { return nil }
        var end = values.count
        var overflow = false
        if !lastValue.isFinite {
            guard lastValue.isInfinite else { return nil }
            end -= 1
            while end > 0 && values[end - 1] == lastValue { end -= 1 }
            overflow = true
        }
        guard end > 0, values[end - 1].isFinite, values[end - 1] != 0 else { return nil }
        let sign: Double = values[end - 1] > 0 ? 1 : -1
        if overflow && lastValue != sign * .infinity { return nil }
        var start = end - 1
        while start > 0, values[start - 1].isFinite, sign * values[start - 1] > 0, sign * values[start - 1] < sign * values[start] {
            start -= 1
        }
        let sizes = values[start..<end].map { sign * $0 }
        let run = Array(distances[start..<end])
        let k = sizes.count
        let widths = (0..<(k - 1)).map { log(run[$0] / run[$0 + 1]) }
        let exponents = (0..<(k - 1)).map { log(sizes[$0 + 1] / sizes[$0]) / widths[$0] }
        // Past the overflow only the sign is left, so the values before it must have grown for real: a bounded
        // body such as (1 + eˣ)^(1/x) → e also overflows inside (from x = 710 on) and may rise a little before.
        if overflow && elementary && k >= 3 && sizes[k - 1] >= 1e6 && sizes[k - 1] >= 2 * sizes[0],
           zip(exponents, exponents.dropFirst()).allSatisfy({ $1 > $0 }) { return (sign, start, end) }
        // The noise allowance of `settles` grows towards the point, so a slow drift shows only far out; at ∞
        // x ≥ 2⁵³ are even integers, so (−1)^⌊x⌋·x looks like x there.
        guard k >= 9, sizes[k - 1] >= 2 * sizes[0], run[0] >= (deep ? 0x1p-16 : 0x1p-8 * unit / Double.ulpOfOne) else { return nil }
        let noise = (0..<(k - 1)).map { deep ? 0 : unit / run[$0 + 1] }
        let steps = (0..<(k - 1)).map { (sizes[$0 + 1] - sizes[$0]) / widths[$0] }
        guard settles(steps, noise) || settles(exponents, noise) else { return nil }
        return (sign, start, end)
    }

    /// The growth measure ys tends to a positive value of its own. noise[i] = ulp(max(1, |a|)) / distance of the
    /// nearest sample that change i uses (0 at ∞): rounding inside f and a pole a few ulps off the point move ys
    /// by up to 16 times that (tan(πx + π/2) at 1 needs 3); a slow drift (x^p ln x with p = 10⁻¹², x^p sin(c ln x))
    /// does not grow like it. So a pole up to 39 ulps of max(1, |a|) beside the point (about 10⁻¹⁴ of it) still
    /// reads as one at the point: 1/(x − 2,00000000000001) is +∞ at 2⁺ here, though f(2) ≈ −10¹⁴; at 256 times
    /// that was 632 ulps, and 1/(x − 2,0000000000001) at 2⁺ was +∞ too.
    static func settles(_ ys: [Double], _ noise: [Double]) -> Bool {
        let n = ys.count
        // Every change after the first is tiny, or at most 3/4 of the one before (a correction that fades).
        for i in 2..<n {
            let change = abs(ys[i] - ys[i - 1])
            if change > (3e-12 + 16 * noise[i]) * abs(ys[i]) && change > 0.75 * abs(ys[i - 1] - ys[i - 2]) { return false }
        }
        // The geometric rest after the last change keeps the value above half of the last one.
        guard 6 * abs(ys[n - 1] - ys[n - 2]) <= abs(ys[n - 1]) else { return false }
        // Over the second half: rounding, a fading correction, noise that wiggles, or deviations that grow
        // towards the point like noise (the first half of the second half then moves little).
        let m = n / 2
        let y = abs(ys[n - 1])
        let drift = abs(ys[n - 1] - ys[m])
        if drift <= 1e-13 * y || drift <= 3 * abs(ys[m + 1] - ys[m]) { return true }
        let wiggle = ((m + 1)..<n).map { abs(ys[$0] - 2 * ys[$0 - 1] + ys[$0 - 2]) }.max() ?? 0
        if drift <= 2 * wiggle && drift <= 3e-12 * y { return true }
        let q = m + (n - 1 - m) / 2
        return drift <= 16 * noise[(m + 1)..<n].reduce(0, +) * y && abs(ys[q] - ys[m]) <= drift / 4
    }

    /// One-sided limit via a geometric sequence of steps and Neville extrapolation to h = 0.
    static func oneSided(_ f: (Double) -> Double, _ a: Double, _ side: Double) -> Double? {
        let h0 = 0.1 * max(1, abs(a))
        var hs: [Double] = []
        var vs: [Double] = []
        for k in 0..<14 {
            let h = h0 / pow(2, Double(k))
            let v = f(a + side * h)
            guard v.isFinite else { continue }
            hs.append(h)
            vs.append(v)
        }
        guard vs.count >= 4 else {
            let direct = f(a)
            return direct.isFinite ? direct : nil
        }
        // Divergence to ±∞: magnitudes keep growing geometrically.
        let tail = vs.suffix(5)
        if let last = tail.last, abs(last) > 1e6 {
            let growing = zip(tail, tail.dropFirst()).allSatisfy { abs($1) > abs($0) * 1.2 }
            if growing { return last > 0 ? .infinity : -.infinity }
        }
        // Neville–Aitken extrapolation on the last few points (polynomial in h).
        let count = min(7, vs.count)
        let x = Array(hs.suffix(count))
        let y = Array(vs.suffix(count))
        var p = y
        var estimates: [Double] = []
        for m in 1..<count {
            for i in 0..<(count - m) {
                p[i] = (x[i + m] * p[i] - x[i] * p[i + 1]) / (x[i + m] - x[i])
            }
            estimates.append(p[0])
        }
        guard let best = estimates.last, best.isFinite else { return vs.last }
        if estimates.count >= 2 {
            let previous = estimates[estimates.count - 2]
            if abs(best - previous) > 1e-5 * max(1, abs(best)) {
                // Not settling (oscillation like sin(1/x)): no limit.
                let spread = (y.max() ?? 0) - (y.min() ?? 0)
                if spread > 1e-3 * max(1, abs(y.last ?? 0)) { return nil }
            }
        }
        return NumericCalculus.clean(best)
    }
}
