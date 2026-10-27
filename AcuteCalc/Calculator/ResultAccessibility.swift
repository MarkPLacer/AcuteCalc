import AcuteCore
import Foundation

/// What VoiceOver says for the calculator's result: the label of the number result (one element
/// instead of "=", mantissa, "·10" and exponent read separately) and the announcement after "=".
/// Numbers and math are written as on screen (decimal comma, the chosen result format).
enum ResultAccessibility {
    static func text(for calculation: Calculation?, format: ResultFormat, settings: AppSettings) -> String? {
        guard let calculation else { return nil }
        let options = settings.numberFormat
        let style = MathAccessibility.style(settings)
        func math(_ e: Expr) -> String { MathAccessibility.label(MathRowConverter.row(for: e), style: style) }
        func spoken(_ value: Double) -> String { MathAccessibility.number(NumberFormatting.format(value, options: options)) }
        func complex(_ c: Complex) -> String {
            switch format {
            case .polar: ComplexFormatting.polar(c, options: options, angleUnit: settings.angleUnit)
            case .exponential: math(ComplexFormatting.exponentialExpr(c))
            default: math(ComplexFormatting.rectangularExpr(c))
            }
        }
        switch calculation.outcome {
        case .number(let r):
            return number(r, format: format, settings: settings)
        case .complex(let c):
            return "je enako " + complex(c)
        case .linearSystem(let solution):
            return solution.unknowns.indices.map { i in
                let value = solution.exact.flatMap { i < $0.count ? math(.number($0[i])) : nil }
                    ?? (i < solution.values.count ? complex(solution.values[i]) : "")
                return MathSymbol.displayName(solution.unknowns[i]) + " = " + value
            }.joined(separator: ", ")
        case .solutions(let result):
            if result.isIdentity { return "Velja za vsak \(result.variable) (identiteta)" }
            if result.solutions.isEmpty {
                guard !result.complexSolutions.isEmpty else { return "Ni realnih rešitev" }
                return "Ni realnih rešitev, v kompleksnem: "
                    + result.complexSolutions.map { ComplexFormatting.text(unit: settings.imaginaryUnit, $0, options: options) }.joined(separator: "; ")
            }
            let many = result.solutions.count > 1
            var text = result.solutions.enumerated().map { index, solution in
                let name = MathSymbol.displayName(many ? "\(result.variable)_\(index + 1)" : result.variable)
                return name + " = " + (solution.exactExpr.map(math) ?? spoken(solution.value))
            }.joined(separator: "; ")
            if let period = result.period {
                text += ", plus k krat " + math(ExactRecognizer.recognize(period)?.expr ?? .decimal(period)) + ", k je celo število"
            }
            return text
        case .symbolic(let e):
            return "je enako " + math(e)
        case .special(.unionArea(let union), let r):
            // P = π/2 (exact when known) and why it is the area or only a bound.
            let headline = union.overlap == .disjoint ? r.displayExact.map { "P = " + math($0) } : nil
            return (headline ?? UnionAreaFormatting.headline(union, options: options)) + ". " + UnionAreaFormatting.explanation(union)
        case .special(let special, _):
            return "je enako " + SpecialFormatting.text(special, options: options)
        case .infinite(let positive):
            return positive ? "je enako neskončno" : "je enako minus neskončno"
        case .inequality(let solution):
            return InequalityFormatting.text(solution, options: options)
        case .matrix(let m):
            return "je enako " + math(MatrixFormatting.expr(m))
        case .error(let e):
            return e.errorDescription ?? e.shortDescription
        case .eigen(let decomposition):
            return decomposition.eigenvalues.enumerated().map { index, eigenvalue in
                "λ\(index + 1) = " + math(EigenFormatting.valueExpr(eigenvalue))
            }.joined(separator: ", ")
        case .incomplete, .empty:
            return calculation.graph != nil ? "Graf" : nil
        }
    }

    /// A number in the selected result format, as ResultView shows it.
    static func number(_ r: NumericResult, format: ResultFormat, settings: AppSettings) -> String {
        let options = settings.numberFormat
        let style = MathAccessibility.style(settings)
        func decimal(_ o: NumberFormatOptions) -> String { "je enako " + MathAccessibility.number(NumberFormatting.format(r.value, options: o)) }
        switch format {
        case .automatic:
            if let exact = r.displayExact {
                return "je enako " + MathAccessibility.label(MathRowConverter.row(for: exact), style: style)
                    + ", približno " + MathAccessibility.number(NumberFormatting.format(r.value, options: options))
            }
        case .fraction:
            if let q = ResultView.rational(r) {
                return "je enako " + MathAccessibility.label(MathRowConverter.row(for: .number(q)), style: style)
            }
        case .mixed:
            if let q = ResultView.rational(r), let m = NumberFormatting.mixedFraction(q) {
                return "je enako \(m.whole) in \(m.numerator)/\(m.denominator)"
            }
        case .recurring:
            // The screen marks the period with an overline, which VoiceOver does not read.
            if let q = ResultView.rational(r), let rec = NumberFormatting.recurringDecimal(q) {
                return "je enako \(rec.integerPart)\(settings.decimalSeparator)\(rec.prefix)\(rec.period), perioda \(rec.period)"
            }
        case .sexagesimal:
            let dms = NumberFormatting.sexagesimal(r.value)
            let seconds = NumberFormatting.format(dms.seconds, options: NumberFormatOptions(mode: .norm1, significantDigits: 6, decimalSeparator: settings.decimalSeparator)).mantissa
            return "je enako \(dms.negative ? "−" : "")\(dms.degrees)° \(dms.minutes)′ \(seconds)″"
        case .scientific:
            return decimal(NumberFormatOptions(mode: .sci, places: options.places, decimalSeparator: options.decimalSeparator))
        case .engineering:
            return decimal(NumberFormatOptions(mode: .eng, places: options.places, decimalSeparator: options.decimalSeparator))
        case .primeFactors:
            if let row = ResultView.primeFactorRow(r.value) {
                return "je enako " + MathAccessibility.label(row, style: style)
            }
        case .decimal, .polar, .exponential:
            break
        }
        return decimal(options)
    }
}
