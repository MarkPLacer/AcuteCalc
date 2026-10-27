import AcuteCore
import Foundation
import Testing
@testable import AcuteCalc

/// PLT-06: a hardware keyboard sends letters as .typedLetter, but after STO only .variable stored the
/// answer, so 4 = STO ⇧A cleared the expression and typed A instead of storing 4 in A.
@MainActor
@Suite struct HardwareKeyboardStoreTests {
    @Test func storeThenTypedMemoryLetterStoresTheAnswer() throws {
        let directory = try AppDataInputTestSupport.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let suite = "AppDataInput-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = AppStore(fileURL: directory.appendingPathComponent("AcuteCalcData.json"))
        let settings = AppSettings(defaults: defaults)   // the model keeps store and settings weakly
        let model = CalculatorModel()
        model.store = store
        model.settings = settings

        for key: KeypadKey in [.digit(4), .enter, .store, .typedLetter("A")] { model.press(key) }
        #expect(store.variables["A"]?.value == 4)   // before the fix: nil, A was typed into a cleared editor
        #expect(!model.storeMode)
    }

    /// Not a regression test: a letter that names no memory still starts a new expression, as before.
    @Test func storeThenOtherLetterStoresNothing() throws {
        let directory = try AppDataInputTestSupport.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let suite = "AppDataInput-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = AppStore(fileURL: directory.appendingPathComponent("AcuteCalcData.json"))
        let settings = AppSettings(defaults: defaults)   // the model keeps store and settings weakly
        let model = CalculatorModel()
        model.store = store
        model.settings = settings

        for key: KeypadKey in [.digit(4), .enter, .store, .typedLetter("k")] { model.press(key) }
        #expect(store.variables.isEmpty)
    }
}
