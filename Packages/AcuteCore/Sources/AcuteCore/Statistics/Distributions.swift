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
        let k = Int(Foundation.floor(kValue))
        guard k >= 0 else { return 0 }
        guard k < n else { return 1 }
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
        let k = Int(Foundation.floor(kValue))
        guard k >= 0 else { return 0 }
        guard k <= 100_000 else { return 1 }
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
