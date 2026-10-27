import AcuteCore
import Foundation
import Testing
@testable import AcuteCalc

/// CON-11, UI-04 (c): a parameter tick of the 2D workspace (a slider, "Animiraj", every ~16 ms) parses no row and
/// forms no derivative again, because only the parameter values changed; a keystroke forms the derivatives of the
/// edited row only. What is drawn and shown is the same as a new calculation gives.
@MainActor
@Suite struct GraphParameterTickTests {
    /// y = a·sin(x)·eˣ with f′ and T₂₀ around 0 (the case of the finding).
    private func definition(_ text: String = "a*sin(x)*e^x") throws -> GraphFunctionDefinition {
        var definition = try GraphFunctionDefinition(row: MathRowConverter.row(fromText: text), colorIndex: 0)
        definition.showDerivative = true
        definition.taylorEnabled = true
        definition.taylorOrder = 20
        return definition
    }

    private func sync(_ model: GraphWorkspaceModel, _ definitions: [GraphFunctionDefinition], a: Double) {
        model.sync(definitions, parameters: ["a": a], lineWidth: 3, showSpecialPoints: true)
    }

    @Test func aParameterTickParsesAndDifferentiatesNothing() throws {
        let model = GraphWorkspaceModel()
        let definitions = try [definition()]
        sync(model, definitions, a: 1)
        let before = model.symbolicWork
        try #require(before.parses == 1)
        try #require(before.derivatives >= 20)
        sync(model, definitions, a: 1.25)
        // Before the fix the tick parsed the row and formed f′ and f′ … f⁽²⁰⁾ again (21 derivatives).
        #expect(model.symbolicWork.parses == before.parses)
        #expect(model.symbolicWork.derivatives == before.derivatives)
    }

    @Test func aTickShowsWhatANewCalculationShows() throws {
        // A row with f′ and T₂₀, and one shown only in 3D (its note).
        let definitions = try [definition(), GraphFunctionDefinition(row: MathRowConverter.row(fromText: "x*y"), colorIndex: 1)]
        let ticked = GraphWorkspaceModel()
        sync(ticked, definitions, a: 1)
        sync(ticked, definitions, a: 1.25)
        let fresh = GraphWorkspaceModel()
        sync(fresh, definitions, a: 1.25)
        #expect(ticked.canvas.items == fresh.canvas.items)
        #expect(ticked.canvas.parameters == ["a": 1.25])
        #expect(ticked.derivatives == fresh.derivatives)
        #expect(ticked.taylorPolynomials == fresh.taylorPolynomials)
        #expect(ticked.errors == fresh.errors)
        #expect(ticked.notes == fresh.notes)
        #expect(ticked.notes.count == 1)
        #expect(ticked.parameterNames == ["a"])
        // The same as the engine gives for a = 1.25 directly (the code before the caching).
        let id = definitions[0].id
        let f = try #require(ticked.primaryExpressions[id])
        let taylor = try #require(TaylorSeries.polynomial(of: f, around: 0, order: 20, context: EvaluationContext(variables: ["a": 1.25])))
        #expect(ticked.taylorPolynomials[id] == taylor)
        let derivative = try Differentiator.derivative(of: f, withRespectTo: "x")
        #expect(ticked.derivatives[id] == Simplifier.simplify(derivative))
    }

    @Test func editingOneRowFormsTheDerivativesOfThatRowOnly() throws {
        let model = GraphWorkspaceModel()
        var definitions = try [definition(), definition("x^2")]
        sync(model, definitions, a: 1)
        let before = model.symbolicWork
        // A keystroke in the second row.
        definitions[1].row = try MathRowConverter.row(fromText: "x^2+1")
        sync(model, definitions, a: 1)
        // The work the edited row needs on its own.
        let alone = GraphWorkspaceModel()
        sync(alone, [definitions[1]], a: 1)
        // The rows changed, so both are parsed again …
        #expect(model.symbolicWork.parses == before.parses + 2)
        // … but the derivatives of a·sin(x)·eˣ are kept. Before the fix both rows formed theirs again.
        #expect(model.symbolicWork.derivatives - before.derivatives == alone.symbolicWork.derivatives)
        // The edited row shows its own f′ and T₂₀.
        let id = definitions[1].id
        #expect(model.derivatives[id] == alone.derivatives[id])
        #expect(model.taylorPolynomials[id] == alone.taylorPolynomials[id])
        #expect(model.derivatives[id] != nil)
    }

    @Test func aNewCentreAndOrderGiveTheirPolynomial() throws {
        let model = GraphWorkspaceModel()
        var definitions = try [definition()]
        sync(model, definitions, a: 1)
        definitions[0].taylorCenter = 0.5
        definitions[0].taylorOrder = 5
        sync(model, definitions, a: 1)
        let id = definitions[0].id
        let f = try #require(model.primaryExpressions[id])
        let taylor = try #require(TaylorSeries.polynomial(of: f, around: 0.5, order: 5, context: EvaluationContext(variables: ["a": 1])))
        #expect(model.taylorPolynomials[id] == taylor)
    }

    @Test func aRowThatReplacesAnotherIsDrawnUnderItsOwnID() throws {
        let model = GraphWorkspaceModel()
        let first = try definition()
        sync(model, [first], a: 1)
        // The same text in a new row (the old one deleted): the parse must not be reused under the old id.
        let second = try definition()
        sync(model, [second], a: 1)
        let ids = model.canvas.items.map(\.id)
        let allOfTheNewRow = ids.allSatisfy { $0.hasPrefix(second.id.uuidString) }
        #expect(!ids.isEmpty)
        #expect(allOfTheNewRow)
        #expect(model.primaryExpressions[second.id] != nil)
        #expect(model.primaryExpressions[first.id] == nil)
    }
}
