import AcuteCore
import SwiftUI

/// How the complex function is shown: domain colouring or one of the 3D landscapes.
enum ComplexViewMode: String, CaseIterable, Identifiable {
    case coloring, modulus, real, imaginary
    var id: String { rawValue }

    var title: String {
        switch self {
        case .coloring: "Barvanje"
        case .modulus: "|f|"
        case .real: "Re f"
        case .imaginary: "Im f"
        }
    }

    var surfaceKind: SurfaceKind? {
        switch self {
        case .coloring: nil
        case .modulus: .complexModulus
        case .real: .complexReal
        case .imaginary: .complexImaginary
        }
    }
}

enum ComplexPresets {
    struct Preset: Identifiable {
        var title: String
        var text: String
        var id: String { text }
    }

    static let all: [Preset] = [
        Preset(title: "Riemannova zeta ζ(z)", text: "zeta(z)"),
        Preset(title: "Funkcija gama Γ(z)", text: "gamma(z)"),
        Preset(title: "z² + 1 (ničli ±i)", text: "z^2+1"),
        Preset(title: "z³ − 1 (koreni enote)", text: "z^3-1"),
        Preset(title: "1/z (pol)", text: "1/z"),
        Preset(title: "(z − 1)/(z + 1)", text: "(z-1)/(z+1)"),
        Preset(title: "eᶻ", text: "e^z"),
        Preset(title: "sin z", text: "sin(z)"),
        Preset(title: "ln z (glavna veja)", text: "ln(z)"),
        Preset(title: "e^(1/z) (bistvena singularnost)", text: "e^(1/z)"),
    ]
}

/// The complex plane: domain colouring of w = f(z) and 3D landscapes |f|, Re f, Im f.
struct ComplexWorkspaceView: View {
    @Environment(AppStore.self) private var store
    @Environment(AppSettings.self) private var settings
    @Environment(\.horizontalSizeClass) private var sizeClass
    @AppStorage("complexViewMode") private var mode: ComplexViewMode = .coloring
    @State private var plot = ComplexPlotModel()
    @State private var landscape = SurfaceModel()
    @State private var editor = FunctionEditorModel()
    @State private var editing = false
    @State private var error: String?
    @State private var parameterNames: [String] = []
    @State private var extent = 3.0

    var body: some View {
        GeometryReader { geometry in
            let sideBySide = sizeClass == .regular && geometry.size.width >= 700
            if sideBySide {
                HStack(spacing: 0) {
                    VStack(spacing: 8) {
                        controls
                        if editing {
                            editorPanel(keypadHeight: min(300, geometry.size.height * 0.36))
                                .padding(.horizontal, 12)
                                .padding(.bottom, 10)
                        }
                    }
                    .frame(width: min(420, geometry.size.width * 0.36))
                    plotView
                }
            } else {
                VStack(spacing: 0) {
                    plotView
                        .frame(height: geometry.size.height * (editing ? 0.36 : 0.55))
                    if editing {
                        editorPanel(keypadHeight: min(300, geometry.size.height * 0.4))
                            .padding(.horizontal, 10)
                            .padding(.top, 8)
                    } else {
                        controls
                    }
                }
            }
        }
        .animation(.snappy(duration: 0.3), value: editing)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    ForEach(ComplexPresets.all) { preset in
                        Button(preset.title) { apply(preset.text) }
                    }
                } label: {
                    Label("Primeri", systemImage: "sparkles")
                }
            }
        }
        .onChange(of: store.complexFunction, initial: true) { _, _ in apply() }
        .onChange(of: store.graphParameters) { _, _ in apply() }
        .onChange(of: mode) { _, _ in apply() }
        .onChange(of: extent) { _, value in landscape.domain = SIMD4(-value, value, -value, value) }
        .onChange(of: settings.surfaceResolution, initial: true) { _, value in landscape.resolution = value }
        .onAppear {
            editor.settings = settings
            landscape.colorMode = .phase
            landscape.domain = SIMD4(-extent, extent, -extent, extent)
        }
    }

    @ViewBuilder
    private var plotView: some View {
        Group {
            if mode == .coloring {
                ComplexPlotView(model: plot)
            } else {
                SurfaceView(model: landscape)
            }
        }
        .overlay(alignment: .top) {
            if let message = error ?? plot.errorMessage {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .glassEffect(.regular.tint(Color.red.opacity(0.35)), in: .capsule)
                    .padding(.top, 12)
            }
        }
    }

    private func editorPanel(keypadHeight: CGFloat) -> some View {
        DefinitionEditorPanel(model: editor,
                              shortcuts: [.symbol(.variable("z")), .symbol(.constant(.i)), .function(.zeta), .power],
                              keypadHeight: keypadHeight) { stopEditing() }
    }

    private var controls: some View {
        List {
            Section {
                Button { startEditing() } label: {
                    HStack(spacing: 8) {
                        Text("f(z) =").foregroundStyle(.secondary)
                        ViewThatFits(in: .horizontal) {
                            MathText(row: store.complexFunction, fontSize: 22)
                            MathText(row: store.complexFunction, fontSize: 16)
                        }
                        Spacer()
                        Image(systemName: "pencil").foregroundStyle(.tint)
                    }
                }
                .buttonStyle(.plain)
                Picker("Prikaz", selection: $mode) {
                    ForEach(ComplexViewMode.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Kompleksna funkcija")
            } footer: {
                Text(mode == .coloring
                     ? "Barva pove argument f(z), svetlost pa |f(z)|. Ničle so točke, okoli katerih se barve zavrtijo, poli so svetli. Dotakni se ravnine za vrednost f(z)."
                     : "3D pokrajina nad ravnino z = x + iy. Pri z² + 1 se |f| dotakne tal v ±i, Re f je sedlo.")
            }
            if mode == .coloring {
                Section("Barvanje") {
                    LabeledContent("Plastnice |f|") {
                        Slider(value: Binding(get: { plot.contourStrength }, set: { plot.contourStrength = $0 }), in: 0...1)
                            .frame(maxWidth: 220)
                    }
                    LabeledContent("Črte argumenta") {
                        Slider(value: Binding(get: { plot.phaseLines }, set: { plot.phaseLines = $0 }), in: 0...1)
                            .frame(maxWidth: 220)
                    }
                    Toggle("Mreža in osi", isOn: Binding(get: { plot.showGrid }, set: { plot.showGrid = $0 }))
                }
            } else {
                Section("Pokrajina") {
                    LabeledContent("Območje ±\(NumberFormatting.plain((extent * 10).rounded() / 10))") {
                        Slider(value: $extent, in: 0.5...25)
                            .frame(maxWidth: 220)
                    }
                    Picker("Barvanje", selection: Binding(get: { landscape.colorMode }, set: { landscape.colorMode = $0 })) {
                        ForEach(SurfaceColorMode.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    Button("Ponastavi kamero", systemImage: "camera.metering.center.weighted") { landscape.resetCamera() }
                }
            }
            if let probe = plot.probeResult, mode == .coloring {
                Section("Izbrana točka") {
                    LabeledContent("z", value: ComplexFormatting.text(unit: settings.imaginaryUnit, probe.z, options: settings.numberFormat))
                    LabeledContent("f(z)", value: ComplexFormatting.text(unit: settings.imaginaryUnit, probe.w, options: settings.numberFormat))
                    LabeledContent("|f(z)|", value: NumberFormatting.format(probe.w.magnitude, options: settings.numberFormat).plainTextLocalized)
                    LabeledContent("arg f(z)", value: NumberFormatting.format(probe.w.argument, options: settings.numberFormat).plainTextLocalized)
                }
            }
            if !parameterNames.isEmpty {
                Section("Parametri") {
                    ForEach(parameterNames, id: \.self) { name in
                        ParameterSliderRow(name: name, value: Binding(get: { store.graphParameters[name] ?? 1 },
                                                                      set: { store.graphParameters[name] = $0 }))
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: Model

    private func apply(_ text: String) {
        guard let expr = try? Parser.parse(text) else { return }
        stopEditing()
        store.complexFunction = MathRowConverter.rowPreservingStructure(for: expr)
    }

    private func apply() {
        let row = store.complexFunction
        guard !row.isEmpty else { error = nil; return }
        let expr: Expr
        do {
            expr = try MathRowConverter.expr(from: row)
        } catch .incomplete {
            return
        } catch {
            self.error = error.errorDescription ?? error.shortDescription
            return
        }
        var body = expr
        if case .relation(let lhs, .equal, let rhs) = expr {
            guard case .variable(let name) = lhs, name == "w" || name == "f" else {
                error = "Vnesi funkcijo spremenljivke z, npr. z² + 1."
                return
            }
            body = rhs
        }
        let free = body.freeVariables
        if free.contains("x") || free.contains("y") {
            error = "Uporabi spremenljivko z (z = x + iy)."
            return
        }
        error = nil
        let names = free.subtracting(["z"]).sorted()
        parameterNames = names
        var parameters: [String: Double] = [:]
        for name in names { parameters[name] = store.graphParameters[name] ?? 1 }
        plot.parameters = parameters
        plot.setFunction(body)
        if let kind = mode.surfaceKind {
            if landscape.kind != kind { landscape.kind = kind }
            landscape.setFunction(body, parameters: parameters)
        }
    }

    private func startEditing() {
        let store = self.store
        editor.load(store.complexFunction)
        editor.onChange = { row in store.complexFunction = row }
        editor.onCommit = { stopEditing() }
        editing = true
    }

    private func stopEditing() {
        editor.onChange = nil
        editor.onCommit = nil
        editor.paletteExpanded = false
        editing = false
    }
}
