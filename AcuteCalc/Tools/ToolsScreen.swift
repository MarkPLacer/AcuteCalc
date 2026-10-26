import AcuteCore
import SwiftUI

/// Every tool of the Tools tab.
enum ToolKind: String, CaseIterable, Identifiable, Hashable {
    case table, analysis, differentialEquations, multivariable, vectorAnalysis, fourier
    case statistics, probability
    case triangle, vectors, spaceGeometry
    case crossSection, beam, geodesy
    case circuit, acCircuit
    case linearSystem, complexNumbers, sequences, finance
    case nBase, drill
    case units, constants

    var id: String { rawValue }

    var title: String {
        switch self {
        case .table: "Tabela vrednosti"
        case .analysis: "Analiza funkcije"
        case .differentialEquations: "Diferencialne enačbe"
        case .multivariable: "Funkcije več spremenljivk"
        case .vectorAnalysis: "Vektorska analiza"
        case .fourier: "Fourierjeva vrsta"
        case .statistics: "Statistika in regresija"
        case .probability: "Verjetnost in kombinatorika"
        case .triangle: "Trikotnik"
        case .vectors: "Vektorji"
        case .spaceGeometry: "Premice in ravnine"
        case .crossSection: "Prerezi"
        case .beam: "Nosilec"
        case .geodesy: "Geodezija"
        case .circuit: "Analiza vezja"
        case .acCircuit: "Izmenični tokokrog"
        case .linearSystem: "Sistemi linearnih enačb"
        case .complexNumbers: "Kompleksna števila"
        case .sequences: "Zaporedja in vrste"
        case .finance: "Obrestni račun"
        case .nBase: "Številski sistemi (N-BASE)"
        case .drill: "Vaja računanja (DRILL)"
        case .units: "Pretvornik enot"
        case .constants: "Fizikalne konstante"
        }
    }

    var systemImage: String {
        switch self {
        case .table: "tablecells"
        case .analysis: "waveform.path.ecg"
        case .differentialEquations: "point.topleft.down.to.point.bottomright.curvepath"
        case .multivariable: "cube"
        case .vectorAnalysis: "wind"
        case .fourier: "waveform"
        case .statistics: "chart.dots.scatter"
        case .probability: "dice"
        case .triangle: "triangle"
        case .vectors: "arrow.up.right"
        case .spaceGeometry: "cube.transparent"
        case .crossSection: "rectangle.split.2x1"
        case .beam: "chart.line.downtrend.xyaxis"
        case .geodesy: "location.north.line"
        case .circuit: "point.3.connected.trianglepath.dotted"
        case .acCircuit: "bolt"
        case .linearSystem: "square.grid.3x2"
        case .complexNumbers: "circle.circle"
        case .sequences: "list.number"
        case .finance: "eurosign.circle"
        case .nBase: "number"
        case .drill: "brain.head.profile"
        case .units: "ruler"
        case .constants: "atom"
        }
    }

    var subtitle: String {
        switch self {
        case .table: "TABLE – vrednosti f(x) od x₀ s korakom Δx"
        case .analysis: "Ničle, ekstremi, prevoji, asimptote, monotonost"
        case .differentialEquations: "y′ = f(x, y), y″ = f(x, y, y′): smerno polje, začetni problem"
        case .multivariable: "Gradient, ekstremi, Lagrange, dvojni in trojni integrali, nivojnice"
        case .vectorAnalysis: "grad, div, rot, potencial, krivuljni in ploskovni integrali"
        case .fourier: "aₙ, bₙ s splošnim členom, delne vsote, soda in liha razširitev"
        case .statistics: "x̄, σ, mediana, kvartili, 7 regresij z grafom"
        case .probability: "Binomska, Poissonova, normalna porazdelitev, n!, C, V"
        case .triangle: "SSS, SAS, ASA, SSA – stranice, koti, ploščina, polmera"
        case .vectors: "Dolžina, skalarni in vektorski produkt, kot, projekcija"
        case .spaceGeometry: "Razdalje, presečišča, koti, projekcije, zrcaljenja"
        case .crossSection: "Težišče, I_x, I_y, I_xy, glavni momenti, W – iz pravokotnikov, krogov, izsekov"
        case .beam: "Reakcije, diagrama V in M, največji moment"
        case .geodesy: "Smerni kot, urezi, poligonski in nivelmanski vlak, Helmert, izravnava, sferni trikotnik"
        case .circuit: "Vozliščna metoda: potenciali, tokovi, moči, Théveninov vir (DC in AC)"
        case .acCircuit: "RLC zaporedno in vzporedno, kazalci, moč, resonanca, kompenzacija"
        case .linearSystem: "Gaussova eliminacija s točnimi ulomki"
        case .complexNumbers: "Algebrska, polarna, eksponentna oblika, koreni"
        case .sequences: "Aritmetično in geometrijsko zaporedje, vsote"
        case .finance: "Navadno in obrestno obrestovanje, varčevanje, anuiteta"
        case .nBase: "BIN, PEN, OCT, DEC, HEX, AND, OR, XOR, NOT"
        case .drill: "Hitro računanje in poštevanka kot na Sharpu"
        case .units: "Dolžina, masa, energija, tlak, temperatura …"
        case .constants: "CODATA 2022 in astronomski podatki"
        }
    }

    struct Section: Identifiable {
        let title: String
        let tools: [ToolKind]
        var id: String { title }
    }

    static let sections: [Section] = [
        Section(title: "Funkcije", tools: [.table, .analysis, .differentialEquations, .multivariable, .vectorAnalysis, .fourier]),
        Section(title: "Statistika in verjetnost", tools: [.statistics, .probability]),
        Section(title: "Geometrija", tools: [.triangle, .vectors, .spaceGeometry]),
        Section(title: "Gradbeništvo in geodezija", tools: [.crossSection, .beam, .geodesy]),
        Section(title: "Elektrotehnika", tools: [.circuit, .acCircuit]),
        Section(title: "Algebra", tools: [.linearSystem, .complexNumbers, .sequences, .finance]),
        Section(title: "Sharp EL-W531", tools: [.nBase, .drill]),
        Section(title: "Fizika", tools: [.units, .constants]),
    ]
}

/// The Tools tab: Sharp EL-W531 modes and matura helpers.
struct ToolsScreen: View {
    @SceneStorage("selectedTool") private var selectionRaw: String?

    private var selection: Binding<ToolKind?> {
        Binding(get: { selectionRaw.flatMap(ToolKind.init(rawValue:)) }, set: { selectionRaw = $0?.rawValue })
    }

    var body: some View {
        NavigationSplitView {
            List(selection: selection) {
                ForEach(ToolKind.sections) { section in
                    Section(section.title) {
                        ForEach(section.tools) { tool in
                            NavigationLink(value: tool) { ToolRow(tool: tool) }
                        }
                    }
                }
            }
            .navigationTitle("Orodja")
            .sectionMenuToolbar()
            #if DEBUG
            .onAppear { SmokeHooks.openTool = { selectionRaw = $0.rawValue } }
            #endif
        } detail: {
            NavigationStack {
                if let tool = selection.wrappedValue {
                    ToolDetailView(tool: tool)
                        .hidesTabBarWhenCompact()
                } else {
                    ContentUnavailableView("Izberi orodje", systemImage: "wrench.and.screwdriver",
                                           description: Text("Tabele, analiza funkcij, statistika, geometrija, številski sistemi in še več."))
                }
            }
        }
    }
}

struct ToolRow: View {
    let tool: ToolKind

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(tool.title)
                Text(tool.subtitle).font(.caption).foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: tool.systemImage)
        }
    }
}

struct ToolDetailView: View {
    let tool: ToolKind

    var body: some View {
        Group {
            switch tool {
            case .table: FunctionToolView(mode: .table)
            case .analysis: FunctionToolView(mode: .analysis)
            case .differentialEquations: DifferentialEquationToolView()
            case .multivariable: MultivariableToolView()
            case .vectorAnalysis: VectorAnalysisToolView()
            case .fourier: FourierToolView()
            case .statistics: StatisticsToolView()
            case .probability: ProbabilityToolView()
            case .triangle: TriangleToolView()
            case .vectors: VectorToolView()
            case .spaceGeometry: SpaceGeometryToolView()
            case .crossSection: CrossSectionToolView()
            case .beam: BeamToolView()
            case .geodesy: GeodesyToolView()
            case .circuit: CircuitToolView()
            case .acCircuit: ACCircuitToolView()
            case .linearSystem: LinearSystemToolView()
            case .complexNumbers: ComplexNumberToolView()
            case .sequences: SequenceToolView()
            case .finance: FinanceToolView()
            case .nBase: NBaseToolView()
            case .drill: DrillToolView()
            case .units: UnitConverterView()
            case .constants: ConstantsView()
            }
        }
        .navigationTitle(tool.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Text (or Scribble) input of one expression, parsed live, with a rendered preview.
struct ExpressionInputField: View {
    let title: String
    @Binding var text: String
    var expr: Expr?
    var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField(title, text: $text)
                .font(.system(.title3, design: .monospaced))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.done)
            if let expr {
                ViewThatFits(in: .horizontal) {
                    MathText(expr: expr, fontSize: 22)
                    MathText(expr: expr, fontSize: 16)
                }
            } else if let error, !text.isEmpty {
                Text(error).font(.caption).foregroundStyle(.red)
            }
        }
    }
}

/// TABLE and function analysis for a typed function y = f(x).
struct FunctionToolView: View {
    enum Mode { case table, analysis }
    let mode: Mode
    @Environment(AppSettings.self) private var settings
    @AppStorage("toolFunctionText") private var text = "x^3-3x"

    private var parsed: (expr: Expr?, error: String?) {
        do {
            var expr = try Parser.parse(text)
            if case .relation(.variable("y"), .equal, let rhs) = expr { expr = rhs }
            return (expr, nil)
        } catch {
            return (nil, error.errorDescription ?? error.shortDescription)
        }
    }

    var body: some View {
        let parsed = self.parsed
        VStack(spacing: 0) {
            ExpressionInputField(title: "f(x) =", text: $text, expr: parsed.expr, error: parsed.error)
                .padding()
            if let expr = parsed.expr {
                switch mode {
                case .table: ValueTableView(expr: expr, angleUnit: settings.angleUnit)
                case .analysis: FunctionAnalysisView(expr: expr, range: -10...10).id(expr)
                }
            } else {
                Spacer()
            }
        }
    }
}

// MARK: Shared tool components

/// The numbers typed on one line: separated by semicolons, by ", " (decimal points), by spaces
/// (decimal commas allowed) or by single commas.
func numberFields(_ line: String) -> [Substring] {
    if line.contains(";") { return line.split(separator: ";") }
    if line.contains(", ") { return line.split(separator: ",") }
    if line.contains(where: \.isWhitespace) { return line.split(whereSeparator: \.isWhitespace) }
    return line.split(separator: ",")
}

/// A number input that accepts expressions (2,5 · pi/3 · sqrt(2)) and reports nil when empty.
struct NumberInputField: View {
    let title: String
    @Binding var value: Double?
    var prompt: String = ""
    @State private var text = ""
    @State private var invalid = false
    @FocusState private var focused: Bool

    var body: some View {
        LabeledContent(title) {
            TextField(prompt.isEmpty ? "—" : prompt, text: $text)
                .multilineTextAlignment(.trailing)
                .keyboardType(.numbersAndPunctuation)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .focused($focused)
                .foregroundStyle(invalid ? Color.red : Color.primary)
                .onSubmit(commit)
                .onChange(of: focused) { _, isFocused in if !isFocused { commit() } }
                .onChange(of: text) { _, _ in commit(quiet: true) }
        }
        .onAppear { text = value.map(NumberFormatting.plain) ?? "" }
        .onChange(of: value) { _, newValue in
            if !focused { text = newValue.map(NumberFormatting.plain) ?? "" }
        }
    }

    private func commit() { commit(quiet: false) }

    private func commit(quiet: Bool) {
        if text.trimmingCharacters(in: .whitespaces).isEmpty {
            if value != nil { value = nil }
            invalid = false
            return
        }
        if let parsed = ExpressionNumberField.parse(text) {
            if value != parsed { value = parsed }
            invalid = false
        } else if !quiet {
            invalid = true
        }
    }
}

/// A labelled result value formatted with the user's number settings; long-press copies it.
struct ResultRow: View {
    let title: String
    let value: Double?
    var exact: Expr?
    var unit: String = ""
    @Environment(AppSettings.self) private var settings

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 6) {
                if let exact {
                    MathText(expr: exact, fontSize: 17)
                    if let value { Text("≈ " + formatted(value)).font(.callout.monospacedDigit()).foregroundStyle(.secondary) }
                } else if let value {
                    Text(formatted(value)).font(.body.monospacedDigit())
                } else {
                    Text("—").foregroundStyle(.secondary)
                }
                if !unit.isEmpty { Text(unit).foregroundStyle(.secondary) }
            }
        }
        .contextMenu {
            if let value {
                Button("Kopiraj", systemImage: "doc.on.doc") { UIPasteboard.general.string = formatted(value) }
            }
        }
    }

    private func formatted(_ x: Double) -> String {
        guard x.isFinite else { return x.isNaN ? "ni definirano" : (x > 0 ? "∞" : "−∞") }
        return NumberFormatting.format(NumericCalculus.clean(x), options: settings.numberFormat).plainTextLocalized
    }
}

extension View {
    /// Shows an error message under a form.
    @ViewBuilder
    func toolError(_ message: String?) -> some View {
        if let message {
            self.safeAreaInset(edge: .bottom) {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .glassEffect(.regular.tint(Color.red.opacity(0.3)), in: .capsule)
                    .padding(.bottom, 8)
            }
        } else {
            self
        }
    }
}
