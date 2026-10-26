import AcuteCore
import SwiftUI

/// Points, lines and planes in space (Matematika I and II): distances, mutual position,
/// intersections, angles, projections and mirror images.
struct SpaceGeometryToolView: View {
    @State private var first = SpaceObjectInput(kind: .point, a: "(1; 2; 3)")
    @State private var second = SpaceObjectInput(kind: .plane, equation: "2x - y + 2z = 3")

    var body: some View {
        List {
            SpaceObjectSection(title: "Prvi objekt", input: $first)
            SpaceObjectSection(title: "Drugi objekt", input: $second)
            if let a = first.entity, let b = second.entity {
                SpaceRelationSection(first: a, second: b)
            } else {
                Section { Text("Vnesi oba objekta.").foregroundStyle(.secondary) }
            }
        }
        .listStyle(.insetGrouped)
        .scrollDismissesKeyboard(.interactively)
    }
}

enum SpaceEntity {
    case point([Double])
    case line(SpatialGeometry.Line)
    case plane(SpatialGeometry.Plane)
}

/// The typed description of a point, a line (point and direction) or a plane (equation,
/// three points, or a point and a normal).
struct SpaceObjectInput: Equatable {
    enum Kind: String, CaseIterable, Identifiable {
        case point, line, plane
        var id: String { rawValue }
        var title: String {
            switch self {
            case .point: "Točka"
            case .line: "Premica"
            case .plane: "Ravnina"
            }
        }
    }

    enum PlaneForm: String, CaseIterable, Identifiable {
        case equation, points, normal
        var id: String { rawValue }
        var title: String {
            switch self {
            case .equation: "Enačba"
            case .points: "Tri točke"
            case .normal: "Točka in normala"
            }
        }
    }

    var kind: Kind
    var planeForm: PlaneForm = .equation
    var a = "(0; 0; 0)"
    var b = "(1; 0; 0)"
    var c = "(0; 1; 0)"
    var equation = "x + y + z = 1"

    var entity: SpaceEntity? {
        switch kind {
        case .point:
            return SpaceObjectInput.vector(a).map { SpaceEntity.point($0) }
        case .line:
            guard let p = SpaceObjectInput.vector(a), let s = SpaceObjectInput.vector(b), VectorGeometry.length(s) > 0 else { return nil }
            return .line(SpatialGeometry.Line(point: p, direction: s))
        case .plane:
            switch planeForm {
            case .equation:
                return SpaceObjectInput.plane(equation).map { SpaceEntity.plane($0) }
            case .points:
                guard let p = SpaceObjectInput.vector(a), let q = SpaceObjectInput.vector(b), let r = SpaceObjectInput.vector(c),
                      let plane = SpatialGeometry.Plane(through: p, q, r) else { return nil }
                return .plane(plane)
            case .normal:
                guard let p = SpaceObjectInput.vector(a), let n = SpaceObjectInput.vector(b), VectorGeometry.length(n) > 0 else { return nil }
                return .plane(SpatialGeometry.Plane(normal: n, point: p))
            }
        }
    }

    /// "(1; 2; 3)", "1, 2, 3" or "1 2 3"; with decimal commas the coordinates need semicolons.
    static func vector(_ text: String) -> [Double]? {
        var t = text.trimmingCharacters(in: .whitespaces)
        if t.hasPrefix("(") || t.hasPrefix("[") { t.removeFirst() }
        if t.hasSuffix(")") || t.hasSuffix("]") { t.removeLast() }
        let parts: [Substring]
        if t.contains(";") {
            parts = t.split(separator: ";")
        } else if t.contains(",") {
            parts = t.split(separator: ",")
        } else {
            parts = t.split(whereSeparator: \.isWhitespace)
        }
        let values = parts.compactMap { ExpressionNumberField.parse(String($0)) }
        return parts.count == 3 && values.count == 3 ? values : nil
    }

    /// ax + by + cz + d = 0 from a typed linear equation in x, y and z.
    static func plane(_ text: String) -> SpatialGeometry.Plane? {
        guard let expr = try? Parser.parse(text) else { return nil }
        var f = expr
        if case .relation(let lhs, .equal, let rhs) = expr { f = .sum([lhs, .negation(rhs)]) }
        func value(_ p: [Double]) -> Double? {
            try? RealEvaluator.evaluate(f, context: EvaluationContext(variables: ["x": p[0], "y": p[1], "z": p[2]]))
        }
        guard let d = value([0, 0, 0]), let a = value([1, 0, 0]), let b = value([0, 1, 0]), let c = value([0, 0, 1]) else { return nil }
        let normal = [a - d, b - d, c - d]
        guard VectorGeometry.length(normal) > 0 else { return nil }
        // Linear: the same values at two more points.
        for p in [[2.0, -3, 5], [0.5, 7, -1.25]] {
            guard let v = value(p), Swift.abs(v - VectorGeometry.dot(normal, p) - d) <= 1e-9 * Swift.max(1, Swift.abs(v)) else { return nil }
        }
        return SpatialGeometry.Plane(normal: normal.map(NumericCalculus.clean), d: NumericCalculus.clean(d))
    }
}

private struct SpaceObjectSection: View {
    let title: String
    @Binding var input: SpaceObjectInput

    var body: some View {
        Section {
            Picker("Vrsta", selection: $input.kind) {
                ForEach(SpaceObjectInput.Kind.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            switch input.kind {
            case .point:
                VectorTextField(title: "T", text: $input.a)
            case .line:
                VectorTextField(title: "Točka A", text: $input.a)
                VectorTextField(title: "Smerni vektor s⃗", text: $input.b)
            case .plane:
                Picker("Podana z", selection: $input.planeForm) {
                    ForEach(SpaceObjectInput.PlaneForm.allCases) { Text($0.title).tag($0) }
                }
                planeFields
            }
            if let entity = input.entity {
                SpaceEntitySummary(entity: entity)
            } else {
                Text("Vnos ni popoln.").font(.caption).foregroundStyle(.secondary)
            }
        } header: {
            Text(title)
        } footer: {
            Text("Koordinate loči s podpičjem, npr. (1; −2; 0,5); ravnino zapiši kot 2x − y + 2z = 3.")
        }
    }

    @ViewBuilder
    private var planeFields: some View {
        switch input.planeForm {
        case .equation:
            TextField("2x − y + 2z = 3", text: $input.equation)
                .font(.system(.body, design: .monospaced))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .foregroundStyle(SpaceObjectInput.plane(input.equation) == nil ? Color.red : Color.primary)
        case .points:
            VectorTextField(title: "A", text: $input.a)
            VectorTextField(title: "B", text: $input.b)
            VectorTextField(title: "C", text: $input.c)
        case .normal:
            VectorTextField(title: "Točka A", text: $input.a)
            VectorTextField(title: "Normala n⃗", text: $input.b)
        }
    }
}

private struct VectorTextField: View {
    let title: String
    @Binding var text: String

    var body: some View {
        LabeledContent(title) {
            TextField("(x; y; z)", text: $text)
                .multilineTextAlignment(.trailing)
                .font(.body.monospacedDigit())
                .keyboardType(.numbersAndPunctuation)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .foregroundStyle(SpaceObjectInput.vector(text) == nil ? Color.red : Color.primary)
        }
    }
}

/// Numbers and vectors in the user's number format.
private struct SpaceFormat {
    let options: NumberFormatOptions

    func number(_ x: Double) -> String {
        NumberFormatting.format(NumericCalculus.clean(x), options: options).plainTextLocalized
    }

    func vector(_ v: [Double]) -> String {
        "(" + v.map(number).joined(separator: "; ") + ")"
    }

    func line(_ l: SpatialGeometry.Line) -> String {
        "r⃗ = " + vector(l.point) + " + t·" + vector(l.direction)
    }

    /// A value worth showing in closed form (√14/14, 2/3), not a whole number or a short decimal.
    static func exact(_ x: Double) -> Expr? {
        guard x.isFinite, x != x.rounded(), (x * 1000).rounded() != x * 1000,
              let e = ExactRecognizer.recognize(x), e.complexity <= 8 else { return nil }
        return e.expr
    }

    /// The plane as ax + by + cz + d = 0, with the smallest whole coefficients when they are whole.
    static func equation(_ plane: SpatialGeometry.Plane) -> Expr {
        var k = plane.normal + [plane.d]
        if let first = k.first(where: { $0 != 0 }), first < 0 { k = k.map { -$0 } }
        if k.allSatisfy({ $0 == $0.rounded() && Swift.abs($0) < 1e9 }) {
            let divisor = k.map { Int(Swift.abs($0)) }.reduce(0, gcd)
            if divisor > 1 { k = k.map { $0 / Double(divisor) } }
        }
        func coefficient(_ v: Double) -> Expr { ExactRecognizer.recognize(v)?.expr ?? .decimal(NumericCalculus.clean(v)) }
        let names = ["x", "y", "z"]
        var terms: [Expr] = []
        for i in 0..<3 where k[i] != 0 { terms.append(.product([coefficient(k[i]), .variable(names[i])])) }
        if k[3] != 0 { terms.append(coefficient(k[3])) }
        return .relation(Simplifier.simplify(.sum(terms)), .equal, .zero)
    }

    static func gcd(_ a: Int, _ b: Int) -> Int { b == 0 ? a : gcd(b, a % b) }
}

private struct SpaceEntitySummary: View {
    let entity: SpaceEntity
    @Environment(AppSettings.self) private var settings

    var body: some View {
        switch entity {
        case .point:
            EmptyView()
        case .line(let line):
            LabeledContent("Parametrično") {
                Text(SpaceFormat(options: settings.numberFormat).line(line)).font(.callout.monospacedDigit())
            }
        case .plane(let plane):
            LabeledContent("Enačba") { MathText(expr: SpaceFormat.equation(plane), fontSize: 16) }
        }
    }
}

private struct SpaceRelationSection: View {
    let first: SpaceEntity
    let second: SpaceEntity
    @Environment(AppSettings.self) private var settings

    private var format: SpaceFormat { SpaceFormat(options: settings.numberFormat) }

    var body: some View {
        Section("Rezultati") {
            switch (first, second) {
            case (.point(let p), .point(let q)):
                pointAndPoint(p, q)
            case (.point(let p), .line(let l)), (.line(let l), .point(let p)):
                pointAndLine(p, l)
            case (.point(let p), .plane(let e)), (.plane(let e), .point(let p)):
                pointAndPlane(p, e)
            case (.line(let a), .line(let b)):
                lineAndLine(a, b)
            case (.line(let l), .plane(let e)), (.plane(let e), .line(let l)):
                lineAndPlane(l, e)
            case (.plane(let a), .plane(let b)):
                planeAndPlane(a, b)
            }
        }
    }

    private func distanceRow(_ title: String, _ d: Double) -> some View {
        ResultRow(title: title, value: d, exact: SpaceFormat.exact(d))
    }

    private func lies(_ d: Double, _ points: [[Double]]) -> Bool {
        d <= 1e-9 * Swift.max(1, points.flatMap { $0 }.map(Swift.abs).max() ?? 1)
    }

    @ViewBuilder
    private func pointAndPoint(_ p: [Double], _ q: [Double]) -> some View {
        let v = zip(q, p).map(-)
        distanceRow("Razdalja |PQ|", VectorGeometry.length(v))
        LabeledContent("Vektor PQ⃗", value: format.vector(v))
        LabeledContent("Razpolovišče", value: format.vector(zip(p, q).map { ($0 + $1) / 2 }))
    }

    @ViewBuilder
    private func pointAndLine(_ p: [Double], _ l: SpatialGeometry.Line) -> some View {
        let d = SpatialGeometry.distance(p, l)
        if lies(d, [p, l.point]) {
            Label("Točka leži na premici.", systemImage: "checkmark.circle")
        } else {
            distanceRow("Razdalja točke od premice", d)
            LabeledContent("Pravokotna projekcija", value: format.vector(SpatialGeometry.projection(p, onto: l)))
            LabeledContent("Zrcalna slika točke", value: format.vector(SpatialGeometry.mirror(p, in: l)))
        }
    }

    @ViewBuilder
    private func pointAndPlane(_ p: [Double], _ e: SpatialGeometry.Plane) -> some View {
        let d = SpatialGeometry.distance(p, e)
        if lies(d, [p]) {
            Label("Točka leži v ravnini.", systemImage: "checkmark.circle")
        } else {
            distanceRow("Razdalja točke od ravnine", d)
            LabeledContent("Pravokotna projekcija", value: format.vector(SpatialGeometry.projection(p, onto: e)))
            LabeledContent("Zrcalna slika točke", value: format.vector(SpatialGeometry.mirror(p, in: e)))
        }
    }

    @ViewBuilder
    private func lineAndLine(_ a: SpatialGeometry.Line, _ b: SpatialGeometry.Line) -> some View {
        switch SpatialGeometry.position(a, b) {
        case .intersecting(let point):
            LabeledContent("Lega", value: "premici se sekata")
            LabeledContent("Presečišče", value: format.vector(point))
            AngleRow(title: "Kot med premicama", radians: SpatialGeometry.angle(a, b))
        case .parallel:
            LabeledContent("Lega", value: "vzporedni premici")
            distanceRow("Razdalja", SpatialGeometry.distance(a, b))
        case .identical:
            LabeledContent("Lega", value: "premici sovpadata")
        case .skew:
            LabeledContent("Lega", value: "mimobežni premici")
            distanceRow("Razdalja", SpatialGeometry.distance(a, b))
            if let feet = SpatialGeometry.closestPoints(a, b) {
                LabeledContent("Nožišči skupne pravokotnice", value: format.vector(feet.0) + ", " + format.vector(feet.1))
            }
            AngleRow(title: "Kot med premicama", radians: SpatialGeometry.angle(a, b))
        }
    }

    @ViewBuilder
    private func lineAndPlane(_ l: SpatialGeometry.Line, _ e: SpatialGeometry.Plane) -> some View {
        if let point = SpatialGeometry.intersection(l, e) {
            LabeledContent("Lega", value: "premica seka ravnino")
            LabeledContent("Presečišče", value: format.vector(point))
            AngleRow(title: "Kot med premico in ravnino", radians: SpatialGeometry.angle(l, e))
        } else {
            let d = SpatialGeometry.distance(l.point, e)
            if lies(d, [l.point]) {
                LabeledContent("Lega", value: "premica leži v ravnini")
            } else {
                LabeledContent("Lega", value: "premica je vzporedna ravnini")
                distanceRow("Razdalja", d)
            }
        }
    }

    @ViewBuilder
    private func planeAndPlane(_ a: SpatialGeometry.Plane, _ b: SpatialGeometry.Plane) -> some View {
        if let line = SpatialGeometry.intersection(a, b) {
            LabeledContent("Lega", value: "ravnini se sekata")
            LabeledContent("Presečnica", value: format.line(line))
            AngleRow(title: "Kot med ravninama", radians: SpatialGeometry.angle(a, b))
        } else {
            let d = SpatialGeometry.distance(a, b)
            if lies(d, []) {
                LabeledContent("Lega", value: "ravnini sovpadata")
            } else {
                LabeledContent("Lega", value: "vzporedni ravnini")
                distanceRow("Razdalja", d)
            }
        }
    }
}
