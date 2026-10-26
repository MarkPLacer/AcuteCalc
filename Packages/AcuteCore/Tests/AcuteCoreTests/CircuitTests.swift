import Foundation
import Testing
@testable import AcuteCore

// MARK: Circuits by nodal analysis

@Suite struct CircuitTests {
    private func close(_ z: Complex?, _ re: Double, _ im: Double = 0) -> Bool {
        guard let z else { return false }
        return approx(z.re, re) && approx(z.im, im)
    }

    @Test func netlist() throws {
        let elements = try Circuit.parse("R1 1 2 4,7k\nC1 2 0 10u   # filter\nU1 1 0 230 30\n\nL1 2 0 2m")
        #expect(elements.count == 4)
        #expect(elements[0].kind == .resistor && elements[0].value == 4700)
        #expect(approx(elements[1].value, 1e-5) && elements[1].kind == .capacitor)
        #expect(elements[2].kind == .voltageSource && approx(elements[2].phase, .pi / 6))
        #expect(approx(elements[3].value, 0.002))
        #expect(throws: MathError.self) { try Circuit.parse("X1 1 2 3") }
        #expect(throws: MathError.self) { try Circuit.parse("R1 1 1 5") }
        #expect(throws: MathError.self) { try Circuit.parse("R1 1 2 abc") }
    }

    @Test func voltageDivider() throws {
        // 12 V over 4 Ω and 8 Ω: V(2) = 8 V, I = 1 A, the source delivers 12 W
        let elements = try Circuit.parse("U1 1 0 12\nR1 1 2 4\nR2 2 0 8")
        let s = try Circuit.solve(elements, frequency: 0)
        #expect(close(s.potentials["2"], 8) && close(s.currents["R1"], 1) && close(s.currents["U1"], -1))
        #expect(close(s.power(elements[0]), -12))
    }

    @Test func currentSourceAndThevenin() throws {
        // V(2) = 12 V, V(3) = 18 V; the powers add up to zero; between 2 and 0: U_Th = 12 V, Z_Th = 4 ∥ 6 = 2,4 Ω
        let elements = try Circuit.parse("U1 1 0 12\nR1 1 2 4\nR2 2 0 6\nR3 2 3 3\nI1 0 3 2")
        let s = try Circuit.solve(elements, frequency: 0)
        #expect(close(s.potentials["2"], 12) && close(s.potentials["3"], 18))
        #expect(close(s.currents["R3"], -2) && close(s.power(elements[4]), -36))
        let total = elements.reduce(0) { $0 + s.power($1).re }
        #expect(abs(total) < 1e-9)
        let th = try Circuit.thevenin(elements, frequency: 0, between: "2", and: "0")
        #expect(close(th.voltage, 12) && close(th.impedance, 2.4))
    }

    @Test func alternatingCurrent() throws {
        // The series RLC of the ACCircuit tests: at f₀ the current is 23 A in phase, |U_C| = 2300 V
        let f0 = 1 / (2 * Double.pi * 1e-3)
        let elements = try Circuit.parse("U1 1 0 230\nR1 1 2 10\nL1 2 3 0,1\nC1 3 0 10u")
        let resonance = try Circuit.solve(elements, frequency: f0)
        #expect(close(resonance.currents["R1"], 23) && approx(resonance.potentials["3"]?.magnitude ?? 0, 2300))
        let at50 = try Circuit.solve(elements, frequency: 50)
        let reference = try ACCircuit.analyze(.series, resistance: 10, inductance: 0.1, capacitance: 1e-5, frequency: 50, voltage: 230)
        #expect(close(at50.currents["L1"], reference.current.re, reference.current.im))
    }

    @Test func directCurrentCoilsAndCapacitors() throws {
        // In direct current the coil is a short circuit and the capacitor an open one: I = 1 A, V(3) = 5 V
        let elements = try Circuit.parse("U1 1 0 10\nR1 1 2 5\nL1 2 3 1\nR2 3 0 5\nC1 3 0 1u")
        let s = try Circuit.solve(elements, frequency: 0)
        #expect(close(s.currents["L1"], 1) && close(s.potentials["3"], 5) && close(s.currents["C1"], 0))
        // A part with no path to node 0 has no unique solution.
        #expect(throws: MathError.self) { try Circuit.solve(try Circuit.parse("U1 1 0 5\nR1 1 0 10\nR2 2 3 10"), frequency: 0) }
    }
}
