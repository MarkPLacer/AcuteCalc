import SwiftUI
import Testing
@testable import AcuteCalc

/// PLT-07: Apple Pencil Pro double tap and squeeze follow Settings › Apple Pencil. Before the fix
/// the calculator and the definition editors deleted on every double tap and toggled the palette
/// on every squeeze, also with the setting Off (.ignore). PencilGestures does not exist there, so
/// on main this file does not compile.
@MainActor
@Suite struct PencilGestureTests {
    /// Every choice but Off and Run Shortcut: Switch to eraser (the default for double tap), Switch
    /// to last used, Show colour palette, Show ink attributes, Show tool palette (the default for
    /// squeeze).
    var switchedOn: [PencilPreferredAction] {
        [.switchEraser, .switchPrevious, .showColorPalette, .showInkAttributes, .showContextualPalette]
    }

    @Test func doubleTapSetToOffDoesNotDelete() {
        let deletes = PencilGestures.doubleTapDeletes(preferredAction: .ignore)
        #expect(!deletes)
    }

    @Test func doubleTapDeletesWithEveryOtherChoice() {
        for action in switchedOn {
            let name = String(describing: action)
            let deletes = PencilGestures.doubleTapDeletes(preferredAction: action)
            #expect(deletes, "\(name)")
        }
        // The system runs a shortcut without notifying the app; the decision stays as before.
        let deletesForShortcut = PencilGestures.doubleTapDeletes(preferredAction: .runSystemShortcut)
        #expect(deletesForShortcut)
    }

    @Test func squeezeSetToOffDoesNotTogglePalette() {
        let toggles = PencilGestures.squeezeTogglesPalette(preferredAction: .ignore)
        #expect(!toggles)
    }

    @Test func squeezeRunningAShortcutDoesNotTogglePalette() {
        let toggles = PencilGestures.squeezeTogglesPalette(preferredAction: .runSystemShortcut)
        #expect(!toggles)
    }

    @Test func squeezeTogglesPaletteWithEveryOtherChoice() {
        for action in switchedOn {
            let name = String(describing: action)
            let toggles = PencilGestures.squeezeTogglesPalette(preferredAction: action)
            #expect(toggles, "\(name)")
        }
    }
}
