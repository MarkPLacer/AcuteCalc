import Foundation
import Testing
@testable import AcuteCore

// MARK: Student t, χ² and F distributions; confidence intervals and tests

@Suite struct SamplingDistributionTests {
    @Test func studentT() throws {
        // t(0,975; 10) = 2,228138851964939
        #expect(abs(try Distributions.inverseStudent(0.975, degrees: 10) - 2.228138851964939) < 1e-9)
        #expect(abs(try value("tcdf(2.228138851964939, 10)") - 0.975) < 1e-10)
        #expect(try Distributions.studentCDF(0, degrees: 7) == 0.5)
        #expect(abs(try Distributions.studentCDF(-1.3, degrees: 4) + (try Distributions.studentCDF(1.3, degrees: 4)) - 1) < 1e-14)
    }

    @Test func chiSquare() throws {
        // χ²(0,95; 1) = 3,841458820694124; χ²(0,95; 10) = 18,307038053275146
        #expect(abs(try Distributions.inverseChiSquare(0.95, degrees: 1) - 3.841458820694124) < 1e-9)
        #expect(abs(try value("chi2cdf(18.307038053275146, 10)") - 0.95) < 1e-10)
        #expect(abs(try value("invChi2(0.05, 10)") - 3.940299136119) < 1e-8)
    }

    @Test func fisherF() throws {
        // F(0,95; 2, 10) = 4,102821015130; F(0,95; 5, 10) = 3,325834530413
        #expect(abs(try Distributions.inverseFisher(0.95, 2, 10) - 4.102821015130) < 1e-8)
        #expect(abs(try value("fcdf(3.325834530413, 5, 10)") - 0.95) < 1e-10)
    }

    @Test func displayedNamesParse() throws {
        #expect(abs(try value("χ²cdf(18.307038053275146, 10)") - 0.95) < 1e-10)
        #expect(abs(try value("invχ²(0.95, 1)") - 3.841458820694124) < 1e-9)
    }

    @Test func limitsAtInfinity() throws {
        #expect(try Distributions.chiSquareCDF(.infinity, degrees: 3) == 1)
        #expect(try Distributions.fisherCDF(.infinity, 2, 7) == 1)
        #expect(try Distributions.studentCDF(-.infinity, degrees: 5) == 0)
    }

    @Test func upperTailsKeepTinyProbabilities() throws {
        // Closed forms: P(χ²₁ > x) = erfc(√(x/2)), t(1) is Cauchy with P(T > t) = atan(1/t)/π,
        // and F(2, 2) has P(X > x) = 1/(1 + x).
        let chi = try Distributions.chiSquareUpperTail(200, degrees: 1)
        #expect(abs(chi / erfc(10) - 1) < 1e-10)
        let t = try Distributions.studentUpperTail(1e20, degrees: 1)
        #expect(abs(t / (atan(1e-20) / .pi) - 1) < 1e-10)
        let f = try Distributions.fisherUpperTail(1e20, 2, 2)
        #expect(abs(f / 1e-20 - 1) < 1e-10)
        // Arguments whose square or product overflows a double still give their tails and densities.
        #expect(abs(try Distributions.studentUpperTail(1e200, degrees: 1) / (atan(1e-200) / .pi) - 1) < 1e-10)
        #expect(abs(try Distributions.fisherUpperTail(1e308, 2, 2) * 1e308 - 1) < 1e-10)
        #expect(try Distributions.studentCDF(-1e200, degrees: 1) > 0)
        #expect(abs(try Distributions.studentPDF(1e200, degrees: 0.5) / 1.603504877071139e-301 - 1) < 1e-10)
        #expect(try Distributions.fisherPDF(1e308, 2, 2) == 0)
        #expect(try Distributions.fisherPDF(.infinity, 2, 7) == 0)
        #expect(try Distributions.studentCDF(0, degrees: .greatestFiniteMagnitude) == 0.5)
        // Normal probabilities far above the mean: P(X ≥ 10) = erfc(10/√2)/2.
        #expect(abs(try Distributions.normalProbability(from: 10, to: .infinity) / 7.619853024160595e-24 - 1) < 1e-9)
        // F(d₁, 2) tends to 2/χ²₂ as d₁ grows, with the density e^(−1/x)/x² (e^(−1) at x = 1).
        #expect(approx(try Distributions.fisherPDF(1, 1e6, 2), exp(-1), 1e-5))
        // Elsewhere the upper tail is the complement of the distribution function.
        #expect(abs(try Distributions.chiSquareUpperTail(3, degrees: 4) + (try Distributions.chiSquareCDF(3, degrees: 4)) - 1) < 1e-13)
        #expect(abs(try Distributions.chiSquareUpperTail(9, degrees: 2) + (try Distributions.chiSquareCDF(9, degrees: 2)) - 1) < 1e-13)
        #expect(abs(try Distributions.studentUpperTail(-0.7, degrees: 6) + (try Distributions.studentCDF(-0.7, degrees: 6)) - 1) < 1e-13)
        #expect(abs(try Distributions.fisherUpperTail(1.5, 3, 8) + (try Distributions.fisherCDF(1.5, 3, 8)) - 1) < 1e-13)
        #expect(try Distributions.chiSquareUpperTail(0, degrees: 3) == 1)
        #expect(try Distributions.fisherUpperTail(.infinity, 2, 7) == 0)
    }

    @Test func discreteAndNormalTails() throws {
        // The tails summed directly, against exact sums.
        #expect(abs(try Distributions.binomialUpperTail(n: 100, p: 0.1, k: 90) / 6.110236824191096e-78 - 1) < 1e-9)
        #expect(abs(try Distributions.poissonUpperTail(lambda: 2, k: 30) / 5.855318609378577e-25 - 1) < 1e-9)
        #expect(abs(try Distributions.normalProbability(from: 10, to: .infinity) / 7.619853024160595e-24 - 1) < 1e-9)
        // Elsewhere they are the complements of the distribution functions.
        #expect(approx(try Distributions.binomialUpperTail(n: 10, p: 0.3, k: 3) + (try Distributions.binomialCDF(n: 10, p: 0.3, k: 2)), 1))
        #expect(approx(try Distributions.poissonUpperTail(lambda: 4, k: 3) + (try Distributions.poissonCDF(lambda: 4, k: 2)), 1))
        // Around a huge mean the tail is about one half (the terms summed in double precision).
        #expect(abs(try Distributions.poissonUpperTail(lambda: 200_000, k: 200_000) - 0.5002973540585708) < 1e-8)
        #expect(try Distributions.binomialUpperTail(n: 5, p: 0.5, k: 0) == 1)
        #expect(try Distributions.binomialUpperTail(n: 5, p: 0.5, k: 6) == 0)
    }

    @Test func densitiesIntegrateToOne() throws {
        let t = try Integrator.integrate({ (try? Distributions.studentPDF($0, degrees: 3)) ?? .nan }, from: -400, to: 400, tolerance: 1e-10)
        #expect(abs(t - 1) < 1e-4)
        let chi = try Integrator.integrate({ (try? Distributions.chiSquarePDF($0, degrees: 4)) ?? .nan }, from: 0, to: 200)
        #expect(abs(chi - 1) < 1e-9)
    }
}

@Suite struct InferenceTests {
    @Test func meanAndVarianceIntervals() throws {
        // x̄ = 12,4, s = 1,8, n = 25, 95 %: t(0,975; 24) = 2,0638985616280205
        let mu = try Inference.meanInterval(mean: 12.4, standardDeviation: 1.8, count: 25, confidence: 0.95)
        #expect(abs(mu.lower - (12.4 - 2.0638985616 * 0.36)) < 1e-8)
        #expect(abs(mu.upper - (12.4 + 2.0638985616 * 0.36)) < 1e-8)
        // σ²: 24·3,24/χ²(0,975; 24) … 24·3,24/χ²(0,025; 24)
        let variance = try Inference.varianceInterval(standardDeviation: 1.8, count: 25, confidence: 0.95)
        #expect(abs(variance.lower - 77.76 / 39.3641) < 1e-4)
        #expect(abs(variance.upper - 77.76 / 12.4012) < 1e-3)
    }

    @Test func tTest() throws {
        let test = try Inference.tTest(mean: 12.4, standardDeviation: 1.8, count: 25, hypothesis: 12)
        #expect(abs(test.statistic - 0.4 / 0.36) < 1e-12)
        #expect(test.degrees == [24])
        #expect(test.pValue > 0.27 && test.pValue < 0.29)
    }

    @Test func chiSquareGoodnessOfFit() throws {
        // Expected 25 each: χ² = (49 + 9 + 25 + 25)/25 = 4,32 with 3 degrees of freedom
        let test = try Inference.chiSquareGoodnessOfFit(observed: [18, 22, 30, 30], expected: [0.25, 0.25, 0.25, 0.25])
        #expect(abs(test.statistic - 4.32) < 1e-12)
        #expect(test.degrees == [3])
        #expect(test.pValue > 0.2 && test.pValue < 0.25)
    }

    @Test func wilsonInterval() throws {
        // 0 successes in 20, 95 %: [0; 0,161125]; the Wald interval is not defined there.
        let none = try Inference.proportionWilsonInterval(proportion: 0, count: 20, confidence: 0.95)
        #expect(abs(none.lower) < 1e-12 && abs(none.upper - 0.161125) < 1e-5)
        #expect(throws: MathError.self) { try Inference.proportionInterval(proportion: 0, count: 20, confidence: 0.95) }
        // 12 of 40: Wilson (0,180748; 0,454300)
        let some = try Inference.proportionWilsonInterval(proportion: 0.3, count: 40, confidence: 0.95)
        #expect(abs(some.lower - 0.180748) < 1e-5 && abs(some.upper - 0.454300) < 1e-5)
    }

    @Test func rejectsImpossibleSamples() {
        #expect(throws: MathError.self) { try Inference.meanInterval(mean: 1, standardDeviation: -1, count: 10, confidence: 0.95) }
        #expect(throws: MathError.self) { try Inference.meanInterval(mean: 1, standardDeviation: 1, count: 2.5, confidence: 0.95) }
        #expect(throws: MathError.self) { try Inference.tTest(mean: 1, standardDeviation: 1, count: 9.5, hypothesis: 0) }
        #expect(throws: MathError.self) { try Inference.chiSquareGoodnessOfFit(observed: [0, 0], expected: [1, 1]) }
        #expect(throws: MathError.self) { try Inference.chiSquareGoodnessOfFit(observed: [-3, 5], expected: [1, 1]) }
        #expect(throws: MathError.self) { try Inference.meanInterval(mean: .infinity, standardDeviation: 1, count: 10, confidence: 0.95) }
    }

    @Test func analysisOfVariance() throws {
        let test = try Inference.anova([[5.1, 4.9, 5.6, 5.0], [5.8, 6.1, 5.9, 6.3], [4.8, 5.2, 4.9, 5.1]])
        #expect(abs(test.statistic - (2.4516666666666667 / 2) / (0.5375 / 9)) < 1e-9)
        #expect(test.degrees == [2, 9])
        #expect(test.pValue < 0.001)
    }

    @Test func twoSamples() throws {
        // A: x̄ = 20, s = 4, n = 10; B: x̄ = 23, s = 5, n = 12. The p-values were found by
        // integrating the densities numerically.
        let pooled = try Inference.twoSampleTTest(meanA: 20, standardDeviationA: 4, countA: 10,
                                                  meanB: 23, standardDeviationB: 5, countB: 12, equalVariances: true)
        #expect(approx(pooled.statistic, -1.5307649996171653) && pooled.degrees == [20])
        #expect(approx(pooled.pValue, 0.14149211631718772, 1e-7))
        let welch = try Inference.twoSampleTTest(meanA: 20, standardDeviationA: 4, countA: 10,
                                                 meanB: 23, standardDeviationB: 5, countB: 12, equalVariances: false)
        #expect(approx(welch.statistic, -1.5631503171567185) && approx(welch.degrees[0], 19.98032652757633))
        #expect(approx(welch.pValue, 0.1337179482158315, 1e-7))
        // With equal sample sizes the pooled and Welch statistics agree.
        let a = try Inference.twoSampleTTest(meanA: 5, standardDeviationA: 1, countA: 8, meanB: 4, standardDeviationB: 3, countB: 8, equalVariances: true)
        let b = try Inference.twoSampleTTest(meanA: 5, standardDeviationA: 1, countA: 8, meanB: 4, standardDeviationB: 3, countB: 8, equalVariances: false)
        #expect(approx(a.statistic, b.statistic))
        // F = 16/25 with 9 and 11 degrees of freedom; swapping the samples keeps p.
        let f = try Inference.varianceRatioTest(standardDeviationA: 4, countA: 10, standardDeviationB: 5, countB: 12)
        #expect(approx(f.statistic, 0.64) && f.degrees == [9, 11])
        #expect(approx(f.pValue, 0.5120603077828897, 1e-7))
        let swapped = try Inference.varianceRatioTest(standardDeviationA: 5, countA: 12, standardDeviationB: 4, countB: 10)
        #expect(approx(swapped.pValue, f.pValue, 1e-12))
        #expect(throws: MathError.self) {
            try Inference.twoSampleTTest(meanA: 1, standardDeviationA: 0, countA: 5, meanB: 2, standardDeviationB: 0, countB: 5, equalVariances: false)
        }
        #expect(throws: MathError.self) { try Inference.varianceRatioTest(standardDeviationA: 1, countA: 1.5, standardDeviationB: 1, countB: 4) }
    }
}
