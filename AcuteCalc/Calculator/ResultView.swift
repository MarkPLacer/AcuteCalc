import AcuteCore
import SwiftUI
import UIKit

/// eig(A): the characteristic polynomial and every eigenvalue with a basis of its eigenspace.
struct EigenResultView: View {
    let decomposition: EigenDecomposition
    var fontSize: CGFloat

    var body: some View {
        VStack(alignment: .trailing, spacing: 10) {
            HStack(spacing: 6) {
                Text("det(A − λI) =")
                    .font(.system(size: fontSize * 0.7))
                    .foregroundStyle(.secondary)
                MathText(expr: decomposition.characteristicPolynomial, fontSize: fontSize * 0.85)
            }
            ScrollView(.horizontal) {
                HStack(alignment: .center, spacing: 22) {
                    ForEach(Array(decomposition.eigenvalues.enumerated()), id: \.offset) { index, eigenvalue in
                        VStack(spacing: 6) {
                            HStack(spacing: 4) {
                                MathText(row: MathRow([.symbol(.variable("λ_\(index + 1)")), .symbol(.equals)]), fontSize: fontSize)
                                MathText(expr: EigenFormatting.valueExpr(eigenvalue), fontSize: fontSize)
                                if eigenvalue.multiplicity > 1 {
                                    Text("(\(eigenvalue.multiplicity)×)")
                                        .font(.system(size: fontSize * 0.6))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            HStack(spacing: 8) {
                                ForEach(Array(EigenFormatting.vectors(eigenvalue).enumerated()), id: \.offset) { _, vector in
                                    MathText(expr: vector, fontSize: fontSize * 0.8)
                                }
                            }
                        }
                    }
                }
            }
            .scrollIndicators(.hidden)
            if !decomposition.isDiagonalizable {
                Text("Matrika ni diagonalizabilna (premalo lastnih vektorjev).")
                    .font(.system(size: fontSize * 0.6))
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// A complex number as a + bi, r∠φ (phasor, in the angle unit) or r·e^{iφ}.
struct ComplexValueView: View {
    let value: Complex
    let format: ResultFormat
    var fontSize: CGFloat
    @Environment(AppSettings.self) private var settings

    var body: some View {
        switch format {
        case .polar:
            Text(ComplexFormatting.polar(value, options: settings.numberFormat, angleUnit: settings.angleUnit))
                .font(.system(size: fontSize * 0.85, weight: .light).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.4)
        case .exponential:
            MathText(expr: ComplexFormatting.exponentialExpr(value), fontSize: fontSize)
        default:
            MathText(expr: ComplexFormatting.rectangularExpr(value), fontSize: fontSize)
        }
    }
}

/// x = 2, y = −1 (exact fractions) or the complex currents and voltages of a circuit.
struct LinearSolutionView: View {
    let solution: LinearEquations.Solution
    let format: ResultFormat
    var fontSize: CGFloat

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 16) { items }
            VStack(alignment: .trailing, spacing: 4) { items }
        }
    }

    private var items: some View {
        ForEach(Array(solution.unknowns.enumerated()), id: \.offset) { index, name in
            HStack(spacing: 6) {
                MathText(row: MathRow([.symbol(.variable(name)), .symbol(.equals)]), fontSize: fontSize)
                if let exact = solution.exact?[index] {
                    MathText(expr: .number(exact), fontSize: fontSize)
                } else {
                    ComplexValueView(value: solution.values[index], format: format, fontSize: fontSize)
                }
            }
        }
    }
}

/// x ∈ (−∞; −2) ∪ [3; ∞) with exact ends where they are known.
struct InequalitySolutionView: View {
    let solution: InequalitySolution
    var fontSize: CGFloat
    @Environment(AppSettings.self) private var settings

    var body: some View {
        HStack(spacing: 4) {
            Text(solution.variable).italic()
            if solution.isEmpty {
                Text(": ni rešitve")
            } else if solution.isAllReals {
                Text("∈ ℝ")
            } else {
                Text("∈")
                ForEach(Array(solution.intervals.enumerated()), id: \.offset) { index, interval in
                    if index > 0 { Text("∪").foregroundStyle(.secondary) }
                    piece(interval)
                }
                if let period = solution.period {
                    Text("+ k·")
                    end(period, exact: ExactRecognizer.recognize(period, tolerance: 1e-9))
                    Text(", k ∈ ℤ").foregroundStyle(.secondary)
                }
            }
        }
        .font(.system(size: fontSize, weight: .light).monospacedDigit())
        .lineLimit(1)
        .minimumScaleFactor(0.35)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func piece(_ interval: InequalitySolution.Interval) -> some View {
        if interval.isPoint {
            HStack(spacing: 2) {
                Text("{")
                end(interval.lower, exact: interval.exactLower)
                Text("}")
            }
        } else {
            HStack(spacing: 2) {
                Text(interval.lowerIncluded ? "[" : "(")
                end(interval.lower, exact: interval.exactLower)
                Text(";")
                end(interval.upper, exact: interval.exactUpper)
                Text(interval.upperIncluded ? "]" : ")")
            }
        }
    }

    @ViewBuilder
    private func end(_ value: Double, exact: ExactReal?) -> some View {
        if value == .infinity {
            Text("∞")
        } else if value == -.infinity {
            Text("−∞")
        } else if let exact, !exact.isRational || !(exact.rational?.isInteger ?? true), exact.complexity <= 10 {
            MathText(expr: exact.expr, fontSize: fontSize * 0.85)
        } else {
            Text(NumberFormatting.format(value, options: settings.numberFormat).plainText)
        }
    }
}

/// Plain text of an inequality solution (history, clipboard).
enum InequalityFormatting {
    static func text(_ solution: InequalitySolution, options: NumberFormatOptions) -> String {
        if solution.isEmpty { return "ni rešitve" }
        if solution.isAllReals { return "\(solution.variable) ∈ ℝ" }
        func end(_ v: Double) -> String {
            v == .infinity ? "∞" : v == -.infinity ? "−∞" : NumberFormatting.format(v, options: options).plainText
        }
        let pieces = solution.intervals.map { i in
            i.isPoint ? "{\(end(i.lower))}" : (i.lowerIncluded ? "[" : "(") + end(i.lower) + "; " + end(i.upper) + (i.upperIncluded ? "]" : ")")
        }
        var text = "\(solution.variable) ∈ " + pieces.joined(separator: " ∪ ")
        if let period = solution.period { text += " + k·" + end(period) }
        return text
    }
}

/// Shows the outcome of the current calculation (with Sharp-style CHANGE formats).
struct ResultView: View {
    let model: CalculatorModel
    var fontSize: CGFloat = 34
    @Environment(AppSettings.self) private var settings

    var body: some View {
        Group {
            switch model.calculation?.outcome {
            case .number(let r)?:
                numberView(r)
                    .contentShape(.rect)
                    .onTapGesture { model.press(.change) }
                    .contextMenu {
                        Button("Kopiraj", systemImage: "doc.on.doc") {
                            UIPasteboard.general.string = NumberFormatting.format(r.value, options: settings.numberFormat).plainText
                        }
                        Menu("Shrani v …", systemImage: "square.and.arrow.down") {
                            ForEach(AppStore.memoryNames, id: \.self) { name in
                                Button(name) { model.storeAnswer(in: name) }
                            }
                        }
                        Menu("Oblika", systemImage: "textformat.123") {
                            ForEach(model.availableFormats) { format in
                                Button(format.title) { model.resultFormat = format }
                            }
                        }
                    }
            case .complex(let c)?:
                equalsRow { ComplexValueView(value: c, format: model.resultFormat, fontSize: fontSize) }
                    .contentShape(.rect)
                    .onTapGesture { model.press(.change) }
            case .linearSystem(let solution)?:
                LinearSolutionView(solution: solution, format: model.resultFormat, fontSize: fontSize * 0.75)
                    .contentShape(.rect)
                    .onTapGesture { model.press(.change) }
            case .solutions(let result)?:
                SolutionsView(result: result, fontSize: fontSize * 0.7)
            case .symbolic(let e)?:
                equalsRow { MathText(expr: e, fontSize: fontSize * 0.85) }
            case .special(let special, _)?:
                equalsRow {
                    Text(SpecialFormatting.text(special, options: settings.numberFormat))
                        .font(.system(size: fontSize * 0.7, weight: .light).monospacedDigit())
                }
            case .infinite(let positive)?:
                equalsRow { Text(positive ? "∞" : "−∞").font(.system(size: fontSize, weight: .light)) }
            case .inequality(let solution)?:
                InequalitySolutionView(solution: solution, fontSize: fontSize * 0.7)
                    .contextMenu {
                        Button("Kopiraj", systemImage: "doc.on.doc") {
                            UIPasteboard.general.string = InequalityFormatting.text(solution, options: settings.numberFormat)
                        }
                    }
            case .matrix(let m)?:
                let expr = MatrixFormatting.expr(m)
                equalsRow { MathText(expr: expr, fontSize: fontSize * 0.78) }
                    .contextMenu {
                        Button("Kopiraj", systemImage: "doc.on.doc") {
                            MathClipboard.copy(MathRowConverter.row(for: expr), decimalComma: settings.decimalComma)
                        }
                        Button("Kopiraj kot LaTeX", systemImage: "chevron.left.forwardslash.chevron.right") {
                            MathClipboard.copyLaTeX(MathRowConverter.row(for: expr), decimalComma: settings.decimalComma)
                        }
                        Menu("Shrani v …", systemImage: "square.and.arrow.down") {
                            ForEach(AppStore.memoryNames, id: \.self) { name in
                                Button(name) { model.storeAnswer(in: name) }
                            }
                        }
                    }
            case .error(let e)?:
                Text(e.errorDescription ?? e.shortDescription)
                    .font(.footnote)
                    .foregroundStyle(.red.opacity(0.85))
                    .lineLimit(2)
                    .multilineTextAlignment(.trailing)
            case .eigen(let decomposition)?:
                EigenResultView(decomposition: decomposition, fontSize: fontSize * 0.62)
            case .incomplete?, .empty?, nil:
                EmptyView()
            }
        }
        .animation(.snappy(duration: 0.18), value: model.resultFormat)
    }

    private func equalsRow<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(alignment: .center, spacing: 8) {
            Text("=")
                .font(.system(size: fontSize * 0.8, weight: .light))
                .foregroundStyle(.secondary)
            content()
        }
    }

    @ViewBuilder
    private func numberView(_ r: NumericResult) -> some View {
        let options = settings.numberFormat
        switch model.resultFormat {
        case .automatic:
            if let exact = r.displayExact {
                VStack(alignment: .trailing, spacing: 2) {
                    equalsRow { MathText(expr: exact, fontSize: fontSize) }
                    Text("≈ " + NumberFormatting.format(r.value, options: options).plainTextLocalized)
                        .font(.system(size: fontSize * 0.5).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            } else {
                equalsRow { decimalView(r.value, options: options) }
            }
        case .decimal:
            equalsRow { decimalView(r.value, options: options) }
        case .fraction:
            if let q = rational(r) {
                equalsRow { MathText(expr: .number(q), fontSize: fontSize) }
            } else {
                equalsRow { decimalView(r.value, options: options) }
            }
        case .mixed:
            if let q = rational(r), let m = NumberFormatting.mixedFraction(q) {
                let row = MathRow(MathRowConverter.digits(String(m.whole)).map { $0 } + [
                    .fraction(numerator: .text(String(m.numerator)), denominator: .text(String(m.denominator))),
                ])
                equalsRow { MathText(row: row, fontSize: fontSize) }
            } else {
                equalsRow { decimalView(r.value, options: options) }
            }
        case .recurring:
            if let q = rational(r), let rec = NumberFormatting.recurringDecimal(q) {
                let overlined = rec.period.map { "\($0)\u{0305}" }.joined()
                equalsRow {
                    Text("\(rec.integerPart)\(settings.decimalSeparator)\(rec.prefix)\(overlined)")
                        .font(.system(size: fontSize * 0.85, weight: .light).monospacedDigit())
                }
            } else {
                equalsRow { decimalView(r.value, options: options) }
            }
        case .sexagesimal:
            let dms = NumberFormatting.sexagesimal(r.value)
            let seconds = NumberFormatting.format(dms.seconds, options: NumberFormatOptions(mode: .norm1, significantDigits: 6, decimalSeparator: settings.decimalSeparator)).mantissa
            equalsRow {
                Text("\(dms.negative ? "−" : "")\(dms.degrees)° \(dms.minutes)′ \(seconds)″")
                    .font(.system(size: fontSize * 0.8, weight: .light).monospacedDigit())
            }
        case .scientific:
            equalsRow { decimalView(r.value, options: NumberFormatOptions(mode: .sci, places: options.places, decimalSeparator: options.decimalSeparator)) }
        case .engineering:
            equalsRow { decimalView(r.value, options: NumberFormatOptions(mode: .eng, places: options.places, decimalSeparator: options.decimalSeparator)) }
        case .primeFactors:
            if let row = primeFactorRow(r.value) {
                equalsRow { MathText(row: row, fontSize: fontSize * 0.85) }
            } else {
                equalsRow { decimalView(r.value, options: options) }
            }
        case .polar, .exponential:
            equalsRow { decimalView(r.value, options: options) }
        }
    }

    /// 360 → 2³·3²·5 (Sharp P.FACT).
    private func primeFactorRow(_ value: Double) -> MathRow? {
        guard value.isFinite, abs(value) < 1e15, let factors = NumberFormatting.primeFactorization(Int(abs(value))) else { return nil }
        var nodes: [MathNode] = value < 0 ? [.symbol(.minus)] : []
        for (i, f) in factors.enumerated() {
            if i > 0 { nodes.append(.symbol(.times)) }
            nodes += MathRowConverter.digits(String(f.prime))
            if f.exponent > 1 { nodes.append(.power(exponent: .text(String(f.exponent)))) }
        }
        return MathRow(nodes)
    }

    private func rational(_ r: NumericResult) -> Rational? {
        r.exact?.rational ?? Rational.approximating(r.value, maxDenominator: 10_000, tolerance: 1e-12)
    }

    @ViewBuilder
    private func decimalView(_ value: Double, options: NumberFormatOptions) -> some View {
        let f = NumberFormatting.format(value, options: options)
        if let exponent = f.exponent {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(f.mantissa).font(.system(size: fontSize, weight: .light).monospacedDigit())
                Text("·10").font(.system(size: fontSize * 0.8, weight: .light))
                Text("\(exponent)".replacingOccurrences(of: "-", with: "−"))
                    .font(.system(size: fontSize * 0.5, weight: .regular).monospacedDigit())
                    .baselineOffset(fontSize * 0.42)
            }
        } else {
            Text(f.mantissa)
                .font(.system(size: fontSize, weight: .light).monospacedDigit())
                .minimumScaleFactor(0.35)
                .lineLimit(1)
                .contentTransition(.numericText())
        }
    }

}

/// Lists equation solutions: exact forms, decimals, periodicity and complex roots.
struct SolutionsView: View {
    let result: EquationResult
    var fontSize: CGFloat = 24
    @Environment(AppSettings.self) private var settings

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            if result.isIdentity {
                Text("Velja za vsak \(result.variable) (identiteta)")
                    .font(.system(size: fontSize * 0.8))
            } else if result.solutions.isEmpty {
                if result.complexSolutions.isEmpty {
                    Text("Ni realnih rešitev").font(.system(size: fontSize * 0.8))
                } else {
                    Text("Ni realnih rešitev — v ℂ:").font(.system(size: fontSize * 0.6)).foregroundStyle(.secondary)
                }
            }
            ForEach(Array(result.solutions.enumerated()), id: \.offset) { index, solution in
                HStack(spacing: 6) {
                    MathText(row: MathRow([.symbol(.variable(result.solutions.count > 1 ? "\(result.variable)_\(index + 1)" : result.variable)), .symbol(.equals)]), fontSize: fontSize)
                    if let exact = solution.exactExpr {
                        MathText(expr: exact, fontSize: fontSize)
                        if exact != .number(Rational(Int(solution.value.rounded()))) || solution.value != solution.value.rounded() {
                            Text("≈ " + NumberFormatting.format(solution.value, options: settings.numberFormat).plainTextLocalized)
                                .font(.system(size: fontSize * 0.6).monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Text(NumberFormatting.format(solution.value, options: settings.numberFormat).plainTextLocalized)
                            .font(.system(size: fontSize, weight: .light).monospacedDigit())
                    }
                    if result.period != nil {
                        Text("+ k·")
                            .font(.system(size: fontSize * 0.75, weight: .light))
                        MathText(expr: periodExpr, fontSize: fontSize * 0.8)
                    }
                }
            }
            if result.period != nil {
                Text("k ∈ ℤ")
                    .font(.system(size: fontSize * 0.55))
                    .foregroundStyle(.secondary)
            }
            if result.solutions.isEmpty {
                ForEach(Array(result.complexSolutions.enumerated()), id: \.offset) { index, z in
                    Text("\(result.variable)\(subscriptDigit(index + 1)) = \(ComplexFormatting.text(unit: settings.imaginaryUnit, z, options: settings.numberFormat))")
                        .font(.system(size: fontSize * 0.8, weight: .light).monospacedDigit())
                }
            }
        }
    }

    private var periodExpr: Expr {
        guard let p = result.period else { return .zero }
        if let exact = ExactRecognizer.recognize(p) { return exact.expr }
        return .decimal(p)
    }

    private func subscriptDigit(_ n: Int) -> String {
        let map: [Character: Character] = ["0": "₀", "1": "₁", "2": "₂", "3": "₃", "4": "₄", "5": "₅", "6": "₆", "7": "₇", "8": "₈", "9": "₉"]
        return String(String(n).map { map[$0] ?? $0 })
    }
}

extension FormattedNumber {
    /// Mantissa with a ·10ⁿ suffix in Unicode superscripts (for compact text).
    var plainTextLocalized: String {
        guard let exponent else { return mantissa }
        let map: [Character: Character] = ["-": "⁻", "0": "⁰", "1": "¹", "2": "²", "3": "³", "4": "⁴", "5": "⁵", "6": "⁶", "7": "⁷", "8": "⁸", "9": "⁹"]
        return mantissa + "·10" + String(String(exponent).map { map[$0] ?? $0 })
    }
}
