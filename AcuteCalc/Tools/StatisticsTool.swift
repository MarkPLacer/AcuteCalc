import AcuteCore
import Charts
import SwiftUI
import UIKit

/// Sharp STAT mode: one-variable statistics, two-variable statistics and the seven regressions,
/// with a frequency chart, a box plot and a scatter plot with the fitted curve.
struct StatisticsToolView: View {
    @Environment(AppStore.self) private var store
    @Environment(AppSettings.self) private var settings
    @Environment(\.openInGraphs) private var openInGraphs
    @AppStorage("statisticsTwoVariable") private var twoVariable = false
    @AppStorage("statisticsModel") private var modelRaw = RegressionModel.linear.rawValue
    @AppStorage("statisticsXTransform") private var xTransformRaw = AxisTransform.none.rawValue
    @AppStorage("statisticsYTransform") private var yTransformRaw = AxisTransform.none.rawValue
    @AppStorage("statisticsCompare") private var compare = false
    @AppStorage("statisticsEqualVariances") private var equalVariances = false
    @State private var estimateX: Double?
    @State private var estimateY: Double?

    private var model: RegressionModel { RegressionModel(rawValue: modelRaw) ?? .linear }
    private var xTransform: AxisTransform { AxisTransform(rawValue: xTransformRaw) ?? .none }
    private var yTransform: AxisTransform { AxisTransform(rawValue: yTransformRaw) ?? .none }

    var body: some View {
        @Bindable var store = store
        List {
            Section {
                Picker("Podatki", selection: $twoVariable) {
                    Text("Ena spremenljivka (x)").tag(false)
                    Text("Dve spremenljivki (x, y)").tag(true)
                }
                .pickerStyle(.segmented)
            }
            dataSection($store.statisticsData, title: !twoVariable && compare ? "Vzorec A" : "Podatki")
            if twoVariable {
                regressionSections
            } else {
                Section {
                    Toggle("Primerjaj z drugim vzorcem B", isOn: $compare)
                } footer: {
                    Text("Npr. višine v dveh razredih: škatli z brki na skupni osi, primerjava srednjih vrednosti in razpršenosti, t-test in F-test.")
                }
                if compare {
                    dataSection($store.statisticsSecondData, title: "Vzorec B", second: true)
                    comparisonSections
                }
                oneVariableSections
            }
        }
        .listStyle(.insetGrouped)
        .scrollDismissesKeyboard(.interactively)
    }

    // MARK: Data entry

    private func dataSection(_ data: Binding<[DataPoint]>, title: String, second: Bool = false) -> some View {
        Section {
            HStack {
                Text("x").frame(maxWidth: .infinity, alignment: .leading)
                if twoVariable { Text("y").frame(maxWidth: .infinity, alignment: .leading) }
                Text("frekvenca f").frame(maxWidth: .infinity, alignment: .leading)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            ForEach(data) { $point in
                HStack {
                    TextField("x", value: $point.x, format: .number)
                        .frame(maxWidth: .infinity)
                    if twoVariable {
                        TextField("y", value: $point.y, format: .number)
                            .frame(maxWidth: .infinity)
                    }
                    TextField("f", value: $point.frequency, format: .number)
                        .frame(maxWidth: .infinity)
                }
                .keyboardType(.numbersAndPunctuation)
                .monospacedDigit()
            }
            .onDelete { data.wrappedValue.remove(atOffsets: $0) }
            HStack {
                Button("Dodaj vrstico", systemImage: "plus.circle.fill") {
                    let last = data.wrappedValue.last
                    data.wrappedValue.append(DataPoint(x: (last?.x ?? 0) + 1, y: last?.y ?? 0))
                }
                Spacer()
                Menu {
                    Button("Prilepi podatke (CSV ali stolpci)", systemImage: "doc.on.clipboard") { pasteData(into: data) }
                    if second {
                        Button("Primer: višine v drugem razredu", systemImage: "person.3") { data.wrappedValue = StatisticsSamples.otherHeights }
                    } else {
                        Button("Primer: višine dijakov", systemImage: "person.3") { data.wrappedValue = StatisticsSamples.heights }
                        Button("Primer: linearna odvisnost", systemImage: "chart.line.uptrend.xyaxis") {
                            data.wrappedValue = StatisticsSamples.linear
                            twoVariable = true
                        }
                        Button("Primer: eksponentna rast", systemImage: "chart.line.uptrend.xyaxis.circle") {
                            data.wrappedValue = StatisticsSamples.exponential
                            twoVariable = true
                            modelRaw = RegressionModel.exponential.rawValue
                        }
                    }
                    Divider()
                    Button("Izbriši vse", systemImage: "trash", role: .destructive) { data.wrappedValue.removeAll() }
                } label: {
                    Label("Več", systemImage: "ellipsis.circle")
                }
            }
        } header: {
            Text("\(title) (\(data.wrappedValue.count))")
        } footer: {
            Text("Frekvenca pove, kolikokrat se vrednost ponovi. Podatke lahko prilepiš iz preglednice.")
        }
    }

    private func pasteData(into data: Binding<[DataPoint]>) {
        guard let text = UIPasteboard.general.string else { return }
        let points = StatisticsSamples.parse(text)
        guard !points.isEmpty else { return }
        data.wrappedValue = points
        if points.contains(where: { $0.y != 0 }), !compare { twoVariable = true }
    }

    // MARK: One variable

    @ViewBuilder
    private var oneVariableSections: some View {
        if let stats = OneVariableStatistics(values: store.statisticsData.map(\.x), frequencies: store.statisticsData.map(\.frequency)) {
            Section("Srednje vrednosti") {
                ResultRow(title: "n", value: stats.count)
                ResultRow(title: "x̄ (aritmetična sredina)", value: stats.mean)
                ResultRow(title: "Mediana", value: stats.median)
                LabeledContent("Modus", value: stats.modes.isEmpty ? "ni" : stats.modes.map(format).joined(separator: "; "))
            }
            Section("Razpršenost") {
                ResultRow(title: "σx (populacijski)", value: stats.populationStandardDeviation)
                ResultRow(title: "sx (vzorčni)", value: stats.sampleStandardDeviation)
                ResultRow(title: "σ² (varianca)", value: stats.populationVariance)
                ResultRow(title: "Razpon R", value: stats.range)
                ResultRow(title: "Kvartilni razmik Q₃ − Q₁", value: stats.interquartileRange)
                ResultRow(title: "Koeficient variacije σ/x̄", value: stats.coefficientOfVariation)
            }
            Section("Petštevilski povzetek") {
                ResultRow(title: "min", value: stats.minimum)
                ResultRow(title: "Q₁", value: stats.lowerQuartile)
                ResultRow(title: "Mediana", value: stats.median)
                ResultRow(title: "Q₃", value: stats.upperQuartile)
                ResultRow(title: "max", value: stats.maximum)
                // Sample A keeps the comparison's blue.
                BoxPlotChart(stats: stats, color: compare ? .blue : .accentColor)
                    .frame(height: 90)
            }
            Section("Vsote") {
                ResultRow(title: "Σx", value: stats.sum)
                ResultRow(title: "Σx²", value: stats.sumOfSquares)
            }
            Section("Frekvenčna porazdelitev") {
                FrequencyChart(data: store.statisticsData)
                    .frame(height: 220)
            }
        } else {
            Section {
                ContentUnavailableView("Ni podatkov", systemImage: "chart.bar", description: Text("Dodaj vrstice ali prilepi podatke."))
            }
        }
    }

    // MARK: Two samples

    @ViewBuilder
    private var comparisonSections: some View {
        let a = OneVariableStatistics(values: store.statisticsData.map(\.x), frequencies: store.statisticsData.map(\.frequency))
        let b = OneVariableStatistics(values: store.statisticsSecondData.map(\.x), frequencies: store.statisticsSecondData.map(\.frequency))
        if let a, let b {
            Section("Primerjava vzorcev A in B") {
                // Fixed colours, not the app's accent, which may itself be orange.
                BoxPlotChart(rows: [BoxPlotChart.Row(name: "A", stats: a, color: .blue),
                                    BoxPlotChart.Row(name: "B", stats: b, color: .orange)])
                    .frame(height: 140)
                Grid(alignment: .trailing, horizontalSpacing: 18, verticalSpacing: 6) {
                    GridRow {
                        Text("").gridColumnAlignment(.leading)
                        Text("A").fontWeight(.semibold).foregroundStyle(.blue)
                        Text("B").fontWeight(.semibold).foregroundStyle(.orange)
                    }
                    ForEach(Self.comparisonRows, id: \.title) { row in
                        GridRow {
                            Text(row.title).foregroundStyle(.secondary)
                            Text(row.value(a).map(format) ?? "—")
                            Text(row.value(b).map(format) ?? "—")
                        }
                    }
                }
                .font(.callout.monospacedDigit())
            }
            Section {
                Toggle("Enaki varianci (združena s²)", isOn: $equalVariances)
                testRows("t-test H₀: μ_A = μ_B", name: "t", Result(catching: { () throws(MathError) -> Inference.Test in
                    let (sA, sB) = try Self.deviations(a, b, rows: store.statisticsData + store.statisticsSecondData)
                    return try Inference.twoSampleTTest(meanA: a.mean, standardDeviationA: sA, countA: a.count,
                                                        meanB: b.mean, standardDeviationB: sB, countB: b.count,
                                                        equalVariances: equalVariances)
                }))
                testRows("F-test H₀: σ_A² = σ_B²", name: "F", Result(catching: { () throws(MathError) -> Inference.Test in
                    let (sA, sB) = try Self.deviations(a, b, rows: store.statisticsData + store.statisticsSecondData)
                    return try Inference.varianceRatioTest(standardDeviationA: sA, countA: a.count, standardDeviationB: sB, countB: b.count)
                }))
            } header: {
                Text("Preizkusa (dvostranska)")
            } footer: {
                Text("Majhna p-vrednost (npr. p < 0,05) pomeni, da se vzorca značilno razlikujeta. Brez enakih varianc t-test uporabi Welchov približek prostostnih stopenj.")
            }
        } else {
            Section {
                Text(a == nil ? "Vnesi podatke vzorca A." : "Vnesi podatke vzorca B.").foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func testRows(_ title: String, name: String, _ result: Result<Inference.Test, MathError>) -> some View {
        switch result {
        case .success(let test):
            LabeledContent(title) {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(name + " = " + format(NumericCalculus.clean(test.statistic)))
                    Text("ν = " + test.degrees.map { format(NumericCalculus.clean($0)) }.joined(separator: "; ")
                         + ", p = " + probabilityText(test.pValue, options: settings.numberFormat))
                        .foregroundStyle(.secondary)
                }
                .font(.callout.monospacedDigit())
            }
        case .failure(let error):
            LabeledContent(title, value: error.errorDescription ?? error.shortDescription)
        }
    }

    /// The sample standard deviations; a sample of one value has none. The tests take n as the
    /// number of values, so the frequencies of the rows that count must be whole.
    private static func deviations(_ a: OneVariableStatistics, _ b: OneVariableStatistics, rows: [DataPoint]) throws(MathError) -> (Double, Double) {
        let counted = rows.filter { $0.x.isFinite && $0.frequency > 0 && $0.frequency.isFinite }
        guard counted.allSatisfy({ $0.frequency == $0.frequency.rounded() }) else {
            throw .domain("frekvence morajo biti cela števila")
        }
        guard let sA = a.sampleStandardDeviation, let sB = b.sampleStandardDeviation else {
            throw .domain("vsak vzorec potrebuje vsaj dve vrednosti")
        }
        return (sA, sB)
    }

    private struct ComparisonRow {
        let title: String
        let value: (OneVariableStatistics) -> Double?
    }

    private static let comparisonRows: [ComparisonRow] = [
        ComparisonRow(title: "n") { $0.count },
        ComparisonRow(title: "x̄") { $0.mean },
        ComparisonRow(title: "Mediana") { $0.median },
        ComparisonRow(title: "Q₁") { $0.lowerQuartile },
        ComparisonRow(title: "Q₃") { $0.upperQuartile },
        ComparisonRow(title: "Q₃ − Q₁") { $0.interquartileRange },
        ComparisonRow(title: "min") { $0.minimum },
        ComparisonRow(title: "max") { $0.maximum },
        ComparisonRow(title: "Razpon R") { $0.range },
        ComparisonRow(title: "σ") { $0.populationStandardDeviation },
        ComparisonRow(title: "s") { $0.sampleStandardDeviation },
    ]

    // MARK: Two variables

    @ViewBuilder
    private var regressionSections: some View {
        Section("Model") {
            Picker("Regresija", selection: $modelRaw) {
                ForEach(RegressionModel.allCases) { m in
                    Text("\(m.title): \(m.formula)").tag(m.rawValue)
                }
            }
            .pickerStyle(.navigationLink)
        }
        Section {
            Picker("Os x", selection: $xTransformRaw) {
                ForEach(AxisTransform.allCases) { Text($0.label("x")).tag($0.rawValue) }
            }
            Picker("Os y", selection: $yTransformRaw) {
                ForEach(AxisTransform.allCases) { Text($0.label("y")).tag($0.rawValue) }
            }
        } header: {
            Text("Osi (linearizacija)")
        } footer: {
            Text("Npr. t² proti l, p proti 1/V ali ln N proti d: v preoblikovanih oseh so meritve na premici, iz njenega naklona dobiš iskano količino.")
        }
        let transformed = xTransform != .none || yTransform != .none
        let points = AxisTransform.transform(store.statisticsData, x: xTransform, y: yTransform)
        if let sums = TwoVariableStatistics(points: points) {
            switch Result(catching: { () throws(MathError) -> RegressionResult in try Regression.fit(model, points: points) }) {
            case .success(let fit):
                Section("Regresijska krivulja") {
                    HStack {
                        Text("y =").foregroundStyle(.secondary)
                        ViewThatFits(in: .horizontal) {
                            MathText(expr: DisplayForm.prettify(fit.expr), fontSize: 19)
                            MathText(expr: DisplayForm.prettify(fit.expr), fontSize: 14)
                        }
                    }
                    ResultRow(title: "a", value: fit.a)
                    ResultRow(title: "b", value: fit.b)
                    if let c = fit.c { ResultRow(title: "c", value: c) }
                    if let r = fit.r { ResultRow(title: "r (korelacijski koeficient)", value: r) }
                    ResultRow(title: "R² (determinacija)", value: fit.rSquared)
                    if transformed {
                        Text("Velja za \(xTransform.label("x")) na osi x in \(yTransform.label("y")) na osi y.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        Button("Nariši v Grafih", systemImage: "chart.xyaxis.line") {
                            let row = MathRowConverter.rowPreservingStructure(for: .relation(.variable("y"), .equal, fit.expr))
                            store.graphFunctions.append(GraphFunctionDefinition(row: row, colorIndex: (store.graphFunctions.map(\.colorIndex).max() ?? -1) + 1))
                            openInGraphs()
                        }
                    }
                    RegressionChart(points: points, fit: fit, xLabel: xTransform.label("x"), yLabel: yTransform.label("y"))
                        .frame(height: 260)
                }
                Section("Ocena (x′ in y′)") {
                    NumberInputField(title: "x", value: $estimateX, prompt: "vnesi x")
                    if let x = estimateX { ResultRow(title: "y′", value: fit.predict(x)) }
                    NumberInputField(title: "y", value: $estimateY, prompt: "vnesi y")
                    if let y = estimateY {
                        let xs = fit.estimateX(y)
                        if xs.isEmpty {
                            LabeledContent("x′", value: "ni rešitve")
                        } else {
                            ForEach(Array(xs.enumerated()), id: \.offset) { i, x in
                                ResultRow(title: xs.count > 1 ? "x′\(i + 1)" : "x′", value: x)
                            }
                        }
                    }
                }
            case .failure(let error):
                Section {
                    Label(error.errorDescription ?? error.shortDescription, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                }
            }
            Section {
                ResultRow(title: "Ploščina pod lomljeno črto", value: TwoVariableStatistics.areaUnderPolyline(points))
            } header: {
                Text("Ploščina pod grafom")
            } footer: {
                Text("Trapezno pravilo skozi točke po vrsti x – npr. pot pod v(t), delo pod F(s).")
            }
            Section("Vsote in sredine") {
                ResultRow(title: "n", value: sums.count)
                ResultRow(title: "x̄", value: sums.meanX)
                ResultRow(title: "ȳ", value: sums.meanY)
                ResultRow(title: "σx", value: sums.populationSDX)
                ResultRow(title: "σy", value: sums.populationSDY)
                ResultRow(title: "sx", value: sums.sampleSDX)
                ResultRow(title: "sy", value: sums.sampleSDY)
                ResultRow(title: "Σx", value: sums.sumX)
                ResultRow(title: "Σy", value: sums.sumY)
                ResultRow(title: "Σx²", value: sums.sumX2)
                ResultRow(title: "Σy²", value: sums.sumY2)
                ResultRow(title: "Σxy", value: sums.sumXY)
                ResultRow(title: "Kovarianca", value: sums.covariance)
            }
        } else {
            Section {
                ContentUnavailableView("Ni podatkov", systemImage: "chart.dots.scatter", description: Text("Vnesi pare (x, y)."))
            }
        }
    }

    private func format(_ x: Double) -> String {
        NumberFormatting.format(x, options: settings.numberFormat).plainTextLocalized
    }
}

/// Frequencies of the values (or of classes when there are many different values).
struct FrequencyChart: View {
    let data: [DataPoint]

    struct Bar: Identifiable {
        var label: String
        var center: Double
        var frequency: Double
        var id: String { label }
    }

    /// Not private so the app tests can check it.
    var bars: [Bar] {
        var tally: [Double: Double] = [:]
        for p in data where p.x.isFinite && p.frequency > 0 { tally[p.x, default: 0] += p.frequency }
        let values = tally.keys.sorted()
        guard let lo = values.first, let hi = values.last else { return [] }
        if values.count <= 16 {
            return values.map { Bar(label: NumberFormatting.plain($0), center: $0, frequency: tally[$0]!) }
        }
        // Sturges' rule for the number of classes.
        let n = tally.values.reduce(0, +)
        let classes = max(4, Int((log2(n) + 1).rounded(.up)))
        let width = (hi - lo) / Double(classes)
        var counts = [Double](repeating: 0, count: classes)
        for (v, f) in tally {
            let k = min(classes - 1, Int((v - lo) / width))
            counts[k] += f
        }
        return (0..<classes).map { k in
            let a = lo + Double(k) * width
            return Bar(label: "[\(NumberFormatting.plain(NumberFormatting.roundSignificant(a, 4))), \(NumberFormatting.plain(NumberFormatting.roundSignificant(a + width, 4))))",
                       center: a + width / 2, frequency: counts[k])
        }
    }

    var body: some View {
        Chart(bars) { bar in
            BarMark(x: .value("Vrednost", bar.label), y: .value("Frekvenca", bar.frequency))
                .foregroundStyle(Color.accentColor.gradient)
        }
        .chartXAxisLabel("x")
        .chartYAxisLabel("f")
    }
}

/// Horizontal box plots (min, Q₁, median, Q₃, max) of one or more samples on one axis.
struct BoxPlotChart: View {
    struct Row: Identifiable {
        var name: String
        var stats: OneVariableStatistics
        var color: Color
        var id: String { name }
    }

    let rows: [Row]

    init(stats: OneVariableStatistics, color: Color = .accentColor) {
        rows = [Row(name: "x", stats: stats, color: color)]
    }

    init(rows: [Row]) {
        self.rows = rows
    }

    var body: some View {
        Chart(rows) { row in
            RuleMark(xStart: .value("min", row.stats.minimum), xEnd: .value("max", row.stats.maximum), y: .value("Vzorec", row.name))
                .foregroundStyle(.secondary)
            BarMark(xStart: .value("Q₁", row.stats.lowerQuartile), xEnd: .value("Q₃", row.stats.upperQuartile),
                    y: .value("Vzorec", row.name), height: .fixed(28))
                .foregroundStyle(row.color.opacity(0.45))
            RectangleMark(x: .value("Mediana", row.stats.median), y: .value("Vzorec", row.name), width: .fixed(3), height: .fixed(28))
                .foregroundStyle(row.color)
            RectangleMark(x: .value("min", row.stats.minimum), y: .value("Vzorec", row.name), width: .fixed(2), height: .fixed(14))
                .foregroundStyle(.secondary)
            RectangleMark(x: .value("max", row.stats.maximum), y: .value("Vzorec", row.name), width: .fixed(2), height: .fixed(14))
                .foregroundStyle(.secondary)
        }
        .chartYAxis(rows.count > 1 ? .visible : .hidden)
    }
}

/// Data points and the fitted regression curve.
struct RegressionChart: View {
    let points: [DataPoint]
    let fit: RegressionResult
    var xLabel = "x"
    var yLabel = "y"

    private struct Sample: Identifiable {
        var x: Double
        var y: Double
        var id: Double { x }
    }

    private var curve: [Sample] {
        let xs = points.map(\.x)
        guard let lo = xs.min(), let hi = xs.max(), hi > lo else { return [] }
        let pad = (hi - lo) * 0.08
        return (0...160).compactMap { i in
            let x = lo - pad + (hi - lo + 2 * pad) * Double(i) / 160
            let y = fit.predict(x)
            return y.isFinite ? Sample(x: x, y: y) : nil
        }
    }

    var body: some View {
        Chart {
            ForEach(curve) { s in
                LineMark(x: .value("x", s.x), y: .value("y", s.y), series: .value("Krivulja", "fit"))
                    .foregroundStyle(Color.accentColor)
                    .interpolationMethod(.catmullRom)
            }
            ForEach(points) { p in
                PointMark(x: .value("x", p.x), y: .value("y", p.y))
                    .foregroundStyle(.orange)
                    .symbolSize(40 + 20 * min(p.frequency, 5))
            }
        }
        .chartXAxisLabel(xLabel)
        .chartYAxisLabel(yLabel)
    }
}

/// Example data sets and clipboard parsing.
enum StatisticsSamples {
    private static let heightRows: [(Double, Double)] = [
        (158, 1), (162, 3), (165, 5), (168, 7), (170, 9), (172, 8), (175, 6), (178, 4), (182, 2), (188, 1),
    ]
    static let heights: [DataPoint] = heightRows.map { DataPoint(x: $0.0, frequency: $0.1) }

    private static let otherHeightRows: [(Double, Double)] = [
        (160, 2), (164, 4), (167, 6), (170, 5), (173, 7), (176, 6), (179, 4), (183, 3), (186, 2), (191, 1),
    ]
    static let otherHeights: [DataPoint] = otherHeightRows.map { DataPoint(x: $0.0, frequency: $0.1) }

    private static let linearRows: [(Double, Double)] = [
        (1, 2.1), (2, 3.9), (3, 6.2), (4, 7.8), (5, 10.1), (6, 11.8), (7, 14.2),
    ]
    static let linear: [DataPoint] = linearRows.map { DataPoint(x: $0.0, y: $0.1) }

    private static let exponentialRows: [(Double, Double)] = [
        (0, 3.0), (1, 4.9), (2, 8.3), (3, 13.4), (4, 22.4), (5, 36.6),
    ]
    static let exponential: [DataPoint] = exponentialRows.map { DataPoint(x: $0.0, y: $0.1) }

    /// Rows of x[, y[, f]] separated by tabs, semicolons or commas (decimal comma when ; or tab separates).
    static func parse(_ text: String) -> [DataPoint] {
        text.split(whereSeparator: \.isNewline).compactMap { line -> DataPoint? in
            let raw = String(line)
            let usesComma = !(raw.contains(";") || raw.contains("\t"))
            let fields = raw.split(whereSeparator: { usesComma ? $0 == "," : ($0 == ";" || $0 == "\t") })
                .compactMap { part -> Double? in
                    var field = part.trimmingCharacters(in: .whitespaces)
                    if !usesComma { field = field.replacingOccurrences(of: ",", with: ".") }
                    return Double(field)
                }
            guard let x = fields.first else { return nil }
            return DataPoint(x: x, y: fields.count > 1 ? fields[1] : 0, frequency: fields.count > 2 ? fields[2] : 1)
        }
    }
}
