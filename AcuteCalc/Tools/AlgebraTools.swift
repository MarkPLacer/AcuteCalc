import AcuteCore
import Charts
import SwiftUI

// MARK: Linear systems

/// m equations with n unknowns, solved exactly with Gauss–Jordan elimination.
struct LinearSystemToolView: View {
    @State private var equations = 3
    @State private var unknowns = 3
    @State private var coefficients: [[Double?]] = LinearSystemToolView.example
    @State private var constants: [Double?] = [6, 2, 1]
    @Environment(AppSettings.self) private var settings

    private static let example: [[Double?]] = [[1, 1, 1], [0, 2, 5], [2, 5, -1]]
    private static let names = ["x", "y", "z", "u", "v", "w"]

    /// "Neskončno rešitev (2 prosti neznanki):" — the Slovenian plural forms (one, two, few, other)
    /// come from Localizable.xcstrings. The UI is Slovenian, so the Slovenian locale picks the
    /// form whatever the device region is.
    static func infiniteSolutionsTitle(freeUnknowns count: Int) -> String {
        String(localized: "Neskončno rešitev (\(count) prostih neznank):", locale: Locale(identifier: "sl"))
    }

    var body: some View {
        List {
            Section {
                Stepper("Enačbe: \(equations)", value: $equations, in: 1...6)
                Stepper("Neznanke: \(unknowns)", value: $unknowns, in: 1...6)
            }
            .onChange(of: equations) { _, _ in resize() }
            .onChange(of: unknowns) { _, _ in resize() }
            ForEach(0..<equations, id: \.self) { row in
                Section("\(row + 1). enačba") {
                    ForEach(0..<unknowns, id: \.self) { column in
                        NumberInputField(title: "Koeficient pri \(Self.names[column])", value: coefficient(row, column))
                    }
                    NumberInputField(title: "= desna stran", value: constant(row))
                }
            }
            solutionSection
        }
        .listStyle(.insetGrouped)
        .scrollDismissesKeyboard(.interactively)
    }

    private func resize() {
        coefficients = (0..<equations).map { r in
            (0..<unknowns).map { c in r < coefficients.count && c < coefficients[r].count ? coefficients[r][c] : 0 }
        }
        constants = (0..<equations).map { r in r < constants.count ? constants[r] : 0 }
    }

    /// Bindings that tolerate the update between a Stepper change and resize(), when the rows and
    /// columns already have the new count but the arrays the old one (as buildSystem() does).
    private func coefficient(_ r: Int, _ c: Int) -> Binding<Double?> {
        Binding(get: { r < coefficients.count && c < coefficients[r].count ? coefficients[r][c] : nil },
                set: { if r < coefficients.count && c < coefficients[r].count { coefficients[r][c] = $0 } })
    }

    private func constant(_ r: Int) -> Binding<Double?> {
        Binding(get: { r < constants.count ? constants[r] : nil },
                set: { if r < constants.count { constants[r] = $0 } })
    }

    @ViewBuilder
    private var solutionSection: some View {
        if let system = buildSystem() {
            Section("Rešitev") {
                switch Result(catching: { () throws(MathError) -> LinearSystemSolver.Solution in try LinearSystemSolver.solve(coefficients: system.a, constants: system.b) }) {
                case .success(.unique(let x)):
                    ForEach(0..<x.rows, id: \.self) { i in
                        ResultRow(title: Self.names[i], value: x[i, 0], exact: x.exactEntry(i, 0).flatMap { $0.isInteger ? nil : Expr.number($0) })
                    }
                    if system.a.isSquare, let det = try? system.a.determinant() {
                        ResultRow(title: "Determinanta sistema D", value: det.value, exact: det.exact.flatMap { $0.isInteger ? nil : Expr.number($0) })
                    }
                case .success(.none):
                    Text("Sistem je protisloven – nima rešitve.").foregroundStyle(.secondary)
                case .success(.infinite(let reduced, let pivots, let free)):
                    Text(Self.infiniteSolutionsTitle(freeUnknowns: free.count))
                    ForEach(Array(pivots.enumerated()), id: \.offset) { row, column in
                        Text(parametric(reduced: reduced, row: row, column: column, free: free))
                            .font(.body.monospacedDigit())
                    }
                    ForEach(free, id: \.self) { column in
                        Text("\(Self.names[column]) = t\(subscriptDigits(column + 1)) ∈ ℝ").foregroundStyle(.secondary)
                    }
                case .failure(let error):
                    Text(error.errorDescription ?? error.shortDescription).foregroundStyle(.red)
                }
            }
        }
    }

    private func buildSystem() -> (a: Matrix, b: Matrix)? {
        var values: [Double] = []
        var exact: [Rational] = []
        for r in 0..<equations {
            for c in 0..<unknowns {
                guard r < coefficients.count, c < coefficients[r].count, let v = coefficients[r][c] else { return nil }
                values.append(v)
                if let q = Rational.approximating(v, maxDenominator: 100_000, tolerance: 1e-13) { exact.append(q) }
            }
        }
        var rhs: [Double] = []
        var rhsExact: [Rational] = []
        for r in 0..<equations {
            guard r < constants.count, let v = constants[r] else { return nil }
            rhs.append(v)
            if let q = Rational.approximating(v, maxDenominator: 100_000, tolerance: 1e-13) { rhsExact.append(q) }
        }
        let a = Matrix(rows: equations, columns: unknowns, values: values, exact: exact.count == values.count ? exact : nil)
        let b = Matrix(rows: equations, columns: 1, values: rhs, exact: rhsExact.count == rhs.count ? rhsExact : nil)
        return (a, b)
    }

    private func parametric(reduced: Matrix, row: Int, column: Int, free: [Int]) -> String {
        var text = "\(Self.names[column]) = \(format(reduced[row, unknowns]))"
        for f in free {
            let coefficient = -reduced[row, f]
            guard Swift.abs(coefficient) > 1e-12 else { continue }
            text += (coefficient < 0 ? " − " : " + ") + "\(format(Swift.abs(coefficient)))·t\(subscriptDigits(f + 1))"
        }
        return text
    }

    private func format(_ x: Double) -> String {
        if let q = Rational.approximating(x, maxDenominator: 10_000, tolerance: 1e-11), !q.isInteger {
            return "\(q.numerator)/\(q.denominator)"
        }
        return NumberFormatting.format(NumericCalculus.clean(x), options: settings.numberFormat).plainTextLocalized
    }

    private func subscriptDigits(_ n: Int) -> String {
        let map: [Character: Character] = ["0": "₀", "1": "₁", "2": "₂", "3": "₃", "4": "₄", "5": "₅", "6": "₆", "7": "₇", "8": "₈", "9": "₉"]
        return String(String(n).map { map[$0] ?? $0 })
    }
}

// MARK: Complex numbers

/// Forms of a complex number, its n-th roots and the Argand diagram.
struct ComplexNumberToolView: View {
    @AppStorage("complexToolText") private var text = "1 + i·sqrt(3)"
    @State private var rootDegree = 3
    @Environment(AppSettings.self) private var settings

    private var value: Result<Complex, MathError> {
        Result { () throws(MathError) -> Complex in
            let expr = try Parser.parse(text)
            let program = try BytecodeCompiler(slots: [:], complexMode: true).compile(expr)
            let z = ComplexVM(program: program, requiresRealArguments: true).evaluate(z: .zero)
            guard z.isFinite else { throw .domain("vrednost ni definirana") }
            return Complex(NumericCalculus.clean(z.re), NumericCalculus.clean(z.im))
        }
    }

    private struct Plotted: Identifiable {
        var label: String
        var z: Complex
        var id: String { label }
    }

    var body: some View {
        List {
            Section {
                TextField("z =", text: $text)
                    .font(.system(.title3, design: .monospaced))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            } header: {
                Text("Kompleksno število z")
            } footer: {
                Text("Vnesi npr. 3 − 4i, (1 + i)^5 ali 2e^(iπ/3).")
            }
            switch value {
            case .success(let z):
                Section("Oblike") {
                    LabeledContent("Algebrska z = a + bi", value: ComplexFormatting.text(unit: settings.imaginaryUnit, z, options: settings.numberFormat))
                    ResultRow(title: "Re z = a", value: z.re)
                    ResultRow(title: "Im z = b", value: z.im)
                    ResultRow(title: "|z| = r", value: z.magnitude)
                    AngleRow(title: "arg z = φ", radians: z.argument)
                    LabeledContent("Polarna", value: "\(format(z.magnitude)) (cos \(format(z.argument)) + i sin \(format(z.argument)))")
                    LabeledContent("Eksponentna", value: "\(format(z.magnitude)) · e^(i·\(format(z.argument)))")
                    LabeledContent("Konjugirano z̄", value: ComplexFormatting.text(unit: settings.imaginaryUnit, z.conjugate, options: settings.numberFormat))
                    if z.squaredMagnitude > 0 {
                        LabeledContent("1/z", value: ComplexFormatting.text(unit: settings.imaginaryUnit, Complex.one / z, options: settings.numberFormat))
                    }
                }
                Section("Koreni ⁿ√z") {
                    Stepper("n = \(rootDegree)", value: $rootDegree, in: 2...12)
                    ForEach(Array(roots(of: z).enumerated()), id: \.offset) { k, root in
                        LabeledContent("z\(k)", value: ComplexFormatting.text(unit: settings.imaginaryUnit, root, options: settings.numberFormat))
                    }
                }
                Section("Gaussova ravnina") {
                    let points = [Plotted(label: "z", z: z), Plotted(label: "z̄", z: z.conjugate)]
                        + roots(of: z).enumerated().map { Plotted(label: "w\($0.offset)", z: $0.element) }
                    Chart {
                        ForEach(points) { p in
                            PointMark(x: .value("Re", p.z.re), y: .value("Im", p.z.im))
                                .foregroundStyle(p.label == "z" ? Color.accentColor : (p.label == "z̄" ? Color.orange : Color.green))
                                .annotation(position: .top) { Text(p.label).font(.caption2) }
                        }
                        RuleMark(x: .value("Re", 0)).foregroundStyle(.secondary.opacity(0.5))
                        RuleMark(y: .value("Im", 0)).foregroundStyle(.secondary.opacity(0.5))
                    }
                    .chartXAxisLabel("Re")
                    .chartYAxisLabel("Im")
                    .frame(height: 260)
                }
            case .failure(let error):
                Section { Text(error.errorDescription ?? error.shortDescription).foregroundStyle(.red) }
            }
        }
        .listStyle(.insetGrouped)
        .scrollDismissesKeyboard(.interactively)
    }

    private func roots(of z: Complex) -> [Complex] {
        let n = Double(rootDegree)
        let r = Foundation.pow(z.magnitude, 1 / n)
        return (0..<rootDegree).map { k in
            let angle = (z.argument + 2 * .pi * Double(k)) / n
            return Complex(NumericCalculus.clean(r * Foundation.cos(angle)), NumericCalculus.clean(r * Foundation.sin(angle)))
        }
    }

    private func format(_ x: Double) -> String {
        NumberFormatting.format(NumericCalculus.clean(x), options: NumberFormatOptions(mode: .norm1, significantDigits: 6, decimalSeparator: settings.decimalSeparator)).plainTextLocalized
    }
}

// MARK: Sequences and series

struct SequenceToolView: View {
    @AppStorage("sequenceGeometric") private var geometric = false
    @State private var first: Double? = 2
    @State private var step: Double? = 3
    @State private var n: Double? = 10
    @Environment(AppSettings.self) private var settings

    private struct Term: Identifiable {
        var n: Int
        var value: Double
        var id: Int { n }
    }

    var body: some View {
        List {
            Section {
                Picker("Zaporedje", selection: $geometric) {
                    Text("Aritmetično").tag(false)
                    Text("Geometrijsko").tag(true)
                }
                .pickerStyle(.segmented)
                NumberInputField(title: "a₁", value: $first)
                NumberInputField(title: geometric ? "q (kvocient)" : "d (diferenca)", value: $step)
                NumberInputField(title: "n", value: $n)
            } footer: {
                Text(geometric ? "aₙ = a₁·qⁿ⁻¹,  sₙ = a₁(qⁿ − 1)/(q − 1),  s = a₁/(1 − q) za |q| < 1"
                               : "aₙ = a₁ + (n − 1)d,  sₙ = n/2 · (2a₁ + (n − 1)d)")
            }
            if let first, let step, let n, let count = RealEvaluator.exactInt(n), count >= 1, count <= 100_000 {
                let terms = (1...min(count, 60)).map { Term(n: $0, value: term($0, first, step)) }
                Section("Rezultati") {
                    ResultRow(title: "aₙ", value: term(count, first, step))
                    ResultRow(title: "sₙ", value: sum(count, first, step))
                    if geometric {
                        if let s = GeometricSequence(first: first, ratio: step).infiniteSum {
                            ResultRow(title: "Vsota neskončne vrste s", value: s)
                        } else {
                            LabeledContent("Neskončna vrsta", value: "divergira (|q| ≥ 1)")
                        }
                    }
                    LabeledContent("Prvi členi", value: terms.prefix(8).map { format($0.value) }.joined(separator: "; ") + (count > 8 ? "; …" : ""))
                }
                Section("Graf členov") {
                    Chart(terms) { t in
                        PointMark(x: .value("n", t.n), y: .value("aₙ", t.value))
                            .foregroundStyle(Color.accentColor)
                    }
                    .frame(height: 200)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollDismissesKeyboard(.interactively)
    }

    private func term(_ k: Int, _ a: Double, _ s: Double) -> Double {
        geometric ? GeometricSequence(first: a, ratio: s).term(k) : ArithmeticSequence(first: a, difference: s).term(k)
    }

    private func sum(_ k: Int, _ a: Double, _ s: Double) -> Double {
        geometric ? GeometricSequence(first: a, ratio: s).sum(k) : ArithmeticSequence(first: a, difference: s).sum(k)
    }

    private func format(_ x: Double) -> String {
        NumberFormatting.format(NumericCalculus.clean(x), options: NumberFormatOptions(mode: .norm1, significantDigits: 6, decimalSeparator: settings.decimalSeparator)).plainTextLocalized
    }
}

// MARK: Interest

struct FinanceToolView: View {
    enum Page: String, CaseIterable, Identifiable {
        case compound, simple, savings, loan
        var id: String { rawValue }
        var title: String {
            switch self {
            case .compound: "Obrestno"
            case .simple: "Navadno"
            case .savings: "Varčevanje"
            case .loan: "Posojilo"
            }
        }
    }

    @AppStorage("financePage") private var page: Page = .compound
    @State private var principal: Double? = 1000
    @State private var rate: Double? = 3
    @State private var years: Double? = 10
    @State private var periodsPerYear = 1
    @State private var target: Double? = 2000
    @State private var deposit: Double? = 100
    @State private var atStart = false
    @State private var annualRate: Double? = 6
    @State private var ratePeriods = 12

    var body: some View {
        List {
            Section {
                Picker("Račun", selection: $page) {
                    ForEach(Page.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            switch page {
            case .compound:
                Section {
                    NumberInputField(title: "Glavnica G₀ (€)", value: $principal)
                    NumberInputField(title: "Obrestna mera p (%)", value: $rate)
                    NumberInputField(title: "Čas n (let)", value: $years)
                    Picker("Pripis obresti", selection: $periodsPerYear) {
                        Text("letno").tag(1)
                        Text("polletno").tag(2)
                        Text("četrtletno").tag(4)
                        Text("mesečno").tag(12)
                        Text("zvezno").tag(0)
                    }
                } footer: {
                    Text("Gₙ = G₀(1 + p/100)ⁿ; pri m pripisih na leto Gₙ = G₀(1 + p/(100m))^(mn); zvezno Gₙ = G₀e^(pn/100).")
                }
                if let principal, let rate, let years {
                    let final = Finance.compound(principal: principal, ratePercent: rate, years: years, periodsPerYear: periodsPerYear == 0 ? nil : periodsPerYear)
                    Section("Rezultat") {
                        ResultRow(title: "Končna vrednost Gₙ", value: final, unit: "€")
                        ResultRow(title: "Obresti", value: final - principal, unit: "€")
                    }
                    Section("Čas do cilja") {
                        NumberInputField(title: "Ciljna vrednost G (€)", value: $target)
                        if let target, let n = Finance.yearsToReach(target: target, principal: principal, ratePercent: rate) {
                            ResultRow(title: "Potrebna leta (letni pripis)", value: n)
                        }
                    }
                }
            case .simple:
                Section {
                    NumberInputField(title: "Glavnica G₀ (€)", value: $principal)
                    NumberInputField(title: "Obrestna mera p (%)", value: $rate)
                    NumberInputField(title: "Čas t (let)", value: $years)
                } footer: {
                    Text("o = G₀ · p · t / 100")
                }
                if let principal, let rate, let years {
                    let interest = Finance.simpleInterest(principal: principal, ratePercent: rate, years: years)
                    Section("Rezultat") {
                        ResultRow(title: "Obresti o", value: interest, unit: "€")
                        ResultRow(title: "Končna vrednost", value: principal + interest, unit: "€")
                    }
                }
            case .savings:
                Section {
                    NumberInputField(title: "Vloga na obdobje a (€)", value: $deposit)
                    NumberInputField(title: "Obrestna mera na obdobje p (%)", value: $rate)
                    NumberInputField(title: "Število vlog n", value: $years)
                    Toggle("Vloge na začetku obdobja (prenumerando)", isOn: $atStart)
                } footer: {
                    Text("S = a·r·(rⁿ − 1)/(r − 1) prenumerando ali a·(rⁿ − 1)/(r − 1) postnumerando, r = 1 + p/100.")
                }
                if let deposit, let rate, let years, let n = RealEvaluator.exactInt(years), n > 0 {
                    let total = Finance.savings(deposit: deposit, ratePercent: rate, periods: n, atStart: atStart)
                    Section("Rezultat") {
                        ResultRow(title: "Privarčevano", value: total, unit: "€")
                        ResultRow(title: "Vplačano", value: deposit * Double(n), unit: "€")
                        ResultRow(title: "Obresti", value: total - deposit * Double(n), unit: "€")
                    }
                }
            case .loan:
                Section {
                    NumberInputField(title: "Posojilo G (€)", value: $principal)
                    NumberInputField(title: "Obrestna mera na obdobje p (%)", value: $rate)
                    NumberInputField(title: "Število obrokov n", value: $years)
                } footer: {
                    Text("Anuiteta a = G·rⁿ(r − 1)/(rⁿ − 1), r = 1 + p/100.")
                }
                if let principal, let rate, let years, let n = RealEvaluator.exactInt(years), n > 0 {
                    let payment = Finance.loanPayment(principal: principal, ratePercent: rate, periods: n)
                    Section("Rezultat") {
                        ResultRow(title: "Obrok a", value: payment, unit: "€")
                        ResultRow(title: "Skupaj plačano", value: payment * Double(n), unit: "€")
                        ResultRow(title: "Obresti skupaj", value: payment * Double(n) - principal, unit: "€")
                    }
                    if n <= 600 {
                        AmortizationPlanSection(rows: Finance.amortizationPlan(principal: principal, ratePercent: rate, periods: n))
                    }
                }
            }
            if page != .simple {
                Section {
                    NumberInputField(title: "Letna obrestna mera p (%)", value: $annualRate)
                    Picker("Obdobij na leto m", selection: $ratePeriods) {
                        Text("2").tag(2)
                        Text("4").tag(4)
                        Text("12").tag(12)
                    }
                    if let annualRate {
                        ResultRow(title: "Konformna mera na obdobje", value: Finance.periodRate(annualPercent: annualRate, periodsPerYear: ratePeriods, conformal: true), unit: "%")
                        ResultRow(title: "Relativna mera na obdobje", value: Finance.periodRate(annualPercent: annualRate, periodsPerYear: ratePeriods, conformal: false), unit: "%")
                    }
                } header: {
                    Text("Obrestna mera na obdobje")
                } footer: {
                    Text("Konformna: (1 + p/100)^(1/m) − 1 – enaka letna rast. Relativna: p/m.")
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollDismissesKeyboard(.interactively)
    }
}

/// Amortizacijski načrt: payment, interest, repayment and remaining debt for every period.
struct AmortizationPlanSection: View {
    let rows: [Finance.AmortizationRow]
    @Environment(AppSettings.self) private var settings

    var body: some View {
        Section {
            HStack {
                Text("k").frame(width: 30, alignment: .leading)
                Text("Obrok").frame(maxWidth: .infinity, alignment: .trailing)
                Text("Obresti").frame(maxWidth: .infinity, alignment: .trailing)
                Text("Razdolžnina").frame(maxWidth: .infinity, alignment: .trailing)
                Text("Ostanek").frame(maxWidth: .infinity, alignment: .trailing)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            ForEach(rows) { row in
                HStack {
                    Text("\(row.period)").frame(width: 30, alignment: .leading)
                    amount(row.payment)
                    amount(row.interest)
                    amount(row.repayment)
                    amount(row.remaining)
                }
                .font(.caption.monospacedDigit())
            }
        } header: {
            Text("Amortizacijski načrt")
        } footer: {
            Text("Obresti se računajo od ostanka dolga; razdolžnina = obrok − obresti.")
        }
    }

    private func amount(_ value: Double) -> some View {
        Text(NumberFormatting.format(value, options: NumberFormatOptions(mode: .fix, places: 2, decimalSeparator: settings.decimalSeparator)).plainText)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
    }
}
