import AcuteCore
import SwiftUI

/// The calculator: live graph/result on top, structured expression, keypad and palette below.
struct CalculatorScreen: View {
    let model: CalculatorModel
    @Environment(AppStore.self) private var store
    @Environment(AppSettings.self) private var settings
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.undoManager) private var undoManager
    @State private var showSettings = false
    @State private var showHistory = false
    @State private var showLinearInput = false
    @FocusState private var keyboardFocused: Bool

    var body: some View {
        GeometryReader { geometry in
            let wide = horizontalSizeClass == .regular && geometry.size.width > 820
            ZStack(alignment: .leading) {
                Group {
                    if wide { wideLayout(geometry.size) } else { compactLayout(geometry.size) }
                }
                if wide && showHistory {
                    HistoryList(model: model, showsHeader: true, onSelect: { withAnimation(.snappy) { showHistory = false } })
                        .frame(width: min(380, geometry.size.width * 0.34))
                        .glassEffect(.regular, in: .rect(cornerRadius: 28))
                        .padding(12)
                        .transition(.move(edge: .leading).combined(with: .opacity))
                        .zIndex(2)
                }
            }
        }
        .background(Color(.systemBackground).ignoresSafeArea())
        .sheet(isPresented: $showSettings) { SettingsView() }
        .sheet(isPresented: Binding(get: { showHistory && horizontalSizeClass != .regular }, set: { showHistory = $0 })) {
            NavigationStack {
                HistoryList(model: model, onSelect: { showHistory = false })
                    .navigationTitle("Zgodovina")
                    .navigationBarTitleDisplayMode(.inline)
            }
            .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showLinearInput) {
            LinearInputSheet { row in model.insert(row: row) }
                .presentationDetents([.height(220), .medium])
        }
        .focusable()
        .focused($keyboardFocused)
        .focusEffectDisabled()
        .keypadKeyboardInput(model)
        .mathClipboard(Binding(get: { model.editor }, set: { model.editor = $0 }))
        // Apple Pencil Pro: squeeze toggles the symbol palette, double tap deletes.
        .onPencilSqueeze { phase in
            if case .ended = phase {
                withAnimation(.bouncy(duration: 0.35)) { model.paletteExpanded.toggle() }
            }
        }
        .onPencilDoubleTap { _ in model.press(.delete) }
        .onAppear {
            model.store = store
            model.settings = settings
            model.undoManager = undoManager
            keyboardFocused = true
        }
        .onChange(of: undoManager) { _, manager in model.undoManager = manager }
        .onChange(of: settings.angleUnit) { _, _ in model.scheduleEvaluation(immediate: true) }
    }

    // MARK: Layouts

    private func compactLayout(_ size: CGSize) -> some View {
        let keypadHeight = min(size.height * 0.52, size.width * 1.25)
        return VStack(spacing: 8) {
            previewArea
                .frame(maxHeight: .infinity)
            if !(model.calculation?.graph?.parameters.isEmpty ?? true) {
                ParameterSliders(graph: model.graph, surface: model.surface, names: model.calculation?.graph?.parameters ?? [])
                    .padding(.horizontal, 16)
            }
            ShortcutRow(model: model)
                .frame(height: 40)
                .padding(.horizontal, 12)
            ZStack(alignment: .top) {
                MainKeypad(model: model, spacing: 12)
                    .padding(.horizontal, 14)
                    .frame(height: keypadHeight)
                if model.paletteExpanded {
                    SymbolPalette(model: model, columns: 5, keyHeight: (keypadHeight - 60) / 4.6)
                        .padding(12)
                        .glassEffect(.regular, in: .rect(cornerRadius: 30))
                        .padding(.horizontal, 8)
                        .transition(AnyTransition.scale(scale: 0.96, anchor: .top).combined(with: .opacity))
                        .zIndex(1)
                }
            }
            .padding(.bottom, 8)
        }
    }

    private func wideLayout(_ size: CGSize) -> some View {
        let bottomHeight = min(size.height * 0.5, 560)
        let paletteKeyHeight = (bottomHeight - 76) / 5.2
        return VStack(spacing: 12) {
            previewArea
                .frame(maxHeight: .infinity)
            if !(model.calculation?.graph?.parameters.isEmpty ?? true) {
                ParameterSliders(graph: model.graph, surface: model.surface, names: model.calculation?.graph?.parameters ?? [])
                    .padding(.horizontal, 24)
            }
            HStack(alignment: .top, spacing: 18) {
                VariablesPanel(model: model)
                    .frame(width: size.width * 0.22)
                VStack(spacing: 6) {
                    // x, y and = for graphs and equations stay on top of every palette page
                    // (the iPhone has the same keys in the row above its keypad).
                    HStack(spacing: 4) {
                        ForEach(KeypadKey.shortcuts, id: \.self) { key in
                            PaletteKey(key: key, model: model)
                                .frame(height: paletteKeyHeight)
                        }
                    }
                    Divider()
                    SymbolPalette(model: model, columns: 5, keyHeight: paletteKeyHeight)
                }
                .frame(width: size.width * 0.31)
                MainKeypad(model: model, spacing: 14)
                    .frame(maxWidth: .infinity)
            }
            .frame(height: bottomHeight)
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
        }
    }

    // MARK: Preview (graph or big result) with the expression

    private var previewArea: some View {
        ZStack(alignment: .bottomTrailing) {
            previewBackground
            LinearGradient(colors: [.clear, Color(.systemBackground).opacity(model.hasGraph && showsGraph ? 0.85 : 0)], startPoint: .center, endPoint: .bottom)
                .allowsHitTesting(false)
            VStack(alignment: .trailing, spacing: 6) {
                MathEditorView(editor: Binding(get: { model.editor }, set: { model.editor = $0 }), fontSize: horizontalSizeClass == .regular ? 46 : 38, alignment: .trailing)
                if !(showsGraph && model.hasGraph) || model.previewMode == .result {
                    ResultView(model: model, fontSize: horizontalSizeClass == .regular ? 44 : 34)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                } else {
                    ResultView(model: model, fontSize: 24)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
        }
        .overlay(alignment: .top) { topBar }
    }

    private var showsGraph: Bool {
        switch model.previewMode {
        case .automatic, .graph: true
        case .result, .hidden: false
        }
    }

    @ViewBuilder
    private var previewBackground: some View {
        if model.hasGraph && showsGraph {
            if model.isSurface {
                SurfaceView(model: model.surface)
                    .transition(.opacity)
            } else {
                GraphCanvasView(model: model.graph)
                    .transition(.opacity)
            }
        } else {
            Color(.systemBackground)
        }
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            Button { withAnimation(.snappy) { showHistory.toggle() } } label: {
                Image(systemName: horizontalSizeClass == .regular ? "sidebar.leading" : "clock.arrow.circlepath")
                    .font(.system(size: 19, weight: .medium))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .accessibilityLabel("Zgodovina")
            if horizontalSizeClass == .compact {
                // iPhone: no tab bar — Grafi, Orodja, Formule and Nastavitve live in this menu.
                SectionMenu {
                    Divider()
                    Button("Nastavitve", systemImage: "gearshape") { showSettings = true }
                } label: {
                    Image(systemName: "square.grid.2x2")
                        .font(.system(size: 18, weight: .medium))
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
            } else {
                Button { showSettings = true } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 19, weight: .medium))
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .accessibilityLabel("Nastavitve")
            }
            Spacer()
            Text(settings.angleUnit.shortLabel)
                .font(.caption.weight(.bold).monospaced())
                .foregroundStyle(.secondary)
            if model.hasGraph {
                Menu {
                    Picker("Prikaz", selection: Binding(get: { model.previewMode }, set: { model.previewMode = $0 })) {
                        ForEach(PreviewMode.allCases) { Text($0.title).tag($0) }
                    }
                    Divider()
                    Button("Prilagodi pogled", systemImage: "arrow.up.left.and.arrow.down.right") { model.graph.fitToContent() }
                    Button("Ponastavi pogled", systemImage: "scope") { model.graph.resetView() }
                    Toggle("Enako merilo osi", systemImage: "aspectratio", isOn: Binding(get: { settings.equalAxes }, set: { settings.equalAxes = $0 }))
                    Toggle("Posebne točke", isOn: Binding(get: { model.graph.showSpecialPoints }, set: { model.graph.showSpecialPoints = $0 }))
                    Toggle("Tangenta pri sledenju", isOn: Binding(get: { model.graph.showTangent }, set: { model.graph.showTangent = $0 }))
                } label: {
                    Label("Graf", systemImage: "chevron.up.chevron.down")
                        .labelStyle(.titleAndIconTrailing)
                        .font(.subheadline.weight(.medium))
                        .padding(.horizontal, 14)
                        .frame(height: 44)
                }
                .buttonStyle(.glass)
            }
            Button { showLinearInput = true } label: {
                Image(systemName: "pencil.and.scribble")
                    .font(.system(size: 18, weight: .medium))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .accessibilityLabel("Vnos z besedilom ali pisalom")
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
    }

}

/// Sliders for free parameters (a, k, r, p …) of the previewed graph.
struct ParameterSliders: View {
    let graph: GraphCanvasModel
    let surface: SurfaceModel
    let names: [String]
    @Environment(AppSettings.self) private var settings

    var body: some View {
        VStack(spacing: 4) {
            ForEach(names, id: \.self) { name in
                HStack(spacing: 10) {
                    MathText(row: MathRow([.symbol(.variable(name))]), fontSize: 20)
                        .frame(width: 26)
                    Slider(value: Binding(
                        get: { graph.parameters[name] ?? 1 },
                        set: { value in
                            let rounded = (value * 20).rounded() / 20
                            graph.parameters[name] = rounded
                            surface.parameters[name] = rounded
                        }), in: -10...10)
                    Text(NumberFormatting.format(graph.parameters[name] ?? 1, options: NumberFormatOptions(mode: .norm1, significantDigits: 3, decimalSeparator: settings.decimalSeparator)).mantissa)
                        .font(.callout.monospacedDigit())
                        .frame(width: 48, alignment: .trailing)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
    }
}

/// Typed or handwritten (Scribble) linear input, e.g. "sin(x)/x" or "x^2 + y^2 = 9".
struct LinearInputSheet: View {
    var onInsert: (MathRow) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var error: String?
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                TextField("npr. sin(x)/x ali x^2 + y^2 = 9", text: $text)
                    .font(.system(size: 22, design: .monospaced))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focused)
                    .submitLabel(.done)
                    .onSubmit(insert)
                    .padding(12)
                    .glassEffect(.regular, in: .rect(cornerRadius: 14))
                Text("Pišeš lahko tudi z Apple Pencilom (Scribble).")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text("Primeri: f(x) = x^2 - 4 · x >= 0, y >= 0, x + y <= 4 · y = 2x + 1, y = 4 - x · |z - 1| <= 2 · a_n = 2n + 1")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                if let error {
                    Text(error).font(.footnote).foregroundStyle(.red)
                }
            }
            .padding()
            .navigationTitle("Vnos izraza")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Prekliči", role: .cancel) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Vstavi", action: insert).disabled(text.isEmpty) }
            }
            .onAppear { focused = true }
        }
    }

    private func insert() {
        do {
            let expr = try Parser.parse(text)
            onInsert(MathRowConverter.rowPreservingStructure(for: expr))
            dismiss()
        } catch {
            self.error = error.errorDescription ?? "Napaka v zapisu"
        }
    }
}
