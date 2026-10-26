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
        if let last = ratios.last {
            let end = ratios.count
            let steady = (1...3).allSatisfy { abs(ratios[end - $0] - ratios[end - $0 - 1]) <= 1e-4 }
            if last <= 0.81 || steady, let value = settled(sums, dropping: 1) { return value }
        }
        // Oscillating tails that still settle like 1/N² (∑ cos n / n²).
        if best.isFinite, agreement <= 1e-9 * max(1, abs(best)) { return best }
        throw .domain("vsote vrste ni mogoče zanesljivo določiti")
    }

    /// The Wynn ε estimate of `sums`, when it agrees with the one from the sums without the last few.
    private static func settled(_ sums: [Double], dropping: Int) -> Double? {
        let full = SeriesAccelerator.estimate(sums)
        let shorter = SeriesAccelerator.estimate(Array(sums.dropLast(dropping)))
        let tolerance = 1e-10 * max(1, abs(full.value))
        guard full.value.isFinite, full.error <= tolerance, abs(full.value - shorter.value) <= tolerance else { return nil }
        return full.value
    }
}

/// Numeric limits with Richardson extrapolation (handles removable singularities such
/// as sin x / x at 0 to full double precision), extrapolation in h·ln h and √h for
/// xˣ and √x at 0⁺, and detection of infinite limits, also slow ones (ln x at 0⁺).
/// A value is only returned when independent estimates agree.
public enum LimitEvaluator {
    /// What the samples f(a ± h) show as h → 0⁺.
    enum OneSided {
        case value(Double)   // finite or ±∞
        case absent          // f is not defined on this side
        case oscillates      // no limit (sin(1/x) at 0)
        case undetermined    // neither settles nor clearly diverges
    }

    public static func limit(_ body: Expr, variable: String, at point: Double, direction: LimitDirection, context: EvaluationContext) throws(MathError) -> Double {
        let f = FunctionAnalyzer.makeFunction(body, variable: variable, context: context)
        return try limit(f, at: point, direction: direction)
    }

    public static func limit(_ f: (Double) -> Double, at point: Double, direction: LimitDirection) throws(MathError) -> Double {
        if point.isInfinite {
            // x → ±∞ becomes t → 0⁺ with x = ±1/t, as in NumericCalculus.limit(of:at:).
            let sign: Double = point > 0 ? 1 : -1
            return try value(of: classify({ t in f(sign / t) }, 0, 1))
        }
        switch direction {
        case .left:
            return try value(of: classify(f, point, -1))
        case .right:
            return try value(of: classify(f, point, 1))
        case .both:
            let l = classify(f, point, -1)
            let r = classify(f, point, 1)
            switch (l, r) {
            case (.undetermined, _), (_, .undetermined):
                throw .domain("limite ni mogoče zanesljivo določiti")
            case (.value(let l), .value(let r)):
                if l.isInfinite || r.isInfinite {
                    guard l == r else { throw .domain("leva in desna limita se razlikujeta") }
                    return l
                }
                guard abs(l - r) <= 1e-7 * max(1, abs(l)) else { throw .domain("leva (\(l)) in desna (\(r)) limita se razlikujeta") }
                return NumericCalculus.clean(0.5 * (l + r))
            case (.value(let v), .absent), (.absent, .value(let v)):
                // Only one side exists (e.g. √x at 0): use it, like most textbooks.
                return v
            default:
                throw .domain("limita ne obstaja")
            }
        }
    }

    private static func value(of side: OneSided) throws(MathError) -> Double {
        switch side {
        case .value(let v): return v
        case .undetermined: throw .domain("limite ni mogoče zanesljivo določiti")
        case .absent, .oscillates: throw .domain("limita ne obstaja")
        }
    }

    /// One-sided limit (nil when there is none or it cannot be determined).
    static func oneSided(_ f: (Double) -> Double, _ a: Double, _ side: Double) -> Double? {
        if case .value(let v) = classify(f, a, side) { return v }
        return nil
    }

    /// One-sided limit via a geometric sequence of steps and extrapolation to h = 0.
    static func classify(_ f: (Double) -> Double, _ a: Double, _ side: Double) -> OneSided {
        let h0 = 0.1 * max(1, abs(a))
        var hs: [Double] = []
        var vs: [Double] = []
        var raw: [Double] = []
        for k in 0..<14 {
            let h = h0 / pow(2, Double(k))
            let v = f(a + side * h)
            raw.append(v)
            guard v.isFinite else { continue }
            hs.append(h)
            vs.append(v)
        }
        // Values of one sign that overflow for good (e^(x²) at ∞) diverge.
        let signed = raw.filter { !$0.isNaN }
        if raw.suffix(4).allSatisfy({ $0 == .infinity }), signed.allSatisfy({ $0 > 0 }) { return .value(.infinity) }
        if raw.suffix(4).allSatisfy({ $0 == -.infinity }), signed.allSatisfy({ $0 < 0 }) { return .value(-.infinity) }
        guard vs.count >= 4 else {
            let direct = f(a)
            return direct.isFinite ? .value(direct) : .absent
        }
        // Rounding noise ((tan x − sin x)/x³) grows as h shrinks: drop the samples after the
        // differences, already tiny, grow again or stall for a step (unlike a value that has
        // converged for good, as 1/(1 + e⁻ˣ) at ∞).
        var end = vs.count
        for k in 2..<(vs.count - 1) {
            let before = abs(vs[k] - vs[k - 1])
            let after = abs(vs[k + 1] - vs[k])
            let stalls = after == 0 && before > 0 && vs[(k + 1)...].contains { $0 != vs[k] }
            if after > before || stalls, before <= 1e-6 * max(1, abs(vs[k])) {
                end = k + 1
                break
            }
        }
        let x = Array(hs[..<end])
        let y = Array(vs[..<end])
        // Divergence to ±∞: magnitudes of one sign keep growing geometrically (e^x·sin x does not).
        let tail = y.suffix(5)
        if let last = tail.last, abs(last) > 1e6, y.allSatisfy({ $0 > 0 }) || y.allSatisfy({ $0 < 0 }) {
            let growing = zip(tail, tail.dropFirst()).allSatisfy { abs($1) > abs($0) * 1.2 }
            if growing { return .value(last > 0 ? .infinity : -.infinity) }
        }
        let tolerance = 1e-9
        // Analytic in h (sin x / x at 0, (1 + 1/x)ˣ at ∞).
        let analytic = neville(x, y, tolerance: tolerance)
        if settled(analytic, tolerance) { return .value(NumericCalculus.clean(analytic.value)) }
        // Slow divergence (1/x and ln x at 0⁺, x and √x at ∞).
        if divergesSlowly(y) { return .value(y[y.count - 1] > 0 ? .infinity : -.infinity) }
        // xˣ = e^(x ln x) and x ln x at 0⁺ are polynomials in h·ln h, √x in √h; Wynn ε handles
        // other powers (x^0.1).
        let small = x.indices.filter { x[$0] <= 0.1 }
        if small.count >= 4 {
            let logarithmic = neville(small.map { x[$0] * log(x[$0]) }, small.map { y[$0] }, tolerance: tolerance)
            if settled(logarithmic, tolerance) { return .value(NumericCalculus.clean(logarithmic.value)) }
        }
        let root = neville(x.map { $0.squareRoot() }, y, tolerance: tolerance)
        if settled(root, tolerance) { return .value(NumericCalculus.clean(root.value)) }
        // Wynn ε only for samples that settle down: on exploding ones it finds an antilimit.
        let wynn = SeriesAccelerator.estimate(y)
        let sizes = zip(y, y.dropFirst()).map { abs($1 - $0) }
        if let lastSize = sizes.last, lastSize < (sizes.max() ?? 0), settled(wynn, 1e-11) {
            return .value(NumericCalculus.clean(wynn.value))
        }
        // No limit when the values keep turning back and forth (sin(1/x)); otherwise undecided.
        let recent = y.suffix(7)
        let steps = zip(recent, recent.dropFirst()).map { $1 - $0 }.filter { $0 != 0 }
        let turns = zip(steps, steps.dropFirst()).filter { ($0 > 0) != ($1 > 0) }.count
        let spread = (recent.max() ?? 0) - (recent.min() ?? 0)
        if turns >= 2, spread > 1e-3 * max(1, abs(recent.last ?? 0)) { return .oscillates }
        return .undetermined
    }

    private static func settled(_ estimate: (value: Double, error: Double), _ tolerance: Double) -> Bool {
        estimate.value.isFinite && estimate.error <= tolerance * max(1, abs(estimate.value))
    }

    /// Neville's tableau extrapolated to 0 (orders ≤ 6), one sample per row. An entry's error is
    /// its distance to the entries it was built from and to the previous window of the same order,
    /// so at least three samples must agree; the entry with the smallest error wins. Once one is
    /// within `tolerance`, rows whose errors grow again (rounding noise) end the search.
    static func neville(_ x: [Double], _ y: [Double], tolerance: Double) -> (value: Double, error: Double) {
        let n = x.count
        var best = (value: y.last ?? .nan, error: Double.infinity)
        guard n >= 3 else { return best }
        var rows: [[Double]] = []
        for i in 0..<n {
            var row = [y[i]]
            var rowError = Double.infinity
            for m in stride(from: 1, through: min(i, 6), by: 1) {
                let j = i - m
                let t = (x[i] * rows[i - 1][m - 1] - x[j] * row[m - 1]) / (x[i] - x[j])
                row.append(t)
                guard i > m else { continue }
                let differences = [t - row[m - 1], t - rows[i - 1][m - 1], t - rows[i - 1][m]]
                guard t.isFinite, differences.allSatisfy({ $0.isFinite }) else { continue }
                let error = differences.map { abs($0) }.max() ?? .infinity
                rowError = min(rowError, error)
                if error < best.error { best = (t, error) }
            }
            rows.append(row)
            if best.error <= tolerance * max(1, abs(best.value)), rowError > 2 * best.error { break }
        }
        return best
    }

    /// The last six values keep their sign and grow in size by regular steps that do not shrink:
    /// at least logarithmic growth, unlike rounding noise.
    static func divergesSlowly(_ vs: [Double]) -> Bool {
        guard vs.count >= 6 else { return false }
        let recent = vs.suffix(6)
        guard recent.allSatisfy({ $0 > 0 }) || recent.allSatisfy({ $0 < 0 }) else { return false }
        let sizes = recent.map { abs($0) }
        let steps = zip(sizes, sizes.dropFirst()).map { $1 - $0 }
        guard steps.allSatisfy({ $0 > 0 }) else { return false }
        let ratios = zip(steps, steps.dropFirst()).map { $1 / $0 }
        guard let smallest = ratios.min(), let largest = ratios.max() else { return false }
        return smallest >= 0.99 && largest <= 1.5 * smallest
    }
}
