import AcuteCore
import Foundation
import Testing
@testable import AcuteCalc

/// concurrency:4 (audit 2026-11-07): every parameter tick of the 2D workspace (a slider, "Animiraj", every ~16 ms)
/// cancelled the shaded integrals and started them again, also when no shaded row uses that parameter, and the
/// cancellation never reached the integration in its detached task. A job now keeps only the parameters its f and g
/// use, and an unchanged job goes on.
@MainActor
@Suite struct GraphIntegralTickTests {
    /// y = `text`, shaded from 0 to 1.
    private func shaded(_ text: String) throws -> GraphFunctionDefinition {
        var definition = try GraphFunctionDefinition(row: MathRowConverter.row(fromText: text), colorIndex: 0)
        definition.shadeEnabled = true
        definition.shadeFrom = 0
        definition.shadeTo = 1
        return definition
    }

    private func sync(_ model: GraphWorkspaceModel, _ definitions: [GraphFunctionDefinition], a: Double) {
        model.sync(definitions, parameters: ["a": a], lineWidth: 3, showSpecialPoints: true)
    }

    @Test func aTickOfAnotherRowsParameterKeepsTheIntegralGoing() async throws {
        let model = GraphWorkspaceModel()
        let area = try shaded("x^2")
        let other = try GraphFunctionDefinition(row: MathRowConverter.row(fromText: "a*x"), colorIndex: 1)
        sync(model, [area, other], a: 1)
        try #require(model.integralRuns == 1)
        sync(model, [area, other], a: 1.25)
        // Before the fix the tick cancelled the integral of x², which does not use a, and started it again.
        #expect(model.integralRuns == 1)
        let done = try await ConcurrencyTesting.eventually { model.integrals[area.id] != nil }
        try #require(done)
        let summary = try #require(model.integrals[area.id])
        #expect(abs(summary.signed - 1.0 / 3) < 1e-12)
    }

    @Test func aTickOfTheShadedRowsParameterComputesItAgain() async throws {
        let model = GraphWorkspaceModel()
        let area = try shaded("a*x^2")
        sync(model, [area], a: 1)
        sync(model, [area], a: 1.5)
        #expect(model.integralRuns == 2)
        // ∫₀¹ 1.5·x² dx = 0.5: the integral for the value of a now, not for the first one.
        let done = try await ConcurrencyTesting.eventually {
            guard let summary = model.integrals[area.id] else { return false }
            return abs(summary.signed - 0.5) < 1e-12
        }
        #expect(done)
    }
}
