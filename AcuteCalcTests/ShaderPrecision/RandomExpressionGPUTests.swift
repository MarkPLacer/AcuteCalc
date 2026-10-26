import AcuteCore
import Foundation
import Metal
import Testing
@testable import AcuteCalc

/// SplitMix64 (Steele, Lea & Flood 2014): a tiny generator with the same sequence on every run and platform.
nonisolated struct SplitMix64 {
    var state: UInt64

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    mutating func int(_ n: Int) -> Int { Int(next() % UInt64(n)) }

    /// Uniform in [0, 1).
    mutating func unit() -> Double { Double(next() >> 11) * 0x1p-53 }
}

/// A random expression built from operations whose float32 error can be bounded (see `bound`).
nonisolated enum RandomExpression {
    nonisolated enum Unary: CaseIterable {
        case neg, square, cube, sin, cos, atan, tanh, exp, sqrt1p, ln1p, abs, floor, arg
    }

    nonisolated enum Binary: CaseIterable {
        case add, sub, mul, div, min, max, mod
    }

    case x, y
    case constant(Double)
    indirect case unary(Unary, RandomExpression)
    indirect case binary(Binary, RandomExpression, RandomExpression)

    /// Exact floats, so constants carry no rounding error.
    static let constants: [Double] = [0.5, 2, 3, -1.5, 0.25, 1.75, -0.75, 5]
    static let divisors: [Double] = [-2.5, 1.5, 3]

    /// Complex expressions use only x (the variable z) and no arg (its branch cut on the negative axis
    /// turns float noise in the imaginary part into a jump of 2π).
    static func random(depth: Int, _ rng: inout SplitMix64, complex: Bool) -> RandomExpression {
        if depth == 0 || rng.int(4) == 0 {
            switch rng.int(5) {
            case 0, 1: return .x
            case 2: return complex ? .x : .y
            default: return .constant(constants[rng.int(constants.count)])
            }
        }
        if rng.int(2) == 0 {
            let operations = complex ? Unary.allCases.filter { $0 != .arg } : Unary.allCases
            let operation = operations[rng.int(operations.count)]
            return .unary(operation, random(depth: depth - 1, &rng, complex: complex))
        }
        let operation = Binary.allCases[rng.int(Binary.allCases.count)]
        let left = random(depth: depth - 1, &rng, complex: complex)
        let right: RandomExpression = operation == .mod
            ? .constant(divisors[rng.int(divisors.count)])
            : random(depth: depth - 1, &rng, complex: complex)
        return .binary(operation, left, right)
    }

    func expr(x: String, y: String) -> Expr {
        switch self {
        case .x: return .variable(x)
        case .y: return .variable(y)
        case .constant(let c): return .decimal(c)
        case .unary(let operation, let operand):
            let e = operand.expr(x: x, y: y)
            switch operation {
            case .neg: return .negation(e)
            case .square: return .power(e, .int(2))
            case .cube: return .power(e, .int(3))
            case .sin: return .function(.sin, [e])
            case .cos: return .function(.cos, [e])
            case .atan: return .function(.atan, [e])
            case .tanh: return .function(.tanh, [e])
            case .exp: return .function(.exp, [e])
            case .sqrt1p: return .function(.sqrt, [.sum([.int(1), .power(e, .int(2))])])
            case .ln1p: return .function(.ln, [.sum([.int(1), .power(e, .int(2))])])
            case .abs: return .function(.abs, [e])
            case .floor: return .function(.floor, [e])
            case .arg: return .function(.arg, [e])
            }
        case .binary(let operation, let left, let right):
            let a = left.expr(x: x, y: y)
            let b = right.expr(x: x, y: y)
            switch operation {
            case .add: return .sum([a, b])
            case .sub: return .sum([a, .negation(b)])
            case .mul: return .product([a, b])
            case .div: return .quotient(a, b)
            case .min: return .function(.min, [a, b])
            case .max: return .function(.max, [a, b])
            case .mod: return .function(.mod, [a, b])
            }
        }
    }

    /// The value (in Double, with the CPU's semantics) and a bound of the error of a float32 evaluation
    /// on the GPU, by first-order propagation (u = 2⁻²⁴, the float unit roundoff):
    /// - a rounding of + − × costs u·|v| (Metal rounds them correctly), ÷ 4u·|v|;
    /// - Metal's precise sin, cos, atan, tanh, exp and log are within a few ulps; 16u·(|v| + 1) allows
    ///   that plus an absolute u-level term of the complex routes (c_atan takes the log of a quotient);
    ///   sin and cos also allow 4u·|a| for the argument reduction;
    /// - an input error e propagates with the largest slope over [a − e, a + e] (sin, cos, atan, tanh,
    ///   √(1 + a²), ln(1 + a²), |a|, min and max are 1-Lipschitz).
    /// `nil` where such a bound does not hold: near a jump of floor, mod or arg, for a divisor not well
    /// away from 0, for |v| > 10¹⁵ and for complex tanh beyond |a| = 40 (sinh/cosh overflow in c_tanh).
    func bound(x: Double, y: Double, complex: Bool) -> (value: Double, error: Double)? {
        let u = 0x1p-24
        func transcendental(_ v: Double) -> Double { 16 * u * (Swift.abs(v) + 1) }
        let result: (value: Double, error: Double)
        switch self {
        case .x: return (x, 0)
        case .y: return (y, 0)
        case .constant(let c): return (c, 0)
        case .unary(let operation, let operand):
            guard let inner = operand.bound(x: x, y: y, complex: complex) else { return nil }
            let a = inner.value, ea = inner.error
            switch operation {
            case .neg:
                result = (-a, ea)
            case .square:
                let v = a * a
                result = (v, 2 * Swift.abs(a) * ea + ea * ea + 2 * u * Swift.abs(v))
            case .cube:
                let v = a * a * a
                result = (v, 3 * a * a * ea + 3 * Swift.abs(a) * ea * ea + ea * ea * ea + 3 * u * Swift.abs(v))
            case .sin:
                let v = Foundation.sin(a)
                let ra = ea + 4 * u * Swift.abs(a)
                result = (v, Swift.min(1, Swift.abs(Foundation.cos(a)) + ra) * ra + transcendental(v))
            case .cos:
                let v = Foundation.cos(a)
                let ra = ea + 4 * u * Swift.abs(a)
                result = (v, Swift.min(1, Swift.abs(Foundation.sin(a)) + ra) * ra + transcendental(v))
            case .atan:
                let v = Foundation.atan(a)
                result = (v, Swift.min(1, 1 / (1 + a * a) + ea) * ea + transcendental(v))
            case .tanh:
                if complex && Swift.abs(a) >= 40 { return nil }
                let v = Foundation.tanh(a)
                result = (v, Swift.min(1, (1 - v * v) + ea) * ea + transcendental(v))
            case .exp:
                let v = Foundation.exp(a)
                result = (v, Foundation.exp(a + ea) * ea + transcendental(v))
            case .sqrt1p:
                let v = (1 + a * a).squareRoot()
                result = (v, ea + 6 * u * v)
            case .ln1p:
                let v = Foundation.log(1 + a * a)
                result = (v, ea + 4 * u + transcendental(v))
            case .abs:
                result = (Swift.abs(a), ea)
            case .floor:
                guard Swift.abs(a - a.rounded()) > ea + 2 * u * Swift.abs(a) else { return nil }
                result = (Foundation.floor(a), 0)
            case .arg:
                guard Swift.abs(a) > ea else { return nil }
                // The shader's float π differs from π by 8.7·10⁻⁸ < 4u·π.
                result = (a < 0 ? Double.pi : 0, 4 * u * Double.pi)
            }
        case .binary(let operation, let left, let right):
            guard let l = left.bound(x: x, y: y, complex: complex),
                  let r = right.bound(x: x, y: y, complex: complex) else { return nil }
            let a = l.value, ea = l.error, b = r.value, eb = r.error
            switch operation {
            case .add:
                let v = a + b
                result = (v, ea + eb + u * Swift.abs(v))
            case .sub:
                let v = a - b
                result = (v, ea + eb + u * Swift.abs(v))
            case .mul:
                let v = a * b
                result = (v, Swift.abs(a) * eb + Swift.abs(b) * ea + ea * eb + u * Swift.abs(v))
            case .div:
                guard Swift.abs(b) > 4 * eb, Swift.abs(b) >= 1e-15 else { return nil }
                let v = a / b
                result = (v, (ea + Swift.abs(v) * eb) / (Swift.abs(b) - eb) + 4 * u * Swift.abs(v))
            case .min:
                result = (Swift.min(a, b), Swift.max(ea, eb))
            case .max:
                result = (Swift.max(a, b), Swift.max(ea, eb))
            case .mod:
                // b is an exact constant; the result jumps where a/b is an integer.
                let q = a / b
                guard Swift.abs(q - q.rounded()) * Swift.abs(b) > ea + 4 * u * Swift.abs(a) else { return nil }
                let remainder = a.truncatingRemainder(dividingBy: b)
                let v = (remainder != 0 && (remainder < 0) != (b < 0)) ? remainder + b : remainder
                result = (v, ea + 2 * u * (Swift.abs(v) + Swift.abs(b)))
            }
        }
        guard result.value.isFinite, result.error.isFinite, Swift.abs(result.value) <= 1e15 else { return nil }
        return result
    }
}

/// Differential test of the three GPU interpreters against the CPU virtual machines: 300 seeded random
/// expressions (depth ≤ 4: + − × ÷ min max mod, sin cos atan tanh exp √(1+a²) ln(1+a²) |a| floor arg,
/// powers 2 and 3) at 12 points in [−3, 3]² each. Every GPU value must lie within twice the float32 error
/// bound of `RandomExpression.bound` around the CPU value (Double). In a float32 emulation of the shaders
/// (correctly rounded operations, and again with transcendentals perturbed by up to 8–12 ulps) the worst
/// error is 0.98 of the bound and about 3400 of the 3600 samples are checked; the old dual arg (SHD-03) and
/// the old complex mod (SHD-04) fail 226 and 270 samples of it.
@MainActor
@Suite(.enabled(if: MTLCreateSystemDefaultDevice() != nil, "needs a Metal device"))
struct RandomExpressionGPUTests {
    @Test func realInterpreterMatchesCPU() throws { try check(.real) }
    @Test func dualInterpreterMatchesCPU() throws { try check(.dual) }
    @Test func complexInterpreterMatchesCPUOnTheRealAxis() throws { try check(.complex) }

    private func check(_ interpreter: ShaderPrecisionGPU.Interpreter) throws {
        let gpu = try ShaderPrecisionGPU()
        let complex = interpreter == .complex
        var rng = SplitMix64(state: 0xAC0E_5EED)
        var checked = 0
        var failures: [String] = []
        var cpuMismatches: [String] = []
        for _ in 0..<300 {
            let tree = RandomExpression.random(depth: 4, &rng, complex: complex)
            var points: [SIMD2<Float>] = []
            for _ in 0..<12 {
                let px = Float(rng.unit() * 6 - 3)
                let py = Float(rng.unit() * 6 - 3)
                points.append(complex ? SIMD2(px, 0) : SIMD2(px, py))
            }
            let expr = tree.expr(x: complex ? "z" : "x", y: "y")
            let slots: [String: VariableSlot] = complex ? ["z": .z] : ["x": .x, "y": .y]
            let program = try BytecodeCompiler(slots: slots, complexMode: complex).compile(expr)
            let values = try gpu.evaluate(program, interpreter, at: points).values
            let realCPU = RealVM(program: program)
            let complexCPU = ComplexVM(program: program)
            for (p, gpuValue) in zip(points, values) {
                guard let bound = tree.bound(x: Double(p.x), y: Double(p.y), complex: complex) else { continue }
                let cpu = complex
                    ? complexCPU.evaluate(z: Complex(Double(p.x), 0))
                    : Complex(realCPU.evaluate(x: Double(p.x), y: Double(p.y)), 0)
                // The bound uses the CPU's semantics, so both agree up to Double roundings (≈ 10⁻⁹ of the
                // float32 bound, which is ≥ u times the magnitudes involved).
                let agreement = 1e-6 * bound.error + 1e-12 * (1 + abs(bound.value))
                if !(abs(cpu.re - bound.value) <= agreement && abs(cpu.im) <= agreement) {
                    cpuMismatches.append("\(expr) at \(p): CPU \(cpu.re) + \(cpu.im)i, bound value \(bound.value)")
                    continue
                }
                checked += 1
                let difference = hypot(Double(gpuValue.x) - cpu.re, complex ? Double(gpuValue.y) - cpu.im : 0)
                if !(difference <= 2 * bound.error) {
                    failures.append("\(expr) at \(p): GPU \(gpuValue.x) + \(gpuValue.y)i, CPU \(cpu.re), bound \(bound.error)")
                }
            }
        }
        #expect(cpuMismatches.isEmpty, "\(cpuMismatches.count) CPU values differ from the bound's value, e.g. \(cpuMismatches.prefix(3))")
        #expect(failures.isEmpty, "\(failures.count) of \(checked) GPU values outside the float32 bound, e.g. \(failures.prefix(3))")
        #expect(checked >= 3000, "only \(checked) samples checked")
    }
}
