import AcuteCore
import Charts
import SwiftUI

/// Binomial, Poisson, normal, t, χ² and F distributions (with charts), confidence intervals,
/// hypothesis tests and combinatorics.
struct ProbabilityToolView: View {
    enum Page: String, CaseIterable, Identifiable {
        case binomial, normal, poisson, student, chiSquare, fisher, intervals, tests, combinatorics
        var id: String { rawValue }
        var title: String {
            switch self {
            case .binomial: "Binomska"
            case .normal: "Normalna"
            case .poisson: "Poissonova"
            case .student: "Studentova t"
            case .chiSquare: "χ²"
            case .fisher: "Fisherjeva F"
            case .intervals: "Intervali zaupanja"
            case .tests: "Preizkusi domnev"
            case .combinatorics: "Kombinatorika"
            }
        }
    }

    @AppStorage("probabilityPage") private var page: Page = .binomial

    var body: some View {
        List {
            Section {
                Picker("Porazdelitev", selection: $page) {
                    ForEach(Page.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.menu)
            }
            switch page {
            case .binomial: BinomialSection()
            case .normal: NormalSection()
            case .poisson: PoissonSection()
            case .student: SamplingDistributionSection(kind: .student)
            case .chiSquare: SamplingDistributionSection(kind: .chiSquare)
            case .fisher: SamplingDistributionSection(kind: .fisher)
            case .intervals: ConfidenceIntervalSection()
            case .tests: HypothesisTestSection()
            case .combinatorics: CombinatoricsSection()
            }
        }
        .listStyle(.insetGrouped)
        .scrollDismissesKeyboard(.interactively)
    }
}

private struct ProbabilityBar: Identifiable {
    var k: Int
    var p: Double
    var highlighted: Bool
    var id: Int { k }
}

/// X ~ B(n, p)
private struct BinomialSection: View {
    @State private var n: Double? = 10
    @State private var p: Double? = 0.3
    @State private var k: Double? = 3

    var body: some View {
        Section {
            NumberInputField(title: "n (število poskusov)", value: $n)
            NumberInputField(title: "p (verjetnost uspeha)", value: $p)
            NumberInputField(title: "k", value: $k)
        } header: {
            Text("X ~ B(n, p)")
        } footer: {
            Text("P(X = k) = C(n, k) · pᵏ · (1 − p)ⁿ⁻ᵏ")
        }
        if let n, let p, let k, let pmf = try? Distributions.binomialPMF(n: n, p: p, k: k),
           let cdf = try? Distributions.binomialCDF(n: n, p: p, k: k) {
            let below = (try? Distributions.binomialCDF(n: n, p: p, k: k - 1)) ?? 0
            Section("Verjetnosti") {
                ResultRow(title: "P(X = k)", value: pmf, keepsSmallValues: true)
                ResultRow(title: "P(X ≤ k)", value: cdf, keepsSmallValues: true)
                ResultRow(title: "P(X < k)", value: below, keepsSmallValues: true)
                ResultRow(title: "P(X ≥ k)", value: 1 - below)
                ResultRow(title: "P(X > k)", value: 1 - cdf)
            }
            Section("Pričakovana vrednost in razpršenost") {
                ResultRow(title: "E(X) = np", value: Distributions.binomialMean(n: n, p: p))
                ResultRow(title: "D(X) = np(1 − p)", value: Distributions.binomialVariance(n: n, p: p))
                ResultRow(title: "σ(X)", value: Distributions.binomialVariance(n: n, p: p).squareRoot())
            }
            if n <= 200 {
                Section("Porazdelitev") {
                    Chart(bars(n: Int(n), p: p, k: Int(k))) { bar in
                        BarMark(x: .value("k", bar.k), y: .value("P", bar.p))
                            .foregroundStyle(bar.highlighted ? Color.accentColor : Color.secondary.opacity(0.5))
                    }
                    .frame(height: 200)
                }
            }
        } else {
            Section { Text("Vnesi celo število n ≥ 0, 0 ≤ p ≤ 1 in celo število k.").foregroundStyle(.secondary) }
        }
    }

    private func bars(n: Int, p: Double, k: Int) -> [ProbabilityBar] {
        (0...max(0, n)).map { i in
            ProbabilityBar(k: i, p: (try? Distributions.binomialPMF(n: Double(n), p: p, k: Double(i))) ?? 0, highlighted: i <= k)
        }
    }
}

/// X ~ N(μ, σ)
private struct NormalSection: View {
    @State private var mean: Double? = 0
    @State private var sigma: Double? = 1
    @State private var a: Double? = -1
    @State private var b: Double? = 1
    @State private var probability: Double? = 0.95

    private struct Point: Identifiable {
        var x: Double
        var y: Double
        var inside: Bool
        var id: Double { x }
    }

    var body: some View {
        Section {
            NumberInputField(title: "μ", value: $mean)
            NumberInputField(title: "σ", value: $sigma)
        } header: {
            Text("X ~ N(μ, σ)")
        }
        Section("Verjetnost na intervalu") {
            NumberInputField(title: "a", value: $a, prompt: "−∞")
            NumberInputField(title: "b", value: $b, prompt: "∞")
            if let mean, let sigma, sigma > 0 {
                let low = a ?? -.infinity, high = b ?? .infinity
                ResultRow(title: "P(a ≤ X ≤ b)", value: (try? Distributions.normalProbability(from: low, to: high, mean: mean, standardDeviation: sigma)),
                          keepsSmallValues: true)
                if let a {
                    ResultRow(title: "z = (a − μ)/σ", value: (a - mean) / sigma)
                }
                Chart(curve(mean: mean, sigma: sigma, low: low, high: high)) { point in
                    AreaMark(x: .value("x", point.x), y: .value("φ", point.inside ? point.y : 0))
                        .foregroundStyle(Color.accentColor.opacity(0.35))
                    LineMark(x: .value("x", point.x), y: .value("φ", point.y))
                        .foregroundStyle(Color.accentColor)
                }
                .frame(height: 200)
            }
        }
        Section {
            NumberInputField(title: "p", value: $probability)
            if let mean, let sigma, let probability, let x = try? Distributions.inverseNormal(probability, mean: mean, standardDeviation: sigma) {
                ResultRow(title: "x, da je P(X ≤ x) = p", value: x)
                let half = (1 - probability) / 2
                if probability > 0, probability < 1, let z = try? Distributions.inverseNormal(1 - half) {
                    ResultRow(title: "Simetrični interval μ ± zσ, z", value: z)
                }
            }
        } header: {
            Text("Obratna porazdelitev")
        } footer: {
            Text("Φ(z) ima pri p = 0,975 vrednost z ≈ 1,96 (95-odstotni interval).")
        }
        Section("Sharp P(t), Q(t), R(t)") {
            if let a, let mean, let sigma, sigma > 0 {
                let t = (a - mean) / sigma
                ResultRow(title: "t = (a − μ)/σ", value: t)
                ResultRow(title: "P(t) = Φ(t)", value: Distributions.sharpP(t))
                ResultRow(title: "Q(t)", value: Distributions.sharpQ(t))
                ResultRow(title: "R(t) = 1 − Φ(t)", value: Distributions.sharpR(t))
            }
        }
    }

    private func curve(mean: Double, sigma: Double, low: Double, high: Double) -> [Point] {
        (0...240).map { i in
            let x = mean - 4 * sigma + 8 * sigma * Double(i) / 240
            let y = (try? Distributions.normalPDF(x, mean: mean, standardDeviation: sigma)) ?? 0
            return Point(x: x, y: y, inside: x >= low && x <= high)
        }
    }
}

/// X ~ Po(λ)
private struct PoissonSection: View {
    @State private var lambda: Double? = 2
    @State private var k: Double? = 1

    var body: some View {
        Section {
            NumberInputField(title: "λ", value: $lambda)
            NumberInputField(title: "k", value: $k)
        } header: {
            Text("X ~ Po(λ)")
        } footer: {
            Text("P(X = k) = λᵏ e^(−λ) / k!")
        }
        if let lambda, let k, let pmf = try? Distributions.poissonPMF(lambda: lambda, k: k),
           let cdf = try? Distributions.poissonCDF(lambda: lambda, k: k) {
            Section("Verjetnosti") {
                ResultRow(title: "P(X = k)", value: pmf, keepsSmallValues: true)
                ResultRow(title: "P(X ≤ k)", value: cdf, keepsSmallValues: true)
                ResultRow(title: "P(X > k)", value: 1 - cdf)
                ResultRow(title: "E(X) = D(X) = λ", value: lambda)
            }
            Section("Porazdelitev") {
                let top = Int(max(10, lambda + 4 * lambda.squareRoot()))
                Chart((0...top).map { i in ProbabilityBar(k: i, p: (try? Distributions.poissonPMF(lambda: lambda, k: Double(i))) ?? 0, highlighted: Double(i) <= k) }) { bar in
                    BarMark(x: .value("k", bar.k), y: .value("P", bar.p))
                        .foregroundStyle(bar.highlighted ? Color.accentColor : Color.secondary.opacity(0.5))
                }
                .frame(height: 200)
            }
        }
    }
}

/// Student t, χ² and Fisher F: density, P(X ≤ x), P(X > x), quantiles and the density curve.
private struct SamplingDistributionSection: View {
    enum Kind { case student, chiSquare, fisher }
    let kind: Kind
    @State private var first: Double? = 10
    @State private var second: Double? = 12
    @State private var x: Double? = 2
    @State private var p: Double? = 0.95

    private struct Point: Identifiable {
        var x: Double
        var y: Double
        var below: Bool
        var id: Double { x }
    }

    var body: some View {
        Section {
            NumberInputField(title: kind == .fisher ? "d₁" : kind == .student ? "ν (prostostne stopnje)" : "k (prostostne stopnje)", value: $first)
            if kind == .fisher { NumberInputField(title: "d₂", value: $second) }
            NumberInputField(title: "x", value: $x)
        } header: {
            Text(kind == .student ? "T ~ t(ν)" : kind == .chiSquare ? "X ~ χ²(k)" : "X ~ F(d₁, d₂)")
        } footer: {
            Text(kind == .student ? "V računalu: tpdf(x; ν), tcdf(x; ν), invT(p; ν)."
                 : kind == .chiSquare ? "V računalu: χ²pdf(x; k), χ²cdf(x; k), invχ²(p; k) (chi2pdf …)."
                 : "V računalu: fpdf(x; d₁; d₂), fcdf(x; d₁; d₂), invF(p; d₁; d₂).")
        }
        if valid, let x, let below = cdf(x) {
            Section("Verjetnosti") {
                ResultRow(title: "Gostota f(x)", value: pdf(x), keepsSmallValues: true)
                ResultRow(title: "P(X ≤ x)", value: below, keepsSmallValues: true)
                ResultRow(title: "P(X > x)", value: above(x), keepsSmallValues: true)
                if kind == .student, let tail = above(Swift.abs(x)) {
                    ResultRow(title: "P(|T| ≥ |x|)", value: 2 * tail, keepsSmallValues: true)
                }
                Chart(curve(x)) { point in
                    AreaMark(x: .value("x", point.x), y: .value("f", point.below ? point.y : 0))
                        .foregroundStyle(Color.accentColor.opacity(0.35))
                    LineMark(x: .value("x", point.x), y: .value("f", point.y))
                        .foregroundStyle(Color.accentColor)
                }
                .frame(height: 200)
            }
        }
        Section {
            NumberInputField(title: "p", value: $p)
            if valid, let p {
                ResultRow(title: "x, da je P(X ≤ x) = p", value: quantile(p))
                if kind == .student {
                    ResultRow(title: "Dvostranska meja t(1 − α/2), α = 1 − p", value: quantile((1 + p) / 2))
                }
            }
        } header: {
            Text("Kvantil")
        }
    }

    private var valid: Bool {
        guard let first, first > 0 else { return false }
        return kind != .fisher || (second ?? 0) > 0
    }

    private func pdf(_ x: Double) -> Double? {
        guard let first else { return nil }
        switch kind {
        case .student: return try? Distributions.studentPDF(x, degrees: first)
        case .chiSquare: return try? Distributions.chiSquarePDF(x, degrees: first)
        case .fisher: return second.flatMap { try? Distributions.fisherPDF(x, first, $0) }
        }
    }

    private func cdf(_ x: Double) -> Double? {
        guard let first else { return nil }
        switch kind {
        case .student: return try? Distributions.studentCDF(x, degrees: first)
        case .chiSquare: return try? Distributions.chiSquareCDF(x, degrees: first)
        case .fisher: return second.flatMap { try? Distributions.fisherCDF(x, first, $0) }
        }
    }

    /// P(X > x) from the tail itself, so tiny probabilities are not rounded to 0.
    private func above(_ x: Double) -> Double? {
        guard let first else { return nil }
        switch kind {
        case .student: return try? Distributions.studentUpperTail(x, degrees: first)
        case .chiSquare: return try? Distributions.chiSquareUpperTail(x, degrees: first)
        case .fisher: return second.flatMap { try? Distributions.fisherUpperTail(x, first, $0) }
        }
    }

    private func quantile(_ p: Double) -> Double? {
        guard let first else { return nil }
        switch kind {
        case .student: return try? Distributions.inverseStudent(p, degrees: first)
        case .chiSquare: return try? Distributions.inverseChiSquare(p, degrees: first)
        case .fisher: return second.flatMap { try? Distributions.inverseFisher(p, first, $0) }
        }
    }

    private func curve(_ x: Double) -> [Point] {
        let low = kind == .student ? (quantile(0.001) ?? -5) : 0
        let high = Swift.max(quantile(kind == .student ? 0.999 : 0.995) ?? 5, Swift.min(x, 1e6))
        return (1...240).compactMap { i in
            let t = low + (high - low) * Double(i) / 240
            guard let y = pdf(t), y.isFinite else { return nil }
            return Point(x: t, y: y, below: t <= x)
        }
    }
}

/// Confidence intervals for μ (t or z), σ², σ and a proportion.
private struct ConfidenceIntervalSection: View {
    @State private var mean: Double? = 12.4
    @State private var deviation: Double? = 1.8
    @State private var count: Double? = 25
    @State private var confidence: Double? = 0.95
    @State private var knownSigma = false
    @State private var proportion: Double?

    var body: some View {
        Section {
            NumberInputField(title: "x̄ (povprečje vzorca)", value: $mean)
            NumberInputField(title: knownSigma ? "σ (znan)" : "s (standardni odklon vzorca)", value: $deviation)
            NumberInputField(title: "n", value: $count)
            NumberInputField(title: "Stopnja zaupanja 1 − α", value: $confidence)
            Toggle("σ populacije je znan", isOn: $knownSigma)
        } header: {
            Text("Podatki vzorca")
        } footer: {
            Text(knownSigma ? "μ: x̄ ± z·σ/√n" : "μ: x̄ ± t(1 − α/2; n − 1)·s/√n; σ²: (n − 1)s²/χ²")
        }
        if let mean, let deviation, let count, let confidence {
            Section("Intervali") {
                intervalRow("μ", meanInterval(mean, deviation, count, confidence))
                if !knownSigma, let variance = try? Inference.varianceInterval(standardDeviation: deviation, count: count, confidence: confidence) {
                    intervalRow("σ²", variance)
                    intervalRow("σ", Inference.Interval(lower: variance.lower.squareRoot(), upper: variance.upper.squareRoot()))
                }
            }
        }
        Section {
            NumberInputField(title: "p̂ (delež v vzorcu)", value: $proportion, prompt: "neobvezno")
            if let proportion, let count, let confidence {
                intervalRow("p (Wald)", try? Inference.proportionInterval(proportion: proportion, count: count, confidence: confidence))
                intervalRow("p (Wilson)", try? Inference.proportionWilsonInterval(proportion: proportion, count: count, confidence: confidence))
            }
        } header: {
            Text("Delež")
        } footer: {
            Text("Wald: p̂ ± z·√(p̂(1 − p̂)/n), normalni približek za velike n. Wilsonov interval velja tudi za majhne n in p̂ = 0 ali 1.")
        }
    }

    private func meanInterval(_ mean: Double, _ deviation: Double, _ count: Double, _ confidence: Double) -> Inference.Interval? {
        if knownSigma {
            return try? Inference.meanIntervalKnownSigma(mean: mean, sigma: deviation, count: count, confidence: confidence)
        }
        return try? Inference.meanInterval(mean: mean, standardDeviation: deviation, count: count, confidence: confidence)
    }

    @ViewBuilder
    private func intervalRow(_ name: String, _ interval: Inference.Interval?) -> some View {
        if let interval {
            IntervalRow(name: name, interval: interval)
        }
    }
}

private struct IntervalRow: View {
    let name: String
    let interval: Inference.Interval
    @Environment(AppSettings.self) private var settings

    var body: some View {
        LabeledContent(name) {
            Text("[" + format(interval.lower) + "; " + format(interval.upper) + "]")
                .font(.body.monospacedDigit())
        }
    }

    private func format(_ x: Double) -> String {
        NumberFormatting.format(NumericCalculus.clean(x), options: settings.numberFormat).plainTextLocalized
    }
}

/// t-test for μ, χ² goodness of fit, one-way analysis of variance, χ² independence in a
/// contingency table and the test of a correlation coefficient.
private struct HypothesisTestSection: View {
    enum Kind: String, CaseIterable, Identifiable {
        case t, chiSquare, anova, independence, correlation
        var id: String { rawValue }
        var title: String {
            switch self {
            case .t: "t-test za μ"
            case .chiSquare: "χ² prileganje"
            case .anova: "ANOVA"
            case .independence: "χ² neodvisnost"
            case .correlation: "Test korelacije"
            }
        }
    }

    @State private var kind: Kind = .t
    @State private var alpha: Double? = 0.05
    @State private var mean: Double? = 12.4
    @State private var deviation: Double? = 1.8
    @State private var count: Double? = 25
    @State private var hypothesis: Double? = 12
    @AppStorage("chiObserved") private var observedText = "18; 22; 30; 30"
    @AppStorage("chiExpected") private var expectedText = "0,25; 0,25; 0,25; 0,25"
    @AppStorage("anovaGroups") private var groupsText = "5,1 4,9 5,6 5,0\n5,8 6,1 5,9 6,3\n4,8 5,2 4,9 5,1"
    @AppStorage("contingencyTable") private var tableText = "10 20\n30 40"
    @State private var correlation: Double? = 0.5
    @State private var pairs: Double? = 27

    var body: some View {
        Section {
            Picker("Preizkus", selection: $kind) {
                ForEach(Kind.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.menu)
            NumberInputField(title: "Stopnja značilnosti α", value: $alpha)
        }
        switch kind {
        case .t:
            Section {
                NumberInputField(title: "x̄", value: $mean)
                NumberInputField(title: "s", value: $deviation)
                NumberInputField(title: "n", value: $count)
                NumberInputField(title: "μ₀ (ničelna domneva)", value: $hypothesis)
            } footer: {
                Text("H₀: μ = μ₀, H₁: μ ≠ μ₀; t = (x̄ − μ₀)/(s/√n), n − 1 prostostnih stopenj.")
            }
            if let mean, let deviation, let count, let hypothesis {
                result(try? Inference.tTest(mean: mean, standardDeviation: deviation, count: count, hypothesis: hypothesis), name: "t")
            }
        case .chiSquare:
            Section {
                LabeledContent("Opazovane") { TextField("18; 22; 30", text: $observedText).multilineTextAlignment(.trailing) }
                LabeledContent("Pričakovane") { TextField("0,25; 0,25 …", text: $expectedText).multilineTextAlignment(.trailing) }
            } footer: {
                Text("Vrednosti loči s podpičjem ali presledkom; pričakovane so frekvence ali verjetnosti. Prostostne stopnje: k − 1.")
            }
            if let observed = numbers(observedText), let expected = numbers(expectedText) {
                result(try? Inference.chiSquareGoodnessOfFit(observed: observed, expected: expected), name: "χ²")
            }
        case .anova:
            Section {
                TextField("Skupine po vrsticah", text: $groupsText, axis: .vertical)
                    .lineLimit(3...8)
                    .font(.body.monospacedDigit())
            } footer: {
                Text("Vsaka vrstica je ena skupina; vrednosti loči s presledkom ali podpičjem. F = MS med skupinami / MS znotraj skupin.")
            }
            let rows = groupsText.split(whereSeparator: \.isNewline).filter { !$0.allSatisfy(\.isWhitespace) }
            let groups = rows.compactMap { numbers(String($0)) }
            // A row with a typo must not silently drop out of the test.
            if groups.count >= 2, groups.count == rows.count {
                result(try? Inference.anova(groups), name: "F")
            } else {
                Section { Text("Vnesi vsaj dve vrstici samih števil.").foregroundStyle(.secondary) }
            }
        case .independence:
            Section {
                TextField("Tabela po vrsticah", text: $tableText, axis: .vertical)
                    .lineLimit(2...10)
                    .font(.body.monospacedDigit())
            } footer: {
                Text("Kontingenčna tabela opazovanih frekvenc: vrstice so vrednosti prve spremenljivke, stolpci druge. E = (vsota vrstice)·(vsota stolpca)/n, χ² = Σ (O − E)²/E z (r − 1)(c − 1) prostostnimi stopnjami.")
            }
            let rows = tableText.split(whereSeparator: \.isNewline).filter { !$0.allSatisfy(\.isWhitespace) }
            let table = rows.compactMap { numbers(String($0)) }
            if table.count == rows.count, let association = try? Inference.chiSquareIndependence(table) {
                result(association.test, name: "χ²")
                Section {
                    ResultRow(title: "Cramérjev V", value: association.cramer)
                    LabeledContent("Pričakovane frekvence E") {
                        MathText(expr: .matrix(rows: association.expected.count, columns: association.expected.first?.count ?? 0,
                                               entries: association.expected.flatMap { $0 }.map { Expr.decimal(NumericCalculus.clean($0)) }),
                                 fontSize: 15)
                    }
                } footer: {
                    Text("Približek s porazdelitvijo χ² je zanesljiv, ko so vse pričakovane frekvence vsaj 5.")
                }
            } else {
                Section { Text("Vnesi vsaj 2 × 2 nenegativnih frekvenc v enako dolgih vrsticah brez praznih vrstic ali stolpcev.").foregroundStyle(.secondary) }
            }
        case .correlation:
            Section {
                NumberInputField(title: "r (vzorčni korelacijski koeficient)", value: $correlation)
                NumberInputField(title: "n (število parov)", value: $pairs)
            } footer: {
                Text("H₀: ρ = 0, H₁: ρ ≠ 0; t = r·√(n − 2)/√(1 − r²) z n − 2 prostostnimi stopnjami.")
            }
            if let correlation, let pairs {
                result(try? Inference.correlationTest(r: correlation, count: pairs), name: "t")
            }
        }
    }

    @ViewBuilder
    private func result(_ test: Inference.Test?, name: String) -> some View {
        if let test {
            Section("Rezultat") {
                ResultRow(title: name, value: test.statistic)
                ResultRow(title: test.degrees.count == 1 ? "Prostostne stopnje" : "Prostostne stopnje d₁", value: test.degrees[0])
                if test.degrees.count > 1 { ResultRow(title: "d₂", value: test.degrees[1]) }
                ResultRow(title: "p-vrednost", value: test.pValue, keepsSmallValues: true)
                if let alpha, alpha > 0, alpha < 1 {
                    Label(test.pValue < alpha ? "H₀ zavrnemo (p < α)" : "H₀ ne zavrnemo (p ≥ α)",
                          systemImage: test.pValue < alpha ? "xmark.circle" : "checkmark.circle")
                        .foregroundStyle(test.pValue < alpha ? Color.orange : Color.green)
                } else if alpha != nil {
                    Text("Za odločitev mora biti α med 0 in 1.").foregroundStyle(.secondary)
                }
            }
        } else {
            Section { Text("Preveri podatke.").foregroundStyle(.secondary) }
        }
    }

    /// Numbers separated by semicolons or spaces (a decimal comma is allowed).
    private func numbers(_ text: String) -> [Double]? {
        let parts = text.split(whereSeparator: { $0 == ";" || $0 == " " || $0 == "\t" }).map(String.init)
        let values = parts.compactMap { ExpressionNumberField.parse($0) }
        return values.count == parts.count && !values.isEmpty ? values : nil
    }
}

/// n!, permutations, variations and combinations (with and without repetition).
private struct CombinatoricsSection: View {
    @State private var n: Double? = 5
    @State private var r: Double? = 3

    var body: some View {
        Section("Podatki") {
            NumberInputField(title: "n", value: $n)
            NumberInputField(title: "r (izbranih)", value: $r)
        }
        if let n, let r, let ni = RealEvaluator.exactInt(n), let ri = RealEvaluator.exactInt(r), ni >= 0, ri >= 0 {
            Section("Brez ponavljanja") {
                ResultRow(title: "Permutacije n!", value: try? RealEvaluator.factorial(n))
                ResultRow(title: "Variacije V(n, r) = n!/(n − r)!", value: try? RealEvaluator.combinatorics(.nPr, n, r))
                ResultRow(title: "Kombinacije C(n, r)", value: try? RealEvaluator.combinatorics(.nCr, n, r))
            }
            Section("S ponavljanjem") {
                ResultRow(title: "Variacije nʳ", value: Foundation.pow(n, r))
                ResultRow(title: "Kombinacije C(n + r − 1, r)", value: try? RealEvaluator.combinatorics(.nCr, Double(ni + ri - 1), r))
            }
        } else {
            Section { Text("n in r morata biti nenegativni celi števili.").foregroundStyle(.secondary) }
        }
    }
}
