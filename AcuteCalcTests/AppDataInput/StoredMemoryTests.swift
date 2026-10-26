import AcuteCore
import Foundation
import Testing
@testable import AcuteCalc

/// GAP-gap-preview-vars-2: "1/2 STO M" while the memory M is 0. numericVariables gives M the memory (0),
/// exactVariables gave it the stored 1/2, so M + 1/3 was value 1/3 with exact 5/6, shown as "= 5/6 ≈ 0,3333".
@MainActor
@Suite struct StoredMemoryTests {
    @Test func memoryMHasOneValue() throws {
        let directory = try AppDataInputTestSupport.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = AppStore(fileURL: directory.appendingPathComponent("AcuteCalcData.json"))
        store.store(0.5, rational: Rational(1, 2), in: "M")
        store.store(0.5, rational: Rational(1, 2), in: "A")

        #expect(store.numericVariables["M"] == 0)
        #expect(store.exactVariables["M"] == nil)            // before the fix: 1/2
        #expect(store.exactVariables["A"]?.doubleValue == 0.5)

        let calculation = CalculationEngine.calculate(MathRow.text("M+1/3"), variables: store.numericVariables,
                                                      exactVariables: store.exactVariables, settings: CalculationSettings())
        guard case .number(let r) = calculation.outcome else {
            Issue.record("M + 1/3 is not a number")
            return
        }
        // M is the memory 0: M + 1/3 = 1/3 (0.333…; 1/3 is not exact in Double, so a tolerance of 1e-15).
        #expect(abs(r.value - 1.0 / 3) < 1e-15, "M + 1/3 gave \(r.value), exact \(String(describing: r.exact))")
        let agrees = r.exact.map { abs($0.doubleValue - r.value) < 1e-12 } ?? true
        #expect(agrees)                                      // before the fix: exact 5/6
    }
}
