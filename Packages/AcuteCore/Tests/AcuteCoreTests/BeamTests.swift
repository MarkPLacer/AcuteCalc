import Foundation
import Testing
@testable import AcuteCore

// MARK: Beams: reactions, V(x), M(x)

@Suite struct BeamTests {
    @Test func pointLoadOnSimpleBeam() throws {
        // L = 6, F = 10 at x = 2: R_A = 20/3, R_B = 10/3, M_max = 40/3 under the load
        let beam = try Beam(length: 6, support: .simple(left: 0, right: 6), loads: [.force(10, at: 2)]).validated()
        let r = beam.reactions()
        #expect(approx(r.forces[0].force, 20.0 / 3) && approx(r.forces[1].force, 10.0 / 3))
        #expect(approx(beam.shear(at: 2, rightSide: false), 20.0 / 3) && approx(beam.shear(at: 2), -10.0 / 3))
        let peak = beam.maximumMoment()
        #expect(approx(peak.position, 2) && approx(peak.value, 40.0 / 3))
        #expect(approx(beam.moment(at: 6, rightSide: false), 0))
    }

    @Test func distributedLoads() throws {
        // q = 2 over L = 6: R = 6 each, M_max = qL²/8 = 9 at the middle
        let uniform = Beam(length: 6, support: .simple(left: 0, right: 6), loads: [.distributed(start: 2, end: 2, from: 0, to: 6)])
        #expect(approx(uniform.reactions().forces[0].force, 6) && approx(uniform.reactions().forces[1].force, 6))
        let peak = uniform.maximumMoment()
        #expect(approx(peak.position, 3) && approx(peak.value, 9))
        // Triangle 0 → 3 over L = 6: R_A = 3, R_B = 6, M_max = 2√12 at x = √12
        let triangle = Beam(length: 6, support: .simple(left: 0, right: 6), loads: [.distributed(start: 0, end: 3, from: 0, to: 6)])
        #expect(approx(triangle.reactions().forces[0].force, 3) && approx(triangle.reactions().forces[1].force, 6))
        let top = triangle.maximumMoment()
        #expect(approx(top.position, 12.0.squareRoot(), 1e-8) && approx(top.value, 2 * 12.0.squareRoot(), 1e-8))
    }

    @Test func cantilevers() throws {
        // Fixed at 0, F = 5 at the free end x = 3: R = 5, M_A = 15 counterclockwise, M(0⁺) = −15
        let left = Beam(length: 3, support: .fixedLeft, loads: [.force(5, at: 3)])
        #expect(left.reactions().forces[0].force == 5 && left.reactions().moment == 15)
        #expect(approx(left.moment(at: 0), -15) && approx(left.moment(at: 3, rightSide: false), 0))
        #expect(approx(left.moment(at: 1.5), -7.5))
        // Fixed at L = 3, F = 5 at x = 0: M_B = −15, M(L⁻) = −15
        let right = Beam(length: 3, support: .fixedRight, loads: [.force(5, at: 0)])
        #expect(right.reactions().moment == -15)
        #expect(approx(right.moment(at: 3, rightSide: false), -15) && approx(right.moment(at: 0, rightSide: false), 0))
        #expect(approx(right.maximumMoment().value, -15))
    }

    @Test func coupleAndOverhang() throws {
        // A counterclockwise couple 12 at x = 2 on L = 6: R_A = 2, R_B = −2, M jumps from 4 to −8
        let couple = Beam(length: 6, support: .simple(left: 0, right: 6), loads: [.couple(12, at: 2)])
        #expect(approx(couple.reactions().forces[0].force, 2) && approx(couple.reactions().forces[1].force, -2))
        #expect(approx(couple.moment(at: 2, rightSide: false), 4) && approx(couple.moment(at: 2), -8))
        // Supports at 0 and 4, F = 6 at the tip x = 6: R_A = −3, R_B = 9, M(4) = −12
        let overhang = Beam(length: 6, support: .simple(left: 0, right: 4), loads: [.force(6, at: 6)])
        #expect(approx(overhang.reactions().forces[0].force, -3) && approx(overhang.reactions().forces[1].force, 9))
        #expect(approx(overhang.moment(at: 4), -12) && approx(overhang.moment(at: 6, rightSide: false), 0))
        #expect(throws: MathError.self) { try Beam(length: 6, support: .simple(left: 4, right: 2), loads: []).validated() }
        #expect(throws: MathError.self) { try Beam(length: 6, support: .fixedLeft, loads: [.force(1, at: 7)]).validated() }
    }
}

// MARK: Least squares adjustment

@Suite struct LeastSquaresTests {
    @Test func lineThroughFourPoints() throws {
        // y = kx + n through (0; 1), (1; 3), (2; 5,1), (3; 6,9): k = 1,98, n = 1,03, σ₀ = √(0,018/2)
        let a: [[Double]] = [[0, 1], [1, 1], [2, 1], [3, 1]]
        let fit = try LeastSquares.adjust(design: a, observations: [1, 3, 5.1, 6.9])
        #expect(approx(fit.parameters[0], 1.98) && approx(fit.parameters[1], 1.03))
        #expect(approx(fit.residuals[2], -0.11) && approx(fit.weightedSquares, 0.018))
        #expect(fit.redundancy == 2 && approx(fit.sigma ?? 0, (0.009).squareRoot()))
        #expect(approx(fit.cofactors[0][0], 0.2) && approx(fit.cofactors[0][1], -0.3) && approx(fit.cofactors[1][1], 0.7))
        let deviations = try #require(fit.standardDeviations)
        #expect(approx(deviations[0], (0.009 * 0.2).squareRoot()))
        // Equal weights 2: the same x̂, vᵀPv doubled, Q halved
        let weighted = try LeastSquares.adjust(design: a, observations: [1, 3, 5.1, 6.9], weights: [2, 2, 2, 2])
        #expect(approx(weighted.parameters[0], 1.98) && approx(weighted.weightedSquares, 0.036) && approx(weighted.cofactors[0][0], 0.1))
        #expect(throws: MathError.self) { try LeastSquares.adjust(design: [[1, 1], [2, 2]], observations: [1, 2]) }
    }
}
