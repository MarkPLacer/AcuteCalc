import Foundation
import Testing
@testable import AcuteCore

// MARK: Audit: definite integrals and infinite series

/// Integrals and series go through the calculator's path, `integral(f, x, a, b)` and `sum(f, n, a, inf)`.
/// The 1e-9 tolerances match `ExactRecognizer`'s, which turns such a result into ½, π or 0. Series
/// references: Euler–Maclaurin in 60-digit decimal arithmetic.
@Suite struct AuditCalculusTests {
    /// MAT-12: bisection stopped at depth 40 with the error estimate ignored:
    /// 9.6930204933447, 3.1092954743286, 1.9999999564377 and −3.9999983417585.
    @Test func endpointSingularitiesIntegrateExactly() throws {
        #expect(abs(try value("integral(x^(-0.9), x, 0, 1)") - 10) < 1e-9 * 10)
        #expect(abs(try value("integral(1/sqrt(1-x^2), x, -1, 1)") - Double.pi) < 1e-9 * Double.pi)
        #expect(abs(try value("integral(1/sqrt(x), x, 0, 1)") - 2) < 1e-9 * 2)
        #expect(abs(try value("integral(ln(x)/sqrt(x), x, 0, 1)") + 4) < 1e-9 * 4)
    }

    /// MAT-12: these gave 34.75768819413, 7.68·10¹⁴ and 0.
    @Test func divergentIntegralsAreReported() throws {
        #expect(throws: MathError.domain("integral divergira")) { try value("integral(1/x, x, 0, 1)") }
        #expect(throws: MathError.domain("integral divergira")) { try value("integral(1/x^2, x, -1, 1)") }
        #expect(throws: MathError.domain("integral divergira")) { try value("integral(1/x, x, -1, 1)") }
    }

    @Test func regularIntegralsKeepTheirValues() throws {
        #expect(abs(try value("integral(ln(x), x, 0, 1)") + 1) < 1e-12)
        #expect(abs(try value("integral(x^2, x, 0, 1)") - 1.0 / 3) < 1e-12)
    }

    /// MAT-12: a node on the singular point (1/0 = ∞ in a closure) or nodes merging with a singular end far
    /// from 0 stopped the integral before the pieces were tried (main: divergent, not defined).
    @Test func singularPointsOnNodesAndFarEnds() throws {
        #expect(abs(try Integrator.integrate({ 1 / abs($0).squareRoot() }, from: -1, to: 1) - 4) < 1e-9 * 4)
        #expect(abs(try value("integral(1/sqrt(x-1000), x, 1000, 1001)") - 2) < 1e-9 * 2)
        #expect(throws: MathError.domain("integral divergira")) { try Integrator.integrate({ 1 / ($0 * $0) }, from: -1, to: 1) }
    }

    /// MAT-12 regression: with a large amplitude the error estimate is rounding noise above every bar, and a
    /// looser retry threw "integral ne konvergira" (or gave −3.04·10⁻⁸ for 10⁸·sin x) where main gives 0.
    /// The integrals are 0; rounding the values of A·sin x alone allows about 10⁻¹⁶·∫|f| = 4·10⁻¹⁶·A.
    @Test func largeAmplitudesKeepTheFirstPass() throws {
        for amplitude in ["3*10^8", "10^9", "3*10^9", "3*10^11", "10^12"] {
            let a = try value(amplitude)
            #expect(abs(try value("integral(\(amplitude)*sin(x), x, 0, 2*pi)")) < 1e-13 * 4 * a, "\(amplitude)")
        }
        let s = try FourierSeries.series([FourierSeries.Piece(expr: try parse("10^9*sin(x)"), end: try parse("2*pi"))],
                                         start: .zero, kind: .full, terms: 8)
        #expect(approx(s.b[1], 1e9))
        #expect(abs(s.a[0]) < 1e-5)
        let others = s.a.dropFirst().allSatisfy { $0 == 0 } && s.b.enumerated().allSatisfy { $0.offset == 1 || $0.element == 0 }
        #expect(others)
    }

    /// MAT-12 regression: ∫ from ε to 1 of sin(ω ln x)/x dx = (cos(ω ln ε) − 1)/ω has no limit as ε → 0, but
    /// Wynn ε summed the endpoint pieces to their mean, −1 and 0, which then showed as exact (main: the wrong
    /// −2.7447886319137 and −1.7797691479211). With x^0.99 the pieces shrink and the integral converges:
    /// ∫₀¹ cos(ln x)/x^0.99 dx = ∫₀^∞ e^(−0.01t)·cos t dt = 0.01/(0.01² + 1).
    @Test func oscillationWithoutDecayDiverges() throws {
        #expect(throws: MathError.domain("integral divergira")) { try value("integral(sin(ln(x))/x, x, 0, 1)") }
        #expect(throws: MathError.domain("integral divergira")) { try value("integral(cos(2*ln(x))/x, x, 0, 1)") }
        #expect(abs(try value("integral(cos(ln(x))/x^0.99, x, 0, 1)") - 0.01 / 1.0001) < 1e-9)
    }

    /// MAT-13: a tail c·N^(−α) with non-integer α is no polynomial in 1/N, so these were "vrsta divergira".
    @Test func convergentSeriesAreSummed() throws {
        #expect(abs(try value("sum(1/n^1.5, n, 1, inf)") - 2.612375348685488) < 1e-9 * 2.612375348685488)
        #expect(abs(try value("sum(1/n^1.1, n, 1, inf)") - 10.58444846495081) < 1e-9 * 10.58444846495081)
        #expect(abs(try value("sum((-1)^(n+1)/sqrt(n), n, 1, inf)") - 0.6048986434216304) < 1e-9)
    }

    /// MAT-13: ζ(2.5) = 1.341487257250917 was accepted as 1.341487257597992 (shown 1,341487258).
    @Test func powerTailsAreRightToTheShownDigits() throws {
        let shown = NumberFormatting.roundSignificant(try value("sum(1/n^2.5, n, 1, inf)"), 10)
        #expect(shown == NumberFormatting.roundSignificant(1.341487257250917, 10))
    }

    /// MAT-13: Σ 1/(n ln²n) = 2.1097428012368917 converges; its tail ~ 1/ln N is too slow to sum,
    /// so the honest outcome is that value or "cannot determine", never "vrsta divergira".
    @Test func slowConvergentSeriesIsNotCalledDivergent() {
        do {
            let sum = try value("sum(1/(n*ln(n)^2), n, 2, inf)")
            #expect(abs(sum - 2.1097428012368917) < 1e-9 * 2.1097428012368917)
        } catch {
            #expect((error as? MathError) == MathError.domain("vsote vrste ni mogoče zanesljivo določiti"))
        }
    }

    /// MAT-13 regression: these tails (exactly 10⁻⁵ and ζ(2, 10⁵) = 1/N + 1/(2N²) + 1/(6N³) − … =
    /// 1.0000050000166667·10⁻⁵) were summed to 2.48·10⁻¹³: Wynn ε of sums that still grow geometrically passed
    /// an absolute 10⁻¹⁰ (main: "vrsta divergira"). A sum must be right, or not be given.
    @Test func smallTailsAreRightOrNotSummed() {
        for (input, exact) in [("sum(1/(n*(n+1)), n, 100000, inf)", 1e-5), ("sum(1/n^2, n, 100000, inf)", 1.0000050000166667e-5)] {
            do {
                let sum = try value(input)
                #expect(abs(sum - exact) < 1e-9 * exact, "\(input)")
            } catch {
                #expect(error is MathError, "\(input)")
            }
        }
    }

    /// MAT-13 regression: main's sums whose old extrapolation agrees only to 2–5·10⁻⁹ became "vsote vrste ni
    /// mogoče zanesljivo določiti". References: ∑ from n = 1334 of 1000/(n(n + 1)) = 1000/1334 (telescoping),
    /// ∑ n·xⁿ = x/(1 − x)² = 999000 at x = 0.999.
    @Test func slowlySettlingSumsAreKept() throws {
        #expect(abs(try value("sum(1000/(n*(n+1)), n, 1334, inf)") - 1000.0 / 1334) < 1e-9 * 1000.0 / 1334)
        #expect(abs(try value("sum(n*0.999^n, n, 1, inf)") - 999000) < 1e-9 * 999000)
    }

    /// MAT-13 regression: ∑ₙ≥₂ 1/(n^1.5·ln n) = 1.113106991040763 (direct sums to N = 2000 and 4000 plus
    /// Euler–Maclaurin tails, ∫ from N of dx/(x^1.5·ln x) = E₁(ln N / 2)) has a tail N^(−0.5)/ln N, no power
    /// law; Wynn ε took it as 1.1131069896189554, wrong in the 10th shown digit (main: "vrsta divergira").
    /// A sum must be right to the shown digits, or not be given.
    @Test func logarithmicTailsAreRightOrNotSummed() {
        do {
            let sum = try value("sum(1/(n^1.5*ln(n)), n, 2, inf)")
            #expect(abs(sum - 1.113106991040763) < 1e-10 * 1.113106991040763)
        } catch {
            #expect(error is MathError)
        }
    }

    /// MAT-13: Σ (−1)ⁿ has partial sums 0 at every N = 2ᵏ and was summed to 0.
    @Test func divergentSeriesStayDivergent() throws {
        #expect(throws: MathError.domain("vrsta divergira")) { try value("sum((-1)^n, n, 1, inf)") }
        #expect(throws: MathError.domain("vrsta divergira")) { try value("sum(1/n, n, 1, inf)") }
        #expect(throws: MathError.domain("vrsta divergira")) { try value("sum(1/sqrt(n), n, 1, inf)") }
        // Σ 1/(n ln n) grows like ln ln N, which 2¹⁹ terms cannot tell from slow convergence:
        // either outcome of the series test, no number and no unrelated error.
        do {
            _ = try value("sum(1/(n*ln(n)), n, 2, inf)")
            Issue.record("Σ 1/(n ln n) diverges")
        } catch {
            let outcome = error as? MathError
            #expect(outcome == MathError.domain("vrsta divergira") || outcome == MathError.domain("vsote vrste ni mogoče zanesljivo določiti"))
        }
    }
}
