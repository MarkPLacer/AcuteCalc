import Foundation

/// Robust 1-D root finding and minimisation.
public enum RootFinder {
    /// Brent's method on a bracketing interval. Returns `nil` if `f(a)·f(b) > 0`.
    public static func brent(_ f: (Double) -> Double, _ lower: Double, _ upper: Double, tolerance: Double = 1e-15) -> Double? {
        var a = lower, b = upper
        var fa = f(a), fb = f(b)
        guard fa.isFinite, fb.isFinite else { return nil }
        if fa == 0 { return a }
        if fb == 0 { return b }
        guard (fa < 0) != (fb < 0) else { return nil }
        var c = a, fc = fa
        var d = b - a, e = d
        for _ in 0..<200 {
            if (fb > 0) == (fc > 0) { c = a; fc = fa; d = b - a; e = d }
            if abs(fc) < abs(fb) { a = b; b = c; c = a; fa = fb; fb = fc; fc = fa }
            let tol = 2 * Double.ulpOfOne * abs(b) + 0.5 * tolerance
            let m = 0.5 * (c - b)
            if abs(m) <= tol || fb == 0 { return b }
            if abs(e) >= tol && abs(fa) > abs(fb) {
                let s = fb / fa
                var p: Double, q: Double
                if a == c {
                    p = 2 * m * s
                    q = 1 - s
                } else {
                    let qa = fa / fc, r = fb / fc
                    p = s * (2 * m * qa * (qa - r) - (b - a) * (r - 1))
                    q = (qa - 1) * (r - 1) * (s - 1)
                }
                if p > 0 { q = -q } else { p = -p }
                if 2 * p < min(3 * m * q - abs(tol * q), abs(e * q)) {
                    e = d; d = p / q
                } else {
                    d = m; e = m
                }
            } else {
                d = m; e = m
            }
            a = b; fa = fb
            b += abs(d) > tol ? d : (m > 0 ? tol : -tol)
            fb = f(b)
            if !fb.isFinite { return nil }
        }
        return b
    }

    /// Golden-section search for a minimum of `g` on [a, b].
    public static func minimize(_ g: (Double) -> Double, _ lower: Double, _ upper: Double, iterations: Int = 90) -> Double {
        let ratio = (5.0.squareRoot() - 1) / 2
        var a = lower, b = upper
        var c = b - ratio * (b - a)
        var d = a + ratio * (b - a)
        var gc = g(c), gd = g(d)
        for _ in 0..<iterations {
            if !(gc.isFinite) { gc = .infinity }
            if !(gd.isFinite) { gd = .infinity }
            if gc < gd {
                b = d; d = c; gd = gc
                c = b - ratio * (b - a); gc = g(c)
            } else {
                a = c; c = d; gc = gd
                d = a + ratio * (b - a); gd = g(d)
            }
            if abs(b - a) < 1e-15 * max(1, abs(a)) { break }
        }
        return 0.5 * (a + b)
    }

    /// Every root of `f` in the range: sign changes refined with Brent, plus
    /// even-multiplicity ("touching") roots found as minima of |f|. Poles are rejected.
    public static func roots(_ f: (Double) -> Double, in range: ClosedRange<Double>, samples: Int = 2400) -> [Double] {
        let n = max(8, samples)
        let width = range.upperBound - range.lowerBound
        guard width > 0 else { return [] }
        let step = width / Double(n)
        var xs = [Double](repeating: 0, count: n + 1)
        var ys = [Double](repeating: 0, count: n + 1)
        var scale = 0.0
        for i in 0...n {
            xs[i] = range.lowerBound + Double(i) * step
            ys[i] = f(xs[i])
            if ys[i].isFinite { scale = max(scale, min(abs(ys[i]), 1e6)) }
        }
        let zeroTolerance = 1e-9 * max(1, scale)
        var found: [Double] = []
        // A root must be tiny next to the samples around it, not next to the largest |f| of the whole
        // range: eˣ − x − 0.9995 has a minimum 5·10⁻⁴ at 0, and eˣ reaching 10⁶ elsewhere made it a root.
        func add(_ r: Double, neighbours: Double) {
            let v = f(r)
            guard v.isFinite, abs(v) <= 1e-9 * max(1, min(neighbours, 1e6)) else { return }
            if let last = found.last, abs(last - r) <= step * 0.5 { return }
            found.append(r)
        }
        for i in 0..<n {
            let ya = ys[i], yb = ys[i + 1]
            guard ya.isFinite, yb.isFinite else { continue }
            if ya == 0 { add(xs[i], neighbours: 0); continue }
            if (ya < 0) != (yb < 0) {
                if let r = brent(f, xs[i], xs[i + 1]) { add(r, neighbours: max(abs(ya), abs(yb))) }
                continue
            }
            // Touching root: local minimum of |f| between neighbours.
            if i > 0, ys[i - 1].isFinite {
                let a = abs(ys[i - 1]), b = abs(ya), c = abs(yb)
                if b <= a && b <= c && b < zeroTolerance * 1e4 {
                    let r = minimize({ abs(f($0)) }, xs[i - 1], xs[i + 1])
                    add(r, neighbours: max(a, c))
                }
            }
        }
        if let last = ys.last, last == 0, let x = xs.last { add(x, neighbours: 0) }
        return found.sorted()
    }

    /// Roots of `f` with a sign change only (used for extrema/inflection from derivatives).
    public static func signChanges(_ f: (Double) -> Double, in range: ClosedRange<Double>, samples: Int = 2400) -> [(x: Double, risingAfter: Bool)] {
        let n = max(8, samples)
        let step = (range.upperBound - range.lowerBound) / Double(n)
        var result: [(Double, Bool)] = []
        // Last non-zero finite sample; exact zeros (a sample landing on the root) are
        // remembered and confirmed once the sign on the other side is known.
        var lastSign: Bool?
        var lastX = range.lowerBound
        var lastY = 0.0
        var pendingZero: Double?
        for i in 0...n {
            let x = range.lowerBound + Double(i) * step
            let y = f(x)
            guard y.isFinite else {
                lastSign = nil
                pendingZero = nil
                continue
            }
            if y == 0 {
                if lastSign != nil { pendingZero = x }
                continue
            }
            let positive = y > 0
            if let previous = lastSign, previous != positive {
                if let zero = pendingZero {
                    result.append((zero, positive))
                } else if let r = brent(f, lastX, x) {
                    // Reject sign changes caused by poles of f.
                    let v = f(r)
                    if v.isFinite, abs(v) < 1e-6 * max(1, abs(lastY), abs(y)) {
                        result.append((r, positive))
                    }
                }
            }
            pendingZero = nil
            lastSign = positive
            lastX = x
            lastY = y
        }
        return result
    }
}
