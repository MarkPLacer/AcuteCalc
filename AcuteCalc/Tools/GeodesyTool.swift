import AcuteCore
import SwiftUI

/// Surveying computations (Geodezija at FGG) in the national grid: y points east, x north,
/// direction angles run clockwise from north; angles in degrees (° ′ ″) or gon.
struct GeodesyToolView: View {
    enum Problem: String, CaseIterable, Identifiable {
        case inverse, polar, forward, arc, resection, area, helmert, sphere
        var id: String { rawValue }
        var title: String {
            switch self {
            case .inverse: "Smerni kot in dolžina"
            case .polar: "Polarna metoda"
            case .forward: "Urez naprej"
            case .arc: "Ločni presek"
            case .resection: "Urez nazaj (Snellius–Pothenot)"
            case .area: "Površina iz koordinat"
            case .helmert: "Helmertova transformacija"
            case .sphere: "Ortodroma in loksodroma"
            }
        }
    }

    @AppStorage("geodesyProblem") private var problem: Problem = .inverse
    @AppStorage("geodesyAngleUnit") private var unit: GeodeticUnit = .degrees

    var body: some View {
        List {
            Section {
                Picker("Naloga", selection: $problem) {
                    ForEach(Problem.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.menu)
                Picker("Koti", selection: $unit) {
                    ForEach(GeodeticUnit.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
            } footer: {
                Text("y je vzhodna, x severna koordinata; smerni kot ν merimo od severa v smeri urinega kazalca. Kote vnesi kot 123 45 12,5 (° ′ ″) ali v gonih.")
            }
            switch problem {
            case .inverse: InverseSection(unit: unit)
            case .polar: PolarSection(unit: unit)
            case .forward: ForwardIntersectionSection(unit: unit)
            case .arc: ArcIntersectionSection()
            case .resection: ResectionSection(unit: unit)
            case .area: AreaSection()
            case .helmert: HelmertSection(unit: unit)
            case .sphere: SphereSection(unit: unit)
            }
        }
        .listStyle(.insetGrouped)
        .scrollDismissesKeyboard(.interactively)
    }
}

enum GeodeticUnit: String, CaseIterable, Identifiable {
    case degrees, gon
    var id: String { rawValue }
    var title: String {
        switch self {
        case .degrees: "° ′ ″"
        case .gon: "gon"
        }
    }

    /// Radians from "123 45 12,5" (degrees, minutes, seconds) or "137,5037" (gon).
    func radians(_ text: String) -> Double? {
        switch self {
        case .degrees: Geodesy.degrees(fromDMS: text).map { $0 * .pi / 180 }
        case .gon: ExpressionNumberField.parse(text).map { Geodesy.radians(fromGon: $0) }
        }
    }

    /// The text that `radians(_:)` reads back.
    func text(_ radians: Double) -> String {
        switch self {
        case .degrees:
            let dms = NumberFormatting.sexagesimal(radians * 180 / .pi)
            return (dms.negative ? "-" : "") + "\(dms.degrees) \(dms.minutes) " + NumberFormatting.plain(dms.seconds)
        case .gon:
            return NumberFormatting.plain(Geodesy.gon(fromRadians: radians))
        }
    }
}

struct GridPoint: Equatable {
    var y: Double?
    var x: Double?

    var point: Geodesy.Point? {
        guard let y, let x else { return nil }
        return Geodesy.Point(y: y, x: x)
    }
}

/// Numbers in rows, one row per line, separated by spaces or semicolons (decimal commas allowed).
enum GeodesyText {
    /// nil when a non-empty line does not hold exactly `columns` numbers.
    static func rows(_ text: String, columns: Int) -> [[Double]]? {
        var rows: [[Double]] = []
        for line in text.split(whereSeparator: \.isNewline) {
            let s = String(line)
            if s.allSatisfy(\.isWhitespace) { continue }
            let parts = s.contains(";") ? s.split(separator: ";") : s.split(whereSeparator: \.isWhitespace)
            let values = parts.compactMap { ExpressionNumberField.parse(String($0)) }
            guard parts.count == columns, values.count == columns else { return nil }
            rows.append(values)
        }
        return rows
    }
}

// MARK: - Shared rows

private struct GridPointFields: View {
    let name: String
    @Binding var point: GridPoint

    var body: some View {
        NumberInputField(title: "\(name): y (vzhod)", value: $point.y)
        NumberInputField(title: "\(name): x (sever)", value: $point.x)
    }
}

private struct GridPointResult: View {
    let name: String
    let point: Geodesy.Point

    var body: some View {
        ResultRow(title: "\(name): y", value: point.y)
        ResultRow(title: "\(name): x", value: point.x)
    }
}

/// An angle typed in the chosen unit, kept in radians.
private struct GeodeticAngleField: View {
    let title: String
    let unit: GeodeticUnit
    @Binding var radians: Double?
    @State private var text = ""

    var body: some View {
        LabeledContent(title) {
            TextField(unit == .degrees ? "° ′ ″" : "gon", text: $text)
                .multilineTextAlignment(.trailing)
                .font(.body.monospacedDigit())
                .keyboardType(.numbersAndPunctuation)
                .autocorrectionDisabled()
                .foregroundStyle(text.isEmpty || unit.radians(text) != nil ? Color.primary : Color.red)
                .onChange(of: text) { _, newValue in
                    let parsed = unit.radians(newValue)
                    if parsed != radians { radians = parsed }
                }
        }
        .onAppear { text = radians.map(unit.text) ?? "" }
        .onChange(of: unit) { _, newUnit in text = radians.map(newUnit.text) ?? "" }
    }
}

/// An angle in the chosen unit, with the other unit below (seconds to 0,1″, gon to 0,1 mgon).
private struct GeodeticAngleRow: View {
    let title: String
    let radians: Double
    let unit: GeodeticUnit
    @Environment(AppSettings.self) private var settings

    var body: some View {
        LabeledContent(title) {
            VStack(alignment: .trailing, spacing: 0) {
                Text(unit == .degrees ? dms : gon).font(.body.monospacedDigit())
                Text(unit == .degrees ? gon : dms).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
        }
        .contextMenu {
            Button("Kopiraj", systemImage: "doc.on.doc") { UIPasteboard.general.string = unit == .degrees ? dms : gon }
        }
    }

    private var dms: String {
        let degrees = radians * 180 / .pi
        let tenths = (Swift.abs(degrees) * 36_000).rounded()
        let d = Int(tenths / 36_000)
        let m = Int((tenths - Double(d) * 36_000) / 600)
        let s = (tenths - Double(d) * 36_000 - Double(m) * 600) / 10
        let seconds = NumberFormatting.format(s, options: NumberFormatOptions(mode: .fix, places: 1, decimalSeparator: settings.decimalSeparator))
        return (degrees < 0 ? "−" : "") + "\(d)° " + (m < 10 ? "0" : "") + "\(m)′ " + (s < 10 ? "0" : "") + seconds.plainTextLocalized + "″"
    }

    private var gon: String {
        let value = NumberFormatting.format(Geodesy.gon(fromRadians: radians), options: NumberFormatOptions(mode: .fix, places: 4, decimalSeparator: settings.decimalSeparator))
        return value.plainTextLocalized + " gon"
    }
}

// MARK: - Tasks

private struct InverseSection: View {
    let unit: GeodeticUnit
    @State private var a = GridPoint(y: 1000, x: 1000)
    @State private var b = GridPoint(y: 1250.37, x: 1430.12)

    var body: some View {
        Section("Dani točki") {
            GridPointFields(name: "A", point: $a)
            GridPointFields(name: "B", point: $b)
        }
        if let pa = a.point, let pb = b.point, let result = Geodesy.inverse(pa, pb) {
            Section("Rezultat") {
                GeodeticAngleRow(title: "Smerni kot ν_AB", radians: result.direction, unit: unit)
                GeodeticAngleRow(title: "Smerni kot ν_BA", radians: Geodesy.normalized(result.direction + .pi), unit: unit)
                ResultRow(title: "Dolžina d_AB", value: result.distance)
                ResultRow(title: "Δy", value: pb.y - pa.y)
                ResultRow(title: "Δx", value: pb.x - pa.x)
            }
        }
    }
}

private struct PolarSection: View {
    let unit: GeodeticUnit
    @State private var a = GridPoint(y: 1000, x: 1000)
    @State private var direction: Double? = Double.pi / 4
    @State private var distance: Double? = 250

    var body: some View {
        Section("Stojišče in meritev") {
            GridPointFields(name: "A", point: $a)
            GeodeticAngleField(title: "Smerni kot ν_AB", unit: unit, radians: $direction)
            NumberInputField(title: "Dolžina d_AB", value: $distance)
        }
        if let pa = a.point, let direction, let distance {
            Section("Nova točka") {
                GridPointResult(name: "B", point: Geodesy.polar(from: pa, direction: direction, distance: distance))
            }
        }
    }
}

private struct ForwardIntersectionSection: View {
    let unit: GeodeticUnit
    @State private var a = GridPoint(y: 1000, x: 1000)
    @State private var b = GridPoint(y: 1300, x: 1050)
    @State private var alpha: Double? = 50 * Double.pi / 180
    @State private var beta: Double? = 60 * Double.pi / 180
    @State private var left = true

    var body: some View {
        Section {
            GridPointFields(name: "A", point: $a)
            GridPointFields(name: "B", point: $b)
            GeodeticAngleField(title: "α pri A (med AB in AP)", unit: unit, radians: $alpha)
            GeodeticAngleField(title: "β pri B (med BA in BP)", unit: unit, radians: $beta)
            Picker("Lega P", selection: $left) {
                Text("levo od AB").tag(true)
                Text("desno od AB").tag(false)
            }
            .pickerStyle(.segmented)
        } header: {
            Text("Dani točki in izmerjena kota")
        } footer: {
            Text("Levo oziroma desno gledano od A proti B.")
        }
        if let pa = a.point, let pb = b.point, let alpha, let beta {
            if let p = Geodesy.forwardIntersection(pa, pb, alpha: alpha, beta: beta, left: left) {
                Section("Točka P") {
                    GridPointResult(name: "P", point: p)
                    if let ap = Geodesy.inverse(pa, p) { ResultRow(title: "d_AP", value: ap.distance) }
                    if let bp = Geodesy.inverse(pb, p) { ResultRow(title: "d_BP", value: bp.distance) }
                }
            } else {
                Section { Text("Žarka iz A in B se ne sekata (α + β mora biti manj kot 180°).").foregroundStyle(.secondary) }
            }
        }
    }
}

private struct ArcIntersectionSection: View {
    @State private var a = GridPoint(y: 1000, x: 1000)
    @State private var b = GridPoint(y: 1300, x: 1050)
    @State private var distanceA: Double? = 220
    @State private var distanceB: Double? = 180
    @State private var left = true

    var body: some View {
        Section {
            GridPointFields(name: "A", point: $a)
            GridPointFields(name: "B", point: $b)
            NumberInputField(title: "d_AP", value: $distanceA)
            NumberInputField(title: "d_BP", value: $distanceB)
            Picker("Lega P", selection: $left) {
                Text("levo od AB").tag(true)
                Text("desno od AB").tag(false)
            }
            .pickerStyle(.segmented)
        } header: {
            Text("Dani točki in izmerjeni dolžini")
        } footer: {
            Text("Krožnici okoli A in B se sekata v dveh točkah; izberi, katera leži levo gledano od A proti B.")
        }
        if let pa = a.point, let pb = b.point, let distanceA, let distanceB {
            if let p = Geodesy.arcIntersection(pa, pb, distanceA: distanceA, distanceB: distanceB, left: left) {
                Section("Točka P") { GridPointResult(name: "P", point: p) }
            } else {
                Section { Text("Krožnici se ne sekata (trikotniška neenakost).").foregroundStyle(.secondary) }
            }
        }
    }
}

private struct ResectionSection: View {
    let unit: GeodeticUnit
    @State private var a = GridPoint(y: 1000, x: 2000)
    @State private var b = GridPoint(y: 2000, x: 2100)
    @State private var c = GridPoint(y: 2600, x: 1200)
    @State private var alpha: Double? = 66.614_779 * Double.pi / 180
    @State private var beta: Double? = 57.893_744 * Double.pi / 180

    var body: some View {
        Section {
            GridPointFields(name: "A", point: $a)
            GridPointFields(name: "B", point: $b)
            GridPointFields(name: "C", point: $c)
            GeodeticAngleField(title: "α od A do B", unit: unit, radians: $alpha)
            GeodeticAngleField(title: "β od B do C", unit: unit, radians: $beta)
        } header: {
            Text("Dane točke in kota, izmerjena na P")
        } footer: {
            Text("Kota merimo na stojišču P v smeri urinega kazalca (razlika odčitkov). Če P leži na krožnici skozi A, B in C (nevarni krog), rešitev ni določena.")
        }
        if let pa = a.point, let pb = b.point, let pc = c.point, let alpha, let beta {
            if let p = Geodesy.resection(pa, pb, pc, alpha: alpha, beta: beta) {
                Section("Stojišče P") {
                    GridPointResult(name: "P", point: p)
                    if let toA = Geodesy.inverse(p, pa) { ResultRow(title: "d_PA", value: toA.distance) }
                    if let toB = Geodesy.inverse(p, pb) { ResultRow(title: "d_PB", value: toB.distance) }
                    if let toC = Geodesy.inverse(p, pc) { ResultRow(title: "d_PC", value: toC.distance) }
                }
            } else {
                Section { Text("Rešitev ni določena: P leži na nevarnem krogu ali pa sta kota 0° ali 180°.").foregroundStyle(.secondary) }
            }
        }
    }
}

private struct AreaSection: View {
    @AppStorage("geodesyAreaPoints") private var text = "1000 1000\n1100 1020\n1120 1150\n990 1110"

    var body: some View {
        Section {
            TextField("y x", text: $text, axis: .vertical)
                .lineLimit(4...12)
                .font(.body.monospacedDigit())
                .autocorrectionDisabled()
        } header: {
            Text("Oglišča po vrsti")
        } footer: {
            Text("V vsaki vrstici y in x, ločena s presledkom ali podpičjem. 2P = Σ yᵢ(xᵢ₊₁ − xᵢ₋₁).")
        }
        if let rows = GeodesyText.rows(text, columns: 2), rows.count >= 3 {
            let points = rows.map { Geodesy.Point(y: $0[0], x: $0[1]) }
            let area = Geodesy.area(points)
            Section("Rezultat") {
                ResultRow(title: "Površina", value: area, unit: "m²")
                ResultRow(title: "Površina", value: area / 10_000, unit: "ha")
                ResultRow(title: "Obseg", value: Geodesy.perimeter(points), unit: "m")
            }
        } else {
            Section { Text("Vnesi vsaj tri točke.").foregroundStyle(.secondary) }
        }
    }
}

private struct HelmertSection: View {
    let unit: GeodeticUnit
    @AppStorage("helmertIdentical") private var identicalText =
        "1000 1000 5258,793 3111,332\n1500 1000 5758,818 3106,976\n1500 1600 5764,06 3707,01\n1000 1600 5264,021 3711,368"
    @AppStorage("helmertTransform") private var transformText = "1200 1300\n1450 1550"
    @Environment(AppSettings.self) private var settings

    var body: some View {
        Section {
            TextField("y x y′ x′", text: $identicalText, axis: .vertical)
                .lineLimit(3...10)
                .font(.callout.monospacedDigit())
                .autocorrectionDisabled()
        } header: {
            Text("Identične točke")
        } footer: {
            Text("V vsaki vrstici y x v izvornem in y′ x′ v ciljnem sistemu; vsaj dve točki. y′ = a·y − b·x + t_y, x′ = b·y + a·x + t_x (izravnava po metodi najmanjših kvadratov).")
        }
        Section("Točke za transformacijo (y x)") {
            TextField("y x", text: $transformText, axis: .vertical)
                .lineLimit(2...10)
                .font(.callout.monospacedDigit())
                .autocorrectionDisabled()
        }
        if let identical = GeodesyText.rows(identicalText, columns: 4),
           let fit = try? Geodesy.helmert(identical.map { (source: Geodesy.Point(y: $0[0], x: $0[1]), target: Geodesy.Point(y: $0[2], x: $0[3])) }) {
            Section("Parametri") {
                ResultRow(title: "a", value: fit.a)
                ResultRow(title: "b", value: fit.b)
                ResultRow(title: "Merilo m", value: fit.scale)
                GeodeticAngleRow(title: "Zasuk smernih kotov", radians: fit.rotation, unit: unit)
                ResultRow(title: "t_y", value: fit.ty)
                ResultRow(title: "t_x", value: fit.tx)
                if let sigma = fit.sigma { ResultRow(title: "σ₀", value: sigma) }
            }
            Section("Popravki v identičnih točkah (v_y, v_x)") {
                ForEach(Array(fit.residuals.enumerated()), id: \.offset) { i, v in
                    LabeledContent("\(i + 1)", value: pair(v))
                }
            }
            if let rows = GeodesyText.rows(transformText, columns: 2), !rows.isEmpty {
                Section("Transformirane točke (y′, x′)") {
                    ForEach(Array(rows.enumerated()), id: \.offset) { i, row in
                        LabeledContent("\(i + 1)", value: pair(fit.apply(Geodesy.Point(y: row[0], x: row[1]))))
                    }
                }
            }
        } else {
            Section { Text("Vnesi vsaj dve različni identični točki s po štirimi koordinatami.").foregroundStyle(.secondary) }
        }
    }

    private func pair(_ p: Geodesy.Point) -> String {
        let format = { (x: Double) in NumberFormatting.format(NumericCalculus.clean(x), options: settings.numberFormat).plainTextLocalized }
        return format(p.y) + "; " + format(p.x)
    }
}

private struct SphereSection: View {
    let unit: GeodeticUnit
    // Ljubljana and New York
    @State private var phi1: Double? = 46.0569 * Double.pi / 180
    @State private var lambda1: Double? = 14.5058 * Double.pi / 180
    @State private var phi2: Double? = 40.7128 * Double.pi / 180
    @State private var lambda2: Double? = -74.006 * Double.pi / 180
    @State private var radius: Double? = 6371

    var body: some View {
        Section {
            GeodeticAngleField(title: "φ₁ (širina)", unit: unit, radians: $phi1)
            GeodeticAngleField(title: "λ₁ (dolžina)", unit: unit, radians: $lambda1)
            GeodeticAngleField(title: "φ₂ (širina)", unit: unit, radians: $phi2)
            GeodeticAngleField(title: "λ₂ (dolžina)", unit: unit, radians: $lambda2)
            NumberInputField(title: "Polmer R (km)", value: $radius)
        } header: {
            Text("Točki na krogli")
        } footer: {
            Text("Severna širina in vzhodna dolžina sta pozitivni, južna in zahodna negativni. Zemlja kot krogla s polmerom 6371 km.")
        }
        if let phi1, let lambda1, let phi2, let lambda2, let radius, radius > 0 {
            let great = Geodesy.greatCircle(latitude1: phi1, longitude1: lambda1, latitude2: phi2, longitude2: lambda2, radius: radius)
            Section("Ortodroma (lok glavnega kroga)") {
                ResultRow(title: "Dolžina", value: great.distance, unit: "km")
                GeodeticAngleRow(title: "Začetni azimut", radians: great.initialAzimuth, unit: unit)
                GeodeticAngleRow(title: "Končni azimut", radians: great.finalAzimuth, unit: unit)
            }
            if let rhumb = Geodesy.rhumbLine(latitude1: phi1, longitude1: lambda1, latitude2: phi2, longitude2: lambda2, radius: radius) {
                Section("Loksodroma (stalni azimut)") {
                    ResultRow(title: "Dolžina", value: rhumb.distance, unit: "km")
                    GeodeticAngleRow(title: "Azimut", radians: rhumb.azimuth, unit: unit)
                }
            }
        }
    }
}
