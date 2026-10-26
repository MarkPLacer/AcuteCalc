import AcuteCore
import SwiftUI

/// Ready-made 3D surfaces, solids of revolution and complex landscapes.
enum SurfacePresets {
    struct Preset: Identifiable {
        var title: String
        var text: String
        var kind: SurfaceKind
        var extent: Double = 4
        var colorMode: SurfaceColorMode = .height
        var id: String { title }
    }

    static let real: [Preset] = [
        Preset(title: "Valovi z = sin(x² + y²)", text: "z=sin(x^2+y^2)", kind: .heightField, extent: 3.5),
        Preset(title: "z = ½(x³ + y³)", text: "z=(x^3+y^3)/2", kind: .heightField, extent: 2.5),
        Preset(title: "Sedlo z = x² − y²", text: "z=x^2-y^2", kind: .heightField, extent: 2.5),
        Preset(title: "Paraboloid z = x² + y²", text: "z=x^2+y^2", kind: .heightField, extent: 2.5),
        Preset(title: "Gaussov zvon", text: "z=e^(-(x^2+y^2))", kind: .heightField, extent: 2.5),
        Preset(title: "z = cos x · sin y", text: "z=cos(x)sin(y)", kind: .heightField, extent: 5),
        Preset(title: "Polkrogla z = √(9 − x² − y²)", text: "z=sqrt(9-x^2-y^2)", kind: .heightField, extent: 3.2),
        Preset(title: "z = x·y·e^(−(x² + y²)/2)", text: "z=x*y*e^(-(x^2+y^2)/2)", kind: .heightField, extent: 3.5),
        Preset(title: "Vrtenina y = √x", text: "y=sqrt(x)", kind: .revolution, extent: 4),
        Preset(title: "Vrtenina y = sin x + 2", text: "y=sin(x)+2", kind: .revolution, extent: 6),
    ]

    static let complex: [Preset] = [
        Preset(title: "|z² + 1| – ničli ±i", text: "z^2+1", kind: .complexModulus, extent: 2.2, colorMode: .phase),
        Preset(title: "Re(z² + 1) – sedlo »Pringles«", text: "z^2+1", kind: .complexReal, extent: 2.2),
        Preset(title: "Im(z² + 1)", text: "z^2+1", kind: .complexImaginary, extent: 2.2),
        Preset(title: "|ζ(z)| – Riemannova funkcija zeta", text: "zeta(z)", kind: .complexModulus, extent: 16, colorMode: .phase),
        Preset(title: "|Γ(z)| – funkcija gama", text: "gamma(z)", kind: .complexModulus, extent: 4.5, colorMode: .phase),
        Preset(title: "|1/z| – pol v 0", text: "1/z", kind: .complexModulus, extent: 2, colorMode: .phase),
        Preset(title: "|z³ − 1| – tretji koreni enote", text: "z^3-1", kind: .complexModulus, extent: 1.8, colorMode: .phase),
        Preset(title: "|sin z|", text: "sin(z)", kind: .complexModulus, extent: 5, colorMode: .phase),
    ]

    static func row(for preset: Preset) -> MathRow? {
        (try? Parser.parse(preset.text)).map(MathRowConverter.rowPreservingStructure(for:))
    }
}

/// 3D workspace: z = f(x, y), solids of revolution and complex landscapes |f|, Re f, Im f.
struct SurfaceWorkspaceView: View {
    @Environment(AppStore.self) private var store
    @Environment(AppSettings.self) private var settings
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var surface = SurfaceModel()
    @State private var editor = FunctionEditorModel()
    @State private var editing = false
    @State private var error: String?
    @State private var parameterNames: [String] = []

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
                    surfaceView
                }
            } else {
                VStack(spacing: 0) {
                    surfaceView
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
            ToolbarItem(placement: .topBarTrailing) { presetsMenu }
        }
        .onChange(of: store.surfaces, initial: true) { _, _ in apply() }
        .onChange(of: store.graphParameters) { _, _ in apply() }
        .onChange(of: settings.surfaceResolution, initial: true) { _, value in surface.resolution = value }
        .onChange(of: settings.accent, initial: true) { _, accent in
            surface.baseColor = accent.rgba
            surface.requestRedraw?()
        }
        .onAppear {
            editor.settings = settings
            if store.surfaces.isEmpty, let first = SurfacePresets.real.first { apply(first) }
        }
    }

    private var definition: SurfaceDefinition? { store.surfaces.first }

    private var surfaceView: some View {
        SurfaceView(model: surface)
            .overlay(alignment: .bottomTrailing) {
                Button("Ponastavi kamero", systemImage: "camera.metering.center.weighted") { surface.resetCamera() }
                    .labelStyle(.iconOnly)
                    .font(.system(size: 17, weight: .medium))
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)
                    .padding(12)
            }
            .overlay(alignment: .top) {
                if let message = error ?? surface.errorMessage {
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
        let isComplex = definition?.kind.isComplex == true
        let shortcuts: [KeypadKey] = isComplex
            ? [.symbol(.variable("z")), .symbol(.constant(.i)), .function(.zeta), .power]
            : [.symbol(.variable("x")), .symbol(.variable("y")), .symbol(.variable("z")), .power]
        return DefinitionEditorPanel(model: editor, shortcuts: shortcuts, keypadHeight: keypadHeight) { stopEditing() }
    }

    // MARK: Controls

    private var controls: some View {
        List {
            if let definition {
                Section {
                    Button { startEditing() } label: {
                        HStack {
                            ViewThatFits(in: .horizontal) {
                                MathText(row: definition.row, fontSize: 22)
                                MathText(row: definition.row, fontSize: 16)
                            }
                            Spacer()
                            Image(systemName: "pencil").foregroundStyle(.tint)
                        }
                    }
                    .buttonStyle(.plain)
                    Picker("Vrsta", selection: binding(\.kind)) {
                        ForEach(SurfaceKind.allCases) { Text($0.title).tag($0) }
                    }
                    Picker("Barvanje", selection: binding(\.colorMode)) {
                        ForEach(SurfaceColorMode.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Ploskev")
                } footer: {
                    Text(footer(for: definition.kind))
                }
                Section("Pogled") {
                    LabeledContent("Območje ±\(NumberFormatting.plain((definition.extent * 10).rounded() / 10))") {
                        Slider(value: binding(\.extent), in: 0.5...25)
                            .frame(maxWidth: 220)
                    }
                    LabeledContent("Raztezek z") {
                        Slider(value: binding(\.zScale), in: 0.1...3)
                            .frame(maxWidth: 220)
                    }
                    Toggle("Samodejni obseg z", isOn: Binding(get: { surface.autoZ }, set: { surface.autoZ = $0 }))
                    Toggle("Mreža", isOn: Binding(get: { surface.showGrid }, set: { surface.showGrid = $0 }))
                    Button("Ponastavi kamero", systemImage: "camera.metering.center.weighted") { surface.resetCamera() }
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
        }
        .listStyle(.insetGrouped)
    }

    private func footer(for kind: SurfaceKind) -> String {
        switch kind {
        case .heightField: "Vnesi z = f(x, y). Vleci za vrtenje, dva prsta za povečavo, dvojni dotik ponastavi pogled."
        case .revolution: "Vnesi y = f(x); graf se zavrti okoli osi x (prostornina V = π∫ f(x)² dx)."
        case .complexModulus: "Pokrajina |f(z)| nad kompleksno ravnino: ničle se dotaknejo tal, poli se dvignejo v nebo. Barva je argument f(z)."
        case .complexReal: "Realni del Re f(z). Za f(z) = z² + 1 je to sedlo x² − y² + 1."
        case .complexImaginary: "Imaginarni del Im f(z)."
        }
    }

    private var presetsMenu: some View {
        Menu {
            Section("Ploskve in vrtenine") {
                ForEach(SurfacePresets.real) { preset in Button(preset.title) { apply(preset) } }
            }
            Section("Kompleksne pokrajine") {
                ForEach(SurfacePresets.complex) { preset in Button(preset.title) { apply(preset) } }
            }
        } label: {
            Label("Primeri", systemImage: "sparkles")
        }
    }

    // MARK: Model

    private func binding<Value>(_ keyPath: WritableKeyPath<SurfaceDefinition, Value>) -> Binding<Value> {
        Binding(get: { store.surfaces.first.map { $0[keyPath: keyPath] } ?? SurfaceDefinition(row: MathRow())[keyPath: keyPath] },
                set: { value in
                    guard !store.surfaces.isEmpty else { return }
                    store.surfaces[0][keyPath: keyPath] = value
                })
    }

    private func apply(_ preset: SurfacePresets.Preset) {
        guard let row = SurfacePresets.row(for: preset) else { return }
        stopEditing()
        var definition = SurfaceDefinition(row: row, kind: preset.kind, extent: preset.extent)
        definition.colorMode = preset.colorMode
        if store.surfaces.isEmpty {
            store.surfaces = [definition]
        } else {
            definition.id = store.surfaces[0].id
            store.surfaces[0] = definition
        }
        surface.resetCamera()
    }

    /// Parses the definition and pushes it to the renderer.
    private func apply() {
        guard let definition else { return }
        surface.colorMode = definition.colorMode
        surface.zScale = definition.zScale
        let e = definition.extent
        surface.domain = SIMD4(-e, e, -e, e)
        guard !definition.row.isEmpty else { error = nil; return }
        let expr: Expr
        do {
            expr = try MathRowConverter.expr(from: definition.row)
        } catch .incomplete {
            return
        } catch {
            self.error = error.errorDescription ?? error.shortDescription
            return
        }
        var body = expr
        if case .relation(let lhs, .equal, let rhs) = expr {
            switch lhs {
            case .variable("z") where !definition.kind.isComplex, .variable("y") where definition.kind == .revolution,
                 .variable("w") where definition.kind.isComplex:
                body = rhs
            default:
                error = definition.kind == .revolution ? "Za vrtenino vnesi y = f(x)." : "Vnesi z = f(x, y)."
                return
            }
        }
        let reserved: Set<String> = definition.kind.isComplex ? ["z", "i"] : ["x", "y"]
        let free = body.freeVariables
        if definition.kind == .revolution, free.contains("y") {
            error = "Vrtenina potrebuje funkcijo ene spremenljivke y = f(x)."
            return
        }
        if definition.kind.isComplex, free.contains("x") || free.contains("y") {
            error = "Kompleksna pokrajina: piši s spremenljivko z (npr. z² + 1)."
            return
        }
        error = nil
        let names = free.subtracting(reserved).sorted()
        parameterNames = names
        var parameters: [String: Double] = [:]
        for name in names { parameters[name] = store.graphParameters[name] ?? 1 }
        if surface.kind != definition.kind { surface.kind = definition.kind }
        surface.setFunction(body, parameters: parameters)
    }

    private func startEditing() {
        guard let definition else { return }
        let store = self.store
        editor.load(definition.row)
        editor.onChange = { row in
            guard !store.surfaces.isEmpty else { return }
            store.surfaces[0].row = row
        }
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
