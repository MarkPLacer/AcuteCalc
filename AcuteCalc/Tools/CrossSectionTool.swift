import AcuteCore
import SwiftUI

/// Cross-sections for statics and strength of materials: rectangles, circles, circular
/// sectors and polygons, openings subtracted; centroid, second moments, principal axes.
struct CrossSectionToolView: View {
    // A T-section: a 20 × 4 flange on a 4 × 16 web.
    @State private var parts = [
        SectionPartInput(kind: .rectangle, x: -10, y: 16, width: 20, height: 4),
        SectionPartInput(kind: .rectangle, x: -2, y: 0, width: 4, height: 16),
    ]

    var body: some View {
        let result = compute()
        List {
            Section {
                CrossSectionDrawing(parts: parts.compactMap { input in input.part.map { (part: $0, hole: input.hole) } },
                                    properties: try? result.get())
                    .frame(height: 260)
                    .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
            } footer: {
                Text("Prerez sestavi iz delov; odprtine se odštejejo. Primer: T-prerez iz pasnice 20 × 4 in stojine 4 × 16.")
            }
            ForEach($parts) { $part in
                let number = (parts.firstIndex(where: { $0.id == part.id }) ?? 0) + 1
                SectionPartEditor(part: $part, title: "Del \(number)") {
                    parts.removeAll { $0.id == part.id }
                }
            }
            Section {
                Button("Dodaj del", systemImage: "plus.circle") { parts.append(SectionPartInput(kind: .rectangle)) }
            }
            CrossSectionResults(result: result)
        }
        .listStyle(.insetGrouped)
        .scrollDismissesKeyboard(.interactively)
    }

    private func compute() -> Result<CrossSection.Properties, MathError> {
        let list = parts.compactMap { input in input.part.map { (part: $0, hole: input.hole) } }
        guard !parts.isEmpty, list.count == parts.count else { return .failure(.incomplete) }
        do throws(MathError) {
            return .success(try CrossSection.properties(list))
        } catch {
            return .failure(error)
        }
    }
}

struct SectionPartInput: Identifiable, Equatable {
    enum Kind: String, CaseIterable, Identifiable {
        case rectangle, circle, sector, polygon
        var id: String { rawValue }
        var title: String {
            switch self {
            case .rectangle: "Pravokotnik"
            case .circle: "Krog"
            case .sector: "Krožni izsek"
            case .polygon: "Mnogokotnik"
            }
        }
    }

    let id = UUID()
    var kind: Kind
    var hole = false
    var x: Double? = 0
    var y: Double? = 0
    var width: Double? = 4
    var height: Double? = 2
    var radius: Double? = 2
    /// Sector angles in degrees, counterclockwise from the x axis.
    var from: Double? = 0
    var to: Double? = 180
    var vertices = "0; 0\n6; 0\n0; 3"

    var part: CrossSection.Part? {
        switch kind {
        case .rectangle:
            guard let x, let y, let width, let height else { return nil }
            return .rectangle(x: x, y: y, width: width, height: height)
        case .circle:
            guard let x, let y, let radius else { return nil }
            return .circle(center: SIMD2(x, y), radius: radius)
        case .sector:
            guard let x, let y, let radius, let from, let to else { return nil }
            return .sector(center: SIMD2(x, y), radius: radius, from: from * .pi / 180, to: to * .pi / 180)
        case .polygon:
            let points = SectionPartInput.points(vertices)
            return points.count >= 3 ? .polygon(points) : nil
        }
    }

    /// One vertex per line: "x; y", "x y" or "x, y".
    static func points(_ text: String) -> [SIMD2<Double>] {
        var result: [SIMD2<Double>] = []
        for line in text.split(whereSeparator: \.isNewline) {
            let s = String(line)
            if s.allSatisfy(\.isWhitespace) { continue }
            let parts: [Substring]
            if s.contains(";") {
                parts = s.split(separator: ";")
            } else if s.contains(where: \.isWhitespace) {
                parts = s.split(whereSeparator: \.isWhitespace)
            } else {
                parts = s.split(separator: ",")
            }
            let values = parts.compactMap { ExpressionNumberField.parse(String($0)) }
            guard parts.count == 2, values.count == 2 else { return [] }
            result.append(SIMD2(values[0], values[1]))
        }
        return result
    }
}

private struct SectionPartEditor: View {
    @Binding var part: SectionPartInput
    let title: String
    let onDelete: () -> Void

    var body: some View {
        Section {
            Picker("Oblika", selection: $part.kind) {
                ForEach(SectionPartInput.Kind.allCases) { Text($0.title).tag($0) }
            }
            Toggle("Odprtina (odštej)", isOn: $part.hole)
            fields
        } header: {
            HStack {
                Text(title)
                Spacer()
                Button("Odstrani", systemImage: "trash", role: .destructive, action: onDelete)
                    .labelStyle(.iconOnly)
            }
        } footer: {
            switch part.kind {
            case .sector: Text("Kota merimo od osi x v nasprotni smeri urinega kazalca: polkrog 0°–180°, četrtina kroga 0°–90°.")
            case .polygon: Text("Oglišča po vrsti, v vsaki vrstici x; y.")
            case .rectangle, .circle: EmptyView()
            }
        }
    }

    @ViewBuilder
    private var fields: some View {
        switch part.kind {
        case .rectangle:
            NumberInputField(title: "x levega spodnjega oglišča", value: $part.x)
            NumberInputField(title: "y levega spodnjega oglišča", value: $part.y)
            NumberInputField(title: "Širina b", value: $part.width)
            NumberInputField(title: "Višina h", value: $part.height)
        case .circle:
            NumberInputField(title: "Središče x", value: $part.x)
            NumberInputField(title: "Središče y", value: $part.y)
            NumberInputField(title: "Polmer r", value: $part.radius)
        case .sector:
            NumberInputField(title: "Središče x", value: $part.x)
            NumberInputField(title: "Središče y", value: $part.y)
            NumberInputField(title: "Polmer r", value: $part.radius)
            NumberInputField(title: "Od kota (°)", value: $part.from)
            NumberInputField(title: "Do kota (°)", value: $part.to)
        case .polygon:
            TextField("x; y", text: $part.vertices, axis: .vertical)
                .lineLimit(3...10)
                .font(.body.monospacedDigit())
                .autocorrectionDisabled()
                .foregroundStyle(SectionPartInput.points(part.vertices).count >= 3 ? Color.primary : Color.red)
        }
    }
}

private struct CrossSectionResults: View {
    let result: Result<CrossSection.Properties, MathError>

    var body: some View {
        switch result {
        case .success(let p):
            Section("Ploščina in težišče") {
                ResultRow(title: "A", value: p.area)
                ResultRow(title: "x_T", value: p.centroid.x)
                ResultRow(title: "y_T", value: p.centroid.y)
            }
            Section {
                ResultRow(title: "I_x = ∫y² dA", value: p.ix)
                ResultRow(title: "I_y = ∫x² dA", value: p.iy)
                ResultRow(title: "I_xy = ∫xy dA", value: p.ixy)
                ResultRow(title: "I_p = I_x + I_y", value: p.polar)
            } header: {
                Text("Vztrajnostni momenti glede na težiščni osi")
            } footer: {
                Text("Steinerjev izrek: I_x = Σ (I_x,i + A_i·d_i²); odprtine štejejo z negativno ploščino.")
            }
            Section {
                ResultRow(title: "I₁", value: p.i1)
                ResultRow(title: "I₂", value: p.i2)
                AngleRow(title: "Kot osi 1 od osi x", radians: p.principalAngle)
            } header: {
                Text("Glavni vztrajnostni momenti")
            } footer: {
                Text("I₁,₂ = (I_x + I_y)/2 ± √(((I_x − I_y)/2)² + I_xy²), tg 2α = −2I_xy/(I_x − I_y). Na skici oranžno.")
            }
            Section("Vztrajnostna polmera in odpornostna momenta") {
                ResultRow(title: "i_x = √(I_x/A)", value: p.radiusX)
                ResultRow(title: "i_y = √(I_y/A)", value: p.radiusY)
                ResultRow(title: "W_x = I_x/e_y", value: p.sectionModulusX)
                ResultRow(title: "W_y = I_y/e_x", value: p.sectionModulusY)
            }
        case .failure(let error):
            Section {
                Text(error == .incomplete ? "Izpolni podatke vseh delov." : (error.errorDescription ?? error.shortDescription))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// The section to scale: solid parts filled, openings cut out, the centroid with the
/// centroidal axes (dashed) and the principal axes (orange).
private struct CrossSectionDrawing: View {
    let parts: [(part: CrossSection.Part, hole: Bool)]
    let properties: CrossSection.Properties?

    var body: some View {
        Canvas { context, size in
            let outlines = parts.map { (points: CrossSectionDrawing.outline($0.part), hole: $0.hole) }
            let all = outlines.flatMap { $0.points }
            guard let minX = all.map(\.x).min(), let maxX = all.map(\.x).max(),
                  let minY = all.map(\.y).min(), let maxY = all.map(\.y).max() else { return }
            let padding = 24.0
            let width = Double(size.width) - 2 * padding, height = Double(size.height) - 2 * padding
            let scale = Swift.min(width / Swift.max(maxX - minX, 1e-9), height / Swift.max(maxY - minY, 1e-9))
            let midX = (minX + maxX) / 2, midY = (minY + maxY) / 2
            func point(_ p: SIMD2<Double>) -> CGPoint {
                CGPoint(x: Double(size.width) / 2 + (p.x - midX) * scale, y: Double(size.height) / 2 - (p.y - midY) * scale)
            }
            func path(_ points: [SIMD2<Double>]) -> Path {
                var path = Path()
                path.addLines(points.map(point))
                path.closeSubpath()
                return path
            }
            context.drawLayer { layer in
                for outline in outlines where !outline.hole {
                    layer.fill(path(outline.points), with: .color(.accentColor.opacity(0.3)))
                }
                layer.blendMode = .destinationOut
                for outline in outlines where outline.hole {
                    layer.fill(path(outline.points), with: .color(.black))
                }
            }
            for outline in outlines {
                context.stroke(path(outline.points), with: .color(outline.hole ? .secondary : .accentColor), lineWidth: 1.5)
            }
            guard let properties else { return }
            let c = point(properties.centroid)
            let reach = Double(Swift.max(size.width, size.height))
            func axis(_ angle: Double) -> Path {
                var path = Path()
                path.move(to: CGPoint(x: c.x - cos(angle) * reach, y: c.y + sin(angle) * reach))
                path.addLine(to: CGPoint(x: c.x + cos(angle) * reach, y: c.y - sin(angle) * reach))
                return path
            }
            let dashed = StrokeStyle(lineWidth: 1, dash: [5, 4])
            context.stroke(axis(0), with: .color(.secondary), style: dashed)
            context.stroke(axis(.pi / 2), with: .color(.secondary), style: dashed)
            if Swift.abs(properties.i1 - properties.i2) > 1e-9 * Swift.max(1, properties.i1) {
                context.stroke(axis(properties.principalAngle), with: .color(.orange), lineWidth: 1.5)
                context.stroke(axis(properties.principalAngle + .pi / 2), with: .color(.orange.opacity(0.55)), lineWidth: 1.5)
            }
            context.fill(Path(ellipseIn: CGRect(x: c.x - 4, y: c.y - 4, width: 8, height: 8)), with: .color(.red))
            context.draw(Text("T").font(.caption.weight(.semibold)), at: CGPoint(x: c.x + 10, y: c.y - 10))
        }
        .clipped()
        .accessibilityLabel("Skica prereza s težiščem in glavnima osema")
    }

    /// The outline of a part as a polygon (arcs in small steps).
    nonisolated static func outline(_ part: CrossSection.Part) -> [SIMD2<Double>] {
        switch part {
        case .rectangle(let x, let y, let b, let h):
            return [SIMD2(x, y), SIMD2(x + b, y), SIMD2(x + b, y + h), SIMD2(x, y + h)]
        case .circle(let c, let r):
            return arc(c, r, from: 0, to: 2 * .pi, steps: 96, includingEnd: false)
        case .sector(let c, let r, let from, let to):
            if to - from >= 2 * .pi - 1e-9 { return arc(c, r, from: from, to: to, steps: 96, includingEnd: false) }
            return [c] + arc(c, r, from: from, to: to, steps: 64, includingEnd: true)
        case .polygon(let p):
            return p
        }
    }

    nonisolated static func arc(_ c: SIMD2<Double>, _ r: Double, from: Double, to: Double, steps: Int, includingEnd: Bool) -> [SIMD2<Double>] {
        (0...(includingEnd ? steps : steps - 1)).map { i in
            let t = from + (to - from) * Double(i) / Double(steps)
            return c + r * SIMD2(cos(t), sin(t))
        }
    }
}
