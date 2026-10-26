import AcuteCore
import Charts
import SwiftUI

/// Binomial, Poisson and normal distributions (with charts) and combinatorics.
struct ProbabilityToolView: View {
    enum Page: String, CaseIterable, Identifiable {
        case binomial, normal, poisson, combinatorics
        var id: String { rawValue }
        var title: String {
            switch self {
            case .binomial: "Binomska"
            case .normal: "Normalna"
            case .poisson: "Poissonova"
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
                .pickerStyle(.segmented)
            }
            switch page {
            case .binomial: BinomialSection()
            case .normal: NormalSection()
            case .poisson: PoissonSection()
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
                ResultRow(title: "P(X = k)", value: pmf)
                ResultRow(title: "P(X ≤ k)", value: cdf)
                ResultRow(title: "P(X < k)", value: below)
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
                ResultRow(title: "P(a ≤ X ≤ b)", value: (try? Distributions.normalProbability(from: low, to: high, mean: mean, standardDeviation: sigma)))
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
                ResultRow(title: "P(X = k)", value: pmf)
                ResultRow(title: "P(X ≤ k)", value: cdf)
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
