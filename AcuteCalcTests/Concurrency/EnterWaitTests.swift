import AcuteCore
import Foundation
import Testing
@testable import AcuteCalc

/// concurrency:3 (audit 2026-11-07): "=" while the live evaluation of the same row and inputs is calculating waits for
/// its result. Before, "=" cancelled it and calculated the row again on the main actor, which blocked the app for as
/// long as the row takes (a Σ of 5·10⁶ terms). Every input after "=" still sees the result, Ans and the committed
/// state, as after the synchronous "=".
@MainActor
@Suite(.serialized) struct EnterWaitTests {
    /// Default settings; the model holds them weakly, the suite instance keeps them alive during a test.
    let settings: AppSettings

    init() throws {
        let name = "AcuteCalcTests.EnterWait"
        let defaults = try #require(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        settings = AppSettings(defaults: defaults)
    }

    /// A calculator whose calculations are counted; the first one (the live evaluation of the first row) runs until
    /// `probe` is released or the evaluation is cancelled.
    private func makeModel(_ probe: ConcurrencyTesting.CancellationProbe) -> (CalculatorModel, ConcurrencyTesting.Counter) {
        let model = CalculatorModel()
        model.settings = settings
        let counter = ConcurrencyTesting.Counter()
        let engine = model.calculate
        model.calculate = { row, inputs in
            counter.increment()
            probe.runFirstCallUntilCancelled()
            return engine(row, inputs)
        }
        return (model, counter)
    }

    /// Types `text` and waits until its live evaluation is calculating.
    private func typeRow(_ text: String, into model: CalculatorModel, _ probe: ConcurrencyTesting.CancellationProbe) async throws {
        model.editor = MathEditor(root: .text(text))
        let started = try await ConcurrencyTesting.eventually { probe.started }
        try #require(started)
    }

    @Test func enterWaitsForTheRunningLiveEvaluation() async throws {
        let probe = ConcurrencyTesting.CancellationProbe()
        // Ends the first calculation also when the test stops early.
        defer { probe.release() }
        let (model, counter) = makeModel(probe)
        try await typeRow("2+3", into: model, probe)
        model.press(.enter)
        // Before the fix "=" cancelled the live evaluation and calculated the row again on the main actor.
        #expect(counter.value == 1)
        #expect(!model.committed)
        // A view can show the wait.
        #expect(model.isEnterPending)
        probe.release()
        let committed = try await ConcurrencyTesting.eventually { model.committed }
        try #require(committed)
        #expect(!model.isEnterPending)
        #expect(counter.value == 1)
        #expect(!probe.sawCancellation)
        #expect(model.lastAnswer?.value == 5)
    }

    /// Not a regression test: a key while "=" waits comes after "=", as it did when "=" calculated synchronously.
    @Test func aKeyWhileEnterWaitsComesAfterIt() async throws {
        let probe = ConcurrencyTesting.CancellationProbe()
        defer { probe.release() }
        let (model, _) = makeModel(probe)
        try await typeRow("2+3", into: model, probe)
        model.press(.enter)
        model.press(.digit(7))
        // "=" committed 2 + 3 first: Ans is 5, and the digit started a new row (7, not 2 + 37).
        #expect(!model.isEnterPending)
        #expect(model.lastAnswer?.value == 5)
        let shown = try await ConcurrencyTesting.eventually { !model.isEvaluating }
        try #require(shown)
        guard case .number(let result)? = model.calculation?.outcome else {
            Issue.record("7 should give a number")
            return
        }
        #expect(result.value == 7)
    }

    /// Not a regression test: an edit straight into the row (a tap into it, a paste) while "=" waits comes after "=",
    /// and the history gets the row "=" calculated, not the edited one.
    @Test func anEditWhileEnterWaitsComesAfterIt() async throws {
        let directory = try AppDataInputTestSupport.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = AppStore(fileURL: directory.appendingPathComponent("AcuteCalcData.json"))
        let probe = ConcurrencyTesting.CancellationProbe()
        defer { probe.release() }
        let (model, _) = makeModel(probe)
        model.store = store
        try await typeRow("2+3", into: model, probe)
        model.press(.enter)
        model.editor = MathEditor(root: .text("2+3+1"))
        #expect(!model.isEnterPending)
        #expect(store.history.count == 1)
        #expect(store.history.first?.expression == MathRow.text("2+3"))
        #expect(model.lastAnswer?.value == 5)
        let shown = try await ConcurrencyTesting.eventually { !model.isEvaluating }
        try #require(shown)
        guard case .number(let result)? = model.calculation?.outcome else {
            Issue.record("2+3+1 should give a number")
            return
        }
        #expect(result.value == 6)
    }
}
