import AcuteCore
import Foundation
import Metal
import Testing
@testable import AcuteCalc

/// The GPU bytecode interpreters (bc_eval_real, bc_eval_dual, bc_eval_complex) against the CPU virtual
/// machines of AcuteCore (Double). A float32 rounding is at most 2⁻²⁴ ≈ 6·10⁻⁸ relative, so values that
/// are exact in float must match to 1e-6 (a few ulps around 1…8); errors of the old code are of order 1.
@MainActor
@Suite(.enabled(if: MTLCreateSystemDefaultDevice() != nil, "needs a Metal device"))
struct BytecodeInterpreterGPUTests {
    private let realSlots: [String: VariableSlot] = ["x": .x, "y": .y]

    /// arg of a real number is π below zero and 0 otherwise (RealVM, bc_eval_real). bc_eval_dual had no
    /// BCOpArg case and returned x itself, so y < arg(x) was drawn as y < x (SHD-03). Its gradient is 0.
    @Test func dualInterpreterArgMatchesCPU() throws {
        let gpu = try ShaderPrecisionGPU()
        let program = try BytecodeCompiler(slots: realSlots).compile(.function(.arg, [.x]))
        let points: [SIMD2<Float>] = [SIMD2(2, 0), SIMD2(-2, 0), SIMD2(0.5, 1), SIMD2(-0.25, -3)]
        let cpu = RealVM(program: program)
        for interpreter in [ShaderPrecisionGPU.Interpreter.real, .dual] {
            let values = try gpu.evaluate(program, interpreter, at: points).values
            for (p, v) in zip(points, values) {
                let expected = cpu.evaluate(x: Double(p.x), y: Double(p.y))
                // The float π of the shader differs from π by 8.7·10⁻⁸.
                #expect(abs(Double(v.x) - expected) < 1e-6, "\(interpreter): arg(\(p.x)) = \(v.x), CPU \(expected)")
                if interpreter == .dual {
                    #expect(v.y == 0 && v.z == 0, "∂ arg(\(p.x)) = (\(v.y), \(v.z))")
                }
            }
        }
    }

    /// mod takes the sign of the divisor everywhere on the CPU (mod(−1; 3) = 2); bc_eval_complex used fmod
    /// (sign of the dividend: −1), so domain colouring and 3D landscapes disagreed with the probe (SHD-04).
    @Test func modWithNegativeOperandsMatchesCPU() throws {
        let gpu = try ShaderPrecisionGPU()
        let z = Expr.variable("z")
        let divisors: [Expr] = [.int(3), .decimal(-2.5)]
        // Values and divisors are exact floats, so are the remainders: 2, 1.5, 1.75, 0, … and −1.5, −1, ….
        let points: [SIMD2<Float>] = [SIMD2(-1, 0), SIMD2(7.5, 0), SIMD2(-7.25, 0), SIMD2(1, 0), SIMD2(-6, 0), SIMD2(4.5, 2)]
        for divisor in divisors {
            let complexProgram = try BytecodeCompiler(slots: ["z": .z], complexMode: true).compile(.function(.mod, [z, divisor]))
            let complexCPU = ComplexVM(program: complexProgram)
            let complexValues = try gpu.evaluate(complexProgram, .complex, at: points).values
            for (p, v) in zip(points, complexValues) {
                let expected = complexCPU.evaluate(z: Complex(Double(p.x), Double(p.y)))
                #expect(abs(Double(v.x) - expected.re) < 1e-6, "complex mod(\(p.x) + \(p.y)i; \(divisor)) = \(v.x), CPU \(expected.re)")
                #expect(v.y == 0)
            }
            let realProgram = try BytecodeCompiler(slots: realSlots).compile(.function(.mod, [.x, divisor]))
            let realCPU = RealVM(program: realProgram)
            for interpreter in [ShaderPrecisionGPU.Interpreter.real, .dual] {
                let values = try gpu.evaluate(realProgram, interpreter, at: points).values
                for (p, v) in zip(points, values) {
                    let expected = realCPU.evaluate(x: Double(p.x), y: Double(p.y))
                    #expect(abs(Double(v.x) - expected) < 1e-6, "\(interpreter): mod(\(p.x); \(divisor)) = \(v.x), CPU \(expected)")
                }
            }
        }
    }

    /// ζ(0) = −1/2 (DLMF 25.6.1). The functional equation used for Re s < ½ is 0·∞ at s = 0, so c_zeta
    /// returned NaN (SHD-02). Checked against the reference value: the CPU fix of Complex.zeta is separate.
    @Test func zetaAtZeroIsMinusOneHalf() throws {
        let gpu = try ShaderPrecisionGPU()
        let origin: [SIMD2<Float>] = [SIMD2(0, 0)]
        let complexProgram = try BytecodeCompiler(slots: ["z": .z], complexMode: true).compile(.function(.zeta, [.variable("z")]))
        let complexValue = try gpu.evaluate(complexProgram, .complex, at: origin).values[0]
        #expect(complexValue.x == -0.5, "complex ζ(0) = \(complexValue.x)")
        #expect(complexValue.y == 0)
        let realProgram = try BytecodeCompiler(slots: realSlots).compile(.function(.zeta, [.x]))
        for interpreter in [ShaderPrecisionGPU.Interpreter.real, .dual] {
            let value = try gpu.evaluate(realProgram, interpreter, at: origin).values[0]
            #expect(value.x == -0.5, "\(interpreter): ζ(0) = \(value.x)")
        }
    }

    /// The neighbouring values are unchanged and agree with the CPU: ζ(2) = π²/6, ζ(3), ζ(4) = π⁴/90 (series
    /// for Re s ≥ ½) and ζ(−1) = −1/12 (functional equation). The 64-term float series is good to ~1e-7
    /// (float32 emulation: ζ(2) off by 9·10⁻⁹, ζ(3) and ζ(4) by 1.6·10⁻⁷); 4e-6 allows 4-ulp exp/log per term.
    @Test func zetaNeighboursMatchCPU() throws {
        let gpu = try ShaderPrecisionGPU()
        let points: [SIMD2<Float>] = [SIMD2(2, 0), SIMD2(3, 0), SIMD2(4, 0), SIMD2(-1, 0)]
        let complexProgram = try BytecodeCompiler(slots: ["z": .z], complexMode: true).compile(.function(.zeta, [.variable("z")]))
        let complexCPU = ComplexVM(program: complexProgram)
        let complexValues = try gpu.evaluate(complexProgram, .complex, at: points).values
        let realProgram = try BytecodeCompiler(slots: realSlots).compile(.function(.zeta, [.x]))
        let realCPU = RealVM(program: realProgram)
        let realValues = try gpu.evaluate(realProgram, .real, at: points).values
        for i in points.indices {
            let s = Double(points[i].x)
            let expected = complexCPU.evaluate(z: Complex(s, 0)).re
            #expect(abs(Double(complexValues[i].x) - expected) < 4e-6, "complex ζ(\(s)) = \(complexValues[i].x), CPU \(expected)")
            #expect(abs(Double(realValues[i].x) - realCPU.evaluate(x: s)) < 4e-6, "real ζ(\(s)) = \(realValues[i].x)")
        }
        #expect(abs(realCPU.evaluate(x: 2) - Double.pi * Double.pi / 6) < 1e-12)
    }

    /// nCr and nPr with a huge k: bc_combination looped k times per pixel (10⁸ iterations per thread here:
    /// seconds of GPU time or a command-buffer timeout, SHD-08). Beyond k = 66 (nCr) and k = 35 (nPr) the
    /// result exceeds FLT_MAX: C(132, 66) ≈ 3.8·10³⁸ and 35! ≈ 1.0·10⁴⁰ (Python math.comb, math.factorial).
    @Test func combinationsWithHugeKAreInfiniteAndFast() throws {
        let gpu = try ShaderPrecisionGPU()
        let nCr = try BytecodeCompiler(slots: realSlots).compile(.function(.nCr, [.x, .y]))
        let nPr = try BytecodeCompiler(slots: realSlots).compile(.function(.nPr, [.x, .y]))
        // 2·10⁸ and 10⁸ are exact floats (multiples of 16 below 2²⁸).
        let huge = [SIMD2<Float>](repeating: SIMD2(2e8, 1e8), count: 4096)
        for program in [nCr, nPr] {
            for interpreter in [ShaderPrecisionGPU.Interpreter.real, .dual, .complex] {
                let result = try gpu.evaluate(program, interpreter, at: huge)
                // Fixed: microseconds of GPU work; before: the loop ran 10⁸ times in each of 4096 threads.
                try #require(result.duration < .seconds(1), "\(interpreter): \(result.duration) for k = 10⁸")
                let allInfinite = result.values.allSatisfy { $0.x == .infinity }
                #expect(allInfinite, "\(interpreter): \(result.values[0].x)")
            }
        }
    }

    /// Below those bounds the loop is unchanged and agrees with the CPU (k ≤ 30 iterations with two
    /// roundings each: ≤ 60 · 2⁻²⁴ ≈ 3.6·10⁻⁶ relative; overflowing results are +∞ in float).
    @Test func combinationsAgreeWithCPU() throws {
        let gpu = try ShaderPrecisionGPU()
        let points: [SIMD2<Float>] = [SIMD2(10, 3), SIMD2(60, 30), SIMD2(30, 10), SIMD2(132, 66), SIMD2(40, 35), SIMD2(5, 7), SIMD2(66, 1)]
        for function in [MathFunction.nCr, .nPr] {
            let program = try BytecodeCompiler(slots: realSlots).compile(.function(function, [.x, .y]))
            let cpu = RealVM(program: program)
            for interpreter in [ShaderPrecisionGPU.Interpreter.real, .dual, .complex] {
                let values = try gpu.evaluate(program, interpreter, at: points).values
                for (p, v) in zip(points, values) {
                    let expected = Float(cpu.evaluate(x: Double(p.x), y: Double(p.y)))
                    if expected.isInfinite {
                        #expect(v.x == expected, "\(interpreter) \(function)(\(p.x); \(p.y)) = \(v.x), CPU \(expected)")
                    } else {
                        #expect(abs(v.x - expected) <= 1e-5 * max(1, abs(expected)), "\(interpreter) \(function)(\(p.x); \(p.y)) = \(v.x), CPU \(expected)")
                    }
                }
            }
        }
    }
}
