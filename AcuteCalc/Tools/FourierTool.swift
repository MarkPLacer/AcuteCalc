import AcuteCore
import SwiftUI

/// Fourier series (Matematika II): f given piecewise on one period, the coefficients with
/// general formulas in n where the integrals have closed forms, and the partial sums S_N
/// drawn over the periodic extension.
struct FourierToolView: View {
    @AppStorage("fourierKind") private var kind: FourierSeries.Kind = .full
    @AppStorage("fourierStart") private var startText = "-pi"
    @AppStorage("fourierPieceCount") private var count = 1
    @AppStorage("fourierF1") private var f1 = "x"
    @AppStorage("fourierB1") private var b1 = "pi"
    @AppStorage("fourierF2") private var f2 = "0"
    @AppStorage("fourierB2") private var b2 = "2pi"
    @AppStorage("fourierF3") private var f3 = "0"
    @AppStorage("fourierB3") private var b3 = "3pi"
    @AppStorage("fourierTerms") private var terms = 5
    @State private var series: FourierSeries.Series?
    @State private var error: String?
    @State private var computing = false
    @State private var canvas = GraphCanvasModel()

    private static let subscripts = ["₁", "₂", "₃"]

    var body: some View {
        let pieces = parsedPieces
        let start = try? Parser.parse(startText)
        List {
            Section {
                Picker("Vrsta", selection: $kind) {
                    Text("Polna").tag(FourierSeries.Kind.full)
                    Text("Sinusna").tag(FourierSeries.Kind.sine)
                    Text("Kosinusna").tag(FourierSeries.Kind.cosine)
                }
                .pickerStyle(.segmented)
            } footer: {
                Text(note)
            }
            Section {
                LabeledContent("Začetek a") {
                    TextField("-pi", text: $startText)
                        .multilineTextAlignment(.trailing)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .foregroundStyle(start == nil ? Color.red : Color.primary)
                }
                ForEach(0..<count, id: \.self) { i in
                    pieceRow(i)
                }
                if count < 3 {
                    Button("Dodaj odsek", systemImage: "plus.circle") { count += 1 }
                }
                if count > 1 {
                    Button("Odstrani zadnji odsek", systemImage: "minus.circle", role: .destructive) { count -= 1 }
                }
            } header: {
                Text("f(x) na enem intervalu")
            } footer: {
                Text("Vsak odsek velja od konca prejšnjega do svoje meje. Pravokotni signal: −1 do 0 in 1 do pi z začetkom −pi.")
            }
            Section("Koeficienti") {
                coefficients
            }
            Section {
                Stepper("Členov N = \(terms)", value: $terms, in: 1...50)
                GraphCanvasView(model: canvas)
                    .frame(height: 320)
                    .listRowInsets(EdgeInsets())
            } header: {
                Text("Delna vsota S_N")
            } footer: {
                Text("Modro: periodično nadaljevanje f; rdeče: S_N(x). V skokih vrsta konvergira k povprečju leve in desne limite.")
            }
        }
        .listStyle(.insetGrouped)
        .scrollDismissesKeyboard(.interactively)
        .task(id: "\(kind.rawValue)|\(startText)|\(count)|\(f1)|\(b1)|\(f2)|\(b2)|\(f3)|\(b3)|\(terms)") {
            await update(pieces, start)
        }
    }

    private var note: String {
        switch kind {
        case .full:
            "T = b − a, ω = 2π/T: f(x) ~ a₀/2 + Σ (aₙ cos nωx + bₙ sin nωx), aₙ = (2/T)∫ f(x) cos nωx dx, bₙ = (2/T)∫ f(x) sin nωx dx."
        case .sine:
            "Liha razširitev f z [a, b], L = b − a: f(x) ~ Σ bₙ sin(nπ(x − a)/L), bₙ = (2/L)∫ f(x) sin(nπ(x − a)/L) dx."
        case .cosine:
            "Soda razširitev f z [a, b], L = b − a: f(x) ~ a₀/2 + Σ aₙ cos(nπ(x − a)/L), aₙ = (2/L)∫ f(x) cos(nπ(x − a)/L) dx."
        }
    }

    // MARK: Input

    private func functionText(_ i: Int) -> String { [f1, f2, f3][i] }

    private func endText(_ i: Int) -> String { [b1, b2, b3][i] }

    private func functionBinding(_ i: Int) -> Binding<String> {
        switch i {
        case 0: $f1
        case 1: $f2
        default: $f3
        }
    }

    private func endBinding(_ i: Int) -> Binding<String> {
        switch i {
        case 0: $b1
        case 1: $b2
        default: $b3
        }
    }

    /// The typed expression; y = … and f(x) = … keep the right side.
    private func parse(_ text: String) -> (expr: Expr?, error: String?) {
        do {
            var expr = try Parser.parse(text)
            if case .relation(_, .equal, let rhs) = expr { expr = rhs }
            return (expr, nil)
        } catch {
            return (nil, error.errorDescription ?? error.shortDescription)
        }
    }

    /// The pieces when every function and every end parse.
    private var parsedPieces: [FourierSeries.Piece]? {
        var pieces: [FourierSeries.Piece] = []
        for i in 0..<count {
            guard let f = parse(functionText(i)).expr, let end = try? Parser.parse(endText(i)) else { return nil }
            pieces.append(FourierSeries.Piece(expr: f, end: end))
        }
        return pieces
    }

    private func pieceRow(_ i: Int) -> some View {
        let f = parse(functionText(i))
        return VStack(alignment: .leading, spacing: 6) {
            ExpressionInputField(title: "f" + FourierToolView.subscripts[i] + "(x) =", text: functionBinding(i), expr: f.expr, error: f.error)
            LabeledContent("do x =") {
                TextField("pi", text: endBinding(i))
                    .multilineTextAlignment(.trailing)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
        }
    }

    // MARK: Results

    @ViewBuilder
    private var coefficients: some View {
        if computing {
            ProgressView()
        } else if let series {
            if kind != .sine {
                formulaRow("a₀", series.a0Formula, value: series.a[0])
                formulaRow("aₙ", series.anFormula, value: nil)
            }
            if kind != .cosine {
                formulaRow("bₙ", series.bnFormula, value: nil)
            }
            if !series.exceptions.isEmpty {
                Text("Splošna formula ne velja za n = " + series.exceptions.map(String.init).joined(separator: ", ") + "; vrednosti so v tabeli.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(1...Swift.min(terms, 12, series.a.count - 1), id: \.self) { n in
                coefficientRow(n, series)
            }
        } else if let error {
            Text(error).foregroundStyle(.red).font(.callout)
        } else {
            Text("Vnesi funkcijo in meje odsekov.").foregroundStyle(.secondary)
        }
    }

    private func formulaRow(_ name: String, _ formula: Expr?, value: Double?) -> some View {
        LabeledContent(name) {
            if let formula {
                MathText(expr: formula, fontSize: 17)
            } else if let value {
                MathText(expr: FourierSeries.recognize(value) ?? .decimal(value), fontSize: 17)
            } else {
                Text("formule ne najdem – glej tabelo").foregroundStyle(.secondary)
            }
        }
    }

    private func coefficientRow(_ n: Int, _ s: FourierSeries.Series) -> some View {
        LabeledContent("n = \(n)") {
            HStack(spacing: 14) {
                if kind != .sine { coefficient("a", s.a[n]) }
                if kind != .cosine { coefficient("b", s.b[n]) }
            }
        }
    }

    private func coefficient(_ name: String, _ value: Double) -> some View {
        HStack(spacing: 3) {
            Text(name + " =").foregroundStyle(.secondary)
            MathText(expr: FourierSeries.recognize(value) ?? .decimal(NumericCalculus.clean(value)), fontSize: 15)
        }
    }

    // MARK: Calculation

    private func update(_ pieces: [FourierSeries.Piece]?, _ start: Expr?) async {
        error = nil
        computing = false
        guard let pieces, let start else {
            series = nil
            canvas.items = []
            error = start == nil ? "Preveri začetek intervala." : "Preveri funkcije in meje odsekov."
            return
        }
        computing = true
        let kind = self.kind, terms = self.terms
        let outcome: Result<FourierSeries.Series, MathError> = await Task.detached(priority: .userInitiated) {
            do throws(MathError) {
                return .success(try FourierSeries.series(pieces, start: start, kind: kind, terms: terms))
            } catch {
                return .failure(error)
            }
        }.value
        // Newer input started another calculation while this one ran.
        guard !Task.isCancelled else { return }
        computing = false
        switch outcome {
        case .success(let found):
            series = found
            draw(found, pieces: pieces, start: start)
        case .failure(let failure):
            series = nil
            canvas.items = []
            error = failure.errorDescription ?? failure.shortDescription
        }
    }

    /// Two periods of the extension and of S_N, framed around their values.
    private func draw(_ s: FourierSeries.Series, pieces: [FourierSeries.Piece], start: Expr) {
        let extended = FourierSeries.periodicExtension(pieces, start: start, kind: s.kind)
        let period = s.kind == .full ? s.length : 2 * s.length
        let lo = s.kind == .full ? s.start - period / 2 : s.start - period
        let hi = lo + 2 * period
        var ys: [Double] = []
        for i in 0...240 {
            let x = lo + (hi - lo) * Double(i) / 240
            ys.append(s.value(at: x, terms: terms))
            if let v = try? RealEvaluator.evaluate(extended, context: EvaluationContext(variables: ["x": x])) { ys.append(v) }
        }
        let finite = ys.filter(\.isFinite)
        if let low = finite.min(), let high = finite.max() {
            let pad = Swift.max(0.5, 0.15 * (high - low))
            canvas.viewport.fit(x: lo...hi, y: (low - pad)...(high + pad))
        }
        canvas.items = [
            PlotItem(id: "extension", kind: .explicit(extended), color: GraphPalette.color(0), width: 2.5, analyzed: false),
            PlotItem(id: "partial", kind: .explicit(s.partialSum(terms)), color: GraphPalette.color(1), width: 2, analyzed: false),
        ]
    }
}
