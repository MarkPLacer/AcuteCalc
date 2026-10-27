import AcuteCore
import Foundation
import Testing
@testable import AcuteCalc

/// UI-07 (c): moving the caret does not calculate the unchanged row again; editing the row does.
@MainActor
@Suite struct CaretMoveTests {
    /// A calculator whose calculations are counted, showing the live result of `text`.
    private func makeModel(showing text: String) async throws -> (CalculatorModel, ConcurrencyTesting.Counter) {
        let model = CalculatorModel()
        let counter = ConcurrencyTesting.Counter()
        let engine = model.calculate
        model.calculate = { row, inputs in
            counter.increment()
            return engine(row, inputs)
        }
        model.editor = MathEditor(root: .text(text))
        try await settle(model)
        try #require(counter.value == 1)
        return (model, counter)
    }

    /// Waits until the live evaluation has shown its result.
    private func settle(_ model: CalculatorModel) async throws {
        let done = try await ConcurrencyTesting.eventually { !model.isEvaluating }
        try #require(done)
    }

    @Test func movingTheCaretDoesNotCalculate() async throws {
        let (model, counter) = try await makeModel(showing: "2+3")
        model.resultFormat = .decimal
        let before = model.editor
        model.press(.left)
        try #require(model.editor != before)
        // Before the fix the caret move scheduled a new evaluation of the same row.
        #expect(!model.isEvaluating)
        // Any change of the editor still resets the result format, as before.
        #expect(model.resultFormat == .automatic)
        // Longer than the 40 ms debounce of the live evaluation.
        try await Task.sleep(for: .milliseconds(300))
        #expect(counter.value == 1)
    }

    @Test func editingTheRowCalculates() async throws {
        let (model, counter) = try await makeModel(showing: "2+3")
        model.press(.left)
        model.press(.digit(4))
        #expect(model.isEvaluating)
        try await settle(model)
        #expect(counter.value == 2)
        guard case .number(let result)? = model.calculation?.outcome else {
            Issue.record("2+43 should give a number")
            return
        }
        #expect(result.value == 45)
    }

    @Test func movingTheCaretAfterEnterCalculatesAgain() async throws {
        let (model, counter) = try await makeModel(showing: "2")
        model.press(.enter)
        // "=" changed Ans and the random seed: the shown result is not the one for the new input,
        // so a caret move calculates the row again, as before the fix.
        model.press(.left)
        #expect(model.isEvaluating)
        try await settle(model)
        #expect(counter.value == 2)
    }
}
