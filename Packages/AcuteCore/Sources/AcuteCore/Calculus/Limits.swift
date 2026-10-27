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
                if k == 12, limit - index <= 30 {
                    if a == 0 || (previousTerm != 0 && (a > 0) == (previousTerm > 0)) { alternating = false }
                    window.append(partial)
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
        // Alternating terms (∑ (−1)ⁿ⁺¹/√n): Wynn ε on consecutive partial sums.
        if alternating, window.count == 30, let value = settled(window, dropping: 2) { return value }
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
        return try limit(f, at: point, direction: direction)
    }

    public static func limit(_ f: (Double) -> Double, at point: Double, direction: LimitDirection) throws(MathError) -> Double {
        if point.isInfinite {
            guard let v = NumericCalculus.limit(of: f, at: point) else { throw .domain("limita ne obstaja") }
            return v
        }
        switch direction {
        case .left:
            guard let v = oneSided(f, point, -1) else { throw .domain("limita ne obstaja") }
            return v
        case .right:
            guard let v = oneSided(f, point, 1) else { throw .domain("limita ne obstaja") }
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
                throw .domain("limita ne obstaja")
            }
        }
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
