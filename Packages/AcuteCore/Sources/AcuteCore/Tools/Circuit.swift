import Foundation

/// Linear circuits by modified nodal analysis (Osnove elektrotehnike I and II at FE): resistors,
/// coils, capacitors and independent voltage and current sources, in direct current (f = 0) or
/// in the sinusoidal steady state as phasors. Node "0" is the reference.
public enum Circuit {
    public enum Kind: String, Sendable, Hashable {
        case resistor, inductor, capacitor, voltageSource, currentSource
    }

    /// An element between nodes a and b. A voltage source keeps V(a) − V(b) = value∠phase; a
    /// current source drives value∠phase through itself from a to b, into node b.
    public struct Element: Sendable, Hashable {
        public var name: String
        public var kind: Kind
        public var a: String
        public var b: String
        public var value: Double
        public var phase: Double

        public init(name: String, kind: Kind, a: String, b: String, value: Double, phase: Double = 0) {
            self.name = name
            self.kind = kind
            self.a = a
            self.b = b
            self.value = value
            self.phase = phase
        }
    }

    // MARK: Netlist

    /// One element per line: name, node, node, value with an optional SI prefix (p n u µ m k M G)
    /// and, for sources, a phase in degrees: `R1 1 2 4,7k`, `U1 1 0 230 30`, `C1 2 0 10u`. The first
    /// letter of the name gives the kind: R, L, C, U/V/E (voltage source), I/J (current source).
    public static func parse(_ text: String) throws(MathError) -> [Element] {
        var elements: [Element] = []
        for raw in text.split(whereSeparator: \.isNewline) {
            let line = raw.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)[0]
            let words = line.split(whereSeparator: \.isWhitespace).map(String.init)
            if words.isEmpty { continue }
            guard words.count == 4 || words.count == 5, let letter = words[0].first else {
                throw .syntax("vrstica »\(line.trimmingCharacters(in: .whitespaces))«: ime, vozlišči in vrednost")
            }
            let kind: Kind
            switch letter.uppercased() {
            case "R": kind = .resistor
            case "L": kind = .inductor
            case "C": kind = .capacitor
            case "U", "V", "E": kind = .voltageSource
            case "I", "J": kind = .currentSource
            default: throw .syntax("»\(words[0])«: ime se začne z R, L, C, U ali I")
            }
            guard let value = number(words[3]) else { throw .syntax("»\(words[3])« ni število") }
            var phase = 0.0
            if words.count == 5 {
                guard kind == .voltageSource || kind == .currentSource, let degrees = number(words[4]) else {
                    throw .syntax("fazo (v stopinjah) imajo le viri")
                }
                phase = degrees * .pi / 180
            }
            guard words[1] != words[2] else { throw .syntax("»\(words[0])« ima obe sponki v istem vozlišču") }
            elements.append(Element(name: words[0], kind: kind, a: words[1], b: words[2], value: value, phase: phase))
        }
        guard !elements.isEmpty else { throw .incomplete }
        return elements
    }

    /// 4,7k → 4700; 10u and 10µ → 1e-5; 2m → 0,002; 3M → 3e6.
    static func number(_ word: String) -> Double? {
        var text = word.replacingOccurrences(of: ",", with: ".")
        let prefixes: [Character: Double] = ["p": 1e-12, "n": 1e-9, "u": 1e-6, "µ": 1e-6, "μ": 1e-6, "m": 1e-3, "k": 1e3, "K": 1e3, "M": 1e6, "G": 1e9]
        var factor = 1.0
        if let last = text.last, let scale = prefixes[last] {
            factor = scale
            text.removeLast()
        }
        guard let value = Double(text), value.isFinite else { return nil }
        return value * factor
    }

    // MARK: Solution

    public struct Solution: Sendable, Hashable {
        public var frequency: Double
        /// Node potentials against node "0".
        public var potentials: [String: Complex]
        /// The current through each element from a to b.
        public var currents: [String: Complex]

        public func voltage(_ e: Element) -> Complex {
            (potentials[e.a] ?? Complex(0)) - (potentials[e.b] ?? Complex(0))
        }

        /// S = U·I*, the complex power the element takes (negative for a source that delivers).
        public func power(_ e: Element) -> Complex {
            let u = voltage(e), i = currents[e.name] ?? Complex(0)
            return u * Complex(i.re, -i.im)
        }
    }

    public static func isGround(_ node: String) -> Bool {
        ["0", "gnd", "GND", "masa"].contains(node)
    }

    /// Node potentials and element currents at frequency f (0: direct current, where a coil is a
    /// short circuit and a capacitor an open one).
    public static func solve(_ elements: [Element], frequency f: Double) throws(MathError) -> Solution {
        guard f >= 0, f.isFinite else { throw .domain("frekvenca ne sme biti negativna") }
        guard f > 0 || elements.allSatisfy({ ($0.kind != .voltageSource && $0.kind != .currentSource) || $0.phase == 0 }) else {
            throw .domain("pri enosmernem toku (f = 0) viri nimajo faze; smer povej s predznakom vrednosti")
        }
        let omega = 2 * Double.pi * f
        var names: [String] = []
        for e in elements {
            for node in [e.a, e.b] where !isGround(node) && !names.contains(node) { names.append(node) }
        }
        guard !names.isEmpty else { throw .domain("vezje potrebuje vsaj eno vozlišče poleg 0") }
        guard elements.contains(where: { isGround($0.a) || isGround($0.b) }) else { throw .domain("vezje mora biti povezano z vozliščem 0") }
        let index = Dictionary(uniqueKeysWithValues: names.enumerated().map { ($1, $0) })
        // Extra unknowns: currents of voltage sources and, in direct current, of coils.
        var branches: [String: Int] = [:]
        for e in elements where e.kind == .voltageSource || (e.kind == .inductor && omega == 0) {
            branches[e.name] = names.count + branches.count
        }
        guard Set(elements.map(\.name)).count == elements.count else { throw .domain("imena elementov se ponavljajo") }
        let size = names.count + branches.count
        var matrix = [[Complex]](repeating: [Complex](repeating: Complex(0), count: size), count: size)
        var rhs = [Complex](repeating: Complex(0), count: size)
        func admittance(_ e: Element) throws(MathError) -> Complex? {
            switch e.kind {
            case .resistor:
                guard e.value > 0 else { throw .domain("upornost \(e.name) mora biti pozitivna") }
                return Complex(1 / e.value)
            case .capacitor:
                guard e.value > 0 else { throw .domain("kapacitivnost \(e.name) mora biti pozitivna") }
                return Complex(0, omega * e.value)
            case .inductor:
                guard e.value > 0 else { throw .domain("induktivnost \(e.name) mora biti pozitivna") }
                return omega == 0 ? nil : Complex(0, -1 / (omega * e.value))
            case .voltageSource, .currentSource:
                return nil
            }
        }
        for e in elements {
            let ia = index[e.a], ib = index[e.b]
            let phasor = Complex(e.value * cos(e.phase), e.value * sin(e.phase))
            if let y = try admittance(e) {
                if let ia { matrix[ia][ia] += y }
                if let ib { matrix[ib][ib] += y }
                if let ia, let ib {
                    matrix[ia][ib] = matrix[ia][ib] - y
                    matrix[ib][ia] = matrix[ib][ia] - y
                }
            } else if e.kind == .currentSource {
                if let ia { rhs[ia] = rhs[ia] - phasor }
                if let ib { rhs[ib] += phasor }
            } else if let j = branches[e.name] {
                // V(a) − V(b) = E; the branch current leaves a and enters b.
                if let ia {
                    matrix[ia][j] += Complex(1)
                    matrix[j][ia] += Complex(1)
                }
                if let ib {
                    matrix[ib][j] = matrix[ib][j] - Complex(1)
                    matrix[j][ib] = matrix[j][ib] - Complex(1)
                }
                rhs[j] = e.kind == .voltageSource ? phasor : Complex(0)
            }
        }
        guard let x = solveComplex(matrix, rhs) else {
            throw .domain("vezje ni enolično rešljivo: preveri plavajoča vozlišča in zanke iz napetostnih virov")
        }
        var potentials: [String: Complex] = [:]
        for (name, i) in index { potentials[name] = clean(x[i]) }
        var currents: [String: Complex] = [:]
        for e in elements {
            if let j = branches[e.name] {
                currents[e.name] = clean(x[j])
            } else if e.kind == .currentSource {
                currents[e.name] = clean(Complex(e.value * cos(e.phase), e.value * sin(e.phase)))
            } else if let y = try admittance(e) {
                let u = (potentials[e.a] ?? Complex(0)) - (potentials[e.b] ?? Complex(0))
                currents[e.name] = clean(y * u)
            }
        }
        return Solution(frequency: f, potentials: potentials, currents: currents)
    }

    /// The Thévenin source seen between nodes a and b with nothing connected there: U_Th is the
    /// open-circuit voltage V(a) − V(b) and Z_Th the impedance with the sources switched off
    /// (voltage sources shorted, current sources opened), found with a test current of 1 A.
    public static func thevenin(_ elements: [Element], frequency f: Double, between a: String, and b: String) throws(MathError) -> (voltage: Complex, impedance: Complex) {
        guard a != b else { throw .domain("vozlišči morata biti različni") }
        let open = try solve(elements, frequency: f)
        let known = Set(open.potentials.keys).union(["0", "gnd", "GND", "masa"])
        guard known.contains(a), known.contains(b) else { throw .domain("vozlišča \(known.contains(a) ? b : a) ni v vezju") }
        let voltage = (open.potentials[a] ?? Complex(0)) - (open.potentials[b] ?? Complex(0))
        var passive = elements.map { e -> Element in
            var quiet = e
            if e.kind == .voltageSource || e.kind == .currentSource { quiet.value = 0 }
            return quiet
        }
        var testName = "I_test"
        while elements.contains(where: { $0.name == testName }) { testName += "′" }
        passive.append(Element(name: testName, kind: .currentSource, a: b, b: a, value: 1))
        let test = try solve(passive, frequency: f)
        let impedance = (test.potentials[a] ?? Complex(0)) - (test.potentials[b] ?? Complex(0))
        return (clean(voltage), clean(impedance))
    }

    // MARK: Helpers

    /// A·x = b over the complex numbers (Gaussian elimination with partial pivoting).
    static func solveComplex(_ a: [[Complex]], _ b: [Complex]) -> [Complex]? {
        let n = b.count
        var m = a, y = b
        // Each row is first scaled to its largest entry, so tiny conductances (10⁻¹⁴ S) next to the
        // unit entries of a voltage source are not mistaken for zero pivots.
        for r in 0..<n {
            let size = m[r].map(\.magnitude).max() ?? 0
            guard size > 0 else { return nil }
            m[r] = m[r].map { $0 / size }
            y[r] = y[r] / size
        }
        let scale = 1.0
        for col in 0..<n {
            guard let pivot = (col..<n).max(by: { m[$0][col].magnitude < m[$1][col].magnitude }),
                  m[pivot][col].magnitude > 1e-13 * scale else { return nil }
            m.swapAt(col, pivot)
            y.swapAt(col, pivot)
            for r in (col + 1)..<Swift.max(col + 1, n) {
                let factor = m[r][col] / m[col][col]
                if factor.re == 0 && factor.im == 0 { continue }
                for c in col..<n { m[r][c] = m[r][c] - factor * m[col][c] }
                y[r] = y[r] - factor * y[col]
            }
        }
        var x = [Complex](repeating: Complex(0), count: n)
        for r in stride(from: n - 1, through: 0, by: -1) {
            var s = y[r]
            for c in (r + 1)..<Swift.max(r + 1, n) { s = s - m[r][c] * x[c] }
            x[r] = s / m[r][r]
        }
        return x.allSatisfy({ $0.re.isFinite && $0.im.isFinite }) ? x : nil
    }

    static func clean(_ z: Complex) -> Complex {
        let size = Swift.max(Swift.abs(z.re), Swift.abs(z.im))
        // Rounding noise in one part next to the other is zero; 1 next to 10¹² is kept.
        let re = Swift.abs(z.re) <= 1e-13 * size ? 0 : NumericCalculus.clean(z.re)
        let im = Swift.abs(z.im) <= 1e-13 * size ? 0 : NumericCalculus.clean(z.im)
        return Complex(re, im)
    }
}
