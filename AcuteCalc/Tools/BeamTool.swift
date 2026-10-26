import AcuteCore
import SwiftUI

/// A beam for Osnove statike: supports, point forces, distributed loads and couples; the
/// reactions, the largest moment and the shear and moment diagrams.
struct BeamToolView: View {
    enum SupportKind: String, CaseIterable, Identifiable {
        case simple, fixedLeft, fixedRight
        var id: String { rawValue }
        var title: String {
            switch self {
            case .simple: "Prostoležeči"
            case .fixedLeft: "Vpet levo"
            case .fixedRight: "Vpet desno"
            }
        }
    }

    @State private var length: Double? = 6
    @State private var supportKind: SupportKind = .simple
    @State private var leftSupport: Double? = 0
    @State private var rightSupport: Double? = 6
    @State private var loads = [
        BeamLoadInput(kind: .force, value: 10, position: 2),
        BeamLoadInput(kind: .distributed, value: 2, secondValue: 2, position: 0, end: 6),
    ]

    var body: some View {
        let beam = self.beam
        List {
            Section {
                NumberInputField(title: "Dolžina L (m)", value: $length)
                Picker("Podpiranje", selection: $supportKind) {
                    ForEach(SupportKind.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                if supportKind == .simple {
                    NumberInputField(title: "Nepomična podpora A pri x (m)", value: $leftSupport)
                    NumberInputField(title: "Pomična podpora B pri x (m)", value: $rightSupport)
                }
            } header: {
                Text("Nosilec")
            } footer: {
                Text("Sile in obtežba so pozitivne navzdol, dvojice v nasprotni smeri urinega kazalca. M > 0, ko je nateg spodaj; diagram M je narisan na strani nategnjenih vlaken.")
            }
            if case .success(let b) = beam {
                Section {
                    BeamDiagram(beam: b)
                        .frame(height: 340)
                        .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
                }
            }
            ForEach($loads) { $load in
                let number = (loads.firstIndex(where: { $0.id == load.id }) ?? 0) + 1
                BeamLoadEditor(load: $load, title: "Obtežba \(number)") {
                    loads.removeAll { $0.id == load.id }
                }
            }
            Section {
                Button("Dodaj silo", systemImage: "arrow.down") { loads.append(BeamLoadInput(kind: .force, value: 5, position: (length ?? 0) / 2)) }
                Button("Dodaj zvezno obtežbo", systemImage: "arrow.down.to.line") {
                    loads.append(BeamLoadInput(kind: .distributed, value: 1, secondValue: 1, position: 0, end: length ?? 1))
                }
                Button("Dodaj dvojico (moment)", systemImage: "arrow.counterclockwise") { loads.append(BeamLoadInput(kind: .couple, value: 5, position: (length ?? 0) / 2)) }
            }
            switch beam {
            case .success(let b): BeamResults(beam: b)
            case .failure(let error):
                Section { Text(error == .incomplete ? "Izpolni vse podatke." : (error.errorDescription ?? error.shortDescription)).foregroundStyle(.secondary) }
            }
        }
        .listStyle(.insetGrouped)
        .scrollDismissesKeyboard(.interactively)
    }

    private var beam: Result<Beam, MathError> {
        guard let length else { return .failure(.incomplete) }
        let support: Beam.Support
        switch supportKind {
        case .simple:
            guard let leftSupport, let rightSupport else { return .failure(.incomplete) }
            support = .simple(left: leftSupport, right: rightSupport)
        case .fixedLeft: support = .fixedLeft
        case .fixedRight: support = .fixedRight
        }
        let parsed = loads.compactMap(\.load)
        guard parsed.count == loads.count else { return .failure(.incomplete) }
        do throws(MathError) {
            return .success(try Beam(length: length, support: support, loads: parsed).validated())
        } catch {
            return .failure(error)
        }
    }
}

struct BeamLoadInput: Identifiable, Equatable {
    enum Kind: String, CaseIterable, Identifiable {
        case force, distributed, couple
        var id: String { rawValue }
        var title: String {
            switch self {
            case .force: "Sila"
            case .distributed: "Zvezna"
            case .couple: "Dvojica"
            }
        }
    }

    let id = UUID()
    var kind: Kind
    /// F (kN), q at the start (kN/m) or the couple (kNm).
    var value: Double?
    /// q at the end (kN/m).
    var secondValue: Double? = nil
    /// x of the force or couple, or where the distributed load starts (m).
    var position: Double?
    /// Where the distributed load ends (m).
    var end: Double? = nil

    var load: Beam.Load? {
        guard let value, let position else { return nil }
        switch kind {
        case .force: return .force(value, at: position)
        case .couple: return .couple(value, at: position)
        case .distributed:
            guard let end else { return nil }
            return .distributed(start: value, end: secondValue ?? value, from: position, to: end)
        }
    }
}

private struct BeamLoadEditor: View {
    @Binding var load: BeamLoadInput
    let title: String
    let onDelete: () -> Void

    var body: some View {
        Section {
            Picker("Vrsta", selection: $load.kind) {
                ForEach(BeamLoadInput.Kind.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            switch load.kind {
            case .force:
                NumberInputField(title: "F (kN, navzdol +)", value: $load.value)
                NumberInputField(title: "pri x (m)", value: $load.position)
            case .distributed:
                NumberInputField(title: "q na začetku (kN/m)", value: $load.value)
                NumberInputField(title: "q na koncu (kN/m)", value: $load.secondValue, prompt: "enako")
                NumberInputField(title: "od x (m)", value: $load.position)
                NumberInputField(title: "do x (m)", value: $load.end)
            case .couple:
                NumberInputField(title: "M (kNm, ↺ +)", value: $load.value)
                NumberInputField(title: "pri x (m)", value: $load.position)
            }
        } header: {
            HStack {
                Text(title)
                Spacer()
                Button("Odstrani", systemImage: "trash", role: .destructive, action: onDelete)
                    .labelStyle(.iconOnly)
            }
        }
    }
}

private struct BeamResults: View {
    let beam: Beam

    var body: some View {
        let reactions = beam.reactions()
        let peak = beam.maximumMoment()
        Section {
            ForEach(Array(reactions.forces.enumerated()), id: \.offset) { i, r in
                ResultRow(title: reactionName(i, reactions.forces.count) + " pri x = " + NumberFormatting.plain(r.position), value: r.force, unit: "kN")
            }
            if let moment = reactions.moment {
                ResultRow(title: "Vpetostni moment (↺ +)", value: moment, unit: "kNm")
            }
        } header: {
            Text("Reakcije (navzgor +)")
        } footer: {
            Text("Iz ravnotežja: ΣF = 0 in ΣM = 0 okoli podpore.")
        }
        let shear = beam.maximumShear()
        Section {
            ResultRow(title: "M z največjo absolutno vrednostjo", value: peak.value, unit: "kNm")
            ResultRow(title: "pri x", value: peak.position, unit: "m")
            ResultRow(title: "V z največjo absolutno vrednostjo", value: shear.value, unit: "kN")
            ResultRow(title: "pri x", value: shear.position, unit: "m")
        } header: {
            Text("Notranje sile")
        } footer: {
            Text("Ekstrem M je v značilni točki ali tam, kjer je V = 0; ekstrem V v značilni točki ali tam, kjer je q = 0.")
        }
        Section("V in M v značilnih točkah") {
            ForEach(beam.keyPoints, id: \.self) { x in
                LabeledContent("x = " + NumberFormatting.plain(x)) {
                    VStack(alignment: .trailing, spacing: 0) {
                        Text("V: " + pair(x == 0 ? nil : beam.shear(at: x, rightSide: false), x == beam.length ? nil : beam.shear(at: x)))
                        Text("M: " + pair(x == 0 ? nil : beam.moment(at: x, rightSide: false), x == beam.length ? nil : beam.moment(at: x)))
                    }
                    .font(.callout.monospacedDigit())
                }
            }
        }
    }

    private func reactionName(_ i: Int, _ count: Int) -> String {
        count == 2 ? (i == 0 ? "A" : "B") : "R"
    }

    /// The value just left and just right of a point ("levo → desno" when V or M jumps).
    private func pair(_ left: Double?, _ right: Double?) -> String {
        func text(_ v: Double) -> String { NumberFormatting.plain(NumericCalculus.clean(v)) }
        switch (left, right) {
        case let (l?, r?) where Swift.abs(l - r) > 1e-9 * Swift.max(1, Swift.abs(l), Swift.abs(r)): return text(l) + " → " + text(r)
        case let (l?, _): return text(l)
        case let (nil, r?): return text(r)
        case (nil, nil): return "—"
        }
    }
}

/// The beam with its supports and loads, and below it the V and M diagrams to scale.
private struct BeamDiagram: View {
    let beam: Beam

    var body: some View {
        Canvas { context, size in
            let margin = 24.0
            let scaleX = (Double(size.width) - 2 * margin) / beam.length
            func x(_ position: Double) -> Double { margin + position * scaleX }
            let beamY = 46.0

            func arrow(from start: CGPoint, to end: CGPoint, color: Color) {
                var path = Path()
                path.move(to: start)
                path.addLine(to: end)
                let direction: CGFloat = end.y > start.y ? -1 : 1
                path.move(to: CGPoint(x: end.x - 4, y: end.y + 6 * direction))
                path.addLine(to: end)
                path.addLine(to: CGPoint(x: end.x + 4, y: end.y + 6 * direction))
                context.stroke(path, with: .color(color), lineWidth: 1.5)
            }

            func support(at p: CGPoint, roller: Bool) {
                var triangle = Path()
                triangle.move(to: p)
                triangle.addLine(to: CGPoint(x: p.x - 8, y: p.y + 13))
                triangle.addLine(to: CGPoint(x: p.x + 8, y: p.y + 13))
                triangle.closeSubpath()
                context.stroke(triangle, with: .color(.primary), lineWidth: 1.5)
                var ground = Path()
                if roller {
                    ground.addEllipse(in: CGRect(x: p.x - 7, y: p.y + 13, width: 5, height: 5))
                    ground.addEllipse(in: CGRect(x: p.x + 2, y: p.y + 13, width: 5, height: 5))
                }
                let y = p.y + (roller ? 19 : 14)
                ground.move(to: CGPoint(x: p.x - 11, y: y))
                ground.addLine(to: CGPoint(x: p.x + 11, y: y))
                context.stroke(ground, with: .color(.primary), lineWidth: 1)
            }

            func wall(at p: CGPoint, facingRight: Bool) {
                let side: CGFloat = facingRight ? -1 : 1
                var path = Path()
                path.move(to: CGPoint(x: p.x, y: p.y - 16))
                path.addLine(to: CGPoint(x: p.x, y: p.y + 16))
                for i in 0..<5 {
                    let y = p.y - 16 + CGFloat(i) * 8
                    path.move(to: CGPoint(x: p.x, y: y))
                    path.addLine(to: CGPoint(x: p.x + 7 * side, y: y + 7))
                }
                context.stroke(path, with: .color(.primary), lineWidth: 1.5)
            }

            /// A diagram in a horizontal band: positive values up, or down for M (the tension side).
            func plot(top: Double, height: Double, name: String, downwards: Bool, color: Color, value: (Double, Bool) -> Double) {
                var samples: [(position: Double, value: Double)] = []
                let points = beam.keyPoints
                for (lo, hi) in zip(points, points.dropFirst()) where hi > lo {
                    samples.append((lo, value(lo, true)))
                    for i in 1..<40 {
                        let p = lo + (hi - lo) * Double(i) / 40
                        samples.append((p, value(p, true)))
                    }
                    samples.append((hi, value(hi, false)))
                }
                let peak = Swift.max(samples.map { Swift.abs($0.value) }.max() ?? 0, 1e-12)
                let axis = top + height / 2
                let scale = (height / 2 - 10) / peak * (downwards ? 1 : -1)
                func point(_ s: (position: Double, value: Double)) -> CGPoint { CGPoint(x: x(s.position), y: axis + s.value * scale) }
                var area = Path()
                area.move(to: CGPoint(x: x(0), y: axis))
                for sample in samples { area.addLine(to: point(sample)) }
                area.addLine(to: CGPoint(x: x(beam.length), y: axis))
                area.closeSubpath()
                context.fill(area, with: .color(color.opacity(0.18)))
                var outline = Path()
                outline.addLines(samples.map(point))
                context.stroke(outline, with: .color(color), lineWidth: 1.5)
                var axisLine = Path()
                axisLine.move(to: CGPoint(x: x(0), y: axis))
                axisLine.addLine(to: CGPoint(x: x(beam.length), y: axis))
                context.stroke(axisLine, with: .color(.secondary), lineWidth: 1)
                context.draw(Text(name).font(.caption.weight(.semibold)).foregroundStyle(color), at: CGPoint(x: 10, y: axis))
                // Values at the key points, each distinct value once
                var labelled: [Double] = []
                for sample in samples where points.contains(sample.position) && Swift.abs(sample.value) > 1e-9 * peak {
                    if labelled.contains(where: { Swift.abs($0 - sample.value) <= 1e-9 * peak }) { continue }
                    labelled.append(sample.value)
                    let offset = sample.value * scale > 0 ? 9.0 : -9.0
                    context.draw(Text(NumberFormatting.plain(NumericCalculus.clean(sample.value))).font(.caption2),
                                 at: CGPoint(x: x(sample.position), y: axis + sample.value * scale + offset))
                }
            }

            // Loads above the beam
            for load in beam.loads {
                switch load {
                case .force(let f, let at):
                    let top = f >= 0 ? beamY - 34 : beamY - 4, bottom = f >= 0 ? beamY - 4 : beamY - 34
                    arrow(from: CGPoint(x: x(at), y: top), to: CGPoint(x: x(at), y: bottom), color: .red)
                    context.draw(Text(NumberFormatting.plain(f)).font(.caption2), at: CGPoint(x: x(at) + 12, y: beamY - 36))
                case .distributed(let q1, let q2, let x1, let x2):
                    let peak = Swift.max(Swift.abs(q1), Swift.abs(q2), 1e-9)
                    var outline = Path()
                    outline.move(to: CGPoint(x: x(x1), y: beamY - 4))
                    outline.addLine(to: CGPoint(x: x(x1), y: beamY - 4 - 22 * Swift.abs(q1) / peak))
                    outline.addLine(to: CGPoint(x: x(x2), y: beamY - 4 - 22 * Swift.abs(q2) / peak))
                    outline.addLine(to: CGPoint(x: x(x2), y: beamY - 4))
                    context.fill(outline, with: .color(.orange.opacity(0.25)))
                    context.stroke(outline, with: .color(.orange), lineWidth: 1)
                    let label = NumberFormatting.plain(q1) + (q1 == q2 ? "" : " … " + NumberFormatting.plain(q2))
                    context.draw(Text(label).font(.caption2), at: CGPoint(x: (x(x1) + x(x2)) / 2, y: beamY - 34))
                case .couple(let c, let at):
                    var arc = Path()
                    arc.addArc(center: CGPoint(x: x(at), y: beamY), radius: 12, startAngle: .degrees(200), endAngle: .degrees(-20), clockwise: c < 0)
                    context.stroke(arc, with: .color(.purple), lineWidth: 1.5)
                    context.draw(Text(NumberFormatting.plain(c)).font(.caption2), at: CGPoint(x: x(at), y: beamY - 22))
                }
            }
            // The beam and its supports
            var line = Path()
            line.move(to: CGPoint(x: x(0), y: beamY))
            line.addLine(to: CGPoint(x: x(beam.length), y: beamY))
            context.stroke(line, with: .color(.primary), lineWidth: 3)
            switch beam.support {
            case .simple(let a, let b):
                support(at: CGPoint(x: x(a), y: beamY), roller: false)
                support(at: CGPoint(x: x(b), y: beamY), roller: true)
            case .fixedLeft:
                wall(at: CGPoint(x: x(0), y: beamY), facingRight: true)
            case .fixedRight:
                wall(at: CGPoint(x: x(beam.length), y: beamY), facingRight: false)
            }
            // Diagrams below
            let band = (Double(size.height) - 80) / 2
            plot(top: 80, height: band, name: "V", downwards: false, color: .blue) { beam.shear(at: $0, rightSide: $1) }
            plot(top: 80 + band, height: band, name: "M", downwards: true, color: .green) { beam.moment(at: $0, rightSide: $1) }
        }
        .accessibilityLabel("Skica nosilca z diagramoma prečnih sil in upogibnih momentov")
    }
}
