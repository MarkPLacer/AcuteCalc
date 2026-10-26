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
