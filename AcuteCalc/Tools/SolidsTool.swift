import AcuteCore
import SwiftUI

/// Solids of school geometry: volume, surface area, lengths and angles, with a sketch that
/// turns (hidden edges dashed).
struct SolidsToolView: View {
    enum Kind: String, CaseIterable, Identifiable {
        case cube, cuboid, prism, pyramid, pyramidFrustum, cylinder, cone, coneFrustum, sphere
        var id: String { rawValue }
        var title: String {
            switch self {
            case .cube: "Kocka"
            case .cuboid: "Kvader"
            case .prism: "Pravilna prizma"
            case .pyramid: "Pravilna piramida"
            case .pyramidFrustum: "Prisekana piramida"
            case .cylinder: "Valj"
            case .cone: "Stožec"
            case .coneFrustum: "Prisekani stožec"
            case .sphere: "Krogla"
            }
        }

        var hasSides: Bool { self == .prism || self == .pyramid || self == .pyramidFrustum }
    }

    /// The given quantity of a cube or a sphere, or the pair given for a pyramid or a cone.
    enum Given: String, CaseIterable, Identifiable {
        case first, second, third, fourth
        var id: String { rawValue }
    }

    @State private var kind = Kind.pyramid
    @State private var sides = 4
    @State private var given = Given.first
    @State private var a: Double? = 6
    @State private var b: Double? = 4
    @State private var c: Double?

    var body: some View {
        let result = compute()
        List {
            Section {
                if case .success(let solid) = result {
                    SpaceSketchView(sketch: SpaceSketch(solid: solid, showsAxes: false), accessibilityText: "Skica telesa: " + kind.title)
                        .frame(height: 280)
                        .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
                }
                Picker("Telo", selection: $kind) {
                    ForEach(Kind.allCases) { Text($0.title).tag($0) }
                }
                if kind.hasSides {
                    Stepper("Osnovna ploskev: \(polygonName(sides))", value: $sides, in: 3...12)
                }
                if !givenTitles.isEmpty {
                    Picker("Podano", selection: Binding(get: { given }, set: { switchGiven(to: $0) })) {
                        ForEach(Array(givenTitles.enumerated()), id: \.offset) { index, title in
                            Text(title).tag(Given.allCases[index])
                        }
                    }
                }
                ForEach(Array(fieldTitles.enumerated()), id: \.offset) { index, title in
                    NumberInputField(title: title, value: [$a, $b, $c][index])
                }
            } footer: {
                Text("Vleci skico za vrtenje, dva prsta za povečavo. Skriti robovi so črtkani, višine in polmeri oranžni.")
            }
            results(result)
        }
        .listStyle(.insetGrouped)
        .scrollDismissesKeyboard(.interactively)
        .onChange(of: kind) { _, kind in
            given = .first
            (a, b, c) = Self.defaults(kind)
        }
    }

    // MARK: Inputs

    private var givenTitles: [String] {
        switch kind {
        case .cube: ["rob a", "telesna diagonala D", "prostornina V", "površina P"]
        case .pyramid: ["a in višina v", "a in stranski rob s", "a in višina stranske ploskve vₐ"]
        case .cone: ["r in v", "r in s", "v in s"]
        case .sphere: ["polmer r", "prostornina V", "površina P"]
        default: []
        }
    }

    private var fieldTitles: [String] { inputTitles(given) }

    private func inputTitles(_ given: Given) -> [String] {
        switch kind {
        case .cube: [["a", "D", "V", "P"][index(given)]]
        case .cuboid: ["a", "b", "c (višina)"]
        case .prism: ["a (osnovni rob)", "v (višina)"]
        case .pyramid: ["a (osnovni rob)", ["v (višina)", "s (stranski rob)", "vₐ (višina stranske ploskve)"][index(given)]]
        case .pyramidFrustum: ["a (spodnji osnovni rob)", "b (zgornji osnovni rob)", "v (višina)"]
        case .cylinder: ["r (polmer)", "v (višina)"]
        case .cone: [["r (polmer)", "v (višina)"], ["r (polmer)", "s (stranica)"], ["v (višina)", "s (stranica)"]][index(given)]
        case .coneFrustum: ["r₁ (spodnji polmer)", "r₂ (zgornji polmer)", "v (višina)"]
        case .sphere: [["r", "V", "P"][index(given)]]
        }
    }

    /// The symbols of the given fields, to carry the solid over to another choice of givens.
    private func givenSymbols(_ given: Given) -> [String] {
        switch kind {
        case .cube: [["a", "D", "V", "P"][index(given)]]
        case .pyramid: ["a", ["v", "s", "vₐ"][index(given)]]
        case .cone: [["r", "v"], ["r", "s"], ["v", "s"]][index(given)]
        case .sphere: [["r", "V", "P"][index(given)]]
        default: []
        }
    }

    /// Changes what is given and fills the fields with the same solid's values.
    private func switchGiven(to new: Given) {
        let current = try? solid(given)
        given = new
        guard let current else { return }
        let values = givenSymbols(new).map { symbol -> Double? in
            switch symbol {
            case "V": current.volume
            case "P": current.surface
            default: current.quantities.first { $0.symbol == symbol }?.value
            }
        }
        if let first = values.first, let first { a = NumericCalculus.clean(first) }
        if values.count > 1, let second = values[1] { b = NumericCalculus.clean(second) }
    }

    private func index(_ given: Given) -> Int {
        Swift.min(Given.allCases.firstIndex(of: given) ?? 0, Swift.max(givenTitles.count - 1, 0))
    }

    private static func defaults(_ kind: Kind) -> (Double?, Double?, Double?) {
        switch kind {
        case .cube: (2, nil, nil)
        case .cuboid: (3, 4, 12)
        case .prism: (2, 5, nil)
        case .pyramid: (6, 4, nil)
        case .pyramidFrustum: (6, 2, 3)
        case .cylinder: (2, 5, nil)
        case .cone: (3, 4, nil)
        case .coneFrustum: (4, 2, 3)
        case .sphere: (3, nil, nil)
        }
    }

    private func polygonName(_ n: Int) -> String {
        switch n {
        case 3: "trikotnik"
        case 4: "kvadrat"
        case 5: "petkotnik"
        case 6: "šestkotnik"
        case 8: "osemkotnik"
        default: "\(n)-kotnik"
        }
    }

    // MARK: Results

    private func compute() -> Result<Solids.Solid, MathError> {
        do throws(MathError) {
            return .success(try solid(given))
        } catch {
            return .failure(error)
        }
    }

    private func solid(_ given: Given) throws(MathError) -> Solids.Solid {
        let values = Array([a, b, c].prefix(inputTitles(given).count))
        guard values.allSatisfy({ $0 != nil }) else { throw .incomplete }
        let x = values.map { $0 ?? 0 }
        switch kind {
        case .cube:
            switch index(given) {
            case 1: return try Solids.cube(try Solids.cubeEdge(diagonal: x[0]))
            case 2: return try Solids.cube(try Solids.cubeEdge(volume: x[0]))
            case 3: return try Solids.cube(try Solids.cubeEdge(surface: x[0]))
            default: return try Solids.cube(x[0])
            }
        case .cuboid:
            return try Solids.cuboid(x[0], x[1], x[2])
        case .prism:
            return try Solids.prism(sides: sides, edge: x[0], height: x[1])
        case .pyramid:
            switch index(given) {
            case 1: return try Solids.pyramid(sides: sides, edge: x[0], height: try Solids.pyramidHeight(sides: sides, edge: x[0], sideEdge: x[1]))
            case 2: return try Solids.pyramid(sides: sides, edge: x[0], height: try Solids.pyramidHeight(sides: sides, edge: x[0], faceHeight: x[1]))
            default: return try Solids.pyramid(sides: sides, edge: x[0], height: x[1])
            }
        case .pyramidFrustum:
            return try Solids.pyramidFrustum(sides: sides, lower: x[0], upper: x[1], height: x[2])
        case .cylinder:
            return try Solids.cylinder(radius: x[0], height: x[1])
        case .cone:
            switch index(given) {
            case 1: return try Solids.cone(radius: x[0], height: try Solids.coneHeight(radius: x[0], slant: x[1]))
            case 2: return try Solids.cone(radius: try Solids.coneRadius(height: x[0], slant: x[1]), height: x[0])
            default: return try Solids.cone(radius: x[0], height: x[1])
            }
        case .coneFrustum:
            return try Solids.coneFrustum(lower: x[0], upper: x[1], height: x[2])
        case .sphere:
            switch index(given) {
            case 1: return try Solids.sphere(radius: try Solids.sphereRadius(volume: x[0]))
            case 2: return try Solids.sphere(radius: try Solids.sphereRadius(surface: x[0]))
            default: return try Solids.sphere(radius: x[0])
            }
        }
    }

    @ViewBuilder
    private func results(_ result: Result<Solids.Solid, MathError>) -> some View {
        switch result {
        case .success(let solid):
            Section("Rezultati") {
                ResultRow(title: "Prostornina V", value: solid.volume, exact: Self.exact(solid.volume))
                ResultRow(title: "Površina P", value: solid.surface, exact: Self.exact(solid.surface))
                ForEach(solid.quantities, id: \.symbol) { quantity in
                    let title = String(quantity.title.prefix(1)).uppercased() + String(quantity.title.dropFirst()) + " " + quantity.symbol
                    if quantity.isAngle {
                        AngleRow(title: title, radians: quantity.value)
                    } else {
                        ResultRow(title: title, value: quantity.value, exact: Self.exact(quantity.value))
                    }
                }
            }
        case .failure(let error):
            Section {
                Text(error == .incomplete ? "Vnesi podatke telesa." : (error.errorDescription ?? error.shortDescription))
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// A value worth showing in closed form (36π, 6√2), not a whole number or a short decimal.
    static func exact(_ value: Double) -> Expr? {
        let x = NumericCalculus.clean(value)
        guard x.isFinite, x != x.rounded(), (x * 1000).rounded() != x * 1000,
              let e = ExactRecognizer.recognize(x), e.complexity <= 8 else { return nil }
        return e.expr
    }
}
