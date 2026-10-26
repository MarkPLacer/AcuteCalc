import Foundation

// Tests that compare two independent samples (Statistične metode at FGG): the t-test for the
// difference of the means, with a pooled variance or Welch's separate variances, and the F-test
// of equal variances.
extension Inference {
    /// The two-sided t-test of H₀: μ_A = μ_B. With equal variances the pooled
    /// s_p² = ((n_A − 1)s_A² + (n_B − 1)s_B²)/(n_A + n_B − 2) gives n_A + n_B − 2 degrees of
    /// freedom; otherwise Welch's t has ν = (a + b)²/(a²/(n_A − 1) + b²/(n_B − 1)) with
    /// a = s_A²/n_A and b = s_B²/n_B.
    public static func twoSampleTTest(meanA: Double, standardDeviationA sA: Double, countA nA: Double,
                                      meanB: Double, standardDeviationB sB: Double, countB nB: Double,
                                      equalVariances: Bool) throws(MathError) -> Test {
        try checkSample(mean: meanA, deviation: sA, count: nA)
        try checkSample(mean: meanB, deviation: sB, count: nB)
        // The deviations are divided by the larger one before squaring, so 10²⁰⁰ or 10⁻²⁰⁰ do not
        // overflow or vanish; ν does not depend on the scale and t takes it back.
        let scale = Swift.max(sA, sB)
        guard scale > 0 else { throw .domain("vzorca nimata razpršenosti") }
        let ua = sA / scale, ub = sB / scale
        let t: Double, nu: Double
        if equalVariances {
            nu = nA + nB - 2
            let pooled = ((nA - 1) * ua * ua + (nB - 1) * ub * ub) / nu
            t = (meanA - meanB) / scale / (pooled * (1 / nA + 1 / nB)).squareRoot()
        } else {
            let a = ua * ua / nA, b = ub * ub / nB
            t = (meanA - meanB) / scale / (a + b).squareRoot()
            nu = (a + b) * (a + b) / (a * a / (nA - 1) + b * b / (nB - 1))
        }
        guard t.isFinite else { throw .overflow }
        let tail = try Distributions.studentUpperTail(Swift.abs(t), degrees: nu)
        return Test(statistic: t, degrees: [nu], pValue: Swift.min(1, 2 * tail))
    }

    /// The two-sided F-test of H₀: σ_A² = σ_B²: F = s_A²/s_B² with n_A − 1 and n_B − 1 degrees
    /// of freedom, p = 2·min(P(F ≤ f), P(F ≥ f)).
    public static func varianceRatioTest(standardDeviationA sA: Double, countA nA: Double,
                                         standardDeviationB sB: Double, countB nB: Double) throws(MathError) -> Test {
        try checkSample(mean: 0, deviation: sA, count: nA)
        try checkSample(mean: 0, deviation: sB, count: nB)
        guard sA > 0, sB > 0 else { throw .domain("standardna odklona morata biti pozitivna") }
        // The tails come from log F, so a ratio such as (10¹⁶⁰)² keeps its p-value.
        let logF = 2 * (log(sA) - log(sB))
        let d1 = nA - 1, d2 = nB - 1
        let tails = Distributions.fisherTails(logF: logF, d1, d2)
        return Test(statistic: exp(logF), degrees: [d1, d2], pValue: Swift.min(1, 2 * Swift.min(tails.lower, tails.upper)))
    }

    private static func checkSample(mean: Double, deviation s: Double, count n: Double) throws(MathError) {
        guard n >= 2, n == n.rounded(), n.isFinite else { throw .domain("vsak vzorec potrebuje celo število n ≥ 2") }
        guard s >= 0, s.isFinite, mean.isFinite else { throw .domain("povprečje in standardni odklon morata biti končni števili (s ≥ 0)") }
    }
}
