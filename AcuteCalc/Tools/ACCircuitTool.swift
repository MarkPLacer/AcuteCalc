import AcuteCore
import SwiftUI

/// Alternating current circuits (Osnove elektrotehnike II): series or parallel RLC, impedance,
/// phasors, power, resonance and the correction of the power factor.
struct ACCircuitToolView: View {
    @AppStorage("acConnection") private var connection: ACCircuit.Connection = .series
    @State private var resistance: Double? = 10
    /// mH
    @State private var inductance: Double? = 100
    /// µF
    @State private var capacitance: Double? = 47
    @State private var frequency: Double? = 50
    @State private var voltage: Double? = 230

    var body: some View {
        List {
            Section {
                Picker("Vezava", selection: $connection) {
                    Text("Zaporedna").tag(ACCircuit.Connection.series)
                    Text("Vzporedna").tag(ACCircuit.Connection.parallel)
                }
                .pickerStyle(.segmented)
                NumberInputField(title: "R (Ω)", value: $resistance)
                NumberInputField(title: "L (mH)", value: $inductance, prompt: "brez")
                NumberInputField(title: "C (µF)", value: $capacitance, prompt: "brez")
                NumberInputField(title: "f (Hz)", value: $frequency)
                NumberInputField(title: "U (V, efektivna)", value: $voltage)
            } header: {
                Text("Vezje RLC")
            } footer: {
                Text("Napetost vira ima fazo 0°. Prazno polje pomeni, da elementa ni.")
            }
            switch analysis {
            case .success(let result):
                ACCircuitResults(analysis: result, connection: connection)
            case .failure(let error):
                Section {
                    Text(error == .incomplete ? "Vnesi R > 0, f > 0 in U." : (error.errorDescription ?? error.shortDescription))
                        .foregroundStyle(.secondary)
                }
            }
            CompensationSection()
        }
        .listStyle(.insetGrouped)
        .scrollDismissesKeyboard(.interactively)
    }

    private var analysis: Result<ACCircuit.Analysis, MathError> {
        guard let resistance, let frequency, let voltage else { return .failure(.incomplete) }
        do throws(MathError) {
            return .success(try ACCircuit.analyze(connection, resistance: resistance, inductance: inductance.map { $0 / 1000 },
                                                  capacitance: capacitance.map { $0 / 1_000_000 }, frequency: frequency, voltage: voltage))
        } catch {
            return .failure(error)
        }
    }
}

/// A complex value as a + jb with |z| ∠ φ below.
private struct ComplexRow: View {
    let title: String
    let value: Complex
    var unit: String = ""
    @Environment(AppSettings.self) private var settings

    var body: some View {
        LabeledContent(title) {
            VStack(alignment: .trailing, spacing: 0) {
                Text(number(value.re) + (value.im < 0 ? " − j" : " + j") + number(Swift.abs(value.im)) + (unit.isEmpty ? "" : " " + unit))
                    .font(.body.monospacedDigit())
                Text(number(value.magnitude) + " ∠ " + number(value.argument * 180 / .pi) + "°")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func number(_ x: Double) -> String {
        NumberFormatting.format(NumericCalculus.clean(x), options: settings.numberFormat).plainTextLocalized
    }
}

private struct ACCircuitResults: View {
    let analysis: ACCircuit.Analysis
    let connection: ACCircuit.Connection

    var body: some View {
        let a = analysis
        let leading = a.impedance.im > 1e-9 * a.impedance.magnitude, lagging = a.impedance.im < -1e-9 * a.impedance.magnitude
        Section("Impedanca in tok vira") {
            ResultRow(title: "ω = 2πf", value: a.omega, unit: "s⁻¹")
            ComplexRow(title: "Z", value: a.impedance, unit: "Ω")
            ComplexRow(title: "I", value: a.current, unit: "A")
            ResultRow(title: "cos φ", value: a.powerFactor)
            LabeledContent("Značaj", value: leading ? "induktiven, tok zaostaja" : (lagging ? "kapacitiven, tok prehiteva" : "ohmski"))
        }
        Section(connection == .series ? "Napetosti na elementih" : "Tokovi skozi elemente") {
            ComplexRow(title: connection == .series ? "U_R" : "I_R", value: a.resistor, unit: connection == .series ? "V" : "A")
            if let l = a.inductor { ComplexRow(title: connection == .series ? "U_L" : "I_L", value: l, unit: connection == .series ? "V" : "A") }
            if let c = a.capacitor { ComplexRow(title: connection == .series ? "U_C" : "I_C", value: c, unit: connection == .series ? "V" : "A") }
        }
        Section {
            ResultRow(title: "Delovna moč P", value: a.power.re, unit: "W")
            ResultRow(title: "Jalova moč Q", value: a.power.im, unit: "var")
            ResultRow(title: "Navidezna moč S", value: a.power.magnitude, unit: "VA")
        } header: {
            Text("Moč")
        } footer: {
            Text("S = U·I* = P + jQ; Q > 0 pri induktivnem značaju.")
        }
        if let f0 = a.resonance {
            Section("Resonanca") {
                ResultRow(title: "f₀ = 1/(2π√(LC))", value: f0, unit: "Hz")
                if let q = a.quality { ResultRow(title: connection == .series ? "Q = √(L/C)/R" : "Q = R·√(C/L)", value: q) }
                if let b = a.bandwidth { ResultRow(title: "Pasovna širina f₀/Q", value: b, unit: "Hz") }
            }
        }
        Section {
            PhasorDiagram(analysis: a, connection: connection)
                .frame(height: 260)
        } header: {
            Text("Kazalčni diagram")
        } footer: {
            Text(connection == .series ? "Napetosti (U modro, U_R zeleno, U_L oranžno, U_C vijolično) in tok I rdeče, v svojem merilu."
                                       : "Tokovi (I modro, I_R zeleno, I_L oranžno, I_C vijolično) in napetost U rdeče, v svojem merilu.")
        }
    }
}

private struct PhasorDiagram: View {
    let analysis: ACCircuit.Analysis
    let connection: ACCircuit.Connection

    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: Double(size.width) / 2, y: Double(size.height) / 2)
            let series = connection == .series
            // Voltages in series and currents in parallel share one scale; the other quantity is drawn at half size.
            // The source voltage U = |S|/|I| at phase 0.
            let source = Complex(analysis.power.magnitude / Swift.max(analysis.current.magnitude, 1e-300))
            var main: [(label: String, value: Complex, color: Color)] = []
            main.append((series ? "U" : "I", series ? source : analysis.current, Color.blue))
            main.append((series ? "U_R" : "I_R", analysis.resistor, Color.green))
            if let l = analysis.inductor { main.append((series ? "U_L" : "I_L", l, Color.orange)) }
            if let c = analysis.capacitor { main.append((series ? "U_C" : "I_C", c, Color.purple)) }
            let other: (label: String, value: Complex, color: Color) = (series ? "I" : "U", series ? analysis.current : source, Color.red)
            let longest = Swift.max(main.map { $0.value.magnitude }.max() ?? 0, 1e-300)
            let radius = Double(Swift.min(size.width, size.height)) / 2 - 26
            func arrow(_ z: Complex, length: Double, color: Color, label: String) {
                guard z.magnitude > 0 else { return }
                let angle = z.argument
                let tip = CGPoint(x: center.x + cos(angle) * length, y: center.y - sin(angle) * length)
                var path = Path()
                path.move(to: center)
                path.addLine(to: tip)
                for side in [-1.0, 1.0] {
                    path.move(to: tip)
                    path.addLine(to: CGPoint(x: tip.x - cos(angle + side * 0.45) * 9, y: tip.y + sin(angle + side * 0.45) * 9))
                }
                context.stroke(path, with: .color(color), lineWidth: 2)
                context.draw(Text(label).font(.caption2.weight(.semibold)).foregroundStyle(color),
                             at: CGPoint(x: tip.x + cos(angle) * 12, y: tip.y - sin(angle) * 12))
            }
            var axes = Path()
            axes.move(to: CGPoint(x: 8, y: center.y))
            axes.addLine(to: CGPoint(x: Double(size.width) - 8, y: center.y))
            axes.move(to: CGPoint(x: center.x, y: 8))
            axes.addLine(to: CGPoint(x: center.x, y: Double(size.height) - 8))
            context.stroke(axes, with: .color(.secondary.opacity(0.5)), lineWidth: 1)
            for phasor in main {
                arrow(phasor.value, length: radius * phasor.value.magnitude / longest, color: phasor.color, label: phasor.label)
            }
            arrow(other.value, length: radius / 2, color: other.color, label: other.label)
        }
        .accessibilityLabel("Kazalčni diagram napetosti in tokov")
    }
}

/// The capacitor that corrects the power factor of an inductive load.
private struct CompensationSection: View {
    /// kW
    @State private var power: Double? = 10
    @State private var from: Double? = 0.6
    @State private var to: Double? = 0.95
    @State private var voltage: Double? = 400
    @State private var frequency: Double? = 50

    var body: some View {
        Section {
            NumberInputField(title: "P (kW)", value: $power)
            NumberInputField(title: "cos φ₁ (zdaj)", value: $from)
            NumberInputField(title: "cos φ₂ (želeno)", value: $to)
            NumberInputField(title: "U (V)", value: $voltage)
            NumberInputField(title: "f (Hz)", value: $frequency)
            switch compensation {
            case .success(let c):
                ResultRow(title: "Q_C = P·(tg φ₁ − tg φ₂)", value: c.reactive / 1000, unit: "kvar")
                ResultRow(title: "C = Q_C/(ωU²)", value: c.capacitance * 1_000_000, unit: "µF")
            case .failure(let error):
                if error != .incomplete {
                    Text(error.errorDescription ?? error.shortDescription).font(.callout).foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Kompenzacija jalove moči")
        } footer: {
            Text("Kondenzator vzporedno k induktivnemu bremenu z delovno močjo P.")
        }
    }

    private var compensation: Result<(reactive: Double, capacitance: Double), MathError> {
        guard let power, let from, let to, let voltage, let frequency else { return .failure(.incomplete) }
        do throws(MathError) {
            return .success(try ACCircuit.compensation(power: power * 1000, from: from, to: to, voltage: voltage, frequency: frequency))
        } catch {
            return .failure(error)
        }
    }
}
