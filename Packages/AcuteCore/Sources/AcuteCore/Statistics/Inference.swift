import Foundation

// Student's t, χ² and Fisher's F distributions (densities, distribution functions and
// quantiles) for statistics at university (Statistične metode, Izravnalni račun at FGG).
extension Distributions {
    // MARK: Student t(ν)

    public static func studentPDF(_ t: Double, degrees nu: Double) throws(MathError) -> Double {
        try positive(nu, "ν")
        // log(1 + t²/ν) as softplus(log(t²/ν)), so t² cannot overflow.
        return exp(lgamma((nu + 1) / 2) - lgamma(nu / 2) - 0.5 * log(nu * Double.pi) - (nu + 1) / 2 * softplus(2 * log(Swift.abs(t)) - log(nu)))
    }

    /// P(T ≤ t)
    public static func studentCDF(_ t: Double, degrees nu: Double) throws(MathError) -> Double {
        try positive(nu, "ν")
        guard t.isFinite else { return t.isNaN ? .nan : (t > 0 ? 1 : 0) }
        // P(T > |t|) = ½·I_x(ν/2, ½) with x = ν/(ν + t²) = 1/(1 + u), u = t²/ν. x and 1 − x go in as
        // logarithms (log x = −log(1 + u), log(1 − x) = −log(1 + 1/u)), so far in the tail t²
        // cannot overflow nor x underflow.
        let logU = 2 * log(Swift.abs(t)) - log(nu)
        let tail = 0.5 * regularizedBeta(logX: -softplus(logU), logY: -softplus(-logU), nu / 2, 0.5)
        return t > 0 ? 1 - tail : tail
    }

    /// P(T > t) = P(T < −t), computed in the tail itself instead of as 1 − P(T ≤ t), so tiny
    /// p-values keep their digits.
    public static func studentUpperTail(_ t: Double, degrees nu: Double) throws(MathError) -> Double {
        try studentCDF(-t, degrees: nu)
    }

    /// t with P(T ≤ t) = p.
    public static func inverseStudent(_ p: Double, degrees nu: Double) throws(MathError) -> Double {
        try positive(nu, "ν")
        try openProbability(p)
        return try quantile(p, lower: nil) { t in (try? studentCDF(t, degrees: nu)) ?? .nan }
    }

    // MARK: χ²(k)

    public static func chiSquarePDF(_ x: Double, degrees k: Double) throws(MathError) -> Double {
        try positive(k, "k")
        guard x > 0 else { return x == 0 && k == 2 ? 0.5 : 0 }
        return exp((k / 2 - 1) * log(x) - x / 2 - k / 2 * log(2) - lgamma(k / 2))
    }

    /// P(X ≤ x)
    public static func chiSquareCDF(_ x: Double, degrees k: Double) throws(MathError) -> Double {
        try positive(k, "k")
        guard x > 0 else { return x.isNaN ? .nan : 0 }
        guard x.isFinite else { return 1 }
        return regularizedGammaP(k / 2, x / 2)
    }

    /// P(X > x) = Q(k/2, x/2), computed in the tail itself.
    public static func chiSquareUpperTail(_ x: Double, degrees k: Double) throws(MathError) -> Double {
        try positive(k, "k")
        guard x > 0 else { return x.isNaN ? .nan : 1 }
        guard x.isFinite else { return 0 }
        return regularizedGammaQ(k / 2, x / 2)
    }

    public static func inverseChiSquare(_ p: Double, degrees k: Double) throws(MathError) -> Double {
        try positive(k, "k")
        try openProbability(p)
        return try quantile(p, lower: 0) { x in (try? chiSquareCDF(x, degrees: k)) ?? .nan }
    }

    // MARK: F(d₁, d₂)

    public static func fisherPDF(_ x: Double, _ d1: Double, _ d2: Double) throws(MathError) -> Double {
        try positive(d1, "d₁")
        try positive(d2, "d₂")
        guard x > 0, x.isFinite else { return x.isNaN ? .nan : 0 }
        let logBeta = lgamma(d1 / 2) + lgamma(d2 / 2) - lgamma((d1 + d2) / 2)
        // With u = d₁x/d₂: d₁·log(d₁x) + d₂·log d₂ − (d₁ + d₂)·log(d₁x + d₂)
        // = −d₁·log(1 + 1/u) − d₂·log(1 + u), without forming d₁ + d₂ or cancelling d₁·log u.
        let logU = log(d1) + log(x) - log(d2)
        return exp(-0.5 * (d1 * softplus(-logU) + d2 * softplus(logU)) - log(x) - logBeta)
    }

    public static func fisherCDF(_ x: Double, _ d1: Double, _ d2: Double) throws(MathError) -> Double {
        try positive(d1, "d₁")
        try positive(d2, "d₂")
        guard x > 0 else { return x.isNaN ? .nan : 0 }
        guard x.isFinite else { return 1 }
        // I_w(d₁/2, d₂/2) with w = u/(1 + u), u = d₁x/d₂, from logarithms (d₁x may overflow).
        let logU = log(d1) + log(x) - log(d2)
        return regularizedBeta(logX: -softplus(-logU), logY: -softplus(logU), d1 / 2, d2 / 2)
    }

    /// P(X > x) = I_{1/(1 + u)}(d₂/2, d₁/2) with u = d₁x/d₂, computed in the tail itself.
    public static func fisherUpperTail(_ x: Double, _ d1: Double, _ d2: Double) throws(MathError) -> Double {
        try positive(d1, "d₁")
        try positive(d2, "d₂")
        guard x > 0 else { return x.isNaN ? .nan : 1 }
        guard x.isFinite else { return 0 }
        let logU = log(d1) + log(x) - log(d2)
        return regularizedBeta(logX: -softplus(logU), logY: -softplus(-logU), d2 / 2, d1 / 2)
    }

    public static func inverseFisher(_ p: Double, _ d1: Double, _ d2: Double) throws(MathError) -> Double {
        try positive(d1, "d₁")
        try positive(d2, "d₂")
        try openProbability(p)
        return try quantile(p, lower: 0) { x in (try? fisherCDF(x, d1, d2)) ?? .nan }
    }

    // MARK: Special functions

    /// Regularized lower incomplete gamma function P(a, x).
    static func regularizedGammaP(_ a: Double, _ x: Double) -> Double {
        incompleteGamma(a, x).lower
    }

    /// Regularized upper incomplete gamma function Q(a, x) = 1 − P(a, x).
    static func regularizedGammaQ(_ a: Double, _ x: Double) -> Double {
        incompleteGamma(a, x).upper
    }

    /// Below a + 1 the series gives P(a, x), above it the continued fraction (modified Lentz) gives
    /// Q(a, x) directly, so tiny tail probabilities keep their digits; the other one is the complement.
    private static func incompleteGamma(_ a: Double, _ x: Double) -> (lower: Double, upper: Double) {
        guard x > 0 else { return (0, 1) }
        let prefix = exp(-x + a * log(x) - lgamma(a))
        // Near x ≈ a both expansions need about √(74a) steps to reach full precision.
        let steps = 10_000 + Int(Swift.min(20 * a.squareRoot(), 2_000_000))
        if x < a + 1 {
            var term = 1 / a, sum = term, n = a
            for _ in 0..<steps {
                n += 1
                term *= x / n
                sum += term
                if Swift.abs(term) < Swift.abs(sum) * 1e-16 { break }
            }
            let p = Swift.min(1, sum * prefix)
            return (p, 1 - p)
        }
        let tiny = 1e-300
        var b = x + 1 - a, c = 1 / tiny, d = 1 / b, h = d
        for i in 1...steps {
            let an = -Double(i) * (Double(i) - a)
            b += 2
            d = an * d + b
            if Swift.abs(d) < tiny { d = tiny }
            c = b + an / c
            if Swift.abs(c) < tiny { c = tiny }
            d = 1 / d
            let delta = d * c
            h *= delta
            if Swift.abs(delta - 1) < 1e-16 { break }
        }
        let q = Swift.min(1, prefix * h)
        return (1 - q, q)
    }

    /// Regularized incomplete beta function I_x(a, b) by its continued fraction, from log x and
    /// log(1 − x), so that an x next to 0 or 1 (even below the smallest double) keeps its digits.
    static func regularizedBeta(logX: Double, logY: Double, _ a: Double, _ b: Double) -> Double {
        // The ends are exact even where the gamma terms below overflow (huge a or b).
        if logX == -.infinity { return 0 }
        if logY == -.infinity { return 1 }
        let x = exp(logX)
        let front = exp(lgamma(a + b) - lgamma(a) - lgamma(b) + a * logX + b * logY)
        if x < (a + 1) / (a + b + 2) { return front * betaFraction(x, a, b) / a }
        return 1 - front * betaFraction(exp(logY), b, a) / b
    }

    /// log(1 + eᶻ) without overflowing eᶻ.
    private static func softplus(_ z: Double) -> Double {
        Swift.max(z, 0) + log1p(exp(-Swift.abs(z)))
    }

    private static func betaFraction(_ x: Double, _ a: Double, _ b: Double) -> Double {
        let tiny = 1e-300
        let qab = a + b, qap = a + 1, qam = a - 1
        var c = 1.0, d = 1 - qab * x / qap
        if Swift.abs(d) < tiny { d = tiny }
        d = 1 / d
        var h = d
        // Near x ≈ a/(a + b) the fraction needs about √(a + b) steps for large a and b.
        let steps = 10_000 + Int(Swift.min(20 * (a + b).squareRoot(), 2_000_000))
        for m in 1...steps {
            let m2 = 2 * Double(m)
            var aa = Double(m) * (b - Double(m)) * x / ((qam + m2) * (a + m2))
            d = 1 + aa * d
            if Swift.abs(d) < tiny { d = tiny }
            c = 1 + aa / c
            if Swift.abs(c) < tiny { c = tiny }
            d = 1 / d
            h *= d * c
            aa = -(a + Double(m)) * (qab + Double(m)) * x / ((a + m2) * (qap + m2))
            d = 1 + aa * d
            if Swift.abs(d) < tiny { d = tiny }
            c = 1 + aa / c
            if Swift.abs(c) < tiny { c = tiny }
            d = 1 / d
            let delta = d * c
            h *= delta
            if Swift.abs(delta - 1) < 1e-16 { break }
        }
        return h
    }

    /// x with cdf(x) = p: the bracket is widened from [lower, 1] (or [−1, 1]), then Brent.
    private static func quantile(_ p: Double, lower: Double?, _ cdf: (Double) -> Double) throws(MathError) -> Double {
        var a = lower ?? -1, b = 1.0
        var steps = 0
        while cdf(b) < p, steps < 200 { b *= 2; steps += 1 }
        if lower == nil { while cdf(a) > p, steps < 400 { a *= 2; steps += 1 } }
        guard let root = RootFinder.brent({ cdf($0) - p }, a, b, tolerance: 1e-14) else { throw .domain("kvantila ni mogoče izračunati") }
        return NumericCalculus.clean(root)
    }

    private static func positive(_ value: Double, _ name: String) throws(MathError) {
        guard value > 0, value.isFinite else { throw .domain("\(name) mora biti pozitiven") }
    }

    private static func openProbability(_ p: Double) throws(MathError) {
        guard p > 0, p < 1 else { throw .domain("verjetnost mora biti med 0 in 1") }
    }
}

/// Confidence intervals and hypothesis tests from summary statistics or data.
public enum Inference {
    public struct Interval: Sendable, Hashable {
        public var lower: Double
        public var upper: Double

        public init(lower: Double, upper: Double) {
            self.lower = lower
            self.upper = upper
        }
    }

    public struct Test: Sendable, Hashable {
        public var statistic: Double
        /// Degrees of freedom (one for t and χ², two for F).
        public var degrees: [Double]
        public var pValue: Double
    }

    /// μ with unknown σ: x̄ ± t(1 − α/2; n − 1)·s/√n
    public static func meanInterval(mean: Double, standardDeviation s: Double, count n: Double, confidence: Double) throws(MathError) -> Interval {
        try check(count: n, confidence: confidence)
        try checkDeviation(s)
        try checkMean(mean)
        let t = try Distributions.inverseStudent((1 + confidence) / 2, degrees: n - 1)
        let half = t * s / n.squareRoot()
        return Interval(lower: mean - half, upper: mean + half)
    }

    /// μ with known σ: x̄ ± z(1 − α/2)·σ/√n
    public static func meanIntervalKnownSigma(mean: Double, sigma: Double, count n: Double, confidence: Double) throws(MathError) -> Interval {
        try check(count: n, confidence: confidence)
        try checkDeviation(sigma)
        try checkMean(mean)
        let z = try Distributions.inverseNormal((1 + confidence) / 2)
        let half = z * sigma / n.squareRoot()
        return Interval(lower: mean - half, upper: mean + half)
    }

    /// σ²: [(n − 1)s²/χ²(1 − α/2), (n − 1)s²/χ²(α/2)]
    public static func varianceInterval(standardDeviation s: Double, count n: Double, confidence: Double) throws(MathError) -> Interval {
        try check(count: n, confidence: confidence)
        try checkDeviation(s)
        let alpha = 1 - confidence
        let upperQuantile = try Distributions.inverseChiSquare(1 - alpha / 2, degrees: n - 1)
        let lowerQuantile = try Distributions.inverseChiSquare(alpha / 2, degrees: n - 1)
        let q = (n - 1) * s * s
        return Interval(lower: q / upperQuantile, upper: q / lowerQuantile)
    }

    /// A proportion (Wald, normal approximation): p̂ ± z·√(p̂(1 − p̂)/n). At p̂ = 0 or 1 it would
    /// have zero width, so it is not defined there.
    public static func proportionInterval(proportion p: Double, count n: Double, confidence: Double) throws(MathError) -> Interval {
        try check(count: n, confidence: confidence)
        guard p > 0, p < 1 else { throw .domain("pri p̂ = 0 ali 1 normalni približek ne velja (Wilsonov interval velja)") }
        let z = try Distributions.inverseNormal((1 + confidence) / 2)
        let half = z * (p * (1 - p) / n).squareRoot()
        return Interval(lower: Swift.max(0, p - half), upper: Swift.min(1, p + half))
    }

    /// A proportion, Wilson score interval: (p̂ + z²/2n ± z·√(p̂(1 − p̂)/n + z²/4n²))/(1 + z²/n).
    /// It stays informative for small n and at p̂ = 0 or 1.
    public static func proportionWilsonInterval(proportion p: Double, count n: Double, confidence: Double) throws(MathError) -> Interval {
        try check(count: n, confidence: confidence)
        guard p >= 0, p <= 1 else { throw .domain("delež mora biti med 0 in 1") }
        let z = try Distributions.inverseNormal((1 + confidence) / 2)
        let shrink = 1 + z * z / n
        let center = (p + z * z / (2 * n)) / shrink
        let half = z * (p * (1 - p) / n + z * z / (4 * n * n)).squareRoot() / shrink
        return Interval(lower: Swift.max(0, center - half), upper: Swift.min(1, center + half))
    }

    /// Two-sided t-test of H₀: μ = μ₀.
    public static func tTest(mean: Double, standardDeviation s: Double, count n: Double, hypothesis mu0: Double) throws(MathError) -> Test {
        guard n >= 2, n == n.rounded(), s > 0, s.isFinite else { throw .domain("potrebna sta celo število n ≥ 2 in s > 0") }
        try checkMean(mean)
        try checkMean(mu0)
        let t = (mean - mu0) / (s / n.squareRoot())
        let tail = try Distributions.studentUpperTail(Swift.abs(t), degrees: n - 1)
        return Test(statistic: t, degrees: [n - 1], pValue: Swift.min(1, 2 * tail))
    }

    /// χ² goodness of fit; `expected` are counts or probabilities (scaled to the total).
    public static func chiSquareGoodnessOfFit(observed: [Double], expected: [Double]) throws(MathError) -> Test {
        guard observed.count >= 2, observed.count == expected.count, expected.allSatisfy({ $0 > 0 }) else {
            throw .domain("vnesi enako število opazovanih in pričakovanih vrednosti (pričakovane > 0)")
        }
        let total = observed.reduce(0, +)
        guard observed.allSatisfy({ $0 >= 0 }), total > 0 else {
            throw .domain("opazovane frekvence morajo biti nenegativne in ne vse enake 0")
        }
        let sumExpected = expected.reduce(0, +)
        let scaled = Swift.abs(sumExpected - 1) < 1e-9 ? expected.map { $0 * total } : expected.map { $0 * total / sumExpected }
        let chi = zip(observed, scaled).reduce(0) { $0 + ($1.0 - $1.1) * ($1.0 - $1.1) / $1.1 }
        let k = Double(observed.count - 1)
        let p = try Distributions.chiSquareUpperTail(chi, degrees: k)
        return Test(statistic: chi, degrees: [k], pValue: p)
    }

    /// One-way analysis of variance: F = MS between / MS within.
    public static func anova(_ groups: [[Double]]) throws(MathError) -> Test {
        let groups = groups.filter { !$0.isEmpty }
        let total = groups.reduce(0) { $0 + $1.count }
        guard groups.count >= 2, total > groups.count else { throw .domain("potrebni sta vsaj dve skupini z več podatki") }
        let grand = groups.flatMap { $0 }.reduce(0, +) / Double(total)
        var between = 0.0, within = 0.0
        for g in groups {
            let mean = g.reduce(0, +) / Double(g.count)
            between += Double(g.count) * (mean - grand) * (mean - grand)
            within += g.reduce(0) { $0 + ($1 - mean) * ($1 - mean) }
        }
        let d1 = Double(groups.count - 1), d2 = Double(total - groups.count)
        guard within > 0 else { throw .domain("znotraj skupin ni razpršenosti") }
        let f = (between / d1) / (within / d2)
        let p = try Distributions.fisherUpperTail(f, d1, d2)
        return Test(statistic: f, degrees: [d1, d2], pValue: p)
    }

    private static func check(count n: Double, confidence: Double) throws(MathError) {
        guard n >= 2, n == n.rounded() else { throw .domain("n mora biti celo število, vsaj 2") }
        guard confidence > 0, confidence < 1 else { throw .domain("stopnja zaupanja mora biti med 0 in 1") }
    }

    private static func checkDeviation(_ s: Double) throws(MathError) {
        guard s >= 0, s.isFinite else { throw .domain("standardni odklon ne sme biti negativen") }
    }

    private static func checkMean(_ mean: Double) throws(MathError) {
        guard mean.isFinite else { throw .domain("povprečje mora biti končno število") }
    }
}
