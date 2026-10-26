import AcuteCore
import Foundation
import Testing
@testable import AcuteCalc

/// GAP-gap-preview-vars-2: "1/2 STO M" while the memory M is 0. numericVariables gives M the memory (0),
/// exactVariables gave it the stored 1/2, so M + 1/3 was value 1/3 with exact 5/6, shown as "= 5/6 ≈ 0,3333".
@MainActor
@Suite struct StoredMemoryTests {
    /// A failed check recorded as an error, so that its values are in the first line of the issue ("Caught error: …"):
    /// CI (xcbeautify) shows only that line, not the comment of an #expect or of Issue.record("…").
    nonisolated struct CheckFailure: Error, CustomStringConvertible {
        let description: String
    }

    @Test func memoryMHasOneValue() throws {
        let directory = try AppDataInputTestSupport.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = AppStore(fileURL: directory.appendingPathComponent("AcuteCalcData.json"))
        store.store(0.5, rational: Rational(1, 2), in: "M")
        store.store(0.5, rational: Rational(1, 2), in: "A")

        #expect(store.numericVariables["M"] == 0)
        #expect(store.exactVariables["M"] == nil)            // before the fix: 1/2
        #expect(store.exactVariables["A"]?.doubleValue == 0.5)

        // The row the keys RCL + 1 ÷ 3 type (the M key and an M typed on a hardware keyboard insert the same variable).
        let row = MathRow.text("M+1/3")
        var typed = MathEditor()
        for key: KeypadKey in [.memoryRecall, .symbol(.plus), .digit(1), .symbol(.divide), .digit(3)] { _ = typed.apply(key) }
        #expect(typed.root == row)

        let calculation = CalculationEngine.calculate(row, variables: store.numericVariables,
                                                      exactVariables: store.exactVariables, settings: CalculationSettings())
        guard case .number(let r) = calculation.outcome else {
            Issue.record(CheckFailure(description: "M + 1/3 is not a number: \(calculation.outcome)"))
            return
        }
        // M is the memory 0: M + 1/3 = 1/3, rounded to 14 significant digits like every result of the calculator
        // (CalculationEngine.numeric → NumericCalculus.clean): 0.33333333333333, 3.3e-15 from the Double 1/3.
        let expected = NumericCalculus.clean(1.0 / 3)
        if r.value != expected {
            Issue.record(CheckFailure(description: "M + 1/3 gave \(r.value), expected \(expected) (exact \(String(describing: r.exact)))"))
        }
        let agrees = r.exact.map { abs($0.doubleValue - r.value) < 1e-12 } ?? true
        if !agrees {                                         // before the fix: exact 5/6
            Issue.record(CheckFailure(description: "M + 1/3 gave exact \(String(describing: r.exact)) next to the value \(r.value)"))
        }
    }
}
