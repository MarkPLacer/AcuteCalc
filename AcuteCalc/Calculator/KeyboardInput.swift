import AcuteCore
import Observation
import SwiftUI

extension KeypadKey {
    /// Maps a hardware-keyboard key press (iPad Magic Keyboard, Smart Keyboard) to a keypad key.
    init?(keyPress press: KeyPress) {
        switch press.key {
        case .return: self = .enter; return
        case .delete: self = .delete; return
        case .escape: self = .clear; return
        case .leftArrow: self = .left; return
        case .rightArrow: self = .right; return
        case .upArrow: self = .up; return
        case .downArrow: self = .down; return
        default: break
        }
        guard let c = press.characters.first else { return nil }
        if c.isASCII, let d = c.wholeNumberValue {
            self = .digit(d)
            return
        }
        switch c {
        case ".", ",": self = .point
        case "+": self = .symbol(.plus)
        case "-", "−": self = .symbol(.minus)
        case "*", "·", "×": self = .symbol(.times)
        case "/": self = .fraction
        case ":", "÷": self = .symbol(.divide)
        case "^": self = .power
        case "(": self = .symbol(.leftParenthesis)
        case ")": self = .symbol(.rightParenthesis)
        case "=": self = .symbol(.equals)
        case "<": self = .symbol(.less)
        case ">": self = .symbol(.greater)
        case "!": self = .symbol(.factorial)
        case "%": self = .symbol(.percent)
        case "|": self = .abs
        case ";": self = .symbol(.comma)
        case "π": self = .symbol(.constant(.pi))
        case "∞": self = .symbol(.constant(.infinity))
        default:
            guard c.isLetter else { return nil }
            self = .typedLetter(String(c))
        }
    }

    /// ⌘Z, ⇧⌘Z and ⌘A (copy, cut and paste are system commands handled by the clipboard modifiers).
    init?(commandPress press: KeyPress) {
        guard press.modifiers.contains(.command), let c = press.characters.lowercased().first else { return nil }
        switch c {
        case "z": self = press.modifiers.contains(.shift) ? .redo : .undo
        case "a": self = .selectAll
        default: return nil
        }
    }
}

extension View {
    /// Routes hardware-keyboard presses to a keypad target.
    func keypadKeyboardInput<Target: KeypadTarget>(_ target: Target) -> some View {
        onKeyPress(phases: [.down, .repeat]) { press in
            if press.modifiers.contains(.command) {
                guard let key = KeypadKey(commandPress: press) else { return .ignored }
                target.press(key)
                return .handled
            }
            guard let key = KeypadKey(keyPress: press) else { return .ignored }
            target.press(key)
            return .handled
        }
    }
}

/// Keypad target for editing one definition (graph function, surface, complex function).
@Observable
final class FunctionEditorModel: KeypadTarget {
    var editor = MathEditor() {
        didSet {
            guard editor != oldValue else { return }
            if !isRestoringUndo { registerUndo(previous: oldValue) }
            onChange?(editor.root)
        }
    }
    var paletteExpanded = false
    var selectedPage: SymbolPage = .main
    var storeMode: Bool { false }
    var enterShowsEquals: Bool { false }

    @ObservationIgnored var onChange: ((MathRow) -> Void)?
    @ObservationIgnored var onCommit: (() -> Void)?
    @ObservationIgnored weak var settings: AppSettings?
    @ObservationIgnored weak var undoManager: UndoManager?
    @ObservationIgnored private var isRestoringUndo = false

    /// The undo manager keeps only an unowned reference to the target: a step of a released editor
    /// (after switching the Graphs space) would crash the next undo.
    isolated deinit {
        undoManager?.removeAllActions(withTarget: self)
    }

    /// Starts editing `row` without reporting it back as a change (and without an undo step).
    /// Steps of the previous session are dropped, so an undo cannot write them into this definition.
    func load(_ row: MathRow) {
        undoManager?.removeAllActions(withTarget: self)
        let callback = onChange
        onChange = nil
        isRestoringUndo = true
        editor = MathEditor(root: row)
        isRestoringUndo = false
        onChange = callback
    }

    private func registerUndo(previous: MathEditor) {
        undoManager?.registerUndo(withTarget: self) { model in
            let current = model.editor
            model.isRestoringUndo = true
            model.editor = previous
            model.isRestoringUndo = false
            model.registerUndo(previous: current)
        }
    }

    func press(_ key: KeypadKey) {
        switch key {
        case .enter: onCommit?()
        case .clear: editor.clear()
        case .expand: paletteExpanded.toggle()
        case .angleMode: settings?.cycleAngleUnit()
        case .undo: undoManager?.undo()
        case .redo: undoManager?.redo()
        case .store, .memoryPlus, .memoryMinus, .change, .modify: break
        default: _ = editor.apply(key)
        }
    }
}

/// Structured editor + keypad + palette for a definition (graph workspaces).
struct DefinitionEditorPanel: View {
    let model: FunctionEditorModel
    var shortcuts: [KeypadKey] = [.symbol(.variable("x")), .symbol(.variable("y")), .symbol(.equals), .power]
    var keypadHeight: CGFloat = 300
    var onDone: () -> Void
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.undoManager) private var undoManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 8) {
            HStack(alignment: .center, spacing: 10) {
                MathEditorView(editor: $model.editor, fontSize: 28, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button("Končano", systemImage: "checkmark", action: onDone)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.glassProminent)
                    .buttonBorderShape(.circle)
                    .accessibilityLabel("Končaj urejanje")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .glassEffect(.regular, in: .rect(cornerRadius: 22))
            ShortcutRow(model: model, keys: shortcuts)
                .frame(height: 36)
            ZStack(alignment: .top) {
                MainKeypad(model: model, spacing: 8, fontSize: 28)
                    .frame(height: keypadHeight)
                if model.paletteExpanded {
                    SymbolPalette(model: model, columns: 5, keyHeight: max(34, (keypadHeight - 50) / 4.4))
                        .padding(10)
                        .glassEffect(.regular, in: .rect(cornerRadius: 26))
                        .transition(reduceMotion ? AnyTransition.opacity : AnyTransition.scale(scale: 0.96, anchor: .top).combined(with: .opacity))
                        .zIndex(1)
                }
            }
        }
        .focusable()
        .focusEffectDisabled()
        .keypadKeyboardInput(model)
        .mathClipboard($model.editor)
        .onAppear { model.undoManager = undoManager }
        .onChange(of: undoManager) { _, manager in model.undoManager = manager }
        .onPencilDoubleTap { _ in model.press(.delete) }
        .onPencilSqueeze { phase in
            if case .ended = phase {
                withAnimation(reduceMotion ? Animation.easeInOut(duration: 0.2) : Animation.bouncy(duration: 0.35)) { model.paletteExpanded.toggle() }
            }
        }
    }
}
