import AcuteCore
import SwiftUI

/// Sets for the matura: intervals on the number line with ∪, ∩, \ and complements, and Venn
/// diagrams of two or three sets with the shaded regions of an expression and their counts.
struct SetsToolView: View {
    enum Mode: String, CaseIterable, Identifiable {
        case line, venn
        var id: String { rawValue }
        var title: String {
            switch self {
            case .line: "Številska premica"
            case .venn: "Vennov diagram"
            }
        }
    }

    @AppStorage("setsMode") private var mode = Mode.line
    @AppStorage("setsA") private var textA = "[-2; 3)"
    @AppStorage("setsB") private var textB = "x > 1"
    @AppStorage("setsC") private var textC = "{0; 2; 5}"
    @AppStorage("setsExpression") private var expressionText = "(A ∪ B) ∩ C′"
    @AppStorage("vennSets") private var vennSets = 2
    @AppStorage("vennExpression") private var vennText = "A ∩ B′"
    @State private var counts: [Double?] = [30, 18, 12, nil, 5, nil, nil, nil]

    var body: some View {
        List {
            Section {
                Picker("Prikaz", selection: $mode) {
                    ForEach(Mode.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            switch mode {
            case .line: lineSections
            case .venn: vennSections
            }
        }
        .listStyle(.insetGrouped)
        .scrollDismissesKeyboard(.interactively)
    }

    // MARK: Number line

    private var sets: [SetAlgebra.RealSet?] { [textA, textB, textC].map(SetAlgebra.RealSet.parse) }

    @ViewBuilder
    private var lineSections: some View {
        let sets = self.sets
        Section {
            setField("A", $textA, valid: sets[0] != nil)
            setField("B", $textB, valid: sets[1] != nil)
            setField("C", $textC, valid: sets[2] != nil || textC.trimmingCharacters(in: .whitespaces).isEmpty)
        } header: {
            Text("Množice")
        } footer: {
            Text("Interval [−2; 3), (1; ∞), števila {0; 2; 5}, unija z ∪, ℝ, ∅ ali neenačba, npr. x² < 4, −1 ≤ x < 2, |x − 1| ≥ 2. Med krajišči podpičje (decimalna vejica) ali vejica (decimalna pika).")
        }
        Section("Izraz") {
            ExpressionEditor(text: $expressionText, names: ["A", "B", "C"])
            if let expression = SetAlgebra.Expression.parse(expressionText) {
                if let value = expression.evaluate(sets) {
                    let lineRows = rows(sets, result: value)
                    InequalitySolutionView(solution: value.solution, fontSize: 22, label: expressionText.trimmingCharacters(in: .whitespaces))
                    NumberLine(rows: lineRows)
                        .frame(height: CGFloat(lineRows.count) * 34 + 30)
                } else {
                    Text("Vnesi vse množice, ki nastopajo v izrazu.").foregroundStyle(.secondary)
                }
            } else {
                Text("Izraz zapiši z A, B, C, ∪, ∩, \\, ′ in oklepaji.").foregroundStyle(.secondary)
            }
        }
        if let a = sets[0], let b = sets[1] {
            Section("Osnovne operacije") {
                setRow("A ∪ B", a.union(b))
                setRow("A ∩ B", a.intersection(b))
                setRow("A \\ B", a.subtracting(b))
                setRow("B \\ A", b.subtracting(a))
                setRow("A′", a.complement)
                setRow("B′", b.complement)
            }
        }
    }

    private func setField(_ name: String, _ text: Binding<String>, valid: Bool) -> some View {
        LabeledContent(name + " =") {
            TextField("[a; b)", text: text)
                .multilineTextAlignment(.trailing)
                .font(.body.monospacedDigit())
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .foregroundStyle(valid ? Color.primary : Color.red)
        }
    }

    private func setRow(_ name: String, _ value: SetAlgebra.RealSet) -> some View {
        InequalitySolutionView(solution: value.solution, fontSize: 19, label: name)
    }

    private func rows(_ sets: [SetAlgebra.RealSet?], result: SetAlgebra.RealSet) -> [NumberLine.Row] {
        let colors: [Color] = [.accentColor, .orange, .green]
        var rows: [NumberLine.Row] = []
        for (i, value) in sets.enumerated() {
            if let value { rows.append(NumberLine.Row(name: ["A", "B", "C"][i], set: value, color: colors[i])) }
        }
        rows.append(NumberLine.Row(name: "izraz", set: result, color: .red))
        return rows
    }

    // MARK: Venn diagram

    @ViewBuilder
    private var vennSections: some View {
        let names = Array(SetAlgebra.Expression.names.prefix(vennSets))
        let expression = SetAlgebra.Expression.parse(vennText).flatMap { $0.sets.allSatisfy { $0 < vennSets } ? $0 : nil }
        let known = regionCounts()
        Section {
            Stepper("Množice: " + names.joined(separator: ", "), value: $vennSets, in: 2...3)
            ExpressionEditor(text: $vennText, names: names)
            VennDiagram(sets: vennSets, shaded: expression?.regions(of: vennSets) ?? [], counts: try? known?.get())
                .frame(height: 240)
                .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
            if expression == nil {
                Text("Izraz zapiši z " + names.joined(separator: ", ") + ", ∪, ∩, \\, ′ in oklepaji.").foregroundStyle(.secondary)
            }
        } header: {
            Text("Izraz")
        } footer: {
            Text("Osenčen je izraz; U je univerzalna množica.")
        }
        Section {
            ForEach(countFields) { field in
                NumberInputField(title: field.title, value: $counts[field.index])
            }
            switch known {
            case .success(let values)?:
                if let expression {
                    // An unknown region asks for n(U); a total beyond the doubles is an error.
                    switch Result(catching: { () throws(MathError) -> Double? in try SetAlgebra.count(expression.regions(of: vennSets), in: values) }) {
                    case .success(let total?):
                        ResultRow(title: "n(" + vennText.trimmingCharacters(in: .whitespaces) + ")", value: total)
                    case .success(.none):
                        Text("Za ta izraz vnesi še n(U).").foregroundStyle(.secondary)
                    case .failure(let error):
                        Label(error.errorDescription ?? error.shortDescription, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                    }
                }
            case .failure(let error)?:
                Label(error.errorDescription ?? error.shortDescription, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
            case nil:
                EmptyView()
            }
        } header: {
            Text("Število elementov (neobvezno)")
        } footer: {
            Text("Iz moči množic in presekov dobiš število elementov vsakega področja (načelo vključitve in izključitve).")
        }
    }

    private struct CountField: Identifiable {
        let index: Int
        let title: String
        var id: Int { index }
    }

    /// The fields of `counts`: n(U), the sets and their intersections.
    private var countFields: [CountField] {
        let all = [(0, "n(U)"), (1, "n(A)"), (2, "n(B)"), (3, "n(C)"), (4, "n(A ∩ B)"), (5, "n(A ∩ C)"), (6, "n(B ∩ C)"), (7, "n(A ∩ B ∩ C)")]
        let used = vennSets == 2 ? [0, 1, 2, 4] : Array(0..<8)
        return used.map { CountField(index: all[$0].0, title: all[$0].1) }
    }

    /// The counts of the regions when the sets and their intersections are given.
    private func regionCounts() -> Result<[Int: Double], MathError>? {
        let n = counts
        if vennSets == 2 {
            guard let a = n[1], let b = n[2], let ab = n[4] else { return nil }
            return Result { () throws(MathError) -> [Int: Double] in try SetAlgebra.regionCounts(universe: n[0], a: a, b: b, ab: ab) }
        }
        guard let a = n[1], let b = n[2], let c = n[3], let ab = n[4], let ac = n[5], let bc = n[6], let abc = n[7] else { return nil }
        return Result { () throws(MathError) -> [Int: Double] in
            try SetAlgebra.regionCounts(universe: n[0], a: a, b: b, c: c, ab: ab, ac: ac, bc: bc, abc: abc)
        }
    }
}

/// A text field for a set expression with buttons for the set symbols.
private struct ExpressionEditor: View {
    @Binding var text: String
    let names: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("(A ∪ B) ∩ C′", text: $text)
                .font(.title3.monospaced())
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .foregroundStyle(SetAlgebra.Expression.parse(text) == nil ? Color.red : Color.primary)
            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    ForEach(names + ["∪", "∩", "\\", "′", "(", ")"], id: \.self) { symbol in
                        Button(symbol) { text += symbol }
                            .buttonStyle(.bordered)
                            .font(.body.monospaced())
                    }
                    Button("Izbriši zadnji znak", systemImage: "delete.left") { if !text.isEmpty { text.removeLast() } }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.bordered)
                }
            }
            .scrollIndicators(.hidden)
        }
    }
}

/// The sets as thick lines over one number line: filled ends belong to the set, hollow ones
/// do not, arrows go on to infinity.
private struct NumberLine: View {
    struct Row: Identifiable {
        var name: String
        var set: SetAlgebra.RealSet
        var color: Color
        var id: String { name }
    }

    let rows: [Row]
    @Environment(AppSettings.self) private var settings

    var body: some View {
        Canvas { context, size in
            let ends = rows.flatMap { $0.set.intervals.flatMap { [$0.lower, $0.upper] } }.filter(\.isFinite)
            var low = ends.min() ?? -1, high = ends.max() ?? 1
            if high - low < 1e-9 { low -= 1; high += 1 }
            let margin = (high - low) * 0.18
            low -= margin
            high += margin
            let left = 52.0, right = Double(size.width) - 14
            func x(_ v: Double) -> Double { left + (v - low) / (high - low) * (right - left) }
            let axisY = Double(size.height) - 22
            // The axis with the ends of all sets marked.
            var axis = Path()
            axis.move(to: CGPoint(x: left, y: axisY))
            axis.addLine(to: CGPoint(x: right, y: axisY))
            context.stroke(axis, with: .color(.secondary), lineWidth: 1)
            var labelled: [Double] = []
            for value in Set(ends).sorted() where !labelled.contains(where: { Swift.abs(x($0) - x(value)) < 26 }) {
                labelled.append(value)
                var tick = Path()
                tick.move(to: CGPoint(x: x(value), y: axisY - 4))
                tick.addLine(to: CGPoint(x: x(value), y: axisY + 4))
                context.stroke(tick, with: .color(.secondary), lineWidth: 1)
                context.draw(Text(NumberFormatting.format(NumericCalculus.clean(value), options: settings.numberFormat).plainTextLocalized)
                                .font(.caption2).foregroundStyle(.secondary),
                             at: CGPoint(x: x(value), y: axisY + 13))
            }
            for (k, row) in rows.enumerated() {
                let y = 16 + Double(k) * 34
                context.draw(Text(row.name).font(.caption.weight(.semibold)).foregroundStyle(row.color), at: CGPoint(x: 22, y: y))
                for interval in row.set.intervals {
                    let a = x(Swift.max(interval.lower, low)), b = x(Swift.min(interval.upper, high))
                    if interval.lower == interval.upper {
                        dot(at: CGPoint(x: a, y: y), filled: true, color: row.color, in: &context)
                        continue
                    }
                    var line = Path()
                    line.move(to: CGPoint(x: a, y: y))
                    line.addLine(to: CGPoint(x: b, y: y))
                    context.stroke(line, with: .color(row.color), style: StrokeStyle(lineWidth: 4, lineCap: .butt))
                    for (end, value, included, direction) in [(a, interval.lower, interval.lowerIncluded, -1.0), (b, interval.upper, interval.upperIncluded, 1.0)] {
                        if value.isFinite {
                            dot(at: CGPoint(x: end, y: y), filled: included, color: row.color, in: &context)
                        } else {
                            var head = Path()
                            head.move(to: CGPoint(x: end + direction * 2, y: y))
                            head.addLine(to: CGPoint(x: end - direction * 8, y: y - 6))
                            head.addLine(to: CGPoint(x: end - direction * 8, y: y + 6))
                            head.closeSubpath()
                            context.fill(head, with: .color(row.color))
                        }
                    }
                }
            }
        }
        .accessibilityLabel("Množice na številski premici")
    }

    private func dot(at p: CGPoint, filled: Bool, color: Color, in context: inout GraphicsContext) {
        let circle = Path(ellipseIn: CGRect(x: p.x - 5, y: p.y - 5, width: 10, height: 10))
        context.fill(circle, with: .color(filled ? color : Color(.systemBackground)))
        context.stroke(circle, with: .color(color), lineWidth: 2)
    }
}

/// The universal set with two or three circles; the regions of the expression shaded and the
/// number of elements written in each region when it is known.
private struct VennDiagram: View {
    let sets: Int
    let shaded: Set<Int>
    let counts: [Int: Double]?
    @Environment(AppSettings.self) private var settings

    var body: some View {
        Canvas { context, size in
            let frame = CGRect(origin: .zero, size: size).insetBy(dx: 6, dy: 6)
            let w = Double(frame.width), h = Double(frame.height)
            let cx = Double(frame.midX), cy = Double(frame.midY)
            let r = sets == 2 ? Swift.min(w / 3.4, h / 2.4) : Swift.min(w / 3.4, h / 3.2)
            let centers: [CGPoint] = sets == 2
                ? [CGPoint(x: cx - 0.55 * r, y: cy), CGPoint(x: cx + 0.55 * r, y: cy)]
                : [CGPoint(x: cx - 0.55 * r, y: cy - 0.45 * r), CGPoint(x: cx + 0.55 * r, y: cy - 0.45 * r), CGPoint(x: cx, y: cy + 0.45 * r)]
            let circles = centers.map { Path(ellipseIn: CGRect(x: $0.x - r, y: $0.y - r, width: 2 * r, height: 2 * r)) }
            let universe = Path(roundedRect: frame, cornerRadius: 10)
            // Each region: inside its sets, outside the others.
            for region in shaded {
                var path = universe
                for (i, circle) in circles.enumerated() {
                    path = region & (1 << i) != 0 ? path.intersection(circle) : path.subtracting(circle)
                }
                context.fill(path, with: .color(Color.accentColor.opacity(0.35)))
            }
            context.stroke(universe, with: .color(.secondary), lineWidth: 1.5)
            context.draw(Text("U").font(.callout.weight(.semibold)).foregroundStyle(.secondary), at: CGPoint(x: frame.minX + 14, y: frame.minY + 14))
            let names = ["A", "B", "C"]
            let nameOffsets: [CGPoint] = sets == 2
                ? [CGPoint(x: -0.75, y: -0.8), CGPoint(x: 0.75, y: -0.8)]
                : [CGPoint(x: -0.85, y: -0.75), CGPoint(x: 0.85, y: -0.75), CGPoint(x: 0.85, y: 0.75)]
            for (i, circle) in circles.enumerated() {
                context.stroke(circle, with: .color(.primary), lineWidth: 1.5)
                let p = CGPoint(x: centers[i].x + nameOffsets[i].x * r, y: centers[i].y + nameOffsets[i].y * r)
                context.draw(Text(names[i]).font(.headline), at: p)
            }
            guard let counts else { return }
            for (region, value) in counts {
                let p = labelPosition(region, cx: cx, cy: cy, r: r, frame: frame)
                context.draw(Text(NumberFormatting.format(NumericCalculus.clean(value), options: settings.numberFormat).plainTextLocalized)
                                .font(.callout.monospacedDigit().weight(.medium)),
                             at: p)
            }
        }
        .accessibilityLabel("Vennov diagram z osenčenim izrazom")
    }

    /// A point inside each region for its number.
    private func labelPosition(_ region: Int, cx: Double, cy: Double, r: Double, frame: CGRect) -> CGPoint {
        if region == 0 { return CGPoint(x: frame.maxX - 22, y: frame.maxY - 16) }
        if sets == 2 {
            switch region {
            case 0b01: return CGPoint(x: cx - 1.05 * r, y: cy)
            case 0b10: return CGPoint(x: cx + 1.05 * r, y: cy)
            default: return CGPoint(x: cx, y: cy)
            }
        }
        let offsets: [Int: (Double, Double)] = [
            0b001: (-0.95, -0.75), 0b010: (0.95, -0.75), 0b100: (0, 1.0),
            0b011: (0, -0.95), 0b101: (-0.55, 0.3), 0b110: (0.55, 0.3), 0b111: (0, -0.05),
        ]
        let (dx, dy) = offsets[region] ?? (0, 0)
        return CGPoint(x: cx + dx * r, y: cy + dy * r)
    }
}
