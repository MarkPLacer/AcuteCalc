import AcuteCore
import Foundation
import Testing
@testable import AcuteCalc

/// CON-07: a new keystroke cancels the live evaluation, and the cancellation must reach the work in
/// its detached task (a detached task does not inherit cancellation from the task that awaits it).
@MainActor
@Suite struct CalculatorCancellationTests {
    @Test func newInputCancelsTheRunningCalculation() async throws {
        let model = CalculatorModel()
        let probe = ConcurrencyTesting.CancellationProbe()
        // Ends the first calculation also when the test stops early.
        defer { probe.release() }
        model.calculate = { _, _ in
            probe.runFirstCallUntilCancelled()
            return Calculation(expr: nil, outcome: .empty, graph: nil)
        }
        model.editor = MathEditor(root: .text("1"))
        let started = try await ConcurrencyTesting.eventually { probe.started }
        try #require(started)
        // Typing on: the model cancels the running evaluation and schedules the next one.
        model.editor = MathEditor(root: .text("12"))
        let shown = try await ConcurrencyTesting.eventually { !model.isEvaluating }
        try #require(shown)
        // The result for "12" is shown; by now the first calculation must have seen the cancellation.
        // Before the fix it never did and ran on until it was released here.
        probe.release()
        let finished = try await ConcurrencyTesting.eventually { probe.finished }
        try #require(finished)
        #expect(probe.sawCancellation)
    }
}
