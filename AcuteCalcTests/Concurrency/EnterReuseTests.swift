import AcuteCore
import Foundation
import Testing
@testable import AcuteCalc

/// CON-06: "=" shows the result the live evaluation already computed for the same row and inputs
/// instead of calculating it again on the main actor, and calculates whenever an input changed.
@MainActor
@Suite(.serialized) struct EnterReuseTests {
    /// Default settings; the model holds them weakly, the suite instance keeps them alive during a test.
    let settings: AppSettings

    init() throws {
        let name = "AcuteCalcTests.EnterReuse"
        let defaults = try #require(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        settings = AppSettings(defaults: defaults)
    }

    /// A calculator whose calculations are counted.
    private func makeModel() -> (CalculatorModel, ConcurrencyTesting.Counter) {
        let model = CalculatorModel()
        model.settings = settings
        let counter = ConcurrencyTesting.Counter()
        let engine = model.calculate
        model.calculate = { row, inputs in
            counter.increment()
            return engine(row, inputs)
        }
        return (model, counter)
    }

    /// Waits until the live evaluation has shown its result.
    private func settle(_ model: CalculatorModel) async throws {
        let done = try await ConcurrencyTesting.eventually { !model.isEvaluating }
        try #require(done)
    }

    @Test func enterUsesTheLiveResult() async throws {
        let (model, counter) = makeModel()
        model.editor = MathEditor(root: .text("2+3"))
        try await settle(model)
        #expect(counter.value == 1)
        model.press(.enter)
        // Before the fix "=" calculated the same row with the same inputs again.
        #expect(counter.value == 1)
        #expect(model.lastAnswer?.value == 5)
    }

    @Test func repeatedEnterCalculatesAgain() async throws {
        let (model, counter) = makeModel()
        model.editor = MathEditor(root: .text("2"))
        try await settle(model)
        model.press(.enter)
        #expect(counter.value == 1)
        // The first "=" changed Ans and the random seed, so the second one calculates.
        model.press(.enter)
        #expect(counter.value == 2)
    }

    @Test func enterCalculatesAnEditNotYetEvaluated() async throws {
        let (model, counter) = makeModel()
        model.editor = MathEditor(root: .text("2+3"))
        try await settle(model)
        // "=" within the 40 ms before the live evaluation of the new row.
        model.editor = MathEditor(root: .text("2+4"))
        model.press(.enter)
        #expect(counter.value == 2)
        #expect(model.lastAnswer?.value == 6)
    }

    @Test func enterCalculatesInTheNewAngleUnit() async throws {
        let (model, counter) = makeModel()
        model.editor = MathEditor(root: MathRow([.function(.sin, argument: .text("30"))]))
        try await settle(model)
        // DRG (radians → degrees), then "=" before the new live evaluation ran.
        model.press(.angleMode)
        model.press(.enter)
        #expect(counter.value == 2)
        #expect(settings.angleUnit == .degrees)
        // sin 30° = 1/2; in radians it would be −0.988… (the tolerance only allows rounding).
        let answer = try #require(model.lastAnswer)
        #expect(abs(answer.value - 0.5) < 1e-12)
    }

    @Test func enterAfterModifyCalculatesAgain() async throws {
        let (model, counter) = makeModel()
        model.editor = MathEditor(root: .text("2"))
        try await settle(model)
        model.press(.enter)
        // A digit after "=" starts a new row; Ans is 2, the same as its rounded result.
        model.press(.digit(2))
        try await settle(model)
        let before = counter.value
        // MDF replaces the shown result, so "=" calculates the row again, as before the fix.
        model.press(.modify)
        try #require(model.resultFormat == .decimal)
        model.press(.enter)
        #expect(counter.value == before + 1)
    }
}
