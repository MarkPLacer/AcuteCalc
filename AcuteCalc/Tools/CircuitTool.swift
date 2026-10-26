import AcuteCore
import SwiftUI

/// Any linear circuit typed as a list of elements: node potentials and the voltage, current and
/// power of every element by nodal analysis, in direct current or as phasors, and the Thévenin
/// source between two nodes.
struct CircuitToolView: View {
    @AppStorage("circuitNetlist") private var netlist = "U1 1 0 12\nR1 1 2 4\nR2 2 0 6\nR3 2 3 3\nI1 0 3 2"
    @AppStorage("circuitTheveninA") private var nodeA = "2"
    @AppStorage("circuitTheveninB") private var nodeB = "0"
    @State private var frequency: Double? = 0

    var body: some View {
        let analysis = self.analysis
        List {
            Section {
                TextField("R1 1 2 100", text: $netlist, axis: .vertical)
                    .lineLimit(4...16)
                    .font(.callout.monospaced())
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                NumberInputField(title: "Frekvenca f (Hz, 0 = enosmerno)", value: $frequency)
            } header: {
                Text("Vezje")
            } footer: {
                Text("Vsaka vrstica je en element: ime, vozlišči in vrednost, npr. R1 1 2 4,7k, L1 2 3 10m, C1 3 0 10u. Napetostni vir U1 1 0 230 30 ima V(1) − V(0) = 230 V s fazo 30°; tokovni vir I1 0 3 2 žene 2 A skozi sebe od vozlišča 0 v vozlišče 3. Vozlišče 0 je masa; predpone p, n, u, m, k, M, G.")
            }
            switch analysis {
            case .success(let result):
                CircuitResults(elements: result.elements, solution: result.solution)
                Section {
                    HStack {
                        TextField("a", text: $nodeA)
                            .multilineTextAlignment(.center)
                        Text("–").foregroundStyle(.secondary)
                        TextField("b", text: $nodeB)
                            .multilineTextAlignment(.center)
                    }
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    TheveninRows(elements: result.elements, frequency: result.solution.frequency, a: nodeA, b: nodeB)
                } header: {
                    Text("Théveninov nadomestni vir med vozliščema")
                } footer: {
                    Text("Na sponkah a in b ne sme biti bremena. U_Th je napetost odprtih sponk, Z_Th impedanca z izklopljenimi viri; največja moč na bremenu Z = Z_Th* je |U_Th|²/(4·R_Th).")
                }
            case .failure(let error):
                Section {
                    Text(error == .incomplete ? "Vnesi elemente vezja in frekvenco f." : (error.errorDescription ?? error.shortDescription))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollDismissesKeyboard(.interactively)
    }

    private var analysis: Result<(elements: [Circuit.Element], solution: Circuit.Solution), MathError> {
        guard let frequency else { return .failure(.incomplete) }
        do throws(MathError) {
            let elements = try Circuit.parse(netlist)
            let solution = try Circuit.solve(elements, frequency: frequency)
            return .success((elements, solution))
        } catch {
            return .failure(error)
        }
    }
}

/// Real values in direct current; a + jb with |z| ∠ φ for phasors.
private struct PhasorText {
    let options: NumberFormatOptions
    let alternating: Bool

    func number(_ x: Double) -> String {
        // The solver already removed rounding noise, so tiny currents and powers are shown.
        NumberFormatting.format(NumericCalculus.roundNoise(x), options: options).plainTextLocalized
    }

    func text(_ z: Complex, _ unit: String) -> String {
        guard alternating else { return number(z.re) + " " + unit }
        return number(z.re) + (z.im < 0 ? " − j" : " + j") + number(Swift.abs(z.im)) + " " + unit
            + " (" + number(z.magnitude) + " ∠ " + number(z.argument * 180 / .pi) + "°)"
    }
}

private struct CircuitResults: View {
    let elements: [Circuit.Element]
    let solution: Circuit.Solution
    @Environment(AppSettings.self) private var settings

    var body: some View {
        let format = PhasorText(options: settings.numberFormat, alternating: solution.frequency > 0)
        let powers = elements.map { solution.power($0) }
        Section(solution.frequency > 0 ? "Kazalci potencialov (efektivne vrednosti)" : "Potenciali vozlišč") {
            ForEach(solution.potentials.keys.sorted(by: Self.nodeOrder), id: \.self) { node in
                LabeledContent("V(\(node))", value: format.text(solution.potentials[node] ?? Complex(0), "V"))
            }
        }
        Section {
            ForEach(Array(elements.enumerated()), id: \.offset) { i, e in
                LabeledContent(e.name + " (" + e.a + " → " + e.b + ")") {
                    VStack(alignment: .trailing, spacing: 1) {
                        Text("U = " + format.text(solution.voltage(e), "V"))
                        Text("I = " + format.text(solution.currents[e.name] ?? Complex(0), "A"))
                        Text("P = " + format.number(powers[i].re) + " W" + (solution.frequency > 0 ? ", Q = " + format.number(powers[i].im) + " var" : ""))
                            .foregroundStyle(.secondary)
                    }
                    .font(.caption.monospacedDigit())
                }
            }
            LabeledContent("Σ P", value: format.number(Self.balance(powers.map(\.re))) + " W")
            if solution.frequency > 0 {
                LabeledContent("Σ Q", value: format.number(Self.balance(powers.map(\.im))) + " var")
            }
        } header: {
            Text("Napetosti, tokovi in moči elementov")
        } footer: {
            Text("U = V(a) − V(b), I teče skozi element od a proti b. Moč je prejeta moč; vir, ki moč oddaja, ima P < 0, zato je vsota vseh moči 0 (pri izmeničnem toku Σ P = 0 in Σ Q = 0).")
        }
    }

    /// A sum that balances to 0, without the rounding noise of its terms.
    private static func balance(_ terms: [Double]) -> Double {
        let sum = terms.reduce(0, +)
        let size = terms.reduce(0) { $0 + Swift.abs($1) }
        return Swift.abs(sum) <= 1e-12 * size ? 0 : sum
    }

    /// Numeric node names in numeric order, the others after them.
    static func nodeOrder(_ a: String, _ b: String) -> Bool {
        switch (Int(a), Int(b)) {
        case let (x?, y?): x < y
        case (.some, nil): true
        case (nil, .some): false
        case (nil, nil): a < b
        }
    }
}

private struct TheveninRows: View {
    let elements: [Circuit.Element]
    let frequency: Double
    let a: String
    let b: String
    @Environment(AppSettings.self) private var settings

    var body: some View {
        let format = PhasorText(options: settings.numberFormat, alternating: frequency > 0)
        switch source {
        case .success(let source):
            LabeledContent("U_Th", value: format.text(source.voltage, "V"))
            LabeledContent(frequency > 0 ? "Z_Th" : "R_Th", value: format.text(source.impedance, "Ω"))
            if source.impedance.magnitude > 0 {
                LabeledContent("I_N = U_Th/Z_Th", value: format.text(source.voltage / source.impedance, "A"))
            }
            if source.impedance.re > 0 {
                LabeledContent("P_max", value: format.number(source.voltage.magnitude * source.voltage.magnitude / (4 * source.impedance.re)) + " W")
            }
        case .failure(let error):
            Text(error.errorDescription ?? error.shortDescription).font(.callout).foregroundStyle(.secondary)
        }
    }

    private var source: Result<(voltage: Complex, impedance: Complex), MathError> {
        do throws(MathError) {
            return .success(try Circuit.thevenin(elements, frequency: frequency, between: a, and: b))
        } catch {
            return .failure(error)
        }
    }
}
