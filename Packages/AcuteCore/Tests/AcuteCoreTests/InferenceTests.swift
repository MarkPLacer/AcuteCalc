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
    }

    @Test func analysisOfVariance() throws {
        let test = try Inference.anova([[5.1, 4.9, 5.6, 5.0], [5.8, 6.1, 5.9, 6.3], [4.8, 5.2, 4.9, 5.1]])
        #expect(abs(test.statistic - (2.4516666666666667 / 2) / (0.5375 / 9)) < 1e-9)
        #expect(test.degrees == [2, 9])
        #expect(test.pValue < 0.001)
    }
}
