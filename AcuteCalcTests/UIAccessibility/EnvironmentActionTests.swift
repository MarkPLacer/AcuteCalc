import AcuteCore
import Testing
@testable import AcuteCalc

/// UI-05: the environment actions are comparable values (no closure stored in @Entry, which made
/// the compiler warn that dependents may be invalidated on every update); calling them still runs
/// the handler, so `openInGraphs()` and `insertIntoCalculator(row)` work as before.
@MainActor
@Suite struct EnvironmentActionTests {
    final class Calls {
        var opened = 0
        var inserted: [MathRow] = []
    }

    @Test func actionsAreEqualValues() {
        #expect(OpenInGraphsAction({}) == OpenInGraphsAction({}))
        #expect(InsertIntoCalculatorAction({ _ in }) == InsertIntoCalculatorAction({ _ in }))
    }

    @Test func callingAnActionRunsItsHandler() {
        let calls = Calls()
        let open = OpenInGraphsAction { calls.opened += 1 }
        let insert = InsertIntoCalculatorAction { row in calls.inserted.append(row) }
        open()
        insert(MathRow.text("2+3"))
        #expect(calls.opened == 1)
        #expect(calls.inserted == [MathRow.text("2+3")])
    }
}
