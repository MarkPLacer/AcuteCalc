import Foundation
import Testing
@testable import AcuteCore

// MARK: Audit: numeric limits, definite integrals and infinite series

/// Limits go through the calculator's path (bytecode function, as `CalculationEngine` evaluates `lim`),
/// integrals and series through `integral(f, x, a, b)` and `sum(f, n, a, inf)`. The 1e-9 tolerances
/// match `ExactRecognizer`'s, which turns such a result into ½, π or 0. Series references: Euler–Maclaurin
/// in 60-digit decimal arithmetic.
@Suite struct AuditCalculusTests {
    func limit(_ text: String, at point: Double, _ direction: LimitDirection = .both) throws -> Double {
        try LimitEvaluator.limit(try parse(text), variable: "x", at: point, direction: direction, context: EvaluationContext())
    }

    /// MAT-07: values like 1/h only reach 8·10⁴ at the smallest step, below the old 10⁶ threshold,
    /// so these were reported as "limita ne obstaja".
    @Test func polesAndSlowGrowthGiveInfiniteLimits() throws {
        #expect(try limit("1/(x-2)", at: 2, .right) == .infinity)
        #expect(try limit("(x+1)/(x-2)", at: 2, .right) == .infinity)
        #expect(try limit("1/(x-3)", at: 3, .left) == -.infinity)
        #expect(try limit("1/x", at: 0, .right) == .infinity)
        #expect(try limit("ln(x)", at: 0, .right) == -.infinity)
        #expect(try limit("x", at: .infinity) == .infinity)
        #expect(try limit("(x^2+1)/x", at: .infinity) == .infinity)
        #expect(try limit("(2x^2+1)/(x-1)", at: .infinity) == .infinity)
        #expect(try limit("sqrt(x)", at: .infinity) == .infinity)
        #expect(try limit("ln(x)", at: .infinity) == .infinity)
    }

    /// MAT-07: xˣ = e^(x ln x) is not a polynomial in h; extrapolating as one gave 0.99999140327113.
    @Test func nonAnalyticLimitsAreExact() throws {
        #expect(abs(try limit("x^x", at: 0, .right) - 1) < 1e-9)
        #expect(abs(try limit("x*ln(x)", at: 0, .right)) < 1e-9)
        #expect(abs(try limit("(x-1)*ln(x-1)", at: 1, .right)) < 1e-9)
        #expect(abs(try limit("ln(x)/x", at: .infinity)) < 1e-9)
        #expect(abs(try limit("x^(1/x)", at: .infinity) - 1) < 1e-9)
        #expect(abs(try limit("sqrt(x)", at: 0, .right)) < 1e-9)
    }

    /// MAT-07: rounding noise of the smallest steps was extrapolated (0.50000062712941, 0.49999794104719).
    @Test func cancellingLimitsStayAccurate() throws {
        #expect(abs(try limit("(1-cos(x))/x^2", at: 0) - 0.5) < 1e-9)
        #expect(abs(try limit("x*(sqrt(x^2+1)-x)", at: .infinity) - 0.5) < 1e-9)
    }

    /// MAT-07: the graph analysis reported the horizontal asymptote y = 8.6·10⁻⁶ for ln x / x.
    @Test func horizontalAsymptoteOfLnXOverX() throws {
        let analysis = FunctionAnalyzer.analyze(try parse("ln(x)/x"), range: 1...10, context: EvaluationContext())
        #expect(analysis.horizontalAsymptoteRight == 0)
    }

    @Test func oscillationHasNoLimit() throws {
        #expect(throws: MathError.domain("limita ne obstaja")) { try limit("sin(1/x)", at: 0) }
    }

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
}
