import AcuteCore
import SwiftUI

/// Surveying computations (Geodezija at FGG) in the national grid: y points east, x north,
/// direction angles run clockwise from north; angles in degrees (° ′ ″) or gon.
struct GeodesyToolView: View {
    enum Problem: String, CaseIterable, Identifiable {
        case inverse, polar, forward, arc, resection, traverse, heighting, leveling, area, helmert, adjustment, sphere, sphericalTriangle
        var id: String { rawValue }
        var title: String {
            switch self {
            case .inverse: "Smerni kot in dolžina"
            case .polar: "Polarna metoda"
            case .forward: "Urez naprej"
            case .arc: "Ločni presek"
            case .resection: "Urez nazaj (Snellius–Pothenot)"
            case .traverse: "Poligonski vlak"
            case .heighting: "Trigonometrično višinomerstvo"
            case .leveling: "Nivelmanski vlak"
            case .area: "Površina iz koordinat"
            case .helmert: "Helmertova transformacija"
            case .adjustment: "Izravnava po MNK"
            case .sphere: "Ortodroma in loksodroma"
            case .sphericalTriangle: "Sferni trikotnik"
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
            case .traverse: TraverseSection(unit: unit)
            case .heighting: HeightingSection(unit: unit)
            case .leveling: LevelingSection()
            case .area: AreaSection()
            case .helmert: HelmertSection(unit: unit)
            case .adjustment: AdjustmentSection()
            case .sphere: SphereSection(unit: unit)
            case .sphericalTriangle: SphericalTriangleSection(unit: unit)
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

    /// Radians from "123 45 12,5" (degrees, minutes, seconds) or "137,5037" (gon); nil, like any
    /// invalid entry, when the angle is not finite in radians (1e308° overflows to ∞).
    func radians(_ text: String) -> Double? {
        let value: Double? = switch self {
        case .degrees: Geodesy.degrees(fromDMS: text).map { $0 * .pi / 180 }
        case .gon: ExpressionNumberField.parse(text).map { Geodesy.radians(fromGon: $0) }
        }
        return value.flatMap { $0.isFinite ? $0 : nil }
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

/// Numbers in rows, one row per line (see `numberFields`).
enum GeodesyText {
    /// nil when a non-empty line does not hold exactly `columns` numbers.
    static func rows(_ text: String, columns: Int) -> [[Double]]? {
        var rows: [[Double]] = []
        for line in text.split(whereSeparator: \.isNewline) {
            let s = String(line)
            if s.allSatisfy(\.isWhitespace) { continue }
            let parts = numberFields(s)
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
        // Int(NaN) or a degree count beyond Int would trap; NaN is shown as "—" like elsewhere.
        guard degrees.isFinite, Swift.abs(degrees) < 1e15 else { return "—" }
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

/// An attached (or closed) traverse with the angular and coordinate misclosures distributed.
private struct TraverseSection: View {
    let unit: GeodeticUnit
    @State private var a = GridPoint(y: 1000, x: 1000)
    @State private var orientationA = GridPoint(y: 1000, x: 2000)
    @State private var b = GridPoint(y: 1900, x: 1200)
    @State private var orientationB = GridPoint(y: 2900, x: 1200)
    @AppStorage("traverseRows") private var text = "71 33 54,2; 316,228\n207 53 50,2; 304,138\n143 58 21,5; 335,410\n206 33 54,2"
    @Environment(AppSettings.self) private var settings

    var body: some View {
        Section {
            GridPointFields(name: "A", point: $a)
            GridPointFields(name: "O_A", point: $orientationA)
            GridPointFields(name: "B", point: $b)
            GridPointFields(name: "O_B", point: $orientationB)
        } header: {
            Text("Dane točke in orientaciji")
        } footer: {
            Text("Vlak se začne v A z orientacijo na O_A in konča v B z orientacijo na O_B; zaprti vlak ima B = A in O_B = O_A.")
        }
        Section {
            TextField("β; d", text: $text, axis: .vertical)
                .lineLimit(3...14)
                .font(.callout.monospacedDigit())
                .autocorrectionDisabled()
        } header: {
            Text("Lomni koti in stranice")
        } footer: {
            Text("Vrstica za vsako točko od A do B: lomni kot β (v smeri urinega kazalca od smeri nazaj do smeri naprej, v A od O_A, v B do O_B), podpičje in dolžina stranice do naslednje točke; v zadnji vrstici le kot v B.")
        }
        switch traverse {
        case .success(let t):
            Section("Odstopanja") {
                GeodeticAngleRow(title: "Kotno odstopanje f_β", radians: t.angularMisclosure, unit: unit)
                GeodeticAngleRow(title: "Popravek vsakega kota", radians: -t.angularMisclosure / Double(t.directions.count + 1), unit: unit)
                ResultRow(title: "f_y", value: t.misclosureY, unit: "m")
                ResultRow(title: "f_x", value: t.misclosureX, unit: "m")
                ResultRow(title: "f_d = √(f_y² + f_x²)", value: t.linearMisclosure, unit: "m")
                ResultRow(title: "Σ d", value: t.length, unit: "m")
                if t.linearMisclosure > 0 {
                    LabeledContent("Relativno odstopanje", value: "1 : " + NumberFormatting.plain((t.length / t.linearMisclosure).rounded()))
                }
            }
            Section {
                ForEach(Array(t.directions.enumerated()), id: \.offset) { i, direction in
                    GeodeticAngleRow(title: "ν stranice \(i + 1)", radians: direction, unit: unit)
                }
                ForEach(Array(t.points.enumerated()).dropFirst().dropLast(), id: \.offset) { i, p in
                    LabeledContent("P\(i): y; x", value: value(p.y) + "; " + value(p.x))
                }
            } header: {
                Text("Izravnani smerni koti in točke")
            } footer: {
                Text("Kotno odstopanje je razdeljeno enako na vse kote, f_y in f_x sorazmerno z dolžinami stranic.")
            }
        case .failure(let error):
            Section { Text(error.errorDescription ?? error.shortDescription).foregroundStyle(.secondary) }
        case nil:
            Section { Text("Potrebnih je n + 1 kotov in n stranic (vsaj ena) ter štiri dane točke.").foregroundStyle(.secondary) }
        }
    }

    private var traverse: Result<Geodesy.Traverse, MathError>? {
        guard let pa = a.point, let poa = orientationA.point, let pb = b.point, let pob = orientationB.point, let rows = parsedRows else {
            return nil
        }
        do throws(MathError) {
            return .success(try Geodesy.traverse(start: pa, startOrientation: poa, end: pb, endOrientation: pob,
                                                 angles: rows.angles, distances: rows.distances))
        } catch {
            return .failure(error)
        }
    }

    private var parsedRows: (angles: [Double], distances: [Double])? {
        let lines = text.split(whereSeparator: \.isNewline).map(String.init).filter { !$0.allSatisfy(\.isWhitespace) }
        var angles: [Double] = [], distances: [Double] = []
        for (i, line) in lines.enumerated() {
            let parts = line.split(separator: ";", omittingEmptySubsequences: false)
            guard let angle = unit.radians(String(parts[0])) else { return nil }
            angles.append(angle)
            if i < lines.count - 1 {
                guard parts.count == 2, let d = ExpressionNumberField.parse(String(parts[1])) else { return nil }
                distances.append(d)
            } else if parts.count > 1, !parts[1].allSatisfy(\.isWhitespace) {
                return nil
            }
        }
        return angles.count >= 2 ? (angles, distances) : nil
    }

    private func value(_ x: Double) -> String {
        NumberFormatting.format(NumericCalculus.clean(x), options: settings.numberFormat).plainTextLocalized
    }
}

/// Height difference and horizontal distance from a slope distance and a zenith angle.
private struct HeightingSection: View {
    let unit: GeodeticUnit
    @State private var slope: Double? = 245.318
    @State private var zenith: Double? = 86.5 * Double.pi / 180
    @State private var instrument: Double? = 1.55
    @State private var target: Double? = 1.7
    @State private var startHeight: Double? = 312.45
    @State private var refraction = false

    var body: some View {
        Section {
            NumberInputField(title: "Poševna dolžina S (m)", value: $slope)
            GeodeticAngleField(title: "Zenitna razdalja z", unit: unit, radians: $zenith)
            NumberInputField(title: "Višina instrumenta i (m)", value: $instrument)
            NumberInputField(title: "Višina signala l (m)", value: $target)
            NumberInputField(title: "Višina stojišča H_A (m)", value: $startHeight, prompt: "neobvezno")
            Toggle("Ukrivljenost Zemlje in refrakcija (k = 0,13)", isOn: $refraction)
        } header: {
            Text("Meritev")
        } footer: {
            Text("d = S·sin z, Δh = S·cos z + i − l; s popravkom za ukrivljenost in refrakcijo še (1 − k)·d²/2R.")
        }
        if let slope, slope > 0, let zenith, let instrument, let target {
            let result = Geodesy.heightDifference(slope: slope, zenith: zenith, instrument: instrument, target: target,
                                                  refraction: refraction ? 0.13 : nil)
            Section("Rezultat") {
                ResultRow(title: "Vodoravna dolžina d", value: result.horizontal, unit: "m")
                ResultRow(title: "Višinska razlika Δh", value: result.difference, unit: "m")
                if refraction { ResultRow(title: "Popravek ukrivljenosti in refrakcije", value: result.correction, unit: "m") }
                if let startHeight { ResultRow(title: "H_B = H_A + Δh", value: startHeight + result.difference, unit: "m") }
            }
        }
    }
}

/// A leveling line between known heights.
private struct LevelingSection: View {
    @AppStorage("levelingReadings") private var text = "1,523 0,874\n1,102 1,689\n2,004 0,511"
    @State private var start: Double? = 100
    @State private var end: Double? = 101.56
    @Environment(AppSettings.self) private var settings

    var body: some View {
        Section {
            NumberInputField(title: "Začetna višina H_A (m)", value: $start)
            NumberInputField(title: "Končna višina H_B (m)", value: $end, prompt: "neobvezno")
            TextField("zadnja sprednja (dolžina)", text: $text, axis: .vertical)
                .lineLimit(3...12)
                .font(.callout.monospacedDigit())
                .autocorrectionDisabled()
        } header: {
            Text("Nivelmanski vlak")
        } footer: {
            Text("Vsaka vrstica je eno stojišče: odčitek na zadnji in na sprednji lati ter po želji dolžina stojišča. Δh = zadnja − sprednja; odstopanje od znane končne višine se razdeli sorazmerno z dolžinami (brez dolžin enako).")
        }
        switch leveling {
        case .success(let line):
            Section {
                ForEach(Array(line.differences.enumerated()), id: \.offset) { i, difference in
                    LabeledContent("Stojišče \(i + 1)") {
                        VStack(alignment: .trailing, spacing: 0) {
                            Text("Δh " + value(difference) + (line.misclosure == nil ? "" : ", popravek " + value(line.corrections[i])))
                            Text("H = " + value(line.heights[i])).foregroundStyle(.secondary)
                        }
                        .font(.callout.monospacedDigit())
                    }
                }
                ResultRow(title: "Σ Δh", value: line.differences.reduce(0, +), unit: "m")
                if let misclosure = line.misclosure { ResultRow(title: "Odstopanje f = Σ Δh − (H_B − H_A)", value: misclosure, unit: "m") }
            } header: {
                Text("Višine")
            }
        case .failure(let error):
            Section { Text(error.errorDescription ?? error.shortDescription).foregroundStyle(.secondary) }
        case nil:
            Section { Text("V vsaki vrstici dva odčitka; dolžino stojišča vnesi pri vseh vrsticah ali pri nobeni.").foregroundStyle(.secondary) }
        }
    }

    private var leveling: Result<Geodesy.LevelingLine, MathError>? {
        guard let start, let rows = parsedRows else { return nil }
        do throws(MathError) {
            return .success(try Geodesy.leveling(start: start, end: end, readings: rows.readings, lengths: rows.lengths))
        } catch {
            return .failure(error)
        }
    }

    private var parsedRows: (readings: [(back: Double, fore: Double)], lengths: [Double]?)? {
        var readings: [(back: Double, fore: Double)] = []
        var lengths: [Double] = []
        for line in text.split(whereSeparator: \.isNewline) {
            let s = String(line)
            if s.allSatisfy(\.isWhitespace) { continue }
            let parts = numberFields(s)
            let values = parts.compactMap { ExpressionNumberField.parse(String($0)) }
            guard values.count == parts.count, values.count == 2 || values.count == 3 else { return nil }
            readings.append((back: values[0], fore: values[1]))
            if values.count == 3 { lengths.append(values[2]) }
        }
        guard !readings.isEmpty else { return nil }
        // Lengths for all stations or for none: a partial list would silently weigh them equally.
        if lengths.isEmpty { return (readings, nil) }
        return lengths.count == readings.count ? (readings, lengths) : nil
    }

    private func value(_ x: Double) -> String {
        NumberFormatting.format(NumericCalculus.clean(x), options: settings.numberFormat).plainTextLocalized
    }
}

/// Least squares adjustment of indirect observations: one line per observation.
private struct AdjustmentSection: View {
    @AppStorage("adjustmentRows") private var text = "0 1; 1\n1 1; 3\n2 1; 5,1\n3 1; 6,9"
    @Environment(AppSettings.self) private var settings

    var body: some View {
        Section {
            TextField("a₁ a₂ …; l; p", text: $text, axis: .vertical)
                .lineLimit(4...14)
                .font(.callout.monospacedDigit())
                .autocorrectionDisabled()
        } header: {
            Text("Enačbe popravkov l + v = A·x̂")
        } footer: {
            Text("Vsaka vrstica je ena meritev: koeficienti vrstice matrike A (ločeni s presledki), podpičje, izmerjena vrednost l ter po želji podpičje in utež p. Primer: premica y = k·x + n skozi štiri točke.")
        }
        switch adjustment {
        case .success(let fit):
            Section("Neznanke x̂ ± σ") {
                ForEach(Array(fit.parameters.enumerated()), id: \.offset) { i, x in
                    LabeledContent(indexed("x", i + 1), value: value(x) + (fit.standardDeviations.map { " ± " + value($0[i]) } ?? ""))
                }
            }
            Section {
                ForEach(Array(fit.residuals.enumerated()), id: \.offset) { i, v in
                    LabeledContent(indexed("v", i + 1), value: value(v))
                }
                LabeledContent("vᵀPv", value: value(fit.weightedSquares))
                LabeledContent("Nadštevilnost r = n − u", value: "\(fit.redundancy)")
                if let sigma = fit.sigma { LabeledContent("σ₀ = √(vᵀPv/r)", value: value(sigma)) }
            } header: {
                Text("Popravki in natančnost")
            }
            Section("Kofaktorska matrika Q_x = (AᵀPA)⁻¹") {
                MathText(expr: .matrix(rows: fit.cofactors.count, columns: fit.cofactors.count,
                                       entries: fit.cofactors.flatMap { $0 }.map { Expr.decimal($0) }), fontSize: 15)
            }
        case .failure(let error):
            Section { Text(error.errorDescription ?? error.shortDescription).foregroundStyle(.secondary) }
        case nil:
            Section { Text("Vsaka vrstica: koeficienti; l; p (utež ni obvezna).").foregroundStyle(.secondary) }
        }
    }

    private var adjustment: Result<LeastSquares.Adjustment, MathError>? {
        var a: [[Double]] = [], l: [Double] = [], p: [Double] = []
        for line in text.split(whereSeparator: \.isNewline) {
            let s = String(line)
            if s.allSatisfy(\.isWhitespace) { continue }
            let parts = s.split(separator: ";", omittingEmptySubsequences: false)
            guard parts.count == 2 || parts.count == 3 else { return nil }
            let words = parts[0].split(whereSeparator: \.isWhitespace)
            let coefficients = words.compactMap { ExpressionNumberField.parse(String($0)) }
            let weight: Double? = parts.count == 3 ? ExpressionNumberField.parse(String(parts[2])) : 1
            guard !words.isEmpty, coefficients.count == words.count, let observation = ExpressionNumberField.parse(String(parts[1])),
                  let weight else { return nil }
            a.append(coefficients)
            l.append(observation)
            p.append(weight)
        }
        guard !a.isEmpty else { return nil }
        do throws(MathError) {
            return .success(try LeastSquares.adjust(design: a, observations: l, weights: p))
        } catch {
            return .failure(error)
        }
    }

    private func value(_ x: Double) -> String {
        NumberFormatting.format(NumericCalculus.clean(x), options: settings.numberFormat).plainTextLocalized
    }

    private func indexed(_ name: String, _ i: Int) -> String {
        let digits = ["₀", "₁", "₂", "₃", "₄", "₅", "₆", "₇", "₈", "₉"]
        return name + String(i).map { digits[Int(String($0)) ?? 0] }.joined()
    }
}

private struct SphericalTriangleSection: View {
    enum Given: String, CaseIterable, Identifiable {
        case sss, aaa, sas, asa
        var id: String { rawValue }
        var title: String {
            switch self {
            case .sss: "a, b, c"
            case .aaa: "α, β, γ"
            case .sas: "b, c, α"
            case .asa: "β, γ, a"
            }
        }
        var labels: [String] {
            switch self {
            case .sss: ["Stranica a", "Stranica b", "Stranica c"]
            case .aaa: ["Kot α", "Kot β", "Kot γ"]
            case .sas: ["Stranica b", "Stranica c", "Kot α med njima"]
            case .asa: ["Kot β", "Kot γ", "Stranica a med njima"]
            }
        }
    }

    let unit: GeodeticUnit
    @State private var given: Given = .sss
    @State private var first: Double? = 60 * Double.pi / 180
    @State private var second: Double? = 70 * Double.pi / 180
    @State private var third: Double? = 80 * Double.pi / 180
    @State private var radius: Double? = 6371

    private var triangle: SphericalTriangle? {
        guard let first, let second, let third else { return nil }
        switch given {
        case .sss: return SphericalTriangle.sides(first, second, third)
        case .aaa: return SphericalTriangle.angles(first, second, third)
        case .sas: return SphericalTriangle.sides(first, second, included: third)
        case .asa: return SphericalTriangle.angles(first, second, included: third)
        }
    }

    var body: some View {
        Section {
            Picker("Dano", selection: $given) {
                ForEach(Given.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            GeodeticAngleField(title: given.labels[0], unit: unit, radians: $first)
            GeodeticAngleField(title: given.labels[1], unit: unit, radians: $second)
            GeodeticAngleField(title: given.labels[2], unit: unit, radians: $third)
            NumberInputField(title: "Polmer R (km)", value: $radius)
        } header: {
            Text("Sferni trikotnik")
        } footer: {
            Text("Stranice so središčni koti (dolžina loka je R·a), kot α leži nasproti stranice a. Kosinusna izreka: cos a = cos b cos c + sin b sin c cos α in cos α = −cos β cos γ + sin β sin γ cos a.")
        }
        if let t = triangle {
            Section("Stranice in koti") {
                GeodeticAngleRow(title: "a", radians: t.a, unit: unit)
                GeodeticAngleRow(title: "b", radians: t.b, unit: unit)
                GeodeticAngleRow(title: "c", radians: t.c, unit: unit)
                GeodeticAngleRow(title: "α", radians: t.alpha, unit: unit)
                GeodeticAngleRow(title: "β", radians: t.beta, unit: unit)
                GeodeticAngleRow(title: "γ", radians: t.gamma, unit: unit)
                GeodeticAngleRow(title: "Sferni presežek ε", radians: t.excess, unit: unit)
            }
            if let radius, radius > 0 {
                Section("Na krogli s polmerom R") {
                    ResultRow(title: "Ploščina R²ε", value: radius * radius * t.excess, unit: "km²")
                    ResultRow(title: "Lok R·a", value: radius * t.a, unit: "km")
                    ResultRow(title: "Lok R·b", value: radius * t.b, unit: "km")
                    ResultRow(title: "Lok R·c", value: radius * t.c, unit: "km")
                }
            }
        } else {
            Section { Text("S temi podatki sferni trikotnik ne obstaja (stranice in koti so med 0° in 180°).").foregroundStyle(.secondary) }
        }
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
            if let great = Geodesy.greatCircle(latitude1: phi1, longitude1: lambda1, latitude2: phi2, longitude2: lambda2, radius: radius) {
                Section {
                    ResultRow(title: "Dolžina", value: great.distance, unit: "km")
                    if let start = great.initialAzimuth, let end = great.finalAzimuth {
                        GeodeticAngleRow(title: "Začetni azimut", radians: start, unit: unit)
                        GeodeticAngleRow(title: "Končni azimut", radians: end, unit: unit)
                    }
                } header: {
                    Text("Ortodroma (lok glavnega kroga)")
                } footer: {
                    if great.initialAzimuth == nil { Text("Točki sovpadata ali sta antipodni, zato azimut ni določen.") }
                }
            } else {
                Section { Text("Geografska širina mora biti med −90° in 90°.").foregroundStyle(.secondary) }
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
