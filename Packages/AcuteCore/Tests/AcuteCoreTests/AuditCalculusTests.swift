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
}
