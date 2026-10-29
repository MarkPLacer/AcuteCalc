import Foundation

/// Convergence acceleration for sequences of partial sums.
public enum SeriesAccelerator {
    /// Wynn's ε-algorithm. Works for alternating and many oscillatory sequences
    /// (∑(−1)ⁿ/(n+1) → ln 2, partial integrals of sin x / x → π/2).
    public static func wynnEpsilon(_ sums: [Double]) -> Double? {
        guard sums.count >= 3 else { return sums.last }
        return estimate(sums).value
    }

    /// Wynn's ε-algorithm with an error estimate: the even-column entry closest to its neighbour
    /// and that distance (∞ when no column has two finite entries).
    static func estimate(_ sums: [Double]) -> (value: Double, error: Double) {
        let n = sums.count
        var e0 = [Double](repeating: 0, count: n + 1) // ε_{-1} column
        var e1 = sums                                  // ε_0 column
        var best = sums.last ?? .nan
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
        guard best.isFinite else { return (sums.last ?? .nan, .infinity) }
        return (best, bestDelta)
    }
}

/// Infinite series ∑ aₙ: direct summation for fast convergence, Richardson
/// extrapolation in 1/N for slow tails (∑ 1/n² → π²/6), Wynn ε for alternating terms
/// and power-law tails (∑ 1/n^1.5 → ζ(1.5)), divergence detection (∑ 1/n). A tail too
/// slow to tell convergence from divergence (∑ 1/(n ln²n)) is reported, never summed.
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
        var largest: [Double] = []   // largest |aₙ| since the previous N
        var window: [Double] = []    // consecutive partial sums just before N = 2¹²
        var later: [Double] = []     // and just before N = 2¹⁶
        var alternating = true
        var previousTerm = 0.0
        for k in 6...19 {
            let limit = start + (1 << k)
            var biggest = 0.0
            while index < limit {
                let a = term(index)
                guard a.isFinite else { throw .domain("člen vrste ni definiran (n = \(index))") }
                partial += a
                biggest = max(biggest, abs(a))
                if k == 12 || k == 16, limit - index <= 30 {
                    if a == 0 || (previousTerm != 0 && (a > 0) == (previousTerm > 0)) { alternating = false }
                    if k == 12 { window.append(partial) } else { later.append(partial) }
                }
                previousTerm = a
                index += 1
            }
            hs.append(1 / Double(limit - start))
            sums.append(partial)
            largest.append(biggest)
        }
        // Terms that do not tend to 0 (∑ (−1)ⁿ, ∑ n/(n + 1)) diverge.
        let early = largest[largest.count - 7]
        let shrink = early > 0 ? largest[largest.count - 1] / early : 0
        guard shrink < 0.99 else { throw .domain("vrsta divergira") }
        // Divergent series (∑ 1/n ~ ln N, ∑ 1/√n): the steps between the sums at N = 2ᵏ do not shrink.
        let steps = zip(sums, sums.dropFirst()).map { $1 - $0 }
        let recent = steps.suffix(6)
        let monotone = recent.allSatisfy { $0 > 0 } || recent.allSatisfy { $0 < 0 }
        let ratios = monotone ? zip(steps, steps.dropFirst()).map { $1 / $0 } : []
        if let last = ratios.last, last >= 0.999 { throw .domain("vrsta divergira") }
        // Terms shrinking this slowly (∑ (−1)ⁿ/n^0.02) leave the outcome open.
        guard shrink < 0.9 else { throw .domain("vsote vrste ni mogoče zanesljivo določiti") }
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
        let best = estimates.last ?? .nan
        let agreement = estimates.count >= 2 ? abs(best - estimates[estimates.count - 2]) : .infinity
        if best.isFinite, agreement <= 1e-10 * max(1, abs(best)) { return best }
        // Alternating terms (∑ (−1)ⁿ⁺¹/√n): Wynn ε on consecutive partial sums, the same just before N = 2¹⁶
        // as before N = 2¹² (sums that no longer change there are the sum). A slowly shrinking tail of one sign
        // (∑ (−1)ⁿ/ln n + 10⁻⁶/n^1.5) or a slowly turning sign pattern (∑ n³·0.99775ⁿ·cos 3.1n) is invisible
        // in 30 terms but moves the estimate in between. The partial sums carry rounding of about 10⁻¹⁴ times
        // the largest term, so a sum 10⁴ times smaller than that (∑ n²·(−0.999)ⁿ) is not trusted to 1e-10.
        if alternating, window.count == 30, later.count == 30, let value = settled(window, dropping: 2) {
            let check: Double? = later.allSatisfy({ $0 == later[0] }) ? later[0] : settled(later, dropping: 2)
            let size = scale(of: value, sums: window)
            if let check, abs(value - check) <= 1e-10 * size, (largest.max() ?? 0) <= 1e4 * size { return value }
        }
        // Power-law tails S − c·N^(−α) (∑ 1/n^1.5): the steps shrink by a steady factor 2^(−α), which
        // Wynn ε removes. Logarithmic tails (∑ 1/(n ln²n)) have drifting ratios near 1 and are not trusted.
        // Fast-shrinking steps whose ratio still drifts (a late start, or ∑ 1/(n^1.5·ln n), whose N^(−0.5)/ln N
        // Wynn ε misses by 10⁻⁹) must agree to 1e-12.
        if let last = ratios.last {
            let end = ratios.count
            let steady = (1...3).allSatisfy { abs(ratios[end - $0] - ratios[end - $0 - 1]) <= 1e-4 }
            if last <= 0.81 || steady, let value = settled(sums, dropping: 1, tolerance: steady ? 1e-10 : 1e-12) { return value }
        }
        // Otherwise the old extrapolation at its own 1e-7, as before: oscillating tails that still settle like
        // 1/N² (∑ cos n / n²) and slow geometric ones (∑ n·0.999ⁿ) keep the sums they had.
        if best.isFinite, agreement <= 1e-7 * max(1, abs(best)) { return best }
        throw .domain("vsote vrste ni mogoče zanesljivo določiti")
    }

    /// The Wynn ε estimate of `sums`, when it agrees with the one from the sums without the last few
    /// to `tolerance` relative to its scale.
    private static func settled(_ sums: [Double], dropping: Int, tolerance: Double = 1e-10) -> Double? {
        let full = SeriesAccelerator.estimate(sums)
        let shorter = SeriesAccelerator.estimate(Array(sums.dropLast(dropping)))
        let bound = tolerance * scale(of: full.value, sums: sums)
        guard full.value.isFinite, full.error <= bound, abs(full.value - shorter.value) <= bound else { return nil }
        return full.value
    }

    /// What a sum is measured against: max(|S|, min(1, |last partial sum|)). That is max(1, |S|) unless S and the
    /// sums are both below 1; then it is relative (a tail ∑ from n = 10⁵ of 1/n² ≈ 10⁻⁵ against 10⁻⁵).
    private static func scale(of value: Double, sums: [Double]) -> Double {
        max(abs(value), min(1, abs(sums.last ?? 0)))
    }
}

/// Numeric limits with Richardson extrapolation (handles removable singularities such
/// as sin x / x at 0 to full double precision) and detection of infinite limits.
public enum LimitEvaluator {
    public static func limit(_ body: Expr, variable: String, at point: Double, direction: LimitDirection, context: EvaluationContext) throws(MathError) -> Double {
        let f = FunctionAnalyzer.makeFunction(body, variable: variable, context: context)
        return try limit(f, at: point, direction: direction, elementary: isElementary(body, variable: variable),
                         cancels: { x in losesDigits(body, variable: variable, at: x, context: context) },
                         smooth: isSmooth(body, variable: variable, at: point, context: context))
    }

    /// Only where `oneSided` finds no limit, `divergence` may give ±∞ (1/(x − 2) at 2⁺, ln x at 0⁺, x at ∞);
    /// `elementary`: f is built as `isElementary` says, so an overflow inside it shows growth, and only then
    /// is a ±∞ at ±∞ read (see `divergence`);
    /// `cancels(x)`: f(x) is rounding there, not f (see `losesDigits`), so no ±∞ is read from it;
    /// `smooth`: f is built as `isSmooth` says, and only then may `refined` replace a finite value of `oneSided`
    /// at a finite point.
    public static func limit(_ f: (Double) -> Double, at point: Double, direction: LimitDirection, elementary: Bool = false,
                             cancels: (Double) -> Bool = { _ in false }, smooth: Bool = false) throws(MathError) -> Double {
        if point.isInfinite {
            guard let v = NumericCalculus.limit(of: f, at: point) else {
                let sign: Double = point > 0 ? 1 : -1
                if let v = divergence({ t in f(sign / t) }, 0, 1, deep: true, elementary: elementary, cancels: { t in cancels(sign / t) }) { return v }
                throw .domain("limita ne obstaja")
            }
            return v
        }
        switch direction {
        case .left:
            guard let v = oneSided(f, point, -1) else {
                if let v = divergence(f, point, -1, deep: false, elementary: elementary, cancels: cancels) { return v }
                throw .domain("limita ne obstaja")
            }
            guard smooth, let w = refined(f, point, -1, v, cancels: cancels) else { return v }
            return finished(w)
        case .right:
            guard let v = oneSided(f, point, 1) else {
                if let v = divergence(f, point, 1, deep: false, elementary: elementary, cancels: cancels) { return v }
                throw .domain("limita ne obstaja")
            }
            guard smooth, let w = refined(f, point, 1, v, cancels: cancels) else { return v }
            return finished(w)
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
                let value = NumericCalculus.clean(0.5 * (l + r))
                // Both sides refined to the same shown digits, or both kept.
                guard smooth, let wl = refined(f, point, -1, l, cancels: cancels), let wr = refined(f, point, 1, r, cancels: cancels),
                      shown(wl) == shown(wr) else { return value }
                let w = finished(0.5 * (wl + wr))
                return shown(w) == shown(value) ? value : w
            case (let v?, nil):
                // Only one side exists (e.g. √x at 0): use it, like most textbooks.
                guard smooth, let w = refined(f, point, -1, v, cancels: cancels) else { return v }
                return finished(w)
            case (nil, let v?):
                guard smooth, let w = refined(f, point, 1, v, cancels: cancels) else { return v }
                return finished(w)
            default:
                // ±∞ when both sides grow to the same infinity (1/x² + ln|x| at 0). A side with no defined sample shows
                // no gap in the domain: e^(45/x) overflows at every sample right of 0, so e^(45/x)/(e^(45/x) + 1) is NaN there.
                if let v = divergence(f, point, -1, deep: false, elementary: elementary, cancels: cancels),
                   divergence(f, point, 1, deep: false, elementary: elementary, cancels: cancels) == v { return v }
                throw .domain("limita ne obstaja")
            }
        }
    }

    /// x → ±∞ typed on its own (the calculator's top-level lim; inside an expression, `limit` above).
    /// ±∞ only as `divergence` confirms it. A number only when two grids shallower than `oneSided`'s
    /// (x = 1,25·2ᵏ up to 10 240 and 0,72·2ᵏ up to 5 912, where rounding inside f is smaller than at
    /// x = 81 920) give the same digits in the default display with a margin, agree with that grid to
    /// 10⁻⁹, and their samples from x = 10 on approach the value monotonically with shrinking steps.
    /// The second grid is log₂√3 ≈ 0,79 octaves off the first, not ½ (0,88 = 1,25/√2): every grid lay on
    /// 1,25·2^(j/2) then, where cos(4π·log₂x) is cos(4π·log₂1,25) = −0,6186, so cos(4π·log₂x) + 1/x got that value.
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
            guard let d = divergence({ t in f(sign / t) }, 0, 1, deep: true, elementary: elementary, cancels: { t in cancels(sign / t) }),
                  main == nil || main == d else { throw .domain("limita ne obstaja") }
            return d
        }
        var estimates: [Double] = []
        var noise = 0.0
        for s in [8, 8 * 3.0.squareRoot()] {
            guard let e = oneSided({ t in f(sign / (s * t)) }, 0, 1), e.isFinite else { throw .domain("limita ne obstaja") }
            // oneSided's samples from x = 10 on, with the first and the last of these x.
            var tail: [Double] = []
            var ends: [Double] = []
            for k in 0..<14 {
                let t = 0.1 / pow(2, Double(k))
                guard 1 / (s * t) >= 10 else { continue }
                ends.append(sign / (s * t))
                let value = f(sign / (s * t))
                if value.isFinite { tail.append(value) }
            }
            guard let first = ends.first, let last = ends.last, !cancels(first), !cancels(last),
                  tail.count >= 7, approachesMonotonically(tail) else { throw .domain("limita ne obstaja") }
            // A constant there says nothing about larger x: floor(x/10⁵) is 0 and e^(−10⁸/x) underflows to 0 up to
            // x = 10 240, and 1 + e^(−x²) rounds to 1, so (1 + e^(−x²))^(e^(x²)) is 1 there, not e.
            if tail.allSatisfy({ $0 == tail[0] }) { throw .domain("limita ne obstaja") }
            // The rounding noise of f where the grid ends: (1 + c/x)^(kx) carries k·x·2⁻⁵³ of its value there, which
            // the extrapolation passes on up to 8 times (its weights sum to 8 in size). f itself changes far less
            // over x·(1 ± 4·2⁻⁴⁰).
            let probe = (-4...4).map { j in f(last * (1 + Double(j) * 0x1p-40)) }
            guard probe.allSatisfy({ $0.isFinite }), let high = probe.max(), let low = probe.min() else { throw .domain("limita ne obstaja") }
            noise = max(noise, (high - low) / 2)
            estimates.append(e)
        }
        let a = estimates[0], b = estimates[1]
        if a == 0 && b == 0 && v == 0 {
            // 0 only where the samples go to 0 themselves (2/x; eˣ at −∞ underflows to 0). oneSided cleans an estimate
            // below 10⁻¹⁴ to 0, but (x/(x + 40))^x → e⁻⁴⁰ = 4,2·10⁻¹⁸ has samples of that size, and numeric() could
            // not show such a value either.
            for s in [1, 8, 8 * 3.0.squareRoot()] {
                guard let r = unroundedEstimate({ t in f(sign / (s * t)) }),
                      r.nearest == 0 || abs(r.estimate) <= 0x1p-30 * abs(r.nearest) else { throw .domain("limita ne obstaja") }
            }
            return 0
        }
        let scale = max(1, abs(a))
        guard abs(a - b) <= 1e-11 * scale, abs(a - v) <= 1e-9 * scale else { throw .domain("limita ne obstaja") }
        // The digits the calculator shows by default must not change within the grids' spread and an error they may
        // share: 1,5 times the spread plus 10⁻¹², 8 times the noise and half the distance to oneSided's deeper grid.
        // With the spread and 10⁻¹² alone, (1 + 3/(2x))^(10x) → e¹⁵ = 3 269 017,372 47… came out as 3 269 017,372 59
        // and showed …373, and ((9x − 8)/(9x − 9))^(9x) → e showed 2,718281829.
        let margin = 1.5 * (abs(a - b) + 1e-12 * scale) + 8 * noise + abs(a - v) / 2
        let digits = NumberFormatting.format(min(a, b) - margin)
        // oneSided's deeper grid (x up to 81 920) must show them too: a change that only starts out there,
        // (2x + 1)/(x − 3) + 10⁻⁹·x⁴/(x⁴ + 10²⁰) → 2,000000001, is still 2 on the shallower grids.
        guard digits == NumberFormatting.format(max(a, b) + margin), digits == NumberFormatting.format(v) else {
            throw .domain("limita ne obstaja")
        }
        return a
    }

    /// Monotone, with steps that shrink by 0,9 at least (or stay 0): convergence, not slow growth (10²⁰ + x²)
    /// or a jump to the constant that an overflow inside f leaves (x/Γ(x + 1)^(1/x) = 0 from x = 171 on).
    static func approachesMonotonically(_ values: [Double]) -> Bool {
        let steps = zip(values, values.dropFirst()).map { $1 - $0 }
        guard steps.allSatisfy({ $0 >= 0 }) || steps.allSatisfy({ $0 <= 0 }) else { return false }
        return zip(steps, steps.dropFirst()).allSatisfy { abs($1) <= 0.9 * abs($0) }
    }

    /// oneSided's Neville estimate at t → 0⁺ (h = 0,1·2⁻ᵏ) before it is cleaned, with its last finite sample.
    static func unroundedEstimate(_ g: (Double) -> Double) -> (estimate: Double, nearest: Double)? {
        var hs: [Double] = []
        var vs: [Double] = []
        for k in 0..<14 {
            let h = 0.1 / pow(2, Double(k))
            let v = g(h)
            guard v.isFinite else { continue }
            hs.append(h)
            vs.append(v)
        }
        guard vs.count >= 4, let nearest = vs.last else { return nil }
        let count = min(7, vs.count)
        let x = Array(hs.suffix(count))
        var p = Array(vs.suffix(count))
        for m in 1..<count {
            for i in 0..<(count - m) {
                p[i] = (x[i + m] * p[i] - x[i] * p[i + 1]) / (x[i + m] - x[i])
            }
        }
        guard p[0].isFinite else { return nil }
        return (p[0], nearest)
    }

    /// `body` is built from the variable, numbers, + − · ÷, powers, roots, exp, ln, |·|, the hyperbolic and the inverse
    /// trigonometric functions, which are monotone from some x on: no periodic or step part that sparse samples miss.
    /// eˣ·sin²x is +∞ at every sample from x = 710 on (an overflow shows only the sign), but 0 at every multiple of π.
    static func isElementary(_ body: Expr, variable: String) -> Bool {
        return !body.contains { e in
            guard e.dependsOn(variable) else { return false }
            switch e {
            case .variable, .sum, .product, .negation, .quotient, .power: return false
            case .function(let f, _): return !elementaryFunctions.contains(f)
            default: return true
            }
        }
    }

    /// The functions `isElementary` allows.
    static let elementaryFunctions: Set<MathFunction> = [.exp, .ln, .log10, .log2, .log, .sqrt, .cbrt, .root, .abs, .sinh, .cosh, .tanh,
                                                         .coth, .sech, .csch, .asinh, .acosh, .atanh, .acoth, .asech, .acsch,
                                                         .asin, .acos, .atan, .acot, .asec, .acsc]

    /// `body` is built as `isElementary` allows or with sin, cos, tan, cot, sec, csc (smooth beside a finite point),
    /// and no part of it sets a scale below `oneSided`'s samples: every part without the variable, and the
    /// constant factor of every product, is 0 or between 2⁻¹⁰ and 2¹⁰ in size ((1 − cos x)/(x² + 10⁻²⁰) → 0 at 0
    /// looks like (1 − cos x)/x² → 1/2 on every sample where 1 − cos x is not rounding), and the argument of every
    /// function changes by at most 2¹⁰ per unit near the point (tanh(10⁶x), tanh(1000·tanh(1000x)) and
    /// tanh(1000·1000·1000·x) are constant on every sample but not at 0).
    static func isSmooth(_ body: Expr, variable: String, at point: Double, context: EvaluationContext) -> Bool {
        let trigonometric: Set<MathFunction> = [.sin, .cos, .tan, .cot, .sec, .csc]
        var evaluator = RealEvaluator(context: context)
        func outsideScale(_ c: Double) -> Bool { c != 0 && (abs(c) < 0x1p-10 || abs(c) > 0x1p10) }
        func value(_ e: Expr, at x: Double) -> Double? {
            var local = context
            local.variables[variable] = x
            var at = RealEvaluator(context: local)
            guard let v = try? at.eval(e), v.isFinite else { return nil }
            return v
        }
        // The slope of g near the point from the side where g is defined, nil when it is defined on neither.
        func slope(_ g: Expr) -> Double? {
            let d = 1e-3 * max(1, abs(point))
            let mid = value(g, at: point)
            let pairs: [(Double?, Double?, Double)] = [(value(g, at: point + d), value(g, at: point - d), 2 * d),
                                                       (value(g, at: point + d), mid, d), (mid, value(g, at: point - d), d)]
            for (u, w, width) in pairs { if let u, let w { return abs(u - w) / width } }
            return nil
        }
        return !body.contains { e in
            guard e.dependsOn(variable) else {
                guard let c = try? evaluator.eval(e), c.isFinite else { return true }
                return outsideScale(c)
            }
            switch e {
            case .variable, .sum, .negation, .quotient, .power: return false
            case .product(let factors):
                var c = 1.0
                for factor in factors where !factor.dependsOn(variable) {
                    guard let v = try? evaluator.eval(factor), v.isFinite else { return true }
                    c *= v
                }
                return outsideScale(c)
            case .function(let f, let arguments):
                guard elementaryFunctions.contains(f) || trigonometric.contains(f) else { return true }
                return arguments.contains { argument in
                    guard argument.dependsOn(variable) else { return false }
                    guard let s = slope(argument) else { return true }
                    return s > 0x1p10
                }
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
    static func divergence(_ f: (Double) -> Double, _ a: Double, _ side: Double, deep: Bool, elementary: Bool,
                           cancels: (Double) -> Bool) -> Double? {
        // At ±∞ the samples x = 16·2ᵏ and 22,6·3ᵏ meet a periodic or step part at unrelated phases, which a product
        // matched to both sequences fools (x·(1 − 2 sin²(π log₂x)·sin²(π log₃(x/(16√2)))) is x on both, but −x
        // elsewhere), and a sum up to x costs x terms per sample (Σ 1/n to x: 8·10⁶ terms up to x = 2²²).
        if deep && !elementary { return nil }
        let scale = max(1, abs(a))
        let unit = scale.ulp
        let smallest = deep ? 0x1p-500 : unit * 0x1p24
        var signs: [Double?] = []
        for (ratio, factor) in [(2.0, 1.0), (3.0, 0.5.squareRoot())] {
            var values: [Double] = []
            var distances: [Double] = []
            var xs: [Double] = []
            var h = scale / 16 * factor
            while h >= smallest {
                let x = a + side * h
                values.append(f(x))
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
        guard let s = signs[0], signs[1] == s else { return nil }
        return s > 0 ? Double.infinity : -Double.infinity
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

    // MARK: Values the samples get wrong

    /// What the calculator shows for a limit value by default.
    static func shown(_ x: Double) -> FormattedNumber {
        NumberFormatting.format(NumericCalculus.clean(x))
    }

    /// A refined value as the limit: cleaned like `oneSided`'s, and 0 for −0 (x²·ln x underflows to it).
    static func finished(_ w: Double) -> Double {
        w == 0 ? 0 : NumericCalculus.clean(w)
    }

    /// A value for the limit at a finite point instead of `oneSided`'s v, or nil to keep v. v can be wrong in the
    /// digits the calculator shows in two ways: rounding inside f that the extrapolation amplifies ((1 − cos x)/x²
    /// at 0 gives 0,500000627: its samples at h ≈ 10⁻⁵ carry 10⁻⁷ of noise), and a part that is no power of h
    /// (x·ln x at 0⁺ gives −0,000008596, xˣ 0,999991403). Only where v's own extrapolation leaves its digits open
    /// (`selfConsistent`), `noiseAware` and `deepAtZero` each give an estimate and an error bound on two grids. One
    /// is used when the grids agree within their bounds, every value within the bounds shows the same digits, and
    /// they are not v's; when both are, they must show the same.
    static func refined(_ f: (Double) -> Double, _ a: Double, _ side: Double, _ v: Double, cancels: (Double) -> Bool) -> Double? {
        guard v.isFinite, !selfConsistent(f, a, side, v) else { return nil }
        let digitsOfV = shown(v)
        var pick: Double?
        for method in 0..<2 {
            guard let r = method == 0 ? noiseAware(f, a, side, v) : deepAtZero(f, a, side, cancels: cancels) else { continue }
            let first = r[0], second = r[1]
            guard abs(first.value - second.value) <= first.margin + second.margin else { continue }
            // noiseAware's bounds are heuristic: a part that is no power of h (x^1,5·sin(ln x)) can bias a window by
            // more than its parents move, so its band is taken twice as wide before it may replace v.
            let widen: Double = method == 0 ? 2 : 1
            let low = min(first.value - widen * first.margin, second.value - widen * second.margin)
            let high = max(first.value + widen * first.margin, second.value + widen * second.margin)
            let digits = shown(low)
            guard digits == shown(high), digits != digitsOfV else { continue }
            if let pick, shown(pick) != digits { return nil }
            pick = first.value
        }
        return pick
    }

    /// `oneSided`'s 7-point estimate, moved by twice the larger change from either of its two 6-point parents,
    /// still shows v's digits: nothing to refine (sin x/x, (2ˣ − 1)/x, and most limits).
    static func selfConsistent(_ f: (Double) -> Double, _ a: Double, _ side: Double, _ v: Double) -> Bool {
        let h0 = 0.1 * max(1, abs(a))
        var hs: [Double] = []
        var vs: [Double] = []
        for k in 0..<14 {
            let h = h0 / pow(2, Double(k))
            let y = f(a + side * h)
            guard y.isFinite else { continue }
            hs.append(h)
            vs.append(y)
        }
        guard vs.count >= 4 else { return true }
        let count = min(7, vs.count)
        let estimate = neville(Array(hs.suffix(count)), Array(vs.suffix(count)), at: 0)
        guard estimate.value.isFinite else { return true }
        let t = max(abs(estimate.value - estimate.parents.0), abs(estimate.value - estimate.parents.1))
        let digits = shown(estimate.value - 2 * t)
        return digits == shown(estimate.value + 2 * t) && digits == shown(v)
    }

    /// The value at `at` of the polynomial through (ds, ys) (Neville–Aitken), with the two of one degree less
    /// (through all but the last point, and all but the first). ds has at least 3 points.
    static func neville(_ ds: [Double], _ ys: [Double], at: Double) -> (value: Double, parents: (Double, Double)) {
        let n = ds.count
        var p = ys
        var parents = (Double.nan, Double.nan)
        for m in 1..<n {
            for i in 0..<(n - m) {
                p[i] = ((ds[i + m] - at) * p[i] - (ds[i] - at) * p[i + 1]) / (ds[i + m] - ds[i])
            }
            if m == n - 2 { parents = (p[0], p[1]) }
        }
        return (p[0], parents)
    }

    /// The weights of the values at ds in that polynomial's value at 0 (Lagrange).
    static func weights(_ ds: [Double]) -> [Double] {
        ds.indices.map { i in
            var q = 1.0
            for m in ds.indices where m != i {
                q *= ds[m] / (ds[m] - ds[i])
            }
            return q
        }
    }

    /// Where f is probed around a sample, in steps of 2⁻¹⁶·h: irregular, so that the rounding steps of f cannot line
    /// up with them (with steps j·2⁻¹⁶·h, 1 − cos x near x = 10⁻⁵ moved by almost whole ulps per step, and its noise
    /// came out 10⁶ times too small); [8] = 0 is the sample itself.
    static let probeOffsets: [Double] = [-8.27, -6.91, -6.12, -5.05, -3.62, -3.22, -1.91, -1.34, 0, 0.71, 2.13, 2.64, 4.08, 4.79, 5.63, 7.16, 7.74]

    /// 1, t and t² on the probe offsets made orthonormal (Gram–Schmidt): a least-squares quadratic is a sum of these.
    static let probeBasis: [[Double]] = {
        var basis: [[Double]] = []
        for power in 0..<3 {
            var v = LimitEvaluator.probeOffsets.map { t in power == 0 ? 1.0 : (power == 1 ? t : t * t) }
            for b in basis {
                let c = zip(v, b).map { $0 * $1 }.reduce(0, +)
                v = zip(v, b).map { $0 - c * $1 }
            }
            let norm = v.map { $0 * $0 }.reduce(0, +).squareRoot()
            basis.append(v.map { $0 / norm })
        }
        return basis
    }()

    /// f at a + side·h·(1 + t·2⁻¹⁶) for the probe offsets t, fitted by a quadratic in t: its value at t = 0, the
    /// rounding noise of that value, and the noise σ of one value of f (from the 14 degrees of freedom left).
    /// Over 17·2⁻¹⁶·h, f itself is a quadratic to far below its rounding; nil when a probe is not finite.
    static func probed(_ f: (Double) -> Double, _ a: Double, _ side: Double, _ h: Double) -> (value: Double, noise: Double, sigma: Double)? {
        var vs: [Double] = []
        for t in probeOffsets {
            let v = f(a + side * h * (1 + t * 0x1p-16))
            guard v.isFinite else { return nil }
            vs.append(v)
        }
        let basis = probeBasis
        let cs = basis.map { b in zip(vs, b).map { $0 * $1 }.reduce(0, +) }
        var squares = 0.0
        for i in vs.indices {
            let fitted = cs[0] * basis[0][i] + cs[1] * basis[1][i] + cs[2] * basis[2][i]
            squares += (vs[i] - fitted) * (vs[i] - fitted)
        }
        let sigma = (squares / 14).squareRoot()
        let center = cs[0] * basis[0][8] + cs[1] * basis[1][8] + cs[2] * basis[2][8]
        let spread = (basis[0][8] * basis[0][8] + basis[1][8] * basis[1][8] + basis[2][8] * basis[2][8]).squareRoot()
        return (center, sigma * spread, sigma)
    }

    /// Rounding inside f at a finite point a: on `oneSided`'s grid h = 0,1·max(1, |a|)·2⁻ᵏ and on one between it
    /// (h/√2), k < 14, the probed value at each h (`probed`), and of the Neville estimates on 4 to 7 consecutive of
    /// them the one with the smallest error bound: twice the larger change from its parents plus 4 times the noise
    /// it passes on. Then every deeper sample must lie on that polynomial within 4σ and the bound (no change below
    /// the window), and v must differ from the estimate by no more than the noise of `oneSided`'s own last 7
    /// samples allows: its error is that noise. The estimates with their bounds, or nil.
    static func noiseAware(_ f: (Double) -> Double, _ a: Double, _ side: Double, _ v: Double) -> [(value: Double, margin: Double)]? {
        let scale = max(1, abs(a))
        var results: [(value: Double, margin: Double)] = []
        var noiseOfV = 0.0
        for h0 in [0.1 * scale, 0.1 * scale / 2.0.squareRoot()] {
            var ds: [Double] = []
            var ys: [Double] = []
            var noise: [Double] = []
            var sigma: [Double] = []
            var h = h0
            for _ in 0..<14 {
                let d = side * ((a + side * h) - a)
                guard let p = probed(f, a, side, h), d > 0, p.value.isFinite, p.noise.isFinite else { return nil }
                ds.append(d)
                ys.append(p.value)
                noise.append(p.noise)
                sigma.append(p.sigma)
                h /= 2
            }
            var best: (value: Double, margin: Double, window: ClosedRange<Int>)?
            for n in 4...7 {
                for end in (n - 1)..<ds.count {
                    let window = (end - n + 1)...end
                    let wd = Array(ds[window])
                    let estimate = neville(wd, Array(ys[window]), at: 0)
                    guard estimate.value.isFinite else { continue }
                    let t = max(abs(estimate.value - estimate.parents.0), abs(estimate.value - estimate.parents.1))
                    let passed = zip(weights(wd), noise[window]).map { abs($0) * $1 }.reduce(0, +)
                    let margin = 2 * t + 4 * passed + 4 * estimate.value.ulp
                    if margin.isFinite, margin < (best?.margin ?? .infinity) { best = (estimate.value, margin, window) }
                }
            }
            guard let best else { return nil }
            let wd = Array(ds[best.window])
            let wy = Array(ys[best.window])
            for i in (best.window.upperBound + 1)..<ds.count {
                guard abs(ys[i] - neville(wd, wy, at: ds[i]).value) <= 4 * sigma[i] + best.margin else { return nil }
            }
            if results.isEmpty {
                noiseOfV = zip(weights(Array(ds.suffix(7))), sigma.suffix(7)).map { abs($0) * $1 }.reduce(0, +)
            }
            results.append((best.value, best.margin))
        }
        guard abs(v - results[0].value) <= 4 * noiseOfV + results[0].margin + 1e-13 * abs(v) else { return nil }
        return results
    }

    /// A part of f that is no power of h at a = 0 (x^p·ln x, xˣ = e^(x·ln x)): on h = 0,1·2⁻ᵏ and 0,1/√2·3⁻ᵏ down to
    /// 2⁻¹⁰⁰⁰, the samples from h = 10⁻³ on approach monotonically, every step at most 0,9 of the one before (up
    /// to 4 ulps of rounding), so the rest after the last sample is at most 9 times the last step; no sum in the
    /// body cancels at the first and the last of them. The last samples with that bound (and 10 times the spread
    /// of the last 32), or nil. x^0,1·ln x shrinks by 2^(−0,1) = 0,93 per step and is left alone.
    static func deepAtZero(_ f: (Double) -> Double, _ a: Double, _ side: Double, cancels: (Double) -> Bool) -> [(value: Double, margin: Double)]? {
        guard a == 0 else { return nil }
        var results: [(value: Double, margin: Double)] = []
        for (h0, ratio) in [(0.1, 2.0), (0.1 / 2.0.squareRoot(), 3.0)] {
            var hs: [Double] = []
            var ys: [Double] = []
            var h = h0
            while h >= 0x1p-1000 {
                let y = f(side * h)
                guard y.isFinite else { return nil }
                hs.append(h)
                ys.append(y)
                h /= ratio
            }
            guard let start = hs.firstIndex(where: { $0 <= 1e-3 }), let deepest = hs.last,
                  !cancels(side * hs[start]), !cancels(side * deepest) else { return nil }
            let tail = Array(ys[start...])
            let steps = zip(tail, tail.dropFirst()).map { $1 - $0 }
            guard let lastStep = steps.last, let end = tail.last else { return nil }
            var sign = 0.0
            for i in steps.indices {
                let d = steps[i]
                let rounding = 4 * max(abs(tail[i]), abs(tail[i + 1])).ulp
                guard abs(d) > rounding else { continue }
                let direction: Double = d > 0 ? 1 : -1
                if sign == 0 {
                    sign = direction
                } else if direction != sign {
                    return nil
                }
                if i > 0 && !(abs(d) <= 0.9 * abs(steps[i - 1]) + rounding) { return nil }
            }
            let last = tail.suffix(32)
            let margin = 10 * ((last.max() ?? 0) - (last.min() ?? 0)) + 9 * abs(lastStep) + 8 * end.ulp
            results.append((end, margin))
        }
        return results
    }
}
