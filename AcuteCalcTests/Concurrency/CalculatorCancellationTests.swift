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
        model.calculate = { _, _ in
            probe.runFirstCallUntilCancelled(limit: .seconds(3))
            return Calculation(expr: nil, outcome: .empty, graph: nil)
        }
        model.editor = MathEditor(root: .text("1"))
        let started = try await ConcurrencyTesting.eventually { probe.started }
        try #require(started)
        // Typing on: the model cancels the running evaluation and schedules the next one.
        model.editor = MathEditor(root: .text("12"))
        let finished = try await ConcurrencyTesting.eventually { probe.finished }
        try #require(finished)
        // Before the fix the first calculation never saw the cancellation and ran to the 3 s limit.
        #expect(probe.sawCancellation)
    }
}
