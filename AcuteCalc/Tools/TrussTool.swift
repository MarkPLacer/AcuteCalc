import AcuteCore
import SwiftUI

/// A plane truss for Osnove statike: joints, bars, supports and loads typed line by line; the
/// axial forces (tension and compression) and the reactions by the method of joints.
struct TrussToolView: View {
    @AppStorage("trussJoints") private var jointsText = "0 0\n4 0\n8 0\n2 3\n6 3"
    @AppStorage("trussBars") private var barsText = "1 2\n2 3\n1 4\n4 2\n2 5\n5 3\n4 5"
    @AppStorage("trussSupports") private var supportsText = "1 n\n3 p"
    @AppStorage("trussLoads") private var loadsText = "4 0 -10\n5 0 -10"

    var body: some View {
        let input = parsed
        let solution = solve(input)
        List {
            if let input, case .success(let s) = solution {
                Section {
                    TrussDrawing(joints: input.joints, bars: input.bars, forces: s.forces)
                        .frame(height: 240)
                        .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
                }
            }
            textSection("Vozlišča (x y)", text: $jointsText, footer: "Eno vozlišče v vrstici; vozlišča so oštevilčena od 1.")
            textSection("Palice (vozlišče vozlišče)", text: $barsText, footer: "Vsaka palica povezuje dve vozlišči, npr. 1 4.")
            textSection("Podpore", text: $supportsText,
                        footer: "»1 n« je nepomična podpora (dve reakciji), »3 p« pomična z navpično reakcijo, »3 p 0« pomična z vodoravno, »3 p 60« z reakcijo pod 60° glede na os x.")
            textSection("Obtežba (vozlišče F_x F_y)", text: $loadsText, footer: "Sile v vozliščih, F_y < 0 kaže navzdol.")
            switch solution {
            case .success(let s):
                results(s, bars: input?.bars ?? [])
            case .failure(let error):
                Section {
                    Text(error == .incomplete ? "Preveri zapis vozlišč, palic, podpor in obtežbe." : (error.errorDescription ?? error.shortDescription))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollDismissesKeyboard(.interactively)
    }

    private func textSection(_ title: String, text: Binding<String>, footer: String) -> some View {
        Section {
            TextField(title, text: text, axis: .vertical)
                .lineLimit(2...12)
                .font(.callout.monospacedDigit())
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        } header: {
            Text(title)
        } footer: {
            Text(footer)
        }
    }

    @ViewBuilder
    private func results(_ s: Truss.Solution, bars: [Truss.Bar]) -> some View {
        Section {
            ForEach(Array(zip(bars, s.forces).enumerated()), id: \.offset) { i, pair in
                ResultRow(title: "N\(i + 1) (\(pair.0.from + 1)–\(pair.0.to + 1))" + (pair.1 > 0 ? " nateg" : (pair.1 < 0 ? " tlak" : "")),
                          value: pair.1)
            }
        } header: {
            Text("Osne sile v palicah")
        } footer: {
            Text("N > 0 je nateg, N < 0 tlak. Paličje je statično določeno, ko je palic in reakcij skupaj dvakrat toliko kot vozlišč.")
        }
        Section("Reakcije") {
            ForEach(Array(s.reactions.enumerated()), id: \.offset) { _, r in
                ResultRow(title: "R\(r.joint + 1), x", value: r.x)
                ResultRow(title: "R\(r.joint + 1), y", value: r.y)
            }
        }
    }

    // MARK: Input

    private typealias Input = (joints: [SIMD2<Double>], bars: [Truss.Bar], supports: [Truss.Support], loads: [Truss.Load])

    private var parsed: Input? {
        guard let jointRows = rows(jointsText, counts: [2]), let barRows = rows(barsText, counts: [2]),
              let loadRows = rows(loadsText, counts: [3]) else { return nil }
        var supports: [Truss.Support] = []
        for line in supportsText.split(whereSeparator: \.isNewline) {
            let words = line.split(whereSeparator: \.isWhitespace).map(String.init)
            if words.isEmpty { continue }
            guard words.count >= 2, let joint = Int(words[0]) else { return nil }
            switch words[1].lowercased() {
            case "n":
                guard words.count == 2 else { return nil }
                supports.append(.pin(joint - 1))
            case "p":
                let degrees = words.count == 3 ? ExpressionNumberField.parse(words[2]) : 90
                guard words.count <= 3, let degrees else { return nil }
                supports.append(.roller(joint - 1, angle: degrees * .pi / 180))
            default:
                return nil
            }
        }
        // Joint numbers must be whole and small before they become indices.
        func isIndex(_ v: Double) -> Bool { v == v.rounded() && v >= 1 && v <= 10_000 }
        guard barRows.allSatisfy({ isIndex($0[0]) && isIndex($0[1]) }), loadRows.allSatisfy({ isIndex($0[0]) }) else { return nil }
        let bars = barRows.map { Truss.Bar(from: Int($0[0]) - 1, to: Int($0[1]) - 1) }
        return (jointRows.map { SIMD2($0[0], $0[1]) }, bars, supports,
                loadRows.map { Truss.Load(joint: Int($0[0]) - 1, fx: $0[1], fy: $0[2]) })
    }

    /// Lines of numbers with one of the allowed counts each (empty lines skipped).
    private func rows(_ text: String, counts: [Int]) -> [[Double]]? {
        var result: [[Double]] = []
        for line in text.split(whereSeparator: \.isNewline) {
            let s = String(line)
            if s.allSatisfy(\.isWhitespace) { continue }
            let parts = numberFields(s)
            let values = parts.compactMap { ExpressionNumberField.parse(String($0)) }
            guard values.count == parts.count, counts.contains(values.count) else { return nil }
            result.append(values)
        }
        return result
    }

    private func solve(_ input: Input?) -> Result<Truss.Solution, MathError> {
        guard let input else { return .failure(.incomplete) }
        do throws(MathError) {
            return .success(try Truss.solve(joints: input.joints, bars: input.bars, supports: input.supports, loads: input.loads))
        } catch {
            return .failure(error)
        }
    }
}

/// The truss to scale: tension blue, compression red, the line width growing with |N|.
private struct TrussDrawing: View {
    let joints: [SIMD2<Double>]
    let bars: [Truss.Bar]
    let forces: [Double]

    var body: some View {
        Canvas { context, size in
            guard let minX = joints.map(\.x).min(), let maxX = joints.map(\.x).max(),
                  let minY = joints.map(\.y).min(), let maxY = joints.map(\.y).max() else { return }
            let padding = 24.0
            let scale = Swift.min((Double(size.width) - 2 * padding) / Swift.max(maxX - minX, 1e-9),
                                  (Double(size.height) - 2 * padding) / Swift.max(maxY - minY, 1e-9))
            func point(_ p: SIMD2<Double>) -> CGPoint {
                CGPoint(x: Double(size.width) / 2 + (p.x - (minX + maxX) / 2) * scale,
                        y: Double(size.height) / 2 - (p.y - (minY + maxY) / 2) * scale)
            }
            let largest = Swift.max(forces.map(Swift.abs).max() ?? 0, 1e-12)
            for (bar, force) in zip(bars, forces) where joints.indices.contains(bar.from) && joints.indices.contains(bar.to) {
                var path = Path()
                path.move(to: point(joints[bar.from]))
                path.addLine(to: point(joints[bar.to]))
                let color: Color = force > 1e-9 * largest ? .blue : (force < -1e-9 * largest ? .red : .secondary)
                context.stroke(path, with: .color(color), lineWidth: 1.5 + 3.5 * Swift.abs(force) / largest)
            }
            for (i, joint) in joints.enumerated() {
                let p = point(joint)
                context.fill(Path(ellipseIn: CGRect(x: p.x - 4, y: p.y - 4, width: 8, height: 8)), with: .color(.primary))
                context.draw(Text("\(i + 1)").font(.caption2.weight(.semibold)), at: CGPoint(x: p.x + 9, y: p.y - 9))
            }
        }
        .accessibilityLabel("Skica paličja: nategnjene palice modre, tlačene rdeče")
    }
}
