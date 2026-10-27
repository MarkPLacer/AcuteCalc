import SwiftUI

/// A command of the calculator in the iPadOS menu bar (menu Računalo). It runs the keypad key that
/// Return or Esc already runs from a hardware keyboard (KeyboardInput).
///
/// The items get no keyboard shortcut. SwiftUI makes a key command of every command with one, and
/// Apple documents neither whether such a key command comes before the focused view's `onKeyPress`
/// nor whether a disabled one lets the key through; a plain Return or Esc in the menu could then run
/// the calculator's action instead of a graph editor's or a text field's, or get lost. KeyboardInput
/// stays the only handler of the keys, so every key press works exactly as before.
enum CalculatorMenuCommand: CaseIterable, Identifiable {
    case calculate, clear

    var id: Self { self }

    var title: String {
        switch self {
        case .calculate: "Izračunaj"
        case .clear: "Počisti"
        }
    }

    var key: KeypadKey {
        switch self {
        case .calculate: .enter
        case .clear: .clear
        }
    }

    /// Runs the command like its key on the keypad or the hardware keyboard.
    func perform(on target: some KeypadTarget) {
        target.press(key)
    }
}

/// The iPadOS menu bar: the sections as items of the View menu and the calculator's commands.
/// Undo, Redo and Select All stay in the system Edit menu.
struct AppCommands: Commands {
    @FocusedBinding(\.appSection) private var section: AppTab?
    @FocusedValue(\.calculator) private var calculator: CalculatorModel?

    var body: some Commands {
        CommandGroup(after: .sidebar) {
            Picker("Razdelek", selection: Binding(get: { section ?? .calculator }, set: { section = $0 })) {
                ForEach(AppTab.allCases) { tab in
                    Label(tab.title, systemImage: tab.systemImage).tag(tab)
                }
            }
            .disabled(section == nil)
        }
        CommandMenu("Računalo") {
            ForEach(CalculatorMenuCommand.allCases) { command in
                Button(command.title) {
                    if let calculator { command.perform(on: calculator) }
                }
            }
            // Only while the calculator is the window's section.
            .disabled(section != .calculator || calculator == nil)
        }
    }
}

extension FocusedValues {
    /// The window's section (RootView's tab), for the View menu.
    @Entry var appSection: Binding<AppTab>?
    /// The window's calculator, for the Računalo menu.
    @Entry var calculator: CalculatorModel?
}
