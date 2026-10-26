import AcuteCore
import Foundation
import Observation

/// How the current numeric result is shown (the Sharp CHANGE key cycles through these).
enum ResultFormat: String, CaseIterable, Identifiable {
    case automatic, decimal, fraction, mixed, recurring, sexagesimal, scientific, engineering, primeFactors
    /// Complex results: r∠φ and r·e^{iφ}.
    case polar, exponential
    var id: String { rawValue }
    var title: String {
        switch self {
        case .automatic: "Točno"
        case .decimal: "Decimalno"
        case .fraction: "Ulomek"
        case .mixed: "Mešani ulomek"
        case .recurring: "Periodično"
        case .sexagesimal: "D°M′S″"
        case .scientific: "SCI"
        case .engineering: "ENG"
        case .primeFactors: "Razcep"
        case .polar: "Polarno r∠φ"
        case .exponential: "Eksponentno r·eⁱᵠ"
        }
    }
}

/// What the area above the keypad shows (the original's "Graph ⌃⌄" menu).
enum PreviewMode: String, CaseIterable, Identifiable {
    case automatic, graph, result, hidden
    var id: String { rawValue }
    var title: String {
        switch self {
        case .automatic: "Samodejno"
        case .graph: "Graf"
        case .result: "Rezultat"
        case .hidden: "Skrij"
        }
    }
}

@Observable
final class CalculatorModel: KeypadTarget {
    var editor = MathEditor() {
        didSet {
            guard editor != oldValue else { return }
            if !isRestoringUndo { registerUndo(previous: oldValue) }
            editorChanged()
        }
    }
    private(set) var calculation: Calculation?
    private(set) var isEvaluating = false
    var resultFormat: ResultFormat = .automatic
    var previewMode: PreviewMode = .automatic
    var storeMode = false
    var paletteExpanded = false
    var selectedPage: SymbolPage = .main
    /// After Enter the result stays visible; typing a digit starts over, an operator continues with Ans.
    private(set) var committed = false
    private(set) var lastAnswer: NumericResult?
    /// Ans when the last result was a matrix or vector.
    private(set) var lastMatrixAnswer: Matrix?
    let graph = GraphCanvasModel()
    let surface = SurfaceModel()

    /// What a calculation gets besides the row: variables with Ans, stored matrices, the functions
    /// from the Graphs tab and the settings.
    typealias EvaluationInputs = (variables: [String: Double], exact: [String: ExactReal], matrices: [String: Matrix],
                                  functions: [String: Expr], settings: CalculationSettings)

    /// The engine call; tests replace it to count calculations or to make one run until it is cancelled.
    @ObservationIgnored var calculate: @Sendable (MathRow, EvaluationInputs) -> Calculation = { row, inputs in
        CalculationEngine.calculate(row, variables: inputs.variables, exactVariables: inputs.exact,
                                    matrixVariables: inputs.matrices, functions: inputs.functions, settings: inputs.settings)
    }
    @ObservationIgnored private var evaluationTask: Task<Void, Never>?
    @ObservationIgnored private var randomSeed: UInt64 = UInt64.random(in: 1...UInt64.max)
    @ObservationIgnored weak var store: AppStore?
    @ObservationIgnored weak var settings: AppSettings?
    /// The window's undo manager (three-finger swipe, shake, ⌘Z).
    @ObservationIgnored weak var undoManager: UndoManager?
    @ObservationIgnored private var isRestoringUndo = false
    /// Stored values (A–F, X, Y, M, Ans) the graph preview got with the last result; they have no slider.
    @ObservationIgnored private var previewValueNames: Set<String> = []

    init() {
        graph.viewport.scale = SIMD2(40, 40)
    }

    // MARK: Keys

    func press(_ key: KeypadKey) {
        if storeMode, case .variable(let name) = key {
            storeAnswer(in: name)
            return
        }
        // A hardware keyboard types letters: after STO the memory's own letter (⇧A) stores too.
        if storeMode, case .typedLetter(let letter) = key, AppStore.memoryNames.contains(letter) {
            storeAnswer(in: letter)
            return
        }
        prepareForInput(key)
        switch key {
        case .clear: clear()
        case .enter: enter()
        case .angleMode:
            settings?.cycleAngleUnit()
            scheduleEvaluation(immediate: true)
        case .store: storeMode.toggle()
        case .memoryPlus: addToMemory(sign: 1)
        case .memoryMinus: addToMemory(sign: -1)
        case .change: cycleResultFormat()
        case .expand: paletteExpanded.toggle()
        case .undo: undoManager?.undo()
        case .redo: undoManager?.redo()
        case .modify: modifyAnswer()
        default: _ = editor.apply(key)
        }
    }

    /// Sharp MDF: the result keeps only the digits shown in the current display mode (FIX, SCI …).
    private func modifyAnswer() {
        guard let settings, case .number(let r)? = calculation?.outcome else { return }
        let shown = NumberFormatting.format(r.value, options: settings.numberFormat)
        let mantissa = shown.mantissa
            .replacingOccurrences(of: settings.decimalSeparator, with: ".")
            .replacingOccurrences(of: "\u{2009}", with: "")
            .replacingOccurrences(of: "−", with: "-")
        guard var value = Double(mantissa) else { return }
        if let exponent = shown.exponent { value *= Foundation.pow(10, Double(exponent)) }
        let exact: ExactReal? = value == value.rounded() && Swift.abs(value) < 1e15 ? ExactReal(Int(value)) : nil
        let rounded = NumericResult(value: value, exact: exact)
        calculation = Calculation(expr: calculation?.expr, outcome: .number(rounded), graph: calculation?.graph)
        lastAnswer = rounded
        resultFormat = .decimal
    }

    // MARK: Undo

    private func registerUndo(previous: MathEditor) {
        undoManager?.registerUndo(withTarget: self) { model in
            let current = model.editor
            model.isRestoringUndo = true
            model.editor = previous
            model.isRestoringUndo = false
            model.committed = false
            // Registering while undoing records the redo step.
            model.registerUndo(previous: current)
        }
    }

    /// After Enter: digits start a new expression, operators continue from Ans.
    private func prepareForInput(_ key: KeypadKey) {
        guard committed else { return }
        switch key {
        case .enter, .left, .right, .up, .down, .change, .expand, .store, .angleMode, .memoryPlus, .memoryMinus, .undo, .redo, .selectAll, .modify:
            return
        case .delete:
            committed = false
            return
        default:
            break
        }
        committed = false
        let continuesWithAns: Bool = {
            switch key {
            case .symbol(let s): s.isOperator && s != .equals || s == .factorial || s == .percent
            case .power, .square, .cube, .inverse, .fraction: true
            default: false
            }
        }()
        editor.clear()
        if continuesWithAns, lastAnswer != nil || lastMatrixAnswer != nil {
            editor.insert(.ans)
        }
    }

    func clear() {
        if let settings, settings.addOnClear, !editor.isEmpty {
            addToHistory(force: false)
        }
        editor.clear()
        committed = false
        storeMode = false
    }

    func enter() {
        guard !editor.isEmpty else { return }
        evaluateNow()
        addToHistory(force: true)
        switch calculation?.outcome {
        case .number(let r)?, .special(_, let r)?:
            lastAnswer = r
            lastMatrixAnswer = nil
        case .matrix(let m)?:
            lastMatrixAnswer = m
            lastAnswer = nil
        default:
            break
        }
        committed = true
        randomSeed = UInt64.random(in: 1...UInt64.max)
    }

    private func cycleResultFormat() {
        let available = availableFormats
        guard !available.isEmpty else { return }
        let index = available.firstIndex(of: resultFormat).map { ($0 + 1) % available.count } ?? 0
        resultFormat = available[index]
    }

    /// Formats that make sense for the current result.
    var availableFormats: [ResultFormat] {
        switch calculation?.outcome {
        case .complex?: return [.automatic, .polar, .exponential]
        case .linearSystem(let solution)? where !solution.isReal: return [.automatic, .polar, .exponential]
        default: break
        }
        guard case .number(let r)? = calculation?.outcome else { return [] }
        var formats: [ResultFormat] = [.automatic, .decimal]
        if let rational = r.exact?.rational ?? Rational.approximating(r.value, maxDenominator: 10_000, tolerance: 1e-12), !rational.isInteger {
            formats.append(.fraction)
            if abs(rational.numerator) > rational.denominator { formats.append(.mixed) }
            if NumberFormatting.recurringDecimal(rational) != nil { formats.append(.recurring) }
        }
        formats.append(contentsOf: [.sexagesimal, .scientific, .engineering])
        if r.value == r.value.rounded(), abs(r.value) >= 2, abs(r.value) < 1e10 { formats.append(.primeFactors) }
        return formats
    }

    // MARK: Memory and variables

    private var currentValue: NumericResult? {
        if case .number(let r)? = calculation?.outcome { return r }
        if case .special(_, let r)? = calculation?.outcome { return r }
        return lastAnswer
    }

    func storeAnswer(in name: String) {
        storeMode = false
        guard let store else { return }
        if case .matrix(let m)? = calculation?.outcome {
            store.store(matrix: m, in: name)
        } else if let value = currentValue {
            store.store(value.value, rational: value.exact?.rational, in: name)
        } else if let m = lastMatrixAnswer {
            store.store(matrix: m, in: name)
        } else {
            return
        }
        scheduleEvaluation(immediate: true)
    }

    private func addToMemory(sign: Double) {
        guard let value = currentValue, let store else { return }
        store.memory += sign * value.value
    }

    // MARK: History

    private func addToHistory(force: Bool) {
        guard let store, let settings else { return }
        if force && !settings.addOnEnter { return }
        let calculation = self.calculation
        var entry = HistoryEntry(expression: editor.root, resultText: "")
        switch calculation?.outcome {
        case .number(let r)?:
            entry.resultText = NumberFormatting.format(r.value, options: settings.numberFormat).plainText
            entry.exactResult = r.displayExact.map(MathRowConverter.row(for:))
            entry.numericValue = r.value
        case .complex(let c)?:
            entry.resultText = ComplexFormatting.text(unit: settings.imaginaryUnit, c, options: settings.numberFormat)
        case .solutions(let s)?:
            entry.resultText = s.solutions.isEmpty ? "ni realnih rešitev" : s.solutions.map { NumberFormatting.format($0.value, options: settings.numberFormat).plainText }.joined(separator: "; ")
        case .symbolic(let e)?:
            entry.resultText = ""
            entry.exactResult = MathRowConverter.row(for: e)
        case .special(let special, let r)?:
            entry.resultText = SpecialFormatting.text(special, options: settings.numberFormat)
            entry.numericValue = r.value
        case .infinite(let positive)?:
            entry.resultText = positive ? "∞" : "−∞"
        case .inequality(let solution)?:
            entry.resultText = InequalityFormatting.text(solution, options: settings.numberFormat)
        case .linearSystem(let solution)?:
            entry.resultText = zip(solution.unknowns, solution.values).map { name, value in
                MathSymbol.displayName(name) + " = " + ComplexFormatting.text(unit: settings.imaginaryUnit, value, options: settings.numberFormat)
            }.joined(separator: ", ")
        case .eigen(let decomposition)?:
            entry.resultText = decomposition.eigenvalues.enumerated().map { index, eigenvalue in
                "λ\(index + 1) = " + MathRowConverter.plainText(MathRowConverter.row(for: EigenFormatting.valueExpr(eigenvalue)))
            }.joined(separator: ", ")
        case .matrix(let m)?:
            entry.resultText = "\(m.rows)×\(m.columns)"
            entry.exactResult = MathRowConverter.row(for: MatrixFormatting.expr(m))
        case .error(let e)?:
            guard settings.addIncomplete else { return }
            entry.resultText = e.shortDescription
        case .incomplete?, .empty?, nil:
            if calculation?.graph != nil {
                guard settings.addGraphsToHistory else { return }
                entry.isGraph = true
                entry.resultText = "graf"
            } else if !settings.addIncomplete {
                return
            }
        }
        if calculation?.graph != nil { entry.isGraph = true }
        store.addHistory(entry)
    }

    func load(_ entry: HistoryEntry) {
        editor = MathEditor(root: entry.expression)
        committed = false
    }

    func insert(row: MathRow) {
        if committed { editor.clear(); committed = false }
        for node in row.nodes { editor.insertNode(node) }
    }

    // MARK: Evaluation

    private func editorChanged() {
        resultFormat = .automatic
        scheduleEvaluation(immediate: false)
    }

    func scheduleEvaluation(immediate: Bool) {
        evaluationTask?.cancel()
        let row = editor.root
        let inputs = evaluationInputs()
        let calculate = self.calculate
        isEvaluating = true
        evaluationTask = Task { [weak self] in
            if !immediate { try? await Task.sleep(for: .milliseconds(40)) }
            guard !Task.isCancelled else { return }
            let result = await BackgroundWork.run(priority: .userInitiated) {
                Signposts.interval("Calculate") { calculate(row, inputs) }
            }
            guard let self, !Task.isCancelled else { return }
            self.apply(result, values: inputs.variables)
        }
    }

    /// Synchronous evaluation (Enter must see the final result immediately).
    private func evaluateNow() {
        evaluationTask?.cancel()
        let inputs = evaluationInputs()
        apply(Signposts.interval("Calculate on Enter") { calculate(editor.root, inputs) }, values: inputs.variables)
    }

    private func evaluationInputs() -> EvaluationInputs {
        var variables = store?.numericVariables ?? [:]
        var exact = store?.exactVariables ?? [:]
        var matrices = store?.matrixVariables ?? [:]
        if let answer = lastAnswer {
            variables["Ans"] = answer.value
            if let e = answer.exact { exact["Ans"] = e }
        }
        if let m = lastMatrixAnswer { matrices["Ans"] = m }
        let settings = CalculationSettings(angleUnit: self.settings?.angleUnit ?? .radians,
                                           complexResults: self.settings?.complexResults ?? true,
                                           randomSeed: randomSeed, imaginaryUnitJ: self.settings?.imaginaryJ ?? false)
        // Functions from the Graphs tab (f(x) = …) can be evaluated here: f(2), f(x) + 1 …
        let functions = CalculationEngine.definedFunctions(store?.graphFunctions.map(\.row) ?? [])
        return (variables, exact, matrices, functions, settings)
    }

    /// `values`: the stored values the result was calculated with.
    private func apply(_ result: Calculation, values: [String: Double]) {
        calculation = result
        isEvaluating = false
        updatePreview(result.graph, values: values)
    }

    // MARK: Graph preview

    var hasGraph: Bool { calculation?.graph != nil }

    /// Calculators always have "=" at the bottom right (it also commits graphs to the history).
    var enterShowsEquals: Bool { true }

    var isSurface: Bool {
        guard let kinds = calculation?.graph?.kinds else { return false }
        return kinds.contains { if case .surface = $0 { true } else { false } }
    }

    private func updatePreview(_ request: GraphRequest?, values: [String: Double]) {
        guard let request else {
            graph.items = []
            return
        }
        var parameters = graph.parameters
        // A memory deleted since then becomes a slider again and starts at 1, not at its old value.
        for name in previewValueNames { parameters[name] = nil }
        for p in request.parameters where parameters[p] == nil { parameters[p] = 1 }
        for p in parameters.keys where !request.parameters.contains(p) { parameters[p] = nil }
        // Stored values get no slider (the engine leaves them out of request.parameters), but the canvas
        // and the 3D model must know them: y = A·x, x² + y² = A or z = A·x·y drew nothing.
        previewValueNames = Set(values.keys).subtracting(request.parameters)
        for name in previewValueNames { parameters[name] = values[name] }
        graph.parameters = parameters
        graph.highlightIntersections = request.highlightIntersections
        graph.showSpecialPoints = settings?.showSpecialPoints ?? true
        var items: [PlotItem] = []
        for (i, kind) in request.kinds.enumerated() {
            if case .surface(let expr) = kind {
                surface.setFunction(expr, parameters: parameters)
                continue
            }
            var item = PlotItem(id: "calc-\(i)", kind: kind, color: GraphPalette.color(i), width: Float(settings?.graphLineWidth ?? 3))
            if let shade = request.shadedIntegral, i == 0 {
                item.shade = shade.lower...shade.upper
                // ∫(f − g): shade between both curves.
                if case .sum(let terms) = shade.integrand, terms.count == 2, case .negation(let g) = terms[1] {
                    item.kind = .explicit(terms[0])
                    item.shadeLower = g
                    items.append(PlotItem(id: "calc-lower", kind: .explicit(g), color: GraphPalette.color(1), width: item.width))
                }
            }
            items.append(item)
        }
        graph.items = items
        // Vectors, complex numbers and sequences: frame them.
        if !request.kinds.isEmpty, request.kinds.allSatisfy({ kind in
            if case .sequence = kind { return true }
            if case .parametric = kind { return true }
            return kind.isFigure
        }) {
            graph.fitToContent()
        }
    }
}

/// Eigenvalues and eigenvectors as expressions (exact where known).
enum EigenFormatting {
    static func valueExpr(_ eigenvalue: EigenDecomposition.Eigenvalue) -> Expr {
        eigenvalue.exact ?? ComplexFormatting.rectangularExpr(eigenvalue.value)
    }

    /// The basis vectors of the eigenspace as columns.
    static func vectors(_ eigenvalue: EigenDecomposition.Eigenvalue) -> [Expr] {
        if let exact = eigenvalue.exactVectors {
            return exact.map { v in .matrix(rows: v.count, columns: 1, entries: v.map { .number($0) }) }
        }
        return eigenvalue.vectors.map { v in .matrix(rows: v.count, columns: 1, entries: v.map(ComplexFormatting.rectangularExpr)) }
    }
}

/// Formatting helpers for complex and special results.
enum ComplexFormatting {
    static func text(unit: String = "i", _ c: Complex, options: NumberFormatOptions) -> String {
        let re = NumberFormatting.format(c.re, options: options)
        let im = NumberFormatting.format(abs(c.im), options: options)
        let reText = re.plainText
        let imText = im.plainText == "1" ? "" : im.plainText
        if c.im == 0 { return reText }
        if c.re == 0 { return (c.im < 0 ? "−" : "") + imText + unit }
        return "\(reText) \(c.im < 0 ? "−" : "+") \(imText)\(unit)"
    }

    /// r∠φ with φ in the calculator's angle unit (electrical engineering phasors).
    static func polar(_ c: Complex, options: NumberFormatOptions, angleUnit: AngleUnit) -> String {
        let r = NumberFormatting.format(c.magnitude, options: options).plainText
        let phi = NumberFormatting.format(NumericCalculus.clean(c.argument / angleUnit.radiansPerUnit), options: options).plainText
        let mark = switch angleUnit {
        case .degrees: "°"
        case .gradians: "ᵍ"
        case .radians: ""
        }
        return "\(r)∠\(phi)\(mark)"
    }

    /// a + bi as an expression (fractions when the parts are simple).
    static func rectangularExpr(_ c: Complex) -> Expr {
        let re = number(c.re)
        let im = number(Swift.abs(c.im))
        let imaginary: Expr = im == .number(.one) ? .constant(.i) : .product([im, .constant(.i)])
        if c.im == 0 { return re }
        if c.re == 0 { return c.im < 0 ? .negation(imaginary) : imaginary }
        return .sum([re, c.im < 0 ? .negation(imaginary) : imaginary])
    }

    /// r·e^{iφ} with φ in radians (π-multiples and surds recognised).
    static func exponentialExpr(_ c: Complex) -> Expr {
        let r = recognised(c.magnitude)
        let phi = recognised(NumericCalculus.clean(c.argument))
        if c.argument == 0 { return r }
        return .product([r, .power(.constant(.e), .product([phi, .constant(.i)]))])
    }

    static func number(_ x: Double) -> Expr {
        if let r = Rational.approximating(x, maxDenominator: 1000, tolerance: 1e-12) { return .number(r) }
        return .decimal(NumberFormatting.roundSignificant(x, 10))
    }

    static func recognised(_ x: Double) -> Expr {
        if let exact = ExactRecognizer.recognize(x, tolerance: 1e-10), exact.complexity <= 8 { return exact.expr }
        return number(x)
    }
}

enum SpecialFormatting {
    static func text(_ special: SpecialResult, options: NumberFormatOptions) -> String {
        switch special {
        case .quotientRemainder(let q, let r): "Q = \(q), R = \(r)"
        case .polar(let r, let theta): "r = \(NumberFormatting.format(r, options: options).plainText), θ = \(NumberFormatting.format(theta, options: options).plainText)"
        case .rectangular(let x, let y): "x = \(NumberFormatting.format(x, options: options).plainText), y = \(NumberFormatting.format(y, options: options).plainText)"
        case .polygon(let area, let perimeter): "S = \(NumberFormatting.format(area, options: options).plainText), o = \(NumberFormatting.format(perimeter, options: options).plainText)"
        case .segmentLength(let d): "d = \(NumberFormatting.format(d, options: options).plainText)"
        case .areaUnderPolyline(let area): "S = \(NumberFormatting.format(area, options: options).plainText) (pod lomljeno črto)"
        case .curve(let length, let area):
            "L = \(NumberFormatting.format(length, options: options).plainText)"
                + (area.map { ", S = \(NumberFormatting.format($0, options: options).plainText)" } ?? "")
        }
    }
}

/// Display of matrix results: exact entries as fractions/surds, others rounded.
enum MatrixFormatting {
    static func expr(_ m: Matrix) -> Expr {
        var entries: [Expr] = []
        for r in 0..<m.rows {
            for c in 0..<m.columns {
                if let q = m.exactEntry(r, c) {
                    entries.append(.number(q))
                } else {
                    let v = NumericCalculus.clean(m[r, c])
                    if let exact = ExactRecognizer.recognize(v, tolerance: 1e-11) {
                        entries.append(exact.expr)
                    } else {
                        entries.append(.decimal(NumberFormatting.roundSignificant(v, 8)))
                    }
                }
            }
        }
        return .matrix(rows: m.rows, columns: m.columns, entries: entries)
    }

    static func plainText(_ m: Matrix) -> String {
        MathRowConverter.plainText(MathRowConverter.row(for: expr(m)))
    }
}
