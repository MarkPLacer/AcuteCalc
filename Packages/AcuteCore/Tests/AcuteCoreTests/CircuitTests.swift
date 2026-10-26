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
        // Huge resistances next to an ideal source still divide the voltage.
        let megaohms = try Circuit.solve(try Circuit.parse("U1 1 0 1\nR1 1 2 1e14\nR2 2 0 1e14"), frequency: 0)
        #expect(close(megaohms.potentials["2"], 0.5))
        // Their current of 5·10⁻¹⁵ A and power of 2,5·10⁻¹⁵ W are kept, not rounded to 0.
        #expect(abs((megaohms.currents["R1"]?.re ?? 0) / 5e-15 - 1) < 1e-9)
        let r1 = try #require(try Circuit.parse("R1 1 2 1e14").first)
        #expect(abs(megaohms.power(r1).re / 2.5e-15 - 1) < 1e-9)
        // A balanced bridge: no voltage and no current across the middle branch.
        let bridge = try Circuit.parse("U1 1 0 10\nR1 1 2 3\nR2 2 0 7\nR3 1 3 3\nR4 3 0 7\nR5 2 3 11")
        let balanced = try Circuit.solve(bridge, frequency: 0)
        #expect(balanced.voltage(bridge[5]).magnitude == 0 && balanced.power(bridge[5]).magnitude == 0)
        // A small imaginary part next to a large real one is kept.
        #expect(Circuit.clean(Complex(1e12, 1)).im == 1)
        // In direct current a source has no phase.
        #expect(throws: MathError.self) { try Circuit.solve(try Circuit.parse("U1 1 0 10 90\nR1 1 0 5"), frequency: 0) }
        // An element called I_test does not clash with the test source of the Thévenin calculation.
        let named = try Circuit.parse("U1 1 0 12\nI_test 0 1 0\nR1 1 2 4\nR2 2 0 6")
        #expect(close(try Circuit.thevenin(named, frequency: 0, between: "2", and: "0").impedance, 2.4))
        // A part with no path to node 0 has no unique solution.
        #expect(throws: MathError.self) { try Circuit.solve(try Circuit.parse("U1 1 0 5\nR1 1 0 10\nR2 2 3 10"), frequency: 0) }
    }
}

// MARK: Plane trusses

@Suite struct TrussTests {
    @Test func triangle() throws {
        // A(0; 0) pin, B(4; 0) roller, 10 down at C(2; 2): AB = +5 (tension), AC = BC = −5√2, reactions 5 and 5
        let joints: [SIMD2<Double>] = [SIMD2(0, 0), SIMD2(4, 0), SIMD2(2, 2)]
        let bars = [Truss.Bar(from: 0, to: 1), Truss.Bar(from: 0, to: 2), Truss.Bar(from: 1, to: 2)]
        let s = try Truss.solve(joints: joints, bars: bars, supports: [.pin(0), .roller(1, angle: .pi / 2)],
                                loads: [Truss.Load(joint: 2, fx: 0, fy: -10)])
        #expect(approx(s.forces[0], 5) && approx(s.forces[1], -5 * 2.0.squareRoot()) && approx(s.forces[2], -5 * 2.0.squareRoot()))
        #expect(approx(s.reactions[0].x, 0) && approx(s.reactions[0].y, 5) && approx(s.reactions[1].y, 5))
        // A load of 10⁻¹⁵ gives forces 10⁻¹⁶ times as large, not zero ones.
        let tiny = try Truss.solve(joints: joints, bars: bars, supports: [.pin(0), .roller(1, angle: .pi / 2)],
                                   loads: [Truss.Load(joint: 2, fx: 0, fy: -1e-15)])
        #expect(abs(tiny.forces[0] / 5e-16 - 1) < 1e-9 && tiny.reactions[0].x == 0)
        // Huge coordinates do not overflow the bar lengths.
        let huge = try Truss.solve(joints: joints.map { $0 * 1e160 }, bars: bars, supports: [.pin(0), .roller(1, angle: .pi / 2)],
                                   loads: [Truss.Load(joint: 2, fx: 0, fy: -10)])
        #expect(approx(huge.forces[0], 5))
    }

    @Test func determinacyAndStability() {
        let joints: [SIMD2<Double>] = [SIMD2(0, 0), SIMD2(4, 0), SIMD2(2, 2)]
        let bars = [Truss.Bar(from: 0, to: 1), Truss.Bar(from: 0, to: 2), Truss.Bar(from: 1, to: 2)]
        let load = [Truss.Load(joint: 2, fx: 0, fy: -10)]
        // One reaction too many, one too few
        #expect(throws: MathError.self) { try Truss.solve(joints: joints, bars: bars, supports: [.pin(0), .pin(1)], loads: load) }
        #expect(throws: MathError.self) { try Truss.solve(joints: joints, bars: bars, supports: [.pin(0)], loads: load) }
        // Three joints on a line: the counts agree, but the middle joint cannot carry a vertical load.
        let line: [SIMD2<Double>] = [SIMD2(0, 0), SIMD2(1, 0), SIMD2(2, 0)]
        let straight = [Truss.Bar(from: 0, to: 1), Truss.Bar(from: 1, to: 2), Truss.Bar(from: 0, to: 2)]
        #expect(throws: MathError.self) {
            try Truss.solve(joints: line, bars: straight, supports: [.pin(0), .roller(2, angle: .pi / 2)], loads: [Truss.Load(joint: 1, fx: 0, fy: -1)])
        }
    }
}

// MARK: Tests of association

@Suite struct AssociationTests {
    @Test func independence() throws {
        // [[10, 20], [30, 40]]: E = [[12, 18], [28, 42]], χ² = 4/12 + 4/18 + 4/28 + 4/42, 1 degree of freedom
        let result = try Inference.chiSquareIndependence([[10, 20], [30, 40]])
        let chi = 4.0 / 12 + 4.0 / 18 + 4.0 / 28 + 4.0 / 42
        #expect(approx(result.test.statistic, chi) && result.test.degrees == [1])
        #expect(approx(result.expected[0][0], 12) && approx(result.expected[1][1], 42))
        #expect(approx(result.test.pValue, 1 - (try Distributions.chiSquareCDF(chi, degrees: 1))))
        #expect(approx(result.cramer, (chi / 100).squareRoot()))
        #expect(throws: MathError.self) { try Inference.chiSquareIndependence([[1, 2], [0, 0]]) }
        #expect(throws: MathError.self) { try Inference.chiSquareIndependence([[1, 2, 3], [4, 5]]) }
    }

    @Test func correlation() throws {
        // r = 0,5 of 27 pairs: t = 0,5·5/√0,75
        let test = try Inference.correlationTest(r: 0.5, count: 27)
        #expect(approx(test.statistic, 2.5 / 0.75.squareRoot()) && test.degrees == [25])
        #expect(test.pValue > 0.005 && test.pValue < 0.01)
        #expect(throws: MathError.self) { try Inference.correlationTest(r: 1, count: 10) }
    }

    @Test func strongAssociationKeepsItsPValue() throws {
        // A perfect 2 × 2 association of n = 200 has χ² = n and, with 1 degree of freedom,
        // p = erfc(√(χ²/2)) = erfc(10) ≈ 2·10⁻⁴⁵, which 1 − P(X ≤ χ²) would round to 0.
        let strong = try Inference.chiSquareIndependence([[100, 0], [0, 100]])
        #expect(approx(strong.test.statistic, 200) && approx(strong.cramer, 1))
        #expect(abs(strong.test.pValue / erfc(10) - 1) < 1e-10)
        // Huge but finite counts give finite results instead of NaN.
        let huge = try Inference.chiSquareIndependence([[1e300, 0], [0, 1e300]])
        #expect(abs(huge.test.statistic / 2e300 - 1) < 1e-12)
        #expect(approx(huge.cramer, 1) && huge.test.pValue == 0)
        #expect(throws: MathError.self) { try Inference.chiSquareIndependence([[1e308, 1e308], [1e308, 1e308]]) }
        // r = 0,9 of 100 pairs: p = 4,06340527749064·10⁻³⁷ (the exact series for an even ν), not 0.
        let correlation = try Inference.correlationTest(r: 0.9, count: 100)
        #expect(abs(correlation.pValue / 4.06340527749064e-37 - 1) < 1e-9)
    }
}
