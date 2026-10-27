import Foundation

/// Discrete and continuous probability distributions used in the matura
/// (binomial, Poisson, normal) and the Sharp P(t), Q(t), R(t) functions.
public enum Distributions {
    // MARK: Binomial B(n, p)

    /// P(X = k) for X ~ B(n, p).
    public static func binomialPMF(n nValue: Double, p: Double, k kValue: Double) throws(MathError) -> Double {
        let n = try trials(nValue)
        try probability(p)
        guard let k = RealEvaluator.exactInt(kValue) else { throw .domain("k mora biti celo število") }
        guard k >= 0, k <= n else { return 0 }
        if p == 0 { return k == 0 ? 1 : 0 }
        if p == 1 { return k == n ? 1 : 0 }
        let logC = lgamma(Double(n) + 1) - lgamma(Double(k) + 1) - lgamma(Double(n - k) + 1)
        if n <= 1000 {
            // Exact binomial coefficient keeps small cases free of rounding (C(10, 3) = 120).
            let c = (try? RealEvaluator.combinatorics(.nCr, Double(n), Double(k))) ?? exp(logC)
            if c.isFinite {
                return c * Foundation.pow(p, Double(k)) * Foundation.pow(1 - p, Double(n - k))
            }
        }
        return exp(logC + Double(k) * log(p) + Double(n - k) * log1p(-p))
    }

    /// P(X ≤ k) for X ~ B(n, p).
    public static func binomialCDF(n nValue: Double, p: Double, k kValue: Double) throws(MathError) -> Double {
        let n = try trials(nValue)
        try probability(p)
        // Compare before converting: Int(_:) traps for a huge, infinite or NaN k (binomcdf(10; 0,5; 10²⁰)).
        guard !kValue.isNaN else { throw .domain("k mora biti celo število") }
        guard kValue >= 0 else { return 0 }
        guard kValue < Double(n) else { return 1 }
        let k = Int(Foundation.floor(kValue))
        if k > 10_000 { return try binomialCDFLargeK(n: n, p: p, k: k) }
        var total = 0.0
        for i in 0...k { total += try binomialPMF(n: Double(n), p: p, k: Double(i)) }
        return min(1, total)
    }

    /// P(X ≥ k) for X ~ B(n, p) = I_p(k, n − k + 1), the regularized incomplete beta function: it
    /// is computed in whichever tail is small and from p itself (no 1 − p), so a tiny tail keeps
    /// its digits, and n = 10⁷ takes no longer than n = 10.
    public static func binomialUpperTail(n nValue: Double, p: Double, k kValue: Double) throws(MathError) -> Double {
        let n = Double(try trials(nValue))
        try probability(p)
        guard !kValue.isNaN else { throw .domain("k mora biti število") }
        let k = Foundation.ceil(kValue)
        guard k > 0 else { return 1 }
        guard k <= n else { return 0 }
        if p == 0 { return 0 }
        if p == 1 { return 1 }
        return regularizedBeta(logX: log(p), logY: log1p(-p), k, n - k + 1)
    }

    public static func binomialMean(n: Double, p: Double) -> Double { n * p }
    public static func binomialVariance(n: Double, p: Double) -> Double { n * p * (1 - p) }

    // MARK: Poisson

    /// P(X = k) for X ~ Po(λ).
    public static func poissonPMF(lambda: Double, k kValue: Double) throws(MathError) -> Double {
        guard lambda > 0, lambda.isFinite else { throw .domain("λ mora biti pozitiven") }
        guard let k = RealEvaluator.exactInt(kValue) else { throw .domain("k mora biti celo število") }
        guard k >= 0 else { return 0 }
        return exp(Double(k) * log(lambda) - lambda - lgamma(Double(k) + 1))
    }

    /// P(X ≤ k) for X ~ Po(λ).
    public static func poissonCDF(lambda: Double, k kValue: Double) throws(MathError) -> Double {
        // Compare before converting: Int(_:) traps for a huge, infinite or NaN k (poissoncdf(3; 10²⁰)).
        guard !kValue.isNaN else { throw .domain("k mora biti celo število") }
        guard kValue >= 0 else { return 0 }
        if kValue >= 100_001 {
            // Too many terms to add, and not simply 1: for λ = k = 10⁹ the probability is about ½.
            guard lambda > 0, lambda.isFinite else { throw .domain("λ mora biti pozitiven") }
            return kValue.isFinite ? poissonCDFLargeK(Foundation.floor(kValue), lambda: lambda) : 1
        }
        let k = Int(Foundation.floor(kValue))
        var total = 0.0
        for i in 0...k { total += try poissonPMF(lambda: lambda, k: Double(i)) }
        return min(1, total)
    }

    /// P(X ≥ k) for X ~ Po(λ) = P(k, λ), the regularized lower incomplete gamma function: it is
    /// computed in whichever tail is small, without summing the terms one by one, so a tiny tail
    /// keeps its digits and λ = 200 000 is as easy as λ = 2.
    public static func poissonUpperTail(lambda: Double, k kValue: Double) throws(MathError) -> Double {
        guard lambda > 0, lambda.isFinite else { throw .domain("λ mora biti pozitiven") }
        guard !kValue.isNaN else { throw .domain("k mora biti število") }
        guard kValue.isFinite else { return kValue < 0 ? 1 : 0 }
        let k = Foundation.ceil(kValue)
        guard k > 0 else { return 1 }
        return regularizedGammaP(k, lambda)
    }

    // MARK: Normal N(μ, σ)

    /// Density of the standard normal distribution.
    public static func normalPDF(_ x: Double) -> Double {
        exp(-0.5 * x * x) / (2 * Double.pi).squareRoot()
    }

    public static func normalPDF(_ x: Double, mean: Double, standardDeviation sigma: Double) throws(MathError) -> Double {
        guard sigma > 0 else { throw .domain("σ mora biti pozitiven") }
        return normalPDF((x - mean) / sigma) / sigma
    }

    /// Φ(x) = P(Z ≤ x); erfc keeps the far tails accurate.
    public static func normalCDF(_ x: Double) -> Double {
        0.5 * erfc(-x / 2.0.squareRoot())
    }

    public static func normalCDF(_ x: Double, mean: Double, standardDeviation sigma: Double) throws(MathError) -> Double {
        guard sigma > 0 else { throw .domain("σ mora biti pozitiven") }
        return normalCDF((x - mean) / sigma)
    }

    /// P(a ≤ X ≤ b) for X ~ N(μ, σ).
    public static func normalProbability(from a: Double, to b: Double, mean: Double = 0, standardDeviation sigma: Double = 1) throws(MathError) -> Double {
        guard sigma > 0 else { throw .domain("σ mora biti pozitiven") }
        let low = (min(a, b) - mean) / sigma, high = (max(a, b) - mean) / sigma
        // Above the mean the upper tails Φ(−z) are subtracted, so P(X ≥ μ + 10σ) ≈ 7,6·10⁻²⁴ is not 0.
        if low > 0 { return normalCDF(-low) - normalCDF(-high) }
        return normalCDF(high) - normalCDF(low)
    }

    /// Φ⁻¹(p): Acklam's rational approximation refined with one Halley step (full double precision).
    public static func inverseNormal(_ p: Double) throws(MathError) -> Double {
        guard p > 0, p < 1 else { throw .domain("verjetnost mora biti med 0 in 1") }
        // Φ⁻¹(p) = −Φ⁻¹(1 − p), and 1 − p is exact for p ≥ ½; near 1 the step below loses digits
        // (Φ⁻¹(1 − 10⁻¹²) was off by 7·10⁻⁹).
        if p > 0.5 { return -(try inverseNormal(1 - p)) }
        let a = [-3.969683028665376e+01, 2.209460984245205e+02, -2.759285104469687e+02,
                 1.383577518672690e+02, -3.066479806614716e+01, 2.506628277459239e+00]
        let b = [-5.447609879822406e+01, 1.615858368580409e+02, -1.556989798598866e+02,
                 6.680131188771972e+01, -1.328068155288572e+01]
        let c = [-7.784894002430293e-03, -3.223964580411365e-01, -2.400758277161838e+00,
                 -2.549732539343734e+00, 4.374664141464968e+00, 2.938163982698783e+00]
        let d = [7.784695709041462e-03, 3.224671290700398e-01, 2.445134137142996e+00, 3.754408661907416e+00]
        let low = 0.02425
        var x: Double
        if p < low {
            let q = (-2 * log(p)).squareRoot()
            x = (((((c[0] * q + c[1]) * q + c[2]) * q + c[3]) * q + c[4]) * q + c[5]) /
                ((((d[0] * q + d[1]) * q + d[2]) * q + d[3]) * q + 1)
        } else if p <= 1 - low {
            let q = p - 0.5
            let r = q * q
            x = (((((a[0] * r + a[1]) * r + a[2]) * r + a[3]) * r + a[4]) * r + a[5]) * q /
                (((((b[0] * r + b[1]) * r + b[2]) * r + b[3]) * r + b[4]) * r + 1)
        } else {
            let q = (-2 * log1p(-p)).squareRoot()
            x = -(((((c[0] * q + c[1]) * q + c[2]) * q + c[3]) * q + c[4]) * q + c[5]) /
                ((((d[0] * q + d[1]) * q + d[2]) * q + d[3]) * q + 1)
        }
        // Halley refinement
        let e = normalCDF(x) - p
        let u = e * (2 * Double.pi).squareRoot() * exp(x * x / 2)
        x -= u / (1 + x * u / 2)
        return x
    }

    public static func inverseNormal(_ p: Double, mean: Double, standardDeviation sigma: Double) throws(MathError) -> Double {
        guard sigma > 0 else { throw .domain("σ mora biti pozitiven") }
        return mean + sigma * (try inverseNormal(p))
    }

    // MARK: Sharp P(t), Q(t), R(t)

    /// P(t): area under the standard normal curve left of t.
    public static func sharpP(_ t: Double) -> Double { normalCDF(t) }
    /// Q(t): area between 0 and |t|.
    public static func sharpQ(_ t: Double) -> Double { normalCDF(Swift.abs(t)) - 0.5 }
    /// R(t): area right of t.
    public static func sharpR(_ t: Double) -> Double { normalCDF(-t) }

    // MARK: Validation

    private static func trials(_ n: Double) throws(MathError) -> Int {
        guard let n = RealEvaluator.exactInt(n), n >= 0, n <= 10_000_000 else { throw .domain("n mora biti nenegativno celo število") }
        return n
    }

    private static func probability(_ p: Double) throws(MathError) {
        guard p >= 0, p <= 1 else { throw .domain("p mora biti med 0 in 1") }
    }
}

// MARK: Distribution functions for large k

extension Distributions {
    /// `binomialCDF` beyond 10 000 terms: only the tail on k's side of the mean is added, from k outwards
    /// until its terms no longer count (about ten standard deviations), instead of all k + 1 terms
    /// (up to 10⁷ for n = 10⁷).
    private static func binomialCDFLargeK(n: Int, p: Double, k: Int) throws(MathError) -> Double {
        let mean = Double(n) * p
        var tail = 0.0
        if Double(k) < mean {
            for i in stride(from: k, through: 0, by: -1) {
                let term = try binomialPMF(n: Double(n), p: p, k: Double(i))
                tail += term
                // Past the mode the terms fall off geometrically: what is left is below 10⁻¹⁶ of the sum.
                if term <= tail * 1e-20, Double(i) < mean - 1 { break }
            }
            return Swift.min(1, tail)
        }
        // From the mean on P(X ≤ k) ≥ ½, so 1 minus the upper tail keeps its digits.
        for i in (k + 1)...n {
            let term = try binomialPMF(n: Double(n), p: p, k: Double(i))
            tail += term
            if term <= tail * 1e-20, Double(i) > mean + 1 { break }
        }
        return Swift.max(0, 1 - tail)
    }

    /// P(X ≤ k) for X ~ Po(λ) and k > 10⁵, which is Q(k + 1, λ), the regularized upper incomplete gamma
    /// function, here by Temme's uniform asymptotic expansion (DLMF §8.12)
    ///     Q(a, λ) = ½·erfc(η·√(a/2)) + e^(−aη²/2)/√(2πa)·(c₀(η) + c₁(η)/a + c₂(η)/a²),
    /// where ½η² = λ/a − 1 − ln(λ/a) and η has the sign of λ − a. For a > 10⁵ the omitted a⁻³ term is
    /// below 10⁻¹⁶ of the result, and only |η| < 0,2 matters (beyond, Q is 0 or 1 in double precision),
    /// so the Taylor series of c₀, c₁, c₂ in η below are enough.
    private static func poissonCDFLargeK(_ k: Double, lambda: Double) -> Double {
        // From 2⁵³ on k + 1 is no Double; then Q(k + 1, λ) = Q(k, λ) + P(X = k).
        let a = k < 0x1p53 ? k + 1 : k
        let mu = (lambda - a) / a
        // d = ½η² = μ − ln(1 + μ), by its series near 0, where the difference cancels.
        var d = 0.0
        if Swift.abs(mu) < 0.5 {
            var power = mu * mu
            for n in 2...80 {
                let term = power / Double(n)
                d += term
                if Swift.abs(term) <= d * 1e-17 { break }
                power *= -mu
            }
        } else {
            d = mu - log1p(mu)
        }
        let eta = (mu < 0 ? -1.0 : 1.0) * (2 * d).squareRoot()
        let t = eta * (a / 2).squareRoot()
        if t > 38 { return 0 }
        if t < -38 { return 1 }
        func series(_ coefficients: [Double]) -> Double { coefficients.reversed().reduce(0.0) { $0 * eta + $1 } }
        let density = exp(-a * d) / (2 * Double.pi * a).squareRoot()
        var q = 0.5 * erfc(t) + density * (series(temmeC0) + (series(temmeC1) + series(temmeC2) / a) / a)
        // P(X = k) = e^(−k·d)/√(2πk) to double precision for k ≥ 2⁵³.
        if a == k { q += density }
        return Swift.min(1, Swift.max(0, q))
    }

    /// Taylor coefficients in η of Temme's c₀(η) = 1/(λ − 1) − 1/η, c₁ and c₂ (DLMF §8.12), computed
    /// exactly with rational series arithmetic and rounded to Double.
    private static let temmeC0: [Double] = [
        -0.3333333333333333, 0.08333333333333333, -0.014814814814814815, 0.0011574074074074073,
        0.0003527336860670194, -0.0001787551440329218, 3.919263178522438e-05, -2.185448510679992e-06,
        -1.85406221071516e-06, 8.296711340953087e-07, -1.7665952736826078e-07, 6.707853543401498e-09,
        1.0261809784240309e-08,
    ]
    private static let temmeC1: [Double] = [
        -0.001851851851851852, -0.003472222222222222, 0.0026455026455026454, -0.0009902263374485596,
        0.00020576131687242798, -4.018775720164609e-07, -1.8098550334489977e-05, 7.64916091608111e-06,
        -1.6120900894563446e-06, 4.647127802807434e-09,
    ]
    private static let temmeC2: [Double] = [
        0.004133597883597883, -0.0026813271604938273, 0.0007716049382716049, 2.0093878600823047e-06,
        -0.0001073665322636516, 5.2923448829120125e-05, -1.2760635188618728e-05,
    ]
}
