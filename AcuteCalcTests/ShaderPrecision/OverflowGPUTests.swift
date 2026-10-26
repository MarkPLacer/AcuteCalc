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

    // MARK: Inequality regions past a float overflow

    private static let size = 240

    /// lhs relation rhs as GraphCanvasModel builds it (program of lhs − rhs), rendered by the app's
    /// Graph2DEncoder as in Graph2DShaderGPUTests (240 × 240 px, 36 px per unit), white fill on black and a
    /// transparent boundary line, so a pixel above 128 is filled.
    private func region(_ lhs: Expr, _ rhs: Expr, mode: Int32, center: SIMD2<Double>) throws -> [UInt8] {
        let program = try BytecodeCompiler(slots: realSlots).compile(.sum([lhs, .negation(rhs)]))
        var scene = GraphScene()
        scene.implicits = [GraphScene.Implicit(id: "r", program: program, parameters: [],
                                               color: .rgba(0, 0, 0, 0), fillColor: .rgba(1, 1, 1), mode: mode)]
        return try GraphRenderHarness.render(scene, pointsPerUnit: 12, contentScale: 3, width: Self.size, height: Self.size,
                                             center: center)
    }

    private func filled(_ pixels: [UInt8]) -> Int { pixels.filter { $0 > 128 }.count }

    private func filled(_ pixels: [UInt8], columns: ClosedRange<Int>) -> Int {
        var count = 0
        for row in 0..<Self.size {
            for px in columns where pixels[row * Self.size + px] > 128 { count += 1 }
        }
        return count
    }

    /// View x ∈ [86.7, 93.3], y ∈ [−3.3, 3.3]: every visible y is below e^x ≥ 4.4·10³⁷. Up to the float
    /// overflow at x = 88.7228 (ln FLT_MAX; column 73 is centred at x = 88.708) F = y − e^x is finite, and
    /// y < e^x and e^x > y fill every pixel (float32 emulation: 74 · 240); y > e^x and y ≥ e^x hold nowhere.
    /// From column 74 (x = 88.736) on F is ±∞ and the region is left empty, see
    /// overflowShrunkBackIntoViewIsNotFilled.
    @Test func regionIsFilledUpToAnOverflow() throws {
        let eToX = Expr.power(.constant(.e), .x)
        let below = try region(.y, eToX, mode: 1, center: SIMD2(90, 0))
        #expect(filled(below, columns: 0...73) == 74 * Self.size)
        let exceeds = try region(eToX, .y, mode: 3, center: SIMD2(90, 0))
        #expect(filled(exceeds, columns: 0...73) == 74 * Self.size)
        let above = try region(.y, eToX, mode: 3, center: SIMD2(90, 0))
        #expect(filled(above) == 0)
        let aboveOrOn = try region(.y, eToX, mode: 4, center: SIMD2(90, 0))
        #expect(filled(aboveOrOn) == 0)
    }

    /// ln(1 + e^x) = x + ln(1 + e^(−x)) lies within 10⁻³⁷ of x in this view (x, y ∈ [86.7, 93.3]), but e^x
    /// overflows float beyond x = 88.7228 and ln(+∞) = +∞, so F = y − ln(1 + e^x) is −∞ there for every y, also
    /// above the line y = x where y < ln(1 + e^x) fails. A float ±∞ does not tell such an overflow from a huge F,
    /// so the region is filled only where F is finite. With ±∞ filled as well the float32 emulation fills
    /// 13603 px above y = x + 1/36, now 0; left of the overflow all 2660 px below y = x − 1/36 are filled. The
    /// one-pixel margin is far above the float error of F and of the pixel centres (below 10⁻⁴).
    @Test func overflowShrunkBackIntoViewIsNotFilled() throws {
        let softplus = Expr.function(.ln, [Expr.one + Expr.power(.constant(.e), .x)])
        let pixels = try region(.y, softplus, mode: 1, center: SIMD2(90, 90))
        let half = Double(Self.size) / 2
        var wronglyFilled = 0
        var below = 0
        var belowFilled = 0
        for row in 0..<Self.size {
            let y = 90 + (half - Double(row) - 0.5) / 36
            for px in 0..<Self.size {
                let x = 90 + (Double(px) + 0.5 - half) / 36
                let isFilled = pixels[row * Self.size + px] > 128
                if isFilled && y > x + 1.0 / 36 { wronglyFilled += 1 }
                if x < 88.72 && y < x - 1.0 / 36 {
                    below += 1
                    if isFilled { belowFilled += 1 }
                }
            }
        }
        #expect(wronglyFilled == 0)
        #expect(below == 2660)
        #expect(belowFilled == below)
    }

    /// cot(⌊x⌋) is undefined on [0, 1) (cot 0), so y < cot(⌊x⌋) fills nothing there (cot 0 was 1/tan(0) = +∞,
    /// which the finite-F guard leaves empty as well; with ±∞ filled the emulation gave 8640 px). On [1, 2)
    /// y < cot 1 = 0.642 is filled in rows 97–239 (row 97 is at y = 0.625, row 96 at 0.653). Column px is
    /// centred at x = 0.5 + (px + 0.5 − 120)/36.
    @Test func exactPolesAreNotFilled() throws {
        let pixels = try region(.y, .function(.cot, [.function(.floor, [.x])]), mode: 1, center: SIMD2(0.5, 0))
        #expect(filled(pixels, columns: 102...137) == 0)
        #expect(filled(pixels, columns: 138...173) == 36 * 143)
    }

    /// cot, csc, coth and csch at 0 and root(−2; x) at 0 divide by an exact zero. Like x/0, 1/x and 0^(−1) in
    /// the same interpreters (and cot 0, csc 0, coth 0, csch 0 in the calculator's RealEvaluator) they are
    /// undefined (NaN); they were 1/0 = +∞. Away from the pole the values are unchanged (CPU in Double; the
    /// float error is a few ulps of values below 2.2, about 10⁻⁶).
    @Test func reciprocalFunctionsAreUndefinedAtTheirPoles() throws {
        let gpu = try ShaderPrecisionGPU()
        let functions: [Expr] = [.function(.cot, [.x]), .function(.csc, [.x]), .function(.coth, [.x]),
                                 .function(.csch, [.x]), .function(.root, [.int(-2), .x])]
        let points: [SIMD2<Float>] = [SIMD2(0, 0), SIMD2(0.5, 0)]
        for f in functions {
            let program = try BytecodeCompiler(slots: realSlots).compile(f)
            let away = RealVM(program: program).evaluate(x: 0.5)
            for interpreter in [ShaderPrecisionGPU.Interpreter.real, .dual] {
                let values = try gpu.evaluate(program, interpreter, at: points).values
                #expect(values[0].x.isNaN, "\(interpreter): \(f) at 0 = \(values[0].x)")
                #expect(abs(Double(values[1].x) - away) < 1e-5, "\(interpreter): \(f) at 0.5 = \(values[1].x), CPU \(away)")
            }
        }
    }
}
