import AcuteCore
import SwiftUI

/// Solves a triangle from any three parts and draws it to scale.
struct TriangleToolView: View {
    @State private var a: Double?
    @State private var b: Double?
    @State private var c: Double?
    @State private var alpha: Double?
    @State private var beta: Double?
    @State private var gamma: Double?
    @Environment(AppSettings.self) private var settings

    private var result: Result<[Triangle], MathError>? {
        let known = [a, b, c, alpha, beta, gamma].compactMap { $0 }.count
        guard known >= 3 else { return nil }
        let toRadians = Double.pi / 180
        let input = TriangleInput(a: a, b: b, c: c, alpha: alpha.map { $0 * toRadians }, beta: beta.map { $0 * toRadians }, gamma: gamma.map { $0 * toRadians })
        return Result { () throws(MathError) -> [Triangle] in try TriangleSolver.solve(input) }
    }

    var body: some View {
        List {
            Section {
                NumberInputField(title: "a", value: $a)
                NumberInputField(title: "b", value: $b)
                NumberInputField(title: "c", value: $c)
                NumberInputField(title: "α (°)", value: $alpha)
                NumberInputField(title: "β (°)", value: $beta)
                NumberInputField(title: "γ (°)", value: $gamma)
                Button("Počisti", systemImage: "eraser", role: .destructive) {
                    a = nil; b = nil; c = nil; alpha = nil; beta = nil; gamma = nil
                }
            } header: {
                Text("Znani podatki (vsaj trije, ena stranica)")
            } footer: {
                Text("Stranica a leži nasproti kota α, b nasproti β, c nasproti γ.")
            }
            switch result {
            case .success(let triangles)?:
                if triangles.isEmpty {
                    Section { Text("Takega trikotnika ni.").foregroundStyle(.secondary) }
                }
                ForEach(Array(triangles.enumerated()), id: \.offset) { index, t in
                    TriangleResultSection(triangle: t, title: triangles.count > 1 ? "Rešitev \(index + 1)" : "Rešitev")
                }
            case .failure(let error)?:
                Section {
                    Label(error.errorDescription ?? error.shortDescription, systemImage: "exclamationmark.triangle").foregroundStyle(.red)
                }
            case nil:
                EmptyView()
            }
        }
        .listStyle(.insetGrouped)
        .scrollDismissesKeyboard(.interactively)
    }
}

private struct TriangleResultSection: View {
    let triangle: Triangle
    let title: String

    var body: some View {
        Section(title) {
            TriangleDrawing(triangle: triangle)
                .frame(height: 180)
            ResultRow(title: "a", value: triangle.a)
            ResultRow(title: "b", value: triangle.b)
            ResultRow(title: "c", value: triangle.c)
            AngleRow(title: "α", radians: triangle.alpha)
            AngleRow(title: "β", radians: triangle.beta)
            AngleRow(title: "γ", radians: triangle.gamma)
            ResultRow(title: "Obseg o", value: triangle.perimeter)
            ResultRow(title: "Ploščina S", value: triangle.area)
            ResultRow(title: "Polmer očrtane krožnice R", value: triangle.circumradius)
            ResultRow(title: "Polmer včrtane krožnice r", value: triangle.inradius)
            ResultRow(title: "Višina vₐ", value: triangle.heightA)
            ResultRow(title: "Višina v_b", value: triangle.heightB)
            ResultRow(title: "Višina v_c", value: triangle.heightC)
            ResultRow(title: "Težiščnica tₐ", value: triangle.medianA)
            LabeledContent("Vrsta", value: kind)
        }
    }

    private var kind: String {
        let angles = [triangle.alpha, triangle.beta, triangle.gamma]
        let byAngle = angles.contains { Swift.abs($0 - .pi / 2) < 1e-9 } ? "pravokoten" : (angles.contains { $0 > .pi / 2 } ? "topokoten" : "ostrokoten")
        let sides = [triangle.a, triangle.b, triangle.c]
        func same(_ x: Double, _ y: Double) -> Bool { Swift.abs(x - y) < 1e-9 * max(1, x) }
        let bySide = same(sides[0], sides[1]) && same(sides[1], sides[2]) ? "enakostraničen"
            : (same(sides[0], sides[1]) || same(sides[1], sides[2]) || same(sides[0], sides[2]) ? "enakokrak" : "raznostraničen")
        return "\(bySide), \(byAngle)"
    }
}

/// An angle in degrees and degrees–minutes–seconds.
struct AngleRow: View {
    let title: String
    let radians: Double
    @Environment(AppSettings.self) private var settings

    var body: some View {
        let degrees = radians * 180 / .pi
        let dms = NumberFormatting.sexagesimal(degrees, secondsDigits: 4)
        LabeledContent(title) {
            VStack(alignment: .trailing, spacing: 0) {
                Text(NumberFormatting.format(degrees, options: settings.numberFormat).plainTextLocalized + "°")
                    .font(.body.monospacedDigit())
                if let dms {
                    Text("\(dms.degrees)° \(dms.minutes)′ \(NumberFormatting.format(dms.seconds, options: NumberFormatOptions(mode: .norm1, significantDigits: 4, decimalSeparator: settings.decimalSeparator)).mantissa)″")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// The triangle drawn to scale with its vertices and sides labelled.
struct TriangleDrawing: View {
    let triangle: Triangle

    var body: some View {
        Canvas { context, size in
            // A at the origin, B on the x axis, C above.
            let A = CGPoint(x: 0, y: 0)
            let B = CGPoint(x: triangle.c, y: 0)
            let C = CGPoint(x: triangle.b * cos(triangle.alpha), y: triangle.b * sin(triangle.alpha))
            let xs = [A.x, B.x, C.x], ys = [A.y, B.y, C.y]
            let minX = xs.min()!, maxX = xs.max()!, minY = ys.min()!, maxY = ys.max()!
            let padding: CGFloat = 26
            let scale = min((size.width - 2 * padding) / max(maxX - minX, 1e-9), (size.height - 2 * padding) / max(maxY - minY, 1e-9))
            func map(_ p: CGPoint) -> CGPoint {
                let x = padding + (p.x - minX) * scale + (size.width - 2 * padding - (maxX - minX) * scale) / 2
                return CGPoint(x: x, y: size.height - padding - (p.y - minY) * scale)
            }
            let a = map(A), b = map(B), c = map(C)
            var path = Path()
            path.move(to: a)
            path.addLine(to: b)
            path.addLine(to: c)
            path.closeSubpath()
            context.fill(path, with: .color(.accentColor.opacity(0.15)))
            context.stroke(path, with: .color(.accentColor), lineWidth: 2)
            let center = CGPoint(x: (a.x + b.x + c.x) / 3, y: (a.y + b.y + c.y) / 3)
            func label(_ text: String, at p: CGPoint, awayFrom q: CGPoint, italic: Bool = false) {
                let dx = p.x - q.x, dy = p.y - q.y
                let length = max(1, (dx * dx + dy * dy).squareRoot())
                let position = CGPoint(x: p.x + dx / length * 14, y: p.y + dy / length * 14)
                context.draw(Text(text).font(italic ? .callout.italic() : .callout.weight(.semibold)), at: position)
            }
            label("A", at: a, awayFrom: center)
            label("B", at: b, awayFrom: center)
            label("C", at: c, awayFrom: center)
            func mid(_ p: CGPoint, _ q: CGPoint) -> CGPoint { CGPoint(x: (p.x + q.x) / 2, y: (p.y + q.y) / 2) }
            label("a", at: mid(b, c), awayFrom: center, italic: true)
            label("b", at: mid(a, c), awayFrom: center, italic: true)
            label("c", at: mid(a, b), awayFrom: center, italic: true)
        }
        .accessibilityLabel("Skica trikotnika")
    }
}

/// Vectors in the plane or space: lengths, products, angle, projection, areas and volume.
struct VectorToolView: View {
    @AppStorage("vectorDimension") private var dimension = 3
    @State private var a: [Double?] = [1, 2, 2]
    @State private var b: [Double?] = [3, 0, 4]
    @State private var c: [Double?] = [nil, nil, nil]
    @Environment(AppSettings.self) private var settings

    var body: some View {
        List {
            Section {
                Picker("Prostor", selection: $dimension) {
                    Text("Ravnina (2D)").tag(2)
                    Text("Prostor (3D)").tag(3)
                }
                .pickerStyle(.segmented)
            }
            vectorInput("a⃗", $a)
            vectorInput("b⃗", $b)
            vectorInput("c⃗ (za mešani produkt)", $c)
            if let va = values(a), let vb = values(b) {
                Section("Rezultati") {
                    ResultRow(title: "|a⃗|", value: VectorGeometry.length(va))
                    ResultRow(title: "|b⃗|", value: VectorGeometry.length(vb))
                    LabeledContent("a⃗ + b⃗", value: format(zip(va, vb).map(+)))
                    LabeledContent("a⃗ − b⃗", value: format(zip(va, vb).map(-)))
                    ResultRow(title: "a⃗ · b⃗", value: VectorGeometry.dot(va, vb))
                    if let angle = VectorGeometry.angle(va, vb) {
                        AngleRow(title: "∢(a⃗, b⃗)", radians: angle)
                    }
                    if dimension == 3 {
                        LabeledContent("a⃗ × b⃗", value: format(VectorGeometry.cross(va, vb)))
                    }
                    ResultRow(title: "Ploščina paralelograma", value: VectorGeometry.parallelogramArea(va, vb))
                    ResultRow(title: "Ploščina trikotnika", value: VectorGeometry.parallelogramArea(va, vb) / 2)
                    if let projection = VectorGeometry.projection(va, onto: vb) {
                        LabeledContent("Pravokotna projekcija a⃗ na b⃗", value: format(projection))
                    }
                    if VectorGeometry.length(va) > 0 {
                        LabeledContent("Enotski vektor a⃗₀", value: format(va.map { $0 / VectorGeometry.length(va) }))
                    }
                    LabeledContent("Odnos", value: relation(va, vb))
                }
                if dimension == 3, let vc = values(c) {
                    Section("Mešani produkt") {
                        ResultRow(title: "(a⃗ × b⃗) · c⃗", value: VectorGeometry.mixedProduct(va, vb, vc))
                        ResultRow(title: "Prostornina paralelepipeda", value: Swift.abs(VectorGeometry.mixedProduct(va, vb, vc)))
                        ResultRow(title: "Prostornina tetraedra", value: Swift.abs(VectorGeometry.mixedProduct(va, vb, vc)) / 6)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollDismissesKeyboard(.interactively)
    }

    private func vectorInput(_ title: String, _ vector: Binding<[Double?]>) -> some View {
        Section(title) {
            let names = ["x", "y", "z"]
            ForEach(0..<dimension, id: \.self) { i in
                NumberInputField(title: names[i], value: vector[i])
            }
        }
    }

    private func values(_ v: [Double?]) -> [Double]? {
        let components = Array(v.prefix(dimension))
        guard components.allSatisfy({ $0 != nil }) else { return nil }
        return components.map { $0! }
    }

    private func format(_ v: [Double]) -> String {
        "(" + v.map { NumberFormatting.format(NumericCalculus.clean($0), options: settings.numberFormat).plainTextLocalized }.joined(separator: "; ") + ")"
    }

    private func relation(_ a: [Double], _ b: [Double]) -> String {
        let dot = VectorGeometry.dot(a, b)
        let scale = max(1e-12, VectorGeometry.length(a) * VectorGeometry.length(b))
        if Swift.abs(dot) / scale < 1e-12 { return "pravokotna (a⃗ · b⃗ = 0)" }
        if VectorGeometry.length(VectorGeometry.cross(a, b)) / scale < 1e-12 { return "kolinearna (vzporedna)" }
        return "splošna lega"
    }
}
