import AcuteCore
import Foundation
import SwiftUI
import Testing
@testable import AcuteCalc

/// PLT-11: the iPadOS menu bar had no commands of the app. The menu Računalo lists the calculator's
/// commands; each runs, once, the keypad key that its hardware key (Return, Esc) already runs, and
/// ⌘Z, ⇧⌘Z and ⌘A stay in the system Edit menu. (Before the fix there was no menu to test.)
@MainActor
@Suite struct MenuBarCommandsTests {
    /// Records the keys a command presses.
    final class RecordingTarget: KeypadTarget {
        var paletteExpanded = false
        var selectedPage: SymbolPage = .main
        var enterShowsEquals: Bool { true }
        var storeMode: Bool { false }
        var pressed: [KeypadKey] = []

        func press(_ key: KeypadKey) { pressed.append(key) }
    }

    @Test func eachCommandPressesItsKeyOnce() {
        for command in CalculatorMenuCommand.allCases {
            let target = RecordingTarget()
            command.perform(on: target)
            #expect(target.pressed == [command.key])
        }
    }

    /// One source of truth: the menu runs what KeyboardInput maps Return and Esc to.
    @Test func commandsMatchTheHardwareKeys() throws {
        let titles = CalculatorMenuCommand.allCases.map { $0.title }
        #expect(titles == ["Izračunaj", "Počisti"])
        let hardwareKeys: [CalculatorMenuCommand: KeyEquivalent] = [.calculate: .return, .clear: .escape]
        for command in CalculatorMenuCommand.allCases {
            let hardwareKey = try #require(hardwareKeys[command])
            let mapped = KeypadKey(key: hardwareKey, characters: String(hardwareKey.character))
            #expect(mapped == command.key)
        }
    }

    @Test func undoRedoAndSelectAllStayInTheEditMenu() {
        let keys = CalculatorMenuCommand.allCases.map { $0.key }
        #expect(!keys.contains(.undo))
        #expect(!keys.contains(.redo))
        #expect(!keys.contains(.selectAll))
    }

    /// Through the calculator itself: Izračunaj shows the result of 2 + 3, Počisti empties the expression.
    @Test func commandsDriveTheCalculator() throws {
        let name = "AcuteCalcTests.MenuBar"
        let defaults = try #require(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        let settings = AppSettings(defaults: defaults)   // the model keeps the settings weakly
        let model = CalculatorModel()
        model.settings = settings
        for key: KeypadKey in [.digit(2), .symbol(.plus), .digit(3)] { model.press(key) }

        CalculatorMenuCommand.calculate.perform(on: model)
        #expect(model.committed)
        #expect(model.lastAnswer?.value == 5)

        CalculatorMenuCommand.clear.perform(on: model)
        #expect(model.editor.isEmpty)
        #expect(!model.committed)
    }
}
