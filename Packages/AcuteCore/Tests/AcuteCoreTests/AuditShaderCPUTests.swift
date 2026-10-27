import Foundation
import Testing
@testable import AcuteCore

/// CPU side of the shader-precision audit (the GPU tests are in AcuteCalcTests/ShaderPrecision).
@Suite struct AuditShaderCPUTests {
    /// The graph of F ≠ G must be the strict region |F − G| > 0 (filled, with the dashed edge of < and >),
    /// not the curve F = G: that curve is exactly the set of points that are NOT solutions (SHD-07).
    /// Before the fix every path returned `.implicit(F, .notEqual, G)`, which the renderer draws as F = G.
    /// |F − G| is max(F − G, G − F), less the tolerance of ≠ on the GPU, 10⁻⁶·max(1, |F|, |G|).
    private func isStrictRegion(_ request: GraphRequest?, _ lhs: Expr, _ rhs: Expr) -> Bool {
        let tolerance = Expr.product([.decimal(1e-6), .function(.max, [.one, .function(.abs, [lhs]), .function(.abs, [rhs])])])
        let region: [GraphKind] = [.implicit(lhs: Expr.function(.max, [lhs - rhs, rhs - lhs]) - tolerance, relation: .greater, rhs: .zero)]
        return request?.kinds == region
    }

    private func drawsNotEqual(_ request: GraphRequest?) -> Bool {
        request?.kinds.contains { kind in
            if case .implicit(_, .notEqual, _) = kind { return true }
            return false
        } ?? false
    }

    @Test func notEqualInXIsAStrictRegion() throws {
        let relation = try parse("x ≠ 2")
        guard case .relation(let lhs, .notEqual, let rhs) = relation else {
            Issue.record("x ≠ 2 did not parse as a ≠ relation")
            return
        }
        let calculation = CalculationEngine.calculate(relation, variables: [:], exactVariables: [:], settings: CalculationSettings())
        #expect(isStrictRegion(calculation.graph, lhs, rhs))
        #expect(isStrictRegion(CalculationEngine.graphRequest(for: relation), lhs, rhs))
    }

    @Test func notEqualInXAndYIsAStrictRegion() throws {
        let relation = try parse("x ≠ y")
        guard case .relation(let lhs, .notEqual, let rhs) = relation else {
            Issue.record("x ≠ y did not parse as a ≠ relation")
            return
        }
        let calculation = CalculationEngine.calculate(relation, variables: [:], exactVariables: [:], settings: CalculationSettings())
        #expect(isStrictRegion(calculation.graph, lhs, rhs))
        #expect(isStrictRegion(CalculationEngine.graphRequest(for: relation), lhs, rhs))
    }

    /// y = x², x ≠ 1: the parabola without the point x = 1, not the parabola plus the line x = 1.
    @Test func notEqualInASystemRestrictsTheCurve() throws {
        let relations = [try parse("y = x^2"), try parse("x ≠ 1")]
        let request = try #require(CalculationEngine.systemGraph(relations))
        #expect(!drawsNotEqual(request))
        #expect(request.kinds.count == 1)
        guard case .implicit(.piecewise(let parts), .equal, _)? = request.kinds.first else {
            Issue.record("expected the parabola restricted to |x − 1| > 0, got \(request.kinds)")
            return
        }
        #expect(parts.count == 2)
    }

    /// Unchanged: x = 2 is still the vertical line.
    @Test func equalityIsStillTheCurve() throws {
        let equation = try parse("x = 2")
        let request = try #require(CalculationEngine.graphRequest(for: equation))
        #expect(!drawsNotEqual(request))
        guard case .explicitInY? = request.kinds.first else {
            Issue.record("x = 2 is no longer the vertical line: \(request.kinds)")
            return
        }
    }
}
