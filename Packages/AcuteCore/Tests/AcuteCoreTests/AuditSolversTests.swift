import Foundation
import Testing
@testable import AcuteCore

// MARK: Audit: equations, inequalities and triangles

@Suite struct AuditSolversTests {
    func inequality(_ s: String) throws -> InequalitySolution {
        guard case .relation(let lhs, let op, let rhs) = try parse(s) else { throw MathError.syntax("ni neenačba") }
        return try #require(InequalitySolver.solve(lhs, op, rhs, context: EvaluationContext()))
    }

    func equation(_ lhs: String, _ rhs: String) throws -> EquationResult {
        try EquationSolver.solve(lhs: try parse(lhs), rhs: try parse(rhs), context: EvaluationContext())
    }

    // MAT-14: a local minimum of |f| was accepted against the largest |f| of the whole range.

    @Test func nearTangencyIsNotReportedAsRoot() throws {
        // eˣ − x − 0,9995 ≥ 0,0005 (minimum at x = 0) and cosh x − 0,9996 ≥ 0,0004: no real solution.
        #expect(try equation("e^x", "x+0.9995").solutions.isEmpty)
        #expect(try equation("cosh(x)", "0.9996").solutions.isEmpty)
        #expect(try inequality("e^x<=x+0.9995").isEmpty)
    }

    @Test func trueTangencyIsStillARoot() throws {
        // Guard for MAT-14 (passes before and after): eˣ = x + 1 touches at 0, sin x = 1 at π/2.
        // A touching root is located only to about √ε, hence 1e-7.
        let touching = try equation("e^x", "x+1")
        try #require(touching.solutions.count == 1)
        #expect(abs(touching.solutions[0].value) < 1e-7)
        let sine = try equation("sin(x)", "1")
        try #require(sine.solutions.count == 1)
        #expect(abs(sine.solutions[0].value - .pi / 2) < 1e-7)
    }
}
