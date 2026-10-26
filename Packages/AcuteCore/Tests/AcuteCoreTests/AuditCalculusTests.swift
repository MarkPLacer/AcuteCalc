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
}
