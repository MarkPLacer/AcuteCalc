import AcuteCore
import Foundation
import Metal
import Testing
@testable import AcuteCalc

/// Float overflows beyond FLT_MAX ≈ 3.4·10³⁸ (e^88.72), so the GPU interpreters get ±∞ where the CPU still
/// has finite Double values: e^(x²) is +∞ in float for 9.42 < |x| and finite in Double up to |x| = 26.6.
/// Conditions must treat such a value as the huge number it stands for.
@MainActor
@Suite(.enabled(if: MTLCreateSystemDefaultDevice() != nil, "needs a Metal device"))
struct OverflowGPUTests {
    private let realSlots: [String: VariableSlot] = ["x": .x, "y": .y]

    /// e^(v²): const e, v, square, pow.
    private static func huge(_ v: Expr) -> Expr { .power(.constant(.e), .power(v, .int(2))) }

    /// Operand pairs of the comparisons: +1 is e^(v²), −1 is −e^(v²), 0 is the constant 5.
    private static let pairs: [(Double, Double)] = [(1, 0), (-1, 0), (0, 1), (1, -1)]

    private static func operand(_ kind: Double, _ v: Expr) -> Expr {
        if kind == 0 { return .int(5) }
        return kind > 0 ? huge(v) : .negation(huge(v))
    }

    private static func value(_ kind: Double, _ x: Double) -> Double {
        kind == 0 ? 5 : kind * Foundation.exp(x * x)
    }

    private static func holds(_ op: RelationOperator, _ a: Double, _ b: Double) -> Bool {
        switch op {
        case .less: a < b
        case .lessOrEqual: a <= b
        case .greater: a > b
        case .greaterOrEqual: a >= b
        case .equal: a == b
        case .notEqual: a != b
        }
    }

    // MARK: bc_compare with an infinite operand

    /// {1 if a op b; 0} with (a, b) = (e^(x²), 5), (−e^(x²), 5), (5, e^(x²)), (e^(x²), −e^(x²)) at x = 10, −12
    /// and 20: e^100, e^144 and e^400 are finite in Double (2.7·10⁴³ … 5.2·10¹⁷³) and +∞ in float. bc_compare's
    /// tolerance 10⁻⁶·max(1, |a|, |b|) was ∞ there, so ∞ ≤ 5, −∞ ≥ 5, ∞ = 5, 5 = ∞ and ∞ = −∞ held and every
    /// ≠ failed (float32 emulation: 30 of the 72 comparisons per interpreter wrong). The order of such operands
    /// is exact: the expected values are the comparisons of the Double values, which RealVM and ComplexVM give.
    @Test func comparisonsWithAnOverflowedOperandAreExact() throws {
        let gpu = try ShaderPrecisionGPU()
        let xs: [Double] = [10, -12, 20]
        let points = xs.map { SIMD2<Float>(Float($0), 0) }
        let z = Expr.variable("z")
        for (left, right) in Self.pairs {
            for op in RelationOperator.allCases {
                let condition = Expr.relation(Self.operand(left, .x), op, Self.operand(right, .x))
                let program = try BytecodeCompiler(slots: realSlots).compile(.piecewise([.one, condition, .zero]))
                let cpu = RealVM(program: program)
                for interpreter in [ShaderPrecisionGPU.Interpreter.real, .dual] {
                    let values = try gpu.evaluate(program, interpreter, at: points).values
                    for (x, v) in zip(xs, values) {
                        let expected: Double = Self.holds(op, Self.value(left, x), Self.value(right, x)) ? 1 : 0
                        #expect(cpu.evaluate(x: x) == expected, "CPU: \(condition) at x = \(x)")
                        #expect(Double(v.x) == expected, "\(interpreter): \(condition) at x = \(x) gives \(v.x)")
                    }
                }
                // Complex plots and landscapes compare real parts with the same function.
                let complexCondition = Expr.relation(Self.operand(left, z), op, Self.operand(right, z))
                let complexProgram = try BytecodeCompiler(slots: ["z": .z], complexMode: true)
                    .compile(.piecewise([.one, complexCondition, .zero]))
                let complexCPU = ComplexVM(program: complexProgram)
                let complexValues = try gpu.evaluate(complexProgram, .complex, at: points).values
                for (x, v) in zip(xs, complexValues) {
                    let expected: Double = Self.holds(op, Self.value(left, x), Self.value(right, x)) ? 1 : 0
                    #expect(complexCPU.evaluate(z: Complex(x, 0)).re == expected, "CPU: \(complexCondition) at z = \(x)")
                    #expect(Double(v.x) == expected, "complex: \(complexCondition) at z = \(x) gives \(v.x)")
                }
            }
        }
    }

    /// 'y = 2, y ≥ e^(x²)' is drawn as the curve y − 2 = 0 restricted to y − e^(x²) ≥ 0 (CalculationEngine's
    /// system graph, compiled as GraphCanvasModel compiles it), i.e. only for |x| ≤ √ln 2 ≈ 0.833. For
    /// |x| > 9.42 the gap y − e^(x²) is −∞ in float and −∞ ≥ 0 held, so y = 2 was drawn there too (the Newton
    /// point passes the same condition). Where the inequality fails the curve is undefined (NaN, as RealVM).
    @Test func systemCurveIsUndefinedWhereTheInequalityFails() throws {
        let gpu = try ShaderPrecisionGPU()
        let condition = Expr.relation(Expr.y - Self.huge(.x), .greaterOrEqual, .zero)
        let lhs = Expr.piecewise([Expr.y - .int(2), condition])
        let program = try BytecodeCompiler(slots: realSlots).compile(.sum([lhs, .negation(.zero)]))
        let cpu = RealVM(program: program)
        // (x, y, F): outside the region F is NaN; inside it is y − 2 (e^0.25 = 1.28 ≤ 2, e^0.0625 = 1.06 ≤ 1.5).
        let cases: [(Float, Float, Double)] = [(10, 2, .nan), (-12, 2, .nan), (20, 2, .nan), (15, 2.5, .nan),
                                               (0.5, 2, 0), (0.5, 3, 1), (-0.25, 1.5, -0.5)]
        let points = cases.map { SIMD2<Float>($0.0, $0.1) }
        for interpreter in [ShaderPrecisionGPU.Interpreter.real, .dual] {
            let values = try gpu.evaluate(program, interpreter, at: points).values
            for (c, v) in zip(cases, values) {
                let onCPU = cpu.evaluate(x: Double(c.0), y: Double(c.1))
                if c.2.isNaN {
                    #expect(onCPU.isNaN, "CPU: F(\(c.0), \(c.1)) = \(onCPU)")
                    #expect(v.x.isNaN, "\(interpreter): F(\(c.0), \(c.1)) = \(v.x) although \(c.1) < e^\(c.0 * c.0)")
                } else {
                    #expect(onCPU == c.2, "CPU: F(\(c.0), \(c.1)) = \(onCPU)")
                    #expect(Double(v.x) == c.2, "\(interpreter): F(\(c.0), \(c.1)) = \(v.x)")
                }
            }
        }
    }
}
