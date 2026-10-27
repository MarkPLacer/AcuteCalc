import AcuteCore
import Observation
import SwiftUI
import UIKit

/// Signed integral and geometric area of a shaded region.
nonisolated struct IntegralSummary: Equatable, Sendable {
    var signed: Double
    var area: Double
}

/// Derived state of the 2D graph workspace: parsed definitions turned into plot items.
@Observable
final class GraphWorkspaceModel {
    let canvas = GraphCanvasModel()
    private(set) var errors: [UUID: String] = [:]
    private(set) var notes: [UUID: String] = [:]
    /// y = f(x) of each definition (for tables, analysis and shading).
    private(set) var primaryExpressions: [UUID: Expr] = [:]
    private(set) var derivatives: [UUID: Expr] = [:]
    private(set) var taylorPolynomials: [UUID: Expr] = [:]
    private(set) var integrals: [UUID: IntegralSummary] = [:]
    private(set) var parameterNames: [String] = []
    @ObservationIgnored private var integralTask: Task<Void, Never>?
    /// Rows parsed and symbolic derivatives formed by `sync` so far; tests count the work of a parameter tick.
    @ObservationIgnored private(set) var symbolicWork = (parses: 0, derivatives: 0)
    /// The rows (with their ids) `sync` parsed last and what that gave.
    @ObservationIgnored private var parsedRows: (ids: [UUID], rows: [MathRow]) = ([], [])
    @ObservationIgnored private var parseResult: (requests: [UUID: GraphRequest], errors: [UUID: String], names: Set<String>) = ([:], [:], [])
    /// The derivatives of the functions y = f(x) of the last `sync` that show f′ or a Taylor polynomial.
    @ObservationIgnored private var derivativeChains: [Expr: DerivativeChain] = [:]

    /// f, f′, f″ … of one function, formed when first needed.
    private struct DerivativeChain {
        var formed: [Expr]
        /// The derivative after the last one formed cannot be formed.
        var ended = false
        /// f′ as shown (simplified once more), once it was needed.
        var shown: Expr?
    }

    init() {
        canvas.viewport.scale = SIMD2(48, 48)
    }

    func sync(_ definitions: [GraphFunctionDefinition], parameters: [String: Double], lineWidth: Double, showSpecialPoints: Bool) {
        // Parsing depends on the rows alone: a parameter tick (a slider, "Animiraj") or a change of a row's
        // settings parses nothing again.
        let key = (ids: definitions.map(\.id), rows: definitions.map(\.row))
        if key.ids != parsedRows.ids || key.rows != parsedRows.rows {
            parseResult = parse(definitions)
            parsedRows = key
        }
        let (parsed, errors, names) = parseResult
        var notes: [UUID: String] = [:]

        var values = parameters.filter { names.contains($0.key) }
        for name in names where values[name] == nil { values[name] = 1 }
        let context = EvaluationContext(variables: values)
        let width = Float(lineWidth)
        var items: [PlotItem] = []
        var primary: [UUID: Expr] = [:]
        var derivatives: [UUID: Expr] = [:]
        var taylors: [UUID: Expr] = [:]
        var shaded: [IntegralJob] = []
        var chains: [Expr: DerivativeChain] = [:]

        for definition in definitions {
            guard let request = parsed[definition.id] else { continue }
            let color = GraphPalette.color(definition.colorIndex)
            for (k, kind) in request.kinds.enumerated() {
                if case .surface = kind {
                    notes[definition.id] = "Funkcija dveh spremenljivk – prikaži jo v 3D."
                    continue
                }
                // Both sides of an equation get their own colour so the intersections stand out.
                let itemColor = request.highlightIntersections && k == 1 ? GraphPalette.color(definition.colorIndex + 1) : color
                var item = PlotItem(id: "\(definition.id.uuidString)#\(k)", kind: kind, color: itemColor, visible: definition.visible, width: width)
                if k == 0, case .explicit(let f) = kind {
                    primary[definition.id] = f
                    if definition.shadeEnabled {
                        let range = min(definition.shadeFrom, definition.shadeTo)...max(definition.shadeFrom, definition.shadeTo)
                        let lower: Expr? = definition.shadeAgainst.flatMap { other in
                            if case .explicit(let g)? = parsed[other]?.kinds.first { return g }
                            return nil
                        }
                        item.shade = range
                        item.shadeLower = lower
                        if definition.visible { shaded.append(IntegralJob(id: definition.id, f: f, g: lower, range: range)) }
                    }
                }
                items.append(item)
            }
            guard let f = primary[definition.id] else { continue }
            // f′ and the derivatives of the Taylor polynomial depend on f alone, not on the parameter values
            // (only the coefficients do): they are formed once and kept while f stays the same.
            var chain = chains[f] ?? derivativeChains[f] ?? DerivativeChain(formed: [f])
            if definition.showDerivative, let simplified = shownDerivative(&chain) {
                derivatives[definition.id] = simplified
                items.append(PlotItem(id: "\(definition.id.uuidString)#d", kind: .explicit(simplified), color: color.withAlpha(0.75),
                                      visible: definition.visible, width: width * 0.75, dashed: true, analyzed: false))
            }
            if definition.showIntegralFunction == true {
                // F(x) = ∫₀ˣ f(τ) dτ, integrated numerically for every sample.
                let integral = Expr.integral(f.substituting("x", with: .variable("τ")), variable: "τ", lower: .zero, upper: .x)
                items.append(PlotItem(id: "\(definition.id.uuidString)#F", kind: .explicit(integral), color: GraphPalette.color(definition.colorIndex + 2),
                                      visible: definition.visible, width: width * 0.85, dashed: true, analyzed: false))
            }
            if definition.showInverse == true {
                // x = f(y): the graph mirrored over y = x, with the mirror line.
                items.append(PlotItem(id: "\(definition.id.uuidString)#i", kind: .explicitInY(f.substituting("x", with: .y)),
                                      color: color.withAlpha(0.8), visible: definition.visible, width: width * 0.85, dashed: true, analyzed: false))
                items.append(PlotItem(id: "\(definition.id.uuidString)#m", kind: .explicit(.x), color: RGBA(0.6, 0.6, 0.6, 0.6),
                                      visible: definition.visible, width: 1, dashed: true, analyzed: false))
            }
            if definition.taylorEnabled,
               let t = TaylorSeries.polynomial(around: definition.taylorCenter, order: definition.taylorOrder, context: context,
                                               derivative: { derivative($0, of: &chain) }) {
                taylors[definition.id] = t
                items.append(PlotItem(id: "\(definition.id.uuidString)#t", kind: .explicit(t), color: GraphPalette.color(definition.colorIndex + 3),
                                      visible: definition.visible, width: width * 0.85, dashed: true, analyzed: false))
            }
            if definition.showDerivative || definition.taylorEnabled { chains[f] = chain }
        }

        derivativeChains = chains
        self.errors = errors
        self.notes = notes
        primaryExpressions = primary
        self.derivatives = derivatives
        taylorPolynomials = taylors
        parameterNames = names.sorted()
        canvas.highlightIntersections = true
        if canvas.showSpecialPoints != showSpecialPoints { canvas.showSpecialPoints = showSpecialPoints }
        canvas.parameters = values
        canvas.items = items
        computeIntegrals(shaded, parameters: values)
    }

    /// What each row draws (or its error) and the parameters of all of them.
    private func parse(_ definitions: [GraphFunctionDefinition]) -> (requests: [UUID: GraphRequest], errors: [UUID: String], names: Set<String>) {
        var parsed: [UUID: GraphRequest] = [:]
        var errors: [UUID: String] = [:]
        var names = Set<String>()
        // f(x) = … rows can be used by the others: g(x) = f(x − 2) + 1.
        let functions = CalculationEngine.definedFunctions(definitions.map(\.row))
        for definition in definitions where !definition.row.isEmpty {
            symbolicWork.parses += 1
            do {
                if let request = try CalculationEngine.graphRequest(for: definition.row, functions: functions) {
                    parsed[definition.id] = request
                    names.formUnion(request.parameters)
                } else {
                    errors[definition.id] = "Tega ni mogoče narisati"
                }
            } catch .incomplete {
                continue
            } catch {
                errors[definition.id] = error.errorDescription ?? error.shortDescription
            }
        }
        return (parsed, errors, names)
    }

    /// d/dx as `sync` forms it (in radians, as it evaluates), counted in `symbolicWork`.
    private func differentiate(_ e: Expr) -> Expr? {
        symbolicWork.derivatives += 1
        return try? Differentiator.derivative(of: e, withRespectTo: "x")
    }

    /// f⁽ᵏ⁾ (nil when it cannot be formed), forming the derivatives `chain` does not have yet.
    private func derivative(_ k: Int, of chain: inout DerivativeChain) -> Expr? {
        while chain.formed.count <= k, !chain.ended {
            if let next = differentiate(chain.formed[chain.formed.count - 1]) {
                chain.formed.append(next)
            } else {
                chain.ended = true
            }
        }
        return k < chain.formed.count ? chain.formed[k] : nil
    }

    /// f′ as shown: simplified once more.
    private func shownDerivative(_ chain: inout DerivativeChain) -> Expr? {
        if chain.shown == nil, let d = derivative(1, of: &chain) { chain.shown = Simplifier.simplify(d) }
        return chain.shown
    }

    // MARK: Integrals

    nonisolated private struct IntegralJob: Sendable {
        var id: UUID
        var f: Expr
        var g: Expr?
        var range: ClosedRange<Double>
    }

    private func computeIntegrals(_ jobs: [IntegralJob], parameters: [String: Double]) {
        integralTask?.cancel()
        guard !jobs.isEmpty else {
            integrals = [:]
            return
        }
        integralTask = Task { [weak self] in
            let results = await Task.detached(priority: .utility) {
                GraphWorkspaceModel.integrate(jobs, parameters: parameters)
            }.value
            guard let self, !Task.isCancelled else { return }
            self.integrals = results
        }
    }

    nonisolated private static func integrate(_ jobs: [IntegralJob], parameters: [String: Double]) -> [UUID: IntegralSummary] {
        let context = EvaluationContext(variables: parameters)
        var result: [UUID: IntegralSummary] = [:]
        for job in jobs {
            let f = FunctionAnalyzer.makeFunction(job.f, variable: "x", context: context)
            let g = job.g.map { FunctionAnalyzer.makeFunction($0, variable: "x", context: context) }
            let h: (Double) -> Double = { x in f(x) - (g?(x) ?? 0) }
            let a = job.range.lowerBound, b = job.range.upperBound
            guard let signed = try? Integrator.integrate(h, from: a, to: b),
                  let area = try? Integrator.integrate({ abs(h($0)) }, from: a, to: b) else { continue }
            result[job.id] = IntegralSummary(signed: NumericCalculus.clean(signed), area: NumericCalculus.clean(area))
        }
        return result
    }
}

/// A sheet opened from a function row.
struct FunctionDetail: Identifiable, Hashable {
    enum Kind: Hashable { case table, analysis, shading }
    var kind: Kind
    var definitionID: UUID
    var id: String { "\(kind)-\(definitionID)" }
}

/// Ready-made examples (matura topics and the ones from the original app).
enum GraphPresets {
    struct Preset: Identifiable {
        var title: String
        var systemImage: String
        var definitions: [String]
        /// Colour of each definition, counted from the first free colour (default: one each).
        var colors: [Int]?
        var id: String { title }
    }

    /// The word "Acute" from line segments and arcs, one colour per letter (the README picture).
    static let lettering = Preset(
        title: "Napis Acute – parametrične krivulje", systemImage: "signature",
        definitions: [
            "(4 + 3t, 6 - 6|t|), -1 <= t <= 1",
            "(2 + 4t, 2), 0 <= t <= 1",
            "(10 + 2cos(t), 2 + 2sin(t)), pi/4 <= t <= 7pi/4",
            "(13, 2 + 2t), (17, 4t), 0 <= t <= 1",
            "(15 - 2cos(t), 2 - 2sin(t)), 0 <= t <= pi",
            "(19, 1 + 4t), (18 + 3t, 4), 0 <= t <= 1",
            "(20 - cos(t), 1 - sin(t)), 0 <= t <= pi/2",
            "(22 + 4t, 2), 0 <= t <= 1",
            "(24 + 2cos(t), 2 + 2sin(t)), 0 <= t <= 7pi/4",
        ],
        colors: [0, 0, 1, 2, 2, 3, 3, 4, 4])

    static let all: [Preset] = [
        Preset(title: "sin x / x", systemImage: "waveform", definitions: ["sin(x)/x"]),
        Preset(title: "xˣ", systemImage: "arrow.up.right", definitions: ["x^x"]),
        Preset(title: "sin x in cos x – presečišča", systemImage: "point.3.connected.trianglepath.dotted", definitions: ["sin(x)", "cos(x)"]),
        Preset(title: "7ˣ + 7²ˣ + 7³ˣ = 14", systemImage: "equal.circle", definitions: ["7^x+7^(2x)+7^(3x)=14"]),
        Preset(title: "Krožnica x² + y² = r²", systemImage: "circle", definitions: ["x^2+y^2=r^2"]),
        Preset(title: "Polkrožnici y = ±√(r² − x²)", systemImage: "circle.lefthalf.filled", definitions: ["y=±sqrt(r^2-x^2)"]),
        Preset(title: "Parabola y² = 2px", systemImage: "chevron.right", definitions: ["y^2=2p*x"]),
        Preset(title: "Kvadratna funkcija a(x − p)² + q", systemImage: "chart.line.uptrend.xyaxis", definitions: ["a(x-p)^2+q"]),
        Preset(title: "Elipsa in hiperbola", systemImage: "oval", definitions: ["x^2/a^2+y^2/b^2=1", "x^2/a^2-y^2/b^2=1"]),
        Preset(title: "eˣ, ln x in y = x", systemImage: "arrow.left.and.right.righttriangle.left.righttriangle.right", definitions: ["e^x", "ln(x)", "x"]),
        Preset(title: "Racionalna funkcija", systemImage: "divide", definitions: ["(x^2-1)/(x-2)"]),
        Preset(title: "Nihanje a·sin(bx + c)", systemImage: "waveform.path", definitions: ["a*sin(b*x+c)"]),
        Preset(title: "Gaussova krivulja", systemImage: "bell", definitions: ["e^(-x^2/2)/sqrt(2pi)"]),
        Preset(title: "|x| in celi del ⌊x⌋", systemImage: "stairs", definitions: ["abs(x)", "floor(x)"]),
        Preset(title: "Območje y < x² − 2", systemImage: "square.bottomhalf.filled", definitions: ["y<x^2-2"]),
        lettering,
    ]

    /// The rows of a preset with their colours (counted from the first free colour).
    static func rows(for preset: Preset) -> [(row: MathRow, color: Int)] {
        preset.definitions.enumerated().compactMap { index, text in
            (try? MathRowConverter.row(fromText: text)).map { (row: $0, color: preset.colors?[index] ?? index) }
        }
    }
}

/// The 2D graph workspace.
struct GraphWorkspaceView: View {
    @Environment(AppStore.self) private var store
    @Environment(AppSettings.self) private var settings
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var model = GraphWorkspaceModel()
    @State private var editor = FunctionEditorModel()
    @State private var editingID: UUID?
    @State private var detail: FunctionDetail?
    @State private var showLinearInput = false
    @State private var taylorCenterFor: UUID?
    @State private var taylorCenterText = ""

    var body: some View {
        GeometryReader { geometry in
            let sideBySide = sizeClass == .regular && geometry.size.width >= 700
            if sideBySide {
                HStack(spacing: 0) {
                    VStack(spacing: 8) {
                        functionList
                        if editingID != nil {
                            DefinitionEditorPanel(model: editor, keypadHeight: min(300, geometry.size.height * 0.36)) { stopEditing() }
                                .padding(.horizontal, 12)
                                .padding(.bottom, 10)
                                .transition(Self.editorTransition(reduceMotion: reduceMotion))
                        }
                    }
                    .frame(width: min(420, geometry.size.width * 0.36))
                    canvas
                }
            } else {
                VStack(spacing: 0) {
                    canvas
                        .frame(height: geometry.size.height * (editingID == nil ? 0.5 : 0.36))
                    if editingID != nil {
                        DefinitionEditorPanel(model: editor, keypadHeight: min(300, geometry.size.height * 0.4)) { stopEditing() }
                            .padding(.horizontal, 10)
                            .padding(.top, 8)
                            .transition(Self.editorTransition(reduceMotion: reduceMotion))
                    } else {
                        functionList
                    }
                }
            }
        }
        .animation(Self.editorAnimation(reduceMotion: reduceMotion), value: editingID)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { addMenu }
        }
        .sheet(item: $detail) { detail in detailSheet(detail) }
        .sheet(isPresented: $showLinearInput) {
            LinearInputSheet { row in add(row) }
                .presentationDetents([.height(220), .medium])
        }
        .alert("Središče Taylorjevega polinoma", isPresented: Binding(get: { taylorCenterFor != nil }, set: { if !$0 { taylorCenterFor = nil } })) {
            TextField("a", text: $taylorCenterText)
                .keyboardType(.numbersAndPunctuation)
            Button("V redu") {
                if let id = taylorCenterFor, let value = ExpressionNumberField.parse(taylorCenterText) {
                    update(id) { $0.taylorCenter = value }
                }
                taylorCenterFor = nil
            }
            Button("Prekliči", role: .cancel) { taylorCenterFor = nil }
        }
        .onChange(of: store.graphFunctions, initial: true) { _, _ in sync() }
        .onChange(of: store.graphParameters) { _, _ in sync() }
        .onChange(of: settings.graphLineWidth) { _, _ in sync() }
        .onChange(of: settings.showSpecialPoints) { _, _ in sync() }
        .onChange(of: settings.graphAxes, initial: true) { _, axes in model.canvas.axes = axes }
        .onAppear { editor.settings = settings }
        #if DEBUG
        .onAppear {
            // Weak: the static hook must not keep the workspace alive.
            // The canvas under a name of its own: `[weak model]` warned that the outer closure captures model strongly.
            SmokeHooks.frameGraph = { [weak canvas = model.canvas] x, y in
                canvas?.show(x: x, y: y)
            }
        }
        #endif
    }

    // MARK: Motion

    /// The function editor slides up from the bottom; with Reduce Motion it cross-fades instead
    /// (HIG Accessibility: replace x-, y- and z-axis transitions with fades).
    static func editorTransition(reduceMotion: Bool) -> AnyTransition {
        reduceMotion ? AnyTransition.opacity : AnyTransition.move(edge: .bottom).combined(with: .opacity)
    }

    /// Opening and closing the editor (and the canvas resizing with it): a snappy spring, with
    /// Reduce Motion a short ease-in-out like the symbol palette.
    static func editorAnimation(reduceMotion: Bool) -> Animation {
        reduceMotion ? Animation.easeInOut(duration: 0.2) : Animation.snappy(duration: 0.3)
    }

    // MARK: Canvas

    private var canvas: some View {
        GraphCanvasView(model: model.canvas)
            .overlay(alignment: .bottomTrailing) {
                GlassEffectContainer(spacing: 8) {
                    VStack(spacing: 8) {
                        canvasButton("Prilagodi pogled", "arrow.up.left.and.arrow.down.right") { model.canvas.fitToContent() }
                        canvasButton("Ponastavi pogled", "scope") { model.canvas.resetView() }
                        canvasButton(settings.equalAxes ? "Prosto merilo osi" : "Enako merilo osi",
                                     settings.equalAxes ? "aspectratio.fill" : "aspectratio") {
                            settings.equalAxes.toggle()
                        }
                        canvasButton(model.canvas.showTangent ? "Skrij tangento" : "Tangenta pri sledenju", "line.diagonal") {
                            model.canvas.showTangent.toggle()
                        }
                    }
                }
                .padding(12)
            }
    }

    private func canvasButton(_ title: String, _ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .medium))
                .frame(width: 30, height: 30)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .accessibilityLabel(title)
    }

    // MARK: Function list

    private var functionList: some View {
        List {
            Section {
                ForEach(store.graphFunctions) { definition in
                    FunctionRow(definition: definition,
                                index: (store.graphFunctions.firstIndex(of: definition) ?? 0) + 1,
                                error: model.errors[definition.id],
                                note: model.notes[definition.id],
                                derivative: model.derivatives[definition.id],
                                taylor: model.taylorPolynomials[definition.id],
                                integral: model.integrals[definition.id],
                                isEditing: editingID == definition.id,
                                actions: actions(for: definition))
                        .swipeActions(edge: .trailing) {
                            Button("Izbriši", systemImage: "trash", role: .destructive) { delete(definition.id) }
                        }
                        .swipeActions(edge: .leading) {
                            Button(definition.visible ? "Skrij" : "Pokaži", systemImage: definition.visible ? "eye.slash" : "eye") {
                                update(definition.id) { $0.visible.toggle() }
                            }
                            .tint(.gray)
                        }
                }
                .onMove { from, to in store.graphFunctions.move(fromOffsets: from, toOffset: to) }
                Button("Dodaj funkcijo", systemImage: "plus.circle.fill") { add(MathRow()) }
            } header: {
                Text("Funkcije in relacije")
            } footer: {
                Text("Vnesi npr. sin x, y = x² − 1, x² + y² = 9, y < 2x ali enačbo v x (pokaže presečišči). Črke, ki niso x ali y, postanejo parametri z drsniki.")
            }
            if !model.parameterNames.isEmpty {
                Section("Parametri") {
                    ForEach(model.parameterNames, id: \.self) { name in
                        ParameterSliderRow(name: name, value: parameterBinding(name))
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollDismissesKeyboard(.interactively)
    }

    private func parameterBinding(_ name: String) -> Binding<Double> {
        Binding(get: { store.graphParameters[name] ?? 1 },
                set: { store.graphParameters[name] = $0 })
    }

    private var addMenu: some View {
        Menu {
            Button("Nova funkcija", systemImage: "plus") { add(MathRow()) }
            Button("Vnos z besedilom ali pisalom", systemImage: "pencil.and.scribble") { showLinearInput = true }
            Divider()
            Menu("Primeri", systemImage: "sparkles") {
                ForEach(GraphPresets.all) { preset in
                    Button(preset.title, systemImage: preset.systemImage) { apply(preset) }
                }
            }
            Divider()
            Button("Odstrani vse", systemImage: "trash", role: .destructive) {
                stopEditing()
                store.graphFunctions.removeAll()
            }
            .disabled(store.graphFunctions.isEmpty)
        } label: {
            Label("Dodaj", systemImage: "plus")
        }
    }

    // MARK: Actions

    private func actions(for definition: GraphFunctionDefinition) -> FunctionRow.Actions {
        let id = definition.id
        return FunctionRow.Actions(
            edit: { startEditing(id) },
            toggleVisible: { update(id) { $0.visible.toggle() } },
            setColor: { index in update(id) { $0.colorIndex = index } },
            toggleShade: {
                update(id) { $0.shadeEnabled.toggle() }
                if store.graphFunctions.first(where: { $0.id == id })?.shadeEnabled == true {
                    detail = FunctionDetail(kind: .shading, definitionID: id)
                }
            },
            editShade: { detail = FunctionDetail(kind: .shading, definitionID: id) },
            toggleDerivative: { update(id) { $0.showDerivative.toggle() } },
            toggleInverse: { update(id) { $0.showInverse = !($0.showInverse ?? false) } },
            toggleIntegralFunction: { update(id) { $0.showIntegralFunction = !($0.showIntegralFunction ?? false) } },
            toggleTaylor: { update(id) { $0.taylorEnabled.toggle() } },
            setTaylorOrder: { order in update(id) { $0.taylorOrder = order } },
            editTaylorCenter: {
                taylorCenterText = NumberFormatting.plain(definition.taylorCenter)
                taylorCenterFor = id
            },
            showTable: { detail = FunctionDetail(kind: .table, definitionID: id) },
            showAnalysis: { detail = FunctionDetail(kind: .analysis, definitionID: id) },
            duplicate: { duplicate(id) },
            delete: { delete(id) })
    }

    private func sync() {
        model.sync(store.graphFunctions, parameters: store.graphParameters,
                   lineWidth: settings.graphLineWidth, showSpecialPoints: settings.showSpecialPoints)
        // Keep defaults for new parameters so the sliders start at 1.
        for name in model.parameterNames where store.graphParameters[name] == nil {
            store.graphParameters[name] = 1
        }
    }

    private func update(_ id: UUID, _ change: (inout GraphFunctionDefinition) -> Void) {
        guard let index = store.graphFunctions.firstIndex(where: { $0.id == id }) else { return }
        change(&store.graphFunctions[index])
    }

    private var nextColorIndex: Int {
        (store.graphFunctions.map(\.colorIndex).max() ?? -1) + 1
    }

    private func add(_ row: MathRow) {
        let definition = GraphFunctionDefinition(row: row, colorIndex: nextColorIndex)
        store.graphFunctions.append(definition)
        if row.isEmpty { startEditing(definition.id) }
    }

    private func apply(_ preset: GraphPresets.Preset) {
        stopEditing()
        let first = nextColorIndex
        for (row, color) in GraphPresets.rows(for: preset) {
            store.graphFunctions.append(GraphFunctionDefinition(row: row, colorIndex: first + color))
        }
    }

    private func duplicate(_ id: UUID) {
        guard let index = store.graphFunctions.firstIndex(where: { $0.id == id }) else { return }
        var copy = store.graphFunctions[index]
        copy.id = UUID()
        copy.colorIndex = nextColorIndex
        store.graphFunctions.insert(copy, at: index + 1)
    }

    private func delete(_ id: UUID) {
        if editingID == id { stopEditing() }
        store.graphFunctions.removeAll { $0.id == id }
        for index in store.graphFunctions.indices where store.graphFunctions[index].shadeAgainst == id {
            store.graphFunctions[index].shadeAgainst = nil
        }
    }

    private func startEditing(_ id: UUID) {
        guard let definition = store.graphFunctions.first(where: { $0.id == id }) else { return }
        let store = self.store
        editor.onChange = nil
        editor.load(definition.row)
        editor.onChange = { row in
            guard let index = store.graphFunctions.firstIndex(where: { $0.id == id }) else { return }
            store.graphFunctions[index].row = row
        }
        editor.onCommit = { stopEditing() }
        editingID = id
    }

    private func stopEditing() {
        editor.onChange = nil
        editor.onCommit = nil
        // Its steps could no longer be seen, and an undo elsewhere would change the editor invisibly.
        editor.undoManager?.removeAllActions(withTarget: editor)
        editor.paletteExpanded = false
        // Drop a function that was left empty.
        if let id = editingID, store.graphFunctions.first(where: { $0.id == id })?.row.isEmpty == true {
            store.graphFunctions.removeAll { $0.id == id }
        }
        editingID = nil
    }

    // MARK: Sheets

    @ViewBuilder
    private func detailSheet(_ detail: FunctionDetail) -> some View {
        let definition = store.graphFunctions.first { $0.id == detail.definitionID }
        let title = definition.map { MathRowConverter.plainText($0.row) } ?? ""
        switch detail.kind {
        case .table:
            NavigationStack {
                Group {
                    if let expr = model.primaryExpressions[detail.definitionID] {
                        ValueTableView(expr: expr, parameters: model.canvas.parameters)
                    } else {
                        ContentUnavailableView("Ni funkcije y = f(x)", systemImage: "tablecells",
                                               description: Text("Tabela vrednosti je na voljo za funkcije ene spremenljivke."))
                    }
                }
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button(role: .close) { self.detail = nil } } }
            }
            .presentationDetents([.medium, .large])
        case .analysis:
            NavigationStack {
                Group {
                    if let expr = model.primaryExpressions[detail.definitionID] {
                        FunctionAnalysisView(expr: expr, range: model.canvas.visibleValuesX, scale: model.canvas.axes.x,
                                             parameters: model.canvas.parameters)
                    } else {
                        ContentUnavailableView("Ni funkcije y = f(x)", systemImage: "function",
                                               description: Text("Analiza je na voljo za funkcije ene spremenljivke."))
                    }
                }
                .navigationTitle("Analiza: \(title)")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button(role: .close) { self.detail = nil } } }
            }
            .presentationDetents([.medium, .large])
        case .shading:
            ShadingSheet(definitionID: detail.definitionID, summary: model.integrals[detail.definitionID])
                .presentationDetents([.medium, .large])
        }
    }
}

/// One function in the list: colour dot (visibility), the expression and its extras.
struct FunctionRow: View {
    struct Actions {
        var edit: () -> Void
        var toggleVisible: () -> Void
        var setColor: (Int) -> Void
        var toggleShade: () -> Void
        var editShade: () -> Void
        var toggleDerivative: () -> Void
        var toggleInverse: () -> Void
        var toggleIntegralFunction: () -> Void
        var toggleTaylor: () -> Void
        var setTaylorOrder: (Int) -> Void
        var editTaylorCenter: () -> Void
        var showTable: () -> Void
        var showAnalysis: () -> Void
        var duplicate: () -> Void
        var delete: () -> Void
    }

    let definition: GraphFunctionDefinition
    let index: Int
    var error: String?
    var note: String?
    var derivative: Expr?
    var taylor: Expr?
    var integral: IntegralSummary?
    var isEditing = false
    let actions: Actions
    @Environment(AppSettings.self) private var settings
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button(action: actions.toggleVisible) {
                Circle()
                    .strokeBorder(GraphPalette.color(definition.colorIndex).color, lineWidth: 2.5)
                    .background(Circle().fill(definition.visible ? GraphPalette.color(definition.colorIndex).color : .clear))
                    .overlay {
                        // Differentiate Without Color: the dot is otherwise told apart only by its colour.
                        if let number = Self.dotNumber(index, differentiateWithoutColor: differentiateWithoutColor) {
                            Text(number)
                                .font(.system(size: 12, weight: .bold).monospacedDigit())
                                // Black has at least 6.2:1 on every palette colour (white as little as 1.4:1).
                                .foregroundStyle(definition.visible ? Color.black : Color.primary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.5)
                                .padding(3)
                        }
                    }
                    .frame(width: 22, height: 22)
                    .padding(.top, 4)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Self.dotLabel(index, visible: definition.visible))

            VStack(alignment: .leading, spacing: 6) {
                Group {
                    if definition.row.isEmpty {
                        Text("Nova funkcija – vnesi izraz").foregroundStyle(.secondary)
                    } else {
                        ViewThatFits(in: .horizontal) {
                            MathText(row: definition.row, fontSize: 22)
                            MathText(row: definition.row, fontSize: 17)
                            MathText(row: definition.row, fontSize: 13)
                        }
                    }
                }
                .opacity(definition.visible ? 1 : 0.5)
                if let error {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                if let note {
                    Label(note, systemImage: "cube").font(.caption).foregroundStyle(.secondary)
                }
                if let derivative {
                    HStack(spacing: 4) {
                        Text("f′(x) =").font(.caption).foregroundStyle(.secondary)
                        MathText(expr: DisplayForm.prettify(derivative), fontSize: 14, color: .secondary)
                    }
                }
                if definition.taylorEnabled {
                    HStack(spacing: 8) {
                        Stepper("T\(subscriptDigits(definition.taylorOrder)) okoli a = \(NumberFormatting.plain(definition.taylorCenter))",
                                value: Binding(get: { definition.taylorOrder }, set: { actions.setTaylorOrder($0) }), in: 0...20)
                            .font(.caption)
                    }
                    if let taylor {
                        ViewThatFits(in: .horizontal) {
                            MathText(expr: DisplayForm.prettify(taylor), fontSize: 13, color: .secondary)
                            Text(MathRowConverter.plainText(MathRowConverter.row(for: DisplayForm.prettify(taylor))))
                                .font(.caption2.monospaced())
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                }
                if definition.shadeEnabled {
                    Button(action: actions.editShade) {
                        HStack(spacing: 10) {
                            Image(systemName: "square.fill.on.square").foregroundStyle(GraphPalette.color(definition.colorIndex).color)
                            if let integral {
                                Text("∫ = \(format(integral.signed))   P = \(format(integral.area))")
                            } else {
                                Text("Računam ploščino …")
                            }
                        }
                        .font(.caption.monospacedDigit())
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect)
            .onTapGesture(perform: actions.edit)

            Menu {
                menuContent
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title3)
                    .frame(width: 36, height: 36)
            }
            .accessibilityLabel("Možnosti funkcije")
        }
        .padding(.vertical, 4)
        .listRowBackground(isEditing ? Color.accentColor.opacity(0.12) : nil)
        .contextMenu { menuContent }
    }

    @ViewBuilder
    private var menuContent: some View {
        Button("Uredi", systemImage: "pencil", action: actions.edit)
        Menu("Barva", systemImage: "paintpalette") {
            ForEach(0..<GraphPalette.colors.count, id: \.self) { index in
                Button {
                    actions.setColor(index)
                } label: {
                    Label {
                        Text(GraphPalette.name(index))
                    } icon: {
                        GraphPalette.swatch(index, selected: definition.colorIndex % GraphPalette.colors.count == index)
                    }
                }
            }
        }
        Divider()
        Toggle(isOn: Binding(get: { definition.shadeEnabled }, set: { _ in actions.toggleShade() })) {
            Label("Ploščina (določeni integral)", systemImage: "square.fill.on.square")
        }
        Toggle(isOn: Binding(get: { definition.showDerivative }, set: { _ in actions.toggleDerivative() })) {
            Label("Odvod f′(x)", systemImage: "function")
        }
        Toggle(isOn: Binding(get: { definition.showIntegralFunction ?? false }, set: { _ in actions.toggleIntegralFunction() })) {
            Label("Integralska funkcija ∫₀ˣ f", systemImage: "sum")
        }
        Toggle(isOn: Binding(get: { definition.showInverse ?? false }, set: { _ in actions.toggleInverse() })) {
            Label("Inverzna funkcija f⁻¹", systemImage: "arrow.left.and.right.righttriangle.left.righttriangle.right")
        }
        Toggle(isOn: Binding(get: { definition.taylorEnabled }, set: { _ in actions.toggleTaylor() })) {
            Label("Taylorjev polinom", systemImage: "chart.line.text.clipboard")
        }
        if definition.taylorEnabled {
            Button("Središče Taylorjevega polinoma …", systemImage: "scope", action: actions.editTaylorCenter)
        }
        Divider()
        Button("Tabela vrednosti", systemImage: "tablecells", action: actions.showTable)
        Button("Analiza funkcije", systemImage: "waveform.path.ecg", action: actions.showAnalysis)
        Divider()
        Button(definition.visible ? "Skrij" : "Pokaži", systemImage: definition.visible ? "eye.slash" : "eye", action: actions.toggleVisible)
        Button("Podvoji", systemImage: "plus.square.on.square", action: actions.duplicate)
        Button("Izbriši", systemImage: "trash", role: .destructive, action: actions.delete)
    }

    /// The function's number in the list, drawn in its colour dot only with Differentiate
    /// Without Color (the default dot is unchanged).
    static func dotNumber(_ index: Int, differentiateWithoutColor: Bool) -> String? {
        differentiateWithoutColor ? String(index) : nil
    }

    /// "Skrij graf 2": the colour dot's VoiceOver label names the function by its number.
    static func dotLabel(_ index: Int, visible: Bool) -> String {
        (visible ? "Skrij graf " : "Pokaži graf ") + String(index)
    }

    private func format(_ x: Double) -> String {
        NumberFormatting.format(x, options: settings.numberFormat).plainTextLocalized
    }

    private func subscriptDigits(_ n: Int) -> String {
        let digits: [Character: Character] = ["0": "₀", "1": "₁", "2": "₂", "3": "₃", "4": "₄", "5": "₅", "6": "₆", "7": "₇", "8": "₈", "9": "₉"]
        return String(String(n).map { digits[$0] ?? $0 })
    }
}

/// Slider for one parameter, with a play button that sweeps it back and forth.
struct ParameterSliderRow: View {
    let name: String
    @Binding var value: Double
    @State private var range: ClosedRange<Double> = -10...10
    @State private var playing = false
    @Environment(AppSettings.self) private var settings

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 10) {
                MathText(row: MathRow([.symbol(.variable(name))]), fontSize: 20)
                    .frame(minWidth: 22)
                Text("= " + NumberFormatting.format(value, options: NumberFormatOptions(mode: .norm1, significantDigits: 4, decimalSeparator: settings.decimalSeparator)).mantissa)
                    .font(.body.monospacedDigit())
                    .contentTransition(.numericText())
                Spacer()
                Button(playing ? "Ustavi" : "Animiraj", systemImage: playing ? "pause.fill" : "play.fill") { playing.toggle() }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)
                Menu {
                    Picker("Obseg", selection: $range) {
                        Text("−1 … 1").tag(-1.0...1.0)
                        Text("−5 … 5").tag(-5.0...5.0)
                        Text("−10 … 10").tag(-10.0...10.0)
                        Text("0 … 10").tag(0.0...10.0)
                        Text("−100 … 100").tag(-100.0...100.0)
                    }
                    Button("Ponastavi na 1", systemImage: "arrow.counterclockwise") { value = 1 }
                } label: {
                    Image(systemName: "slider.horizontal.3")
                }
                .accessibilityLabel("Obseg parametra \(name)")
            }
            Slider(value: Binding(get: { min(max(value, range.lowerBound), range.upperBound) },
                                  set: { value = ($0 * 100).rounded() / 100 }),
                   in: range) {
                Text(name)
            } minimumValueLabel: {
                Text(NumberFormatting.plain(range.lowerBound)).font(.caption2)
            } maximumValueLabel: {
                Text(NumberFormatting.plain(range.upperBound)).font(.caption2)
            }
        }
        .task(id: playing) {
            guard playing else { return }
            var direction = 1.0
            let clock = ContinuousClock()
            var last = clock.now
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(16))
                let now = clock.now
                let dt = (now - last) / .seconds(1)
                last = now
                let speed = (range.upperBound - range.lowerBound) / 6
                var next = value + direction * speed * dt
                if next > range.upperBound { next = range.upperBound; direction = -1 }
                if next < range.lowerBound { next = range.lowerBound; direction = 1 }
                value = next
            }
        }
    }
}

/// Bounds and between-curves choice for a shaded definite integral.
struct ShadingSheet: View {
    let definitionID: UUID
    let summary: IntegralSummary?
    @Environment(AppStore.self) private var store
    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                if let index = store.graphFunctions.firstIndex(where: { $0.id == definitionID }) {
                    let definition = store.graphFunctions[index]
                    Section {
                        MathText(row: definition.row, fontSize: 22)
                        Toggle("Pobarvaj ploščino", isOn: binding(index, \.shadeEnabled))
                    }
                    Section {
                        ExpressionNumberField(title: "Spodnja meja a", value: binding(index, \.shadeFrom))
                        ExpressionNumberField(title: "Zgornja meja b", value: binding(index, \.shadeTo))
                    } header: {
                        Text("Meje")
                    } footer: {
                        Text("Vneseš lahko tudi izraz, npr. pi/2 ali −3.")
                    }
                    Section("Ploščina med") {
                        Picker("Spodnja krivulja", selection: binding(index, \.shadeAgainst)) {
                            Text("os x (y = 0)").tag(UUID?.none)
                            ForEach(store.graphFunctions.filter { $0.id != definitionID && !$0.row.isEmpty }) { other in
                                Text(MathRowConverter.plainText(other.row)).tag(UUID?.some(other.id))
                            }
                        }
                    }
                    if let summary {
                        Section {
                            LabeledContent("∫ₐᵇ (f − g) dx", value: format(summary.signed))
                            LabeledContent("Ploščina |…|", value: format(summary.area))
                        } header: {
                            Text("Rezultat")
                        } footer: {
                            Text("Integral šteje ploščino pod osjo x negativno (rdeče), ploščina jo šteje pozitivno.")
                        }
                    }
                }
            }
            .navigationTitle("Določeni integral")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(role: .close) { dismiss() } } }
        }
    }

    private func binding<Value>(_ index: Int, _ keyPath: WritableKeyPath<GraphFunctionDefinition, Value>) -> Binding<Value> {
        Binding(get: { store.graphFunctions[index][keyPath: keyPath] },
                set: { store.graphFunctions[index][keyPath: keyPath] = $0 })
    }

    private func format(_ x: Double) -> String {
        NumberFormatting.format(x, options: settings.numberFormat).plainTextLocalized
    }
}

/// A text field that accepts a number or an expression (π/2, −∞ is not allowed) and reports a Double.
struct ExpressionNumberField: View {
    let title: String
    @Binding var value: Double
    @State private var text = ""
    @State private var invalid = false
    @FocusState private var focused: Bool

    var body: some View {
        LabeledContent(title) {
            TextField(title, text: $text)
                .multilineTextAlignment(.trailing)
                .keyboardType(.numbersAndPunctuation)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .focused($focused)
                .foregroundStyle(invalid ? Color.red : Color.primary)
                .onSubmit(commit)
                .onChange(of: focused) { _, isFocused in if !isFocused { commit() } }
        }
        .onAppear { text = NumberFormatting.plain(value) }
        .onChange(of: value) { _, newValue in if !focused { text = NumberFormatting.plain(newValue) } }
    }

    private func commit() {
        if let parsed = Self.parse(text) {
            value = parsed
            invalid = false
        } else {
            invalid = true
        }
    }

    /// Parses "2,5", "pi/2", "-3", "sqrt(2)" into a finite number.
    static func parse(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        let normalized = trimmed.replacingOccurrences(of: ",", with: ".")
        if let direct = Double(normalized), direct.isFinite { return direct }
        guard let expr = try? Parser.parse(normalized),
              let value = try? RealEvaluator.evaluate(expr), value.isFinite else { return nil }
        return value
    }
}

extension SIMD4 where Scalar == Float {
    /// The same colour for SwiftUI (labels, swatches).
    nonisolated var color: Color {
        Color(.sRGB, red: Double(x), green: Double(y), blue: Double(z), opacity: Double(w))
    }
}

extension GraphPalette {
    static let names = ["Modra", "Rdeča", "Zelena", "Oranžna", "Vijolična", "Rumena", "Turkizna", "Roza"]

    static func name(_ index: Int) -> String {
        names[((index % names.count) + names.count) % names.count]
    }

    /// A coloured circle for menus (menu icons are templates unless the image keeps its own colours).
    static func swatch(_ index: Int, selected: Bool) -> Image {
        let symbol = selected ? "checkmark.circle.fill" : "circle.fill"
        let c = color(index)
        let tint = UIColor(red: CGFloat(c.x), green: CGFloat(c.y), blue: CGFloat(c.z), alpha: 1)
        guard let image = UIImage(systemName: symbol)?.withTintColor(tint, renderingMode: .alwaysOriginal) else {
            return Image(systemName: symbol)
        }
        return Image(uiImage: image)
    }
}
