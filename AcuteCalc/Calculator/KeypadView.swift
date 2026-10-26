import AcuteCore
import SwiftUI

enum KeyRole {
    case number, function, operation, accent, plain

    func tint(accent: Color) -> Color {
        switch self {
        case .number: Color.white.opacity(0.10)
        case .function: Color.white.opacity(0.55)
        case .operation, .accent: accent
        case .plain: .clear
        }
    }

    var foreground: Color {
        switch self {
        case .function: .black
        default: .white
        }
    }
}

/// A calculator key: Liquid Glass capsule, haptics, press-and-hold repeat.
struct KeyButton: View {
    let key: KeypadKey
    var role: KeyRole = .number
    var fontSize: CGFloat = 34
    var repeats = false
    /// Replaces the key's own label (decimal separator, = vs →).
    var labelOverride: KeypadKey.Label?
    var action: (KeypadKey) -> Void
    @Environment(AppSettings.self) private var settings
    @State private var pressed = false
    @State private var repeatTask: Task<Void, Never>?
    @State private var tapCount = 0

    var body: some View {
        let accent = settings.accent.color
        KeyLabel(label: labelOverride ?? (key == .point ? .text(settings.decimalSeparator) : key.label), fontSize: fontSize, color: role.foreground)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(.capsule)
            .glassEffect(role == .plain ? .identity : .regular.tint(role.tint(accent: accent)).interactive(), in: .capsule)
            .scaleEffect(pressed ? 0.94 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: pressed)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard !pressed else { return }
                        pressed = true
                        fire()
                        if repeats { startRepeating() }
                    }
                    .onEnded { _ in
                        pressed = false
                        repeatTask?.cancel()
                        repeatTask = nil
                    }
            )
            .sensoryFeedback(.impact(weight: .light, intensity: 0.7), trigger: tapCount) { _, _ in settings.haptics }
            .accessibilityElement()
            .accessibilityLabel(key.accessibilityName)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { action(key) }
    }

    private func fire() {
        tapCount += 1
        action(key)
    }

    private func startRepeating() {
        repeatTask?.cancel()
        let delay = settings.keyRepeatDelay
        let rate = max(0.03, settings.keyRepeatRate)
        repeatTask = Task {
            try? await Task.sleep(for: .seconds(delay))
            while !Task.isCancelled && pressed {
                fire()
                try? await Task.sleep(for: .seconds(rate))
            }
        }
    }
}

/// Renders a key label: text, SF Symbol or a small math row.
struct KeyLabel: View {
    let label: KeypadKey.Label
    var fontSize: CGFloat
    var color: Color

    var body: some View {
        switch label {
        case .text(let text):
            Text(text)
                .font(.system(size: fontSize, weight: .regular))
                .minimumScaleFactor(0.4)
                .lineLimit(1)
                .foregroundStyle(color)
        case .systemImage(let name):
            Image(systemName: name)
                .font(.system(size: fontSize * 0.78, weight: .semibold))
                .foregroundStyle(color)
        case .math(let row):
            // Templates show their empty boxes (□/□, √□ …), like the original keypad.
            MathText(row: row, fontSize: fontSize * 0.72, color: color, showsPlaceholders: true)
        }
    }
}

/// The face of a keypad key (no gesture): the keypad tracks the finger across keys.
struct KeyFace: View {
    let key: KeypadKey
    var role: KeyRole = .number
    var fontSize: CGFloat = 34
    var labelOverride: KeypadKey.Label?
    var isPressed = false
    var action: (KeypadKey) -> Void
    @Environment(AppSettings.self) private var settings

    var body: some View {
        KeyLabel(label: labelOverride ?? (key == .point ? .text(settings.decimalSeparator) : key.label), fontSize: fontSize, color: role.foreground)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(.capsule)
            .glassEffect(.regular.tint(role.tint(accent: settings.accent.color)).interactive(), in: .capsule)
            .scaleEffect(isPressed ? 0.94 : 1)
            .brightness(isPressed ? 0.08 : 0)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: isPressed)
            .accessibilityElement()
            .accessibilityLabel(key.accessibilityName)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { action(key) }
    }
}

/// The main 4×5 keypad (like the original Acute Calc). One gesture tracks the finger:
/// slide to another key before lifting (keys fire on release), hold digits or ⌫ to repeat.
struct MainKeypad<Target: KeypadTarget>: View {
    let model: Target
    var spacing: CGFloat = 12
    var fontSize: CGFloat = 36
    @Environment(AppSettings.self) private var settings
    @State private var frames: [KeypadKey: CGRect] = [:]
    @State private var pressed: KeypadKey?
    @State private var repeated = false
    @State private var repeatTask: Task<Void, Never>?
    @State private var feedback = 0

    var body: some View {
        GlassEffectContainer(spacing: spacing) {
            Grid(horizontalSpacing: spacing, verticalSpacing: spacing) {
                GridRow {
                    face(.clear, .function)
                    face(.symbol(.leftParenthesis), .function)
                    face(.symbol(.rightParenthesis), .function)
                    face(.symbol(.divide), .operation)
                }
                GridRow {
                    face(.digit(7)); face(.digit(8)); face(.digit(9))
                    face(.symbol(.times), .operation)
                }
                GridRow {
                    face(.digit(4)); face(.digit(5)); face(.digit(6))
                    face(.symbol(.minus), .operation)
                }
                GridRow {
                    face(.digit(1)); face(.digit(2)); face(.digit(3))
                    face(.symbol(.plus), .operation)
                }
                GridRow {
                    face(.digit(0))
                    face(.point)
                    face(.delete, size: fontSize * 0.83)
                    face(.enter, .accent, size: fontSize * 0.89,
                         label: model.enterShowsEquals ? .systemImage("equal") : .systemImage("checkmark"))
                }
            }
        }
        .coordinateSpace(.named("mainKeypad"))
        .contentShape(.rect)
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .named("mainKeypad"))
                .onChanged { value in track(value.location) }
                .onEnded { value in release(at: value.location) }
        )
        .sensoryFeedback(.impact(weight: .light, intensity: 0.7), trigger: feedback) { _, _ in settings.haptics }
        .onDisappear { repeatTask?.cancel() }
    }

    private func face(_ key: KeypadKey, _ role: KeyRole = .number, size: CGFloat? = nil, label: KeypadKey.Label? = nil) -> some View {
        KeyFace(key: key, role: role, fontSize: size ?? fontSize, labelOverride: label, isPressed: pressed == key) { model.press($0) }
            .onGeometryChange(for: CGRect.self) { proxy in
                proxy.frame(in: .named("mainKeypad"))
            } action: { frame in
                frames[key] = frame
            }
    }

    private func isRepeatable(_ key: KeypadKey) -> Bool {
        switch key {
        case .digit, .point, .delete: true
        default: false
        }
    }

    /// Highlights the key under the finger; holding a repeatable key repeats it.
    private func track(_ location: CGPoint) {
        let key = frames.first { $0.value.insetBy(dx: -spacing / 2, dy: -spacing / 2).contains(location) }?.key
        guard key != pressed else { return }
        pressed = key
        repeated = false
        repeatTask?.cancel()
        repeatTask = nil
        guard let key else { return }
        feedback += 1
        if isRepeatable(key) {
            let delay = settings.keyRepeatDelay
            let rate = max(0.03, settings.keyRepeatRate)
            repeatTask = Task {
                try? await Task.sleep(for: .seconds(delay))
                while !Task.isCancelled, pressed == key {
                    model.press(key)
                    repeated = true
                    feedback += 1
                    try? await Task.sleep(for: .seconds(rate))
                }
            }
        }
    }

    /// Fires the key under the finger when it lifts (unless it was already repeating).
    private func release(at location: CGPoint) {
        track(location)
        repeatTask?.cancel()
        repeatTask = nil
        if let key = pressed, !repeated {
            model.press(key)
        }
        pressed = nil
        repeated = false
    }
}

extension KeypadKey {
    /// x, y, = (for equations), % and ^: above the iPhone keypad, on top of the iPad palette.
    static let shortcuts: [KeypadKey] = [.symbol(.variable("x")), .symbol(.variable("y")), .symbol(.equals), .symbol(.percent), .power]
}

/// The row above the keypad: x, y, = (for equations), %, ^ and the palette toggle.
struct ShortcutRow<Target: KeypadTarget>: View {
    let model: Target
    var keys: [KeypadKey] = KeypadKey.shortcuts

    var body: some View {
        HStack(spacing: 0) {
            ForEach(keys, id: \.self) { key in
                KeyButton(key: key, role: .plain, fontSize: 26) { model.press($0) }
            }
            Button {
                withAnimation(.bouncy(duration: 0.35)) { model.paletteExpanded.toggle() }
            } label: {
                Image(systemName: model.paletteExpanded ? "xmark" : "ellipsis")
                    .font(.system(size: 22, weight: .semibold))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .foregroundStyle(model.paletteExpanded ? Color.accentColor : .primary)
            .accessibilityLabel(model.paletteExpanded ? "Zapri simbole" : "Več simbolov")
        }
    }
}

/// The expanded symbol palette (glass panel with pages, like the original "Main Palette").
struct SymbolPalette<Target: KeypadTarget>: View {
    let model: Target
    var columns = 5
    var keyHeight: CGFloat = 52
    var showsHeader = true
    @Environment(AppSettings.self) private var settings

    var body: some View {
        VStack(spacing: 6) {
            let keys = model.selectedPage.keys
            let rows = stride(from: 0, to: keys.count, by: columns).map { Array(keys[$0..<min($0 + columns, keys.count)]) }
            ForEach(rows.indices, id: \.self) { r in
                HStack(spacing: 4) {
                    ForEach(rows[r], id: \.self) { key in
                        PaletteKey(key: key, model: model)
                            .frame(height: keyHeight)
                    }
                    if rows[r].count < columns {
                        ForEach(0..<(columns - rows[r].count), id: \.self) { _ in Color.clear.frame(height: keyHeight) }
                    }
                }
            }
            if showsHeader {
                HStack {
                    Menu {
                        Picker("Paleta", selection: Binding(get: { model.selectedPage }, set: { model.selectedPage = $0 })) {
                            ForEach(SymbolPage.all) { page in Text(page.title).tag(page) }
                        }
                    } label: {
                        Label(model.selectedPage.title, systemImage: "chevron.up.chevron.down")
                            .labelStyle(.titleAndIconTrailing)
                            .font(.headline)
                    }
                    Spacer()
                    Button("Razveljavi", systemImage: "arrow.uturn.backward") { model.press(.undo) }
                        .labelStyle(.iconOnly)
                        .font(.system(size: 16, weight: .semibold))
                        .padding(.horizontal, 6)
                    Button("Uveljavi", systemImage: "arrow.uturn.forward") { model.press(.redo) }
                        .labelStyle(.iconOnly)
                        .font(.system(size: 16, weight: .semibold))
                        .padding(.horizontal, 6)
                    Text(settings.angleUnit.shortLabel)
                        .font(.caption.weight(.bold).monospaced())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .glassEffect(.regular.tint(settings.accent.color.opacity(0.4)), in: .capsule)
                }
                .padding(.horizontal, 10)
                .padding(.top, 4)
            }
        }
    }
}

struct PaletteKey<Target: KeypadTarget>: View {
    let key: KeypadKey
    let model: Target
    @Environment(AppSettings.self) private var settings
    @State private var taps = 0

    var body: some View {
        Button {
            taps += 1
            model.press(key)
        } label: {
            Group {
                if case .angleMode = key {
                    Text(settings.angleUnit.shortLabel).font(.system(size: 19, weight: .medium))
                } else if case .point = key {
                    Text(settings.decimalSeparator).font(.system(size: 22))
                } else {
                    KeyLabel(label: key.label, fontSize: 24, color: .primary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                if key == .store && model.storeMode {
                    Capsule().fill(Color.accentColor.opacity(0.35))
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: taps) { _, _ in settings.haptics }
        .accessibilityLabel(key.accessibilityName)
    }
}

extension LabelStyle where Self == TitleAndIconTrailingLabelStyle {
    static var titleAndIconTrailing: TitleAndIconTrailingLabelStyle { TitleAndIconTrailingLabelStyle() }
}

struct TitleAndIconTrailingLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.title
            configuration.icon.imageScale(.small)
        }
    }
}
