import AcuteCore
import SwiftUI
import UIKit

/// Table of values of y = f(x) (Sharp TABLE mode): start, step and number of rows.
struct ValueTableView: View {
    let expr: Expr
    var parameters: [String: Double] = [:]
    var angleUnit: AngleUnit = .radians
    @Environment(AppSettings.self) private var settings
    @State private var start = -3.0
    @State private var step = 1.0
    @State private var count = 13

    private struct Row: Identifiable {
        var id: Int
        var x: Double
        var y: Double
    }

    private var rows: [Row] {
        let context = EvaluationContext(angleUnit: angleUnit, variables: parameters)
        let f = FunctionAnalyzer.makeFunction(expr, variable: "x", context: context)
        return (0..<count).map { i in
            let x = NumericCalculus.clean(start + Double(i) * step)
            return Row(id: i, x: x, y: NumericCalculus.clean(f(x)))
        }
    }

    var body: some View {
        List {
            Section {
                ExpressionNumberField(title: "Začetek x₀", value: $start)
                ExpressionNumberField(title: "Korak Δx", value: $step)
                Stepper("Vrstic: \(count)", value: $count, in: 2...200)
            } footer: {
                Text("Korak je lahko tudi izraz, npr. pi/6.")
            }
            Section {
                ForEach(rows) { row in
                    HStack(alignment: .firstTextBaseline) {
                        valueCell(row.x)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        valueCell(row.y)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    .accessibilityElement(children: .combine)
                }
            } header: {
                HStack {
                    Text("x").frame(maxWidth: .infinity, alignment: .leading)
                    Text("f(x)").frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Kopiraj tabelo", systemImage: "doc.on.doc") {
                    UIPasteboard.general.string = csv
                }
            }
        }
    }

    @ViewBuilder
    private func valueCell(_ value: Double) -> some View {
        if !value.isFinite {
            Text("ni definirano")
                .font(.callout)
                .foregroundStyle(.secondary)
        } else if let exact = ExactRecognizer.recognize(value, tolerance: 1e-11), exact.rational?.isInteger != true {
            HStack(spacing: 6) {
                MathText(expr: exact.expr, fontSize: 17)
                Text("≈ " + format(value))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        } else {
            Text(format(value)).font(.body.monospacedDigit())
        }
    }

    private func format(_ x: Double) -> String {
        NumberFormatting.format(x, options: settings.numberFormat).plainTextLocalized
    }

    private var csv: String {
        let separator = settings.decimalComma ? ";" : ","
        return (["x\(separator)f(x)"] + rows.map { row in
            "\(format(row.x))\(separator)\(row.y.isFinite ? format(row.y) : "")"
        }).joined(separator: "\n")
    }
}

/// Complete analysis of y = f(x): domain, zeros, extrema, inflection points, asymptotes,
/// monotonicity and convexity (the "analiza funkcije" from the matura).
struct FunctionAnalysisView: View {
    let expr: Expr
    var range: ClosedRange<Double>
    var parameters: [String: Double] = [:]
    @Environment(AppSettings.self) private var settings
    @State private var analysis: FunctionAnalysis?
    @State private var from: Double
    @State private var to: Double

    init(expr: Expr, range: ClosedRange<Double>, parameters: [String: Double] = [:]) {
        self.expr = expr
        self.range = range
        self.parameters = parameters
        _from = State(initialValue: (range.lowerBound * 100).rounded() / 100)
        _to = State(initialValue: (range.upperBound * 100).rounded() / 100)
    }

    var body: some View {
        List {
            Section {
                ExpressionNumberField(title: "Od x", value: $from)
                ExpressionNumberField(title: "Do x", value: $to)
            } header: {
                Text("Interval")
            }
            if let analysis {
                derivativeSection(analysis)
                if let points = analysis.excludedPoints, !points.isEmpty {
                    Section("Definicijsko območje") {
                        Text("x ≠ " + points.map(format).joined(separator: "; "))
                            .font(.body.monospacedDigit())
                    }
                }
                symmetrySection(analysis)
                pointSection("Ničle", analysis.zeros, empty: "Ni ničel na intervalu")
                if let y0 = analysis.yIntercept {
                    pointSection("Začetna vrednost", [y0], empty: "")
                }
                pointSection("Ekstremi", analysis.extrema, empty: "Ni lokalnih ekstremov")
                pointSection("Prevoji", analysis.inflections, empty: "Ni prevojev")
                asymptoteSection(analysis)
                intervalSection("Narašča na", analysis.increasing)
                intervalSection("Pada na", analysis.decreasing)
                intervalSection("Konveksna (∪) na", analysis.convex)
                intervalSection("Konkavna (∩) na", analysis.concave)
            } else {
                Section {
                    HStack {
                        ProgressView()
                        Text("Analiziram …").foregroundStyle(.secondary)
                    }
                }
            }
        }
        .task(id: AnalysisKey(from: from, to: to)) {
            analysis = nil
            guard to > from else { return }
            let expr = self.expr
            let interval = from...to
            let context = EvaluationContext(variables: parameters)
            analysis = await Task.detached(priority: .userInitiated) {
                FunctionAnalyzer.analyze(expr, range: interval, context: context)
            }.value
        }
    }

    private struct AnalysisKey: Equatable {
        var from: Double
        var to: Double
    }

    @ViewBuilder
    private func derivativeSection(_ analysis: FunctionAnalysis) -> some View {
        Section("Funkcija in odvoda") {
            row("f(x)", MathText(expr: DisplayForm.prettify(expr), fontSize: 19))
            if let d = analysis.derivative {
                row("f′(x)", MathText(expr: DisplayForm.prettify(d), fontSize: 19))
            }
            if let d2 = analysis.secondDerivative {
                row("f″(x)", MathText(expr: DisplayForm.prettify(d2), fontSize: 19))
            }
        }
    }

    @ViewBuilder
    private func symmetrySection(_ analysis: FunctionAnalysis) -> some View {
        if analysis.isEven || analysis.isOdd || analysis.period != nil {
            Section("Lastnosti") {
                if analysis.isEven { Text("Soda funkcija: f(−x) = f(x)") }
                if analysis.isOdd { Text("Liha funkcija: f(−x) = −f(x)") }
                if let period = analysis.period {
                    HStack {
                        Text("Periodična, osnovna perioda")
                        Spacer()
                        exactOrDecimal(period)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func pointSection(_ title: String, _ points: [SpecialPoint], empty: String) -> some View {
        Section(title) {
            if points.isEmpty {
                if !empty.isEmpty { Text(empty).foregroundStyle(.secondary) }
            } else {
                ForEach(points) { point in
                    HStack(spacing: 8) {
                        if point.kind == .maximum || point.kind == .minimum {
                            Text(point.kind.title)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(point.kind == .maximum ? Color.green : Color.orange)
                        }
                        Spacer()
                        Text("(").foregroundStyle(.secondary)
                        exactOrDecimal(point.x, exact: point.exactX)
                        Text(";").foregroundStyle(.secondary)
                        exactOrDecimal(point.y, exact: point.exactY)
                        Text(")").foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func asymptoteSection(_ analysis: FunctionAnalysis) -> some View {
        let hasAny = !analysis.poles.isEmpty || analysis.horizontalAsymptoteLeft != nil
            || analysis.horizontalAsymptoteRight != nil || analysis.obliqueAsymptote != nil
        if hasAny {
            Section("Asimptote") {
                ForEach(analysis.poles, id: \.self) { pole in
                    Text("Navpična: x = \(format(pole))")
                }
                if let left = analysis.horizontalAsymptoteLeft, let right = analysis.horizontalAsymptoteRight, abs(left - right) < 1e-9 {
                    Text("Vodoravna: y = \(format(left))")
                } else {
                    if let left = analysis.horizontalAsymptoteLeft { Text("Vodoravna (x → −∞): y = \(format(left))") }
                    if let right = analysis.horizontalAsymptoteRight { Text("Vodoravna (x → ∞): y = \(format(right))") }
                }
                if let line = analysis.obliqueAsymptote {
                    Text("Poševna: y = \(format(line.slope))·x \(line.intercept < 0 ? "−" : "+") \(format(abs(line.intercept)))")
                }
            }
            .font(.body.monospacedDigit())
        }
    }

    @ViewBuilder
    private func intervalSection(_ title: String, _ intervals: [ClosedRange<Double>]) -> some View {
        if !intervals.isEmpty {
            Section(title) {
                Text(intervals.map { "(\(format($0.lowerBound)), \(format($0.upperBound)))" }.joined(separator: " ∪ "))
                    .font(.callout.monospacedDigit())
            }
        }
    }

    private func row(_ title: String, _ content: some View) -> some View {
        HStack(spacing: 10) {
            Text(title).foregroundStyle(.secondary)
            ViewThatFits(in: .horizontal) {
                content
                Text("(dolg izraz)").foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private func exactOrDecimal(_ value: Double, exact: ExactReal? = nil) -> some View {
        if let exact = exact ?? ExactRecognizer.recognize(value, tolerance: 1e-9), exact.rational?.isInteger != true {
            MathText(expr: exact.expr, fontSize: 17)
        } else {
            Text(format(value)).font(.body.monospacedDigit())
        }
    }

    private func format(_ x: Double) -> String {
        NumberFormatting.format(x, options: NumberFormatOptions(mode: .norm1, significantDigits: 6, decimalSeparator: settings.decimalSeparator)).plainTextLocalized
    }
}
