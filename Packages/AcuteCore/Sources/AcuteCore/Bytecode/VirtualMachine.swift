import Foundation

/// Executes a `Program` with `Double` arithmetic. NaN signals "undefined here",
/// which the curve sampler turns into a gap in the graph.
public struct RealVM: Sendable {
    public let program: Program
    public var parameters: [Double]

    public init(program: Program, parameters: [Double] = []) {
        self.program = program
        self.parameters = parameters
    }

    public func evaluate(x: Double, y: Double = 0, t: Double = 0) -> Double {
        program.instructions.withUnsafeBufferPointer { code in
            withUnsafeTemporaryAllocation(of: Double.self, capacity: Program.maximumStackDepth + 1) { stack in
                run(code, stack, x: x, y: y, t: t)
            }
        }
    }

    /// Evaluates many x values with a single stack allocation (no per-sample heap traffic).
    public func evaluate(xs: [Double], y: Double = 0) -> [Double] {
        program.instructions.withUnsafeBufferPointer { code in
            withUnsafeTemporaryAllocation(of: Double.self, capacity: Program.maximumStackDepth + 1) { stack in
                xs.map { run(code, stack, x: $0, y: y, t: 0) }
            }
        }
    }

    /// Evaluates the program on a contiguous buffer, writing results in place of the inputs.
    public func evaluate(inPlace values: UnsafeMutableBufferPointer<Double>, y: Double = 0) {
        program.instructions.withUnsafeBufferPointer { code in
            withUnsafeTemporaryAllocation(of: Double.self, capacity: Program.maximumStackDepth + 1) { stack in
                for i in values.indices {
                    values[i] = run(code, stack, x: values[i], y: y, t: 0)
                }
            }
        }
    }

    @inline(__always)
    private func run(_ code: UnsafeBufferPointer<Instruction>, _ s: UnsafeMutableBufferPointer<Double>, x: Double, y: Double, t: Double) -> Double {
        var sp = 0
        for ins in code {
            switch ins.op {
            case .end: break
            case .const: s[sp] = ins.value; sp += 1
            case .x: s[sp] = x; sp += 1
            case .y: s[sp] = y; sp += 1
            case .t: s[sp] = t; sp += 1
            case .z: s[sp] = x; sp += 1
            case .param:
                let i = Int(ins.value)
                s[sp] = i < parameters.count ? parameters[i] : 0
                sp += 1
            case .imaginaryUnit: s[sp] = .nan; sp += 1
            case .add: sp -= 1; s[sp - 1] += s[sp]
            case .sub: sp -= 1; s[sp - 1] -= s[sp]
            case .mul: sp -= 1; s[sp - 1] *= s[sp]
            case .div: sp -= 1; s[sp - 1] = s[sp] == 0 ? .nan : s[sp - 1] / s[sp]
            case .pow: sp -= 1; s[sp - 1] = RealVM.power(s[sp - 1], s[sp])
            case .neg: s[sp - 1] = -s[sp - 1]
            case .mod:
                sp -= 1
                let b = s[sp]
                let r = s[sp - 1].truncatingRemainder(dividingBy: b)
                s[sp - 1] = b == 0 ? .nan : ((r != 0 && (r < 0) != (b < 0)) ? r + b : r)
            case .powInt: s[sp - 1] = RealVM.integerPower(s[sp - 1], Int(ins.value))
            case .square: s[sp - 1] *= s[sp - 1]
            case .cube: s[sp - 1] = s[sp - 1] * s[sp - 1] * s[sp - 1]
            case .recip: s[sp - 1] = s[sp - 1] == 0 ? .nan : 1 / s[sp - 1]
            case .sqrt: s[sp - 1] = s[sp - 1] < 0 ? .nan : s[sp - 1].squareRoot()
            case .cbrt: s[sp - 1] = Foundation.cbrt(s[sp - 1])
            case .rootN:
                sp -= 1
                s[sp - 1] = RealVM.realRoot(s[sp - 1], s[sp])
            case .abs: s[sp - 1] = Swift.abs(s[sp - 1])
            case .sign: s[sp - 1] = s[sp - 1] > 0 ? 1 : (s[sp - 1] < 0 ? -1 : 0)
            case .floor: s[sp - 1] = Foundation.floor(s[sp - 1])
            case .ceil: s[sp - 1] = Foundation.ceil(s[sp - 1])
            case .round: s[sp - 1] = s[sp - 1].rounded(.toNearestOrAwayFromZero)
            case .frac: s[sp - 1] -= s[sp - 1].rounded(.towardZero)
            case .trunc: s[sp - 1] = s[sp - 1].rounded(.towardZero)
            // min and max of an undefined value are undefined: Swift.min(a, .nan) is a (only a NaN first
            // operand came through), so min(2 − y, y − ln x) was 2 − y where ln x is undefined.
            case .min: sp -= 1; s[sp - 1] = s[sp - 1].isNaN || s[sp].isNaN ? .nan : Swift.min(s[sp - 1], s[sp])
            case .max: sp -= 1; s[sp - 1] = s[sp - 1].isNaN || s[sp].isNaN ? .nan : Swift.max(s[sp - 1], s[sp])
            case .exp: s[sp - 1] = Foundation.exp(s[sp - 1])
            case .ln: s[sp - 1] = s[sp - 1] <= 0 ? .nan : Foundation.log(s[sp - 1])
            case .log10: s[sp - 1] = s[sp - 1] <= 0 ? .nan : Foundation.log10(s[sp - 1])
            case .log2: s[sp - 1] = s[sp - 1] <= 0 ? .nan : Foundation.log2(s[sp - 1])
            case .logBase:
                sp -= 1
                let base = s[sp - 1]
                let v = s[sp]
                s[sp - 1] = (base <= 0 || base == 1 || v <= 0) ? .nan : Foundation.log(v) / Foundation.log(base)
            case .sin: s[sp - 1] = Foundation.sin(s[sp - 1])
            case .cos: s[sp - 1] = Foundation.cos(s[sp - 1])
            case .tan: s[sp - 1] = Foundation.tan(s[sp - 1])
            case .cot: s[sp - 1] = 1 / Foundation.tan(s[sp - 1])
            case .sec: s[sp - 1] = 1 / Foundation.cos(s[sp - 1])
            case .csc: s[sp - 1] = 1 / Foundation.sin(s[sp - 1])
            case .asin: s[sp - 1] = Swift.abs(s[sp - 1]) > 1 ? .nan : Foundation.asin(s[sp - 1])
            case .acos: s[sp - 1] = Swift.abs(s[sp - 1]) > 1 ? .nan : Foundation.acos(s[sp - 1])
            case .atan: s[sp - 1] = Foundation.atan(s[sp - 1])
            case .acot:
                let v = s[sp - 1]
                s[sp - 1] = v == 0 ? .pi / 2 : Foundation.atan(1 / v) + (v < 0 ? .pi : 0)
            case .asec: s[sp - 1] = Swift.abs(s[sp - 1]) < 1 ? .nan : Foundation.acos(1 / s[sp - 1])
            case .acsc: s[sp - 1] = Swift.abs(s[sp - 1]) < 1 ? .nan : Foundation.asin(1 / s[sp - 1])
            case .sinh: s[sp - 1] = Foundation.sinh(s[sp - 1])
            case .cosh: s[sp - 1] = Foundation.cosh(s[sp - 1])
            case .tanh: s[sp - 1] = Foundation.tanh(s[sp - 1])
            case .coth: s[sp - 1] = 1 / Foundation.tanh(s[sp - 1])
            case .sech: s[sp - 1] = 1 / Foundation.cosh(s[sp - 1])
            case .csch: s[sp - 1] = 1 / Foundation.sinh(s[sp - 1])
            case .asinh: s[sp - 1] = Foundation.asinh(s[sp - 1])
            case .acosh: s[sp - 1] = s[sp - 1] < 1 ? .nan : Foundation.acosh(s[sp - 1])
            case .atanh: s[sp - 1] = Swift.abs(s[sp - 1]) >= 1 ? .nan : Foundation.atanh(s[sp - 1])
            case .acoth:
                let v = s[sp - 1]
                s[sp - 1] = Swift.abs(v) <= 1 ? .nan : 0.5 * Foundation.log((v + 1) / (v - 1))
            case .asech:
                let v = s[sp - 1]
                s[sp - 1] = (v <= 0 || v > 1) ? .nan : Foundation.acosh(1 / v)
            case .acsch: s[sp - 1] = s[sp - 1] == 0 ? .nan : Foundation.asinh(1 / s[sp - 1])
            case .gamma:
                let v = s[sp - 1]
                s[sp - 1] = (v <= 0 && v == v.rounded()) ? .nan : Foundation.tgamma(v)
            case .factorial:
                let v = s[sp - 1]
                s[sp - 1] = (v < 0 && v == v.rounded()) ? .nan : Foundation.tgamma(v + 1)
            case .zeta: s[sp - 1] = s[sp - 1] == 1 ? .nan : Complex.zeta(Complex(s[sp - 1], 0)).re
            case .erf: s[sp - 1] = Foundation.erf(s[sp - 1])
            case .normcdf: s[sp - 1] = Distributions.normalCDF(s[sp - 1])
            case .nCr, .nPr:
                sp -= 1
                s[sp - 1] = (try? RealEvaluator.combinatorics(ins.op == .nCr ? .nCr : .nPr, s[sp - 1], s[sp])) ?? .nan
            case .gcd, .lcm:
                sp -= 1
                if let a = RealEvaluator.exactInt(s[sp - 1]), let b = RealEvaluator.exactInt(s[sp]) {
                    if ins.op == .gcd {
                        s[sp - 1] = Double(RealEvaluator.greatestCommonDivisor(a, b))
                    } else {
                        s[sp - 1] = Rational.lcm(a, b).map(Double.init) ?? .nan
                    }
                } else {
                    s[sp - 1] = .nan
                }
            case .re, .conj: break
            case .im: s[sp - 1] = 0
            case .arg: s[sp - 1] = s[sp - 1] < 0 ? .pi : 0
            case .lt, .le, .gt, .ge, .eq, .ne:
                sp -= 1
                s[sp - 1] = RealVM.compare(ins.op, s[sp - 1], s[sp]) ? 1 : 0
            case .select:
                sp -= 2
                s[sp - 1] = s[sp + 1] != 0 ? s[sp] : s[sp - 1]
            }
        }
        return sp > 0 ? s[0] : .nan
    }

    @inline(__always)
    static func compare(_ op: Opcode, _ a: Double, _ b: Double) -> Bool {
        // An infinite side has an exact order, as in `RealEvaluator.compare` (the tolerance would be ∞).
        if let order = RealEvaluator.infiniteOrder(a, b) {
            switch op {
            case .lt, .le: return order.less
            case .gt, .ge: return order.greater
            case .eq: return false
            default: return true
            }
        }
        let tolerance = 1e-12 * Swift.max(1, Swift.abs(a), Swift.abs(b))
        switch op {
        case .lt: return a < b
        case .le: return a <= b + tolerance
        case .gt: return a > b
        case .ge: return a >= b - tolerance
        case .eq: return Swift.abs(a - b) <= tolerance
        default: return Swift.abs(a - b) > tolerance
        }
    }

    @inline(__always)
    static func integerPower(_ base: Double, _ n: Int) -> Double {
        if n == 0 { return base == 0 ? .nan : 1 }
        if n < 0 { return base == 0 ? .nan : 1 / integerPower(base, -n) }
        var result = 1.0
        var b = base
        var e = n
        while e > 0 {
            if e & 1 == 1 { result *= b }
            b *= b
            e >>= 1
        }
        return result
    }

    @inline(__always)
    static func power(_ base: Double, _ exponent: Double) -> Double {
        if base == 0 && exponent <= 0 { return .nan }
        return Foundation.pow(base, exponent)
    }

    /// x^(1/n) with real results for odd n and negative x.
    @inline(__always)
    static func realRoot(_ x: Double, _ n: Double) -> Double {
        if n == 0 { return .nan }
        if x < 0 {
            // Odd index, tested without Int(_:), which traps for a huge or infinite index.
            guard n.isFinite, n == n.rounded(), n.truncatingRemainder(dividingBy: 2) != 0 else { return .nan }
            return -Foundation.pow(-x, 1 / n)
        }
        return Foundation.pow(x, 1 / n)
    }
}

/// Executes a `Program` over complex numbers (`z` is the complex variable).
public struct ComplexVM: Sendable {
    public let program: Program
    public var parameters: [Complex]
    /// The calculator: functions defined only for real numbers (sgn, erf, Φ, mod, min, max, nCr, nPr, gcd,
    /// lcm) and the order <, ≤, >, ≥ give NaN for a non-real value, and = and ≠ compare complex numbers.
    /// Plots keep using the real part, like `bc_eval_complex`.
    public var requiresRealArguments: Bool

    public init(program: Program, parameters: [Complex] = [], requiresRealArguments: Bool = false) {
        self.program = program
        self.parameters = parameters
        self.requiresRealArguments = requiresRealArguments
    }

    /// Real up to rounding (e^(iπ) = −1 + 1,2·10⁻¹⁶i), with the tolerance of `RealVM.compare`. An overflowed real
    /// part counts as the largest Double (its tolerance would be ∞): e¹⁰⁰⁰ + i = ∞ + i stays real, but
    /// 10³⁰⁸·(2 + i) = ∞ + 10³⁰⁸i and (1 + i)·e¹⁰⁰⁰ = ∞ + ∞i are not.
    static func isNearlyReal(_ z: Complex) -> Bool {
        z.im.isFinite && Swift.abs(z.im) <= 1e-12 * Swift.max(1, Swift.min(Swift.abs(z.re), Double.greatestFiniteMagnitude))
    }

    public func evaluate(z: Complex) -> Complex {
        var s = [Complex](repeating: .zero, count: Program.maximumStackDepth + 1)
        var sp = 0
        for ins in program.instructions {
            switch ins.op {
            case .end: break
            case .const: s[sp] = Complex(ins.value, 0); sp += 1
            case .x, .z: s[sp] = z; sp += 1
            case .y: s[sp] = Complex(z.im, 0); sp += 1
            case .t: s[sp] = .zero; sp += 1
            case .param:
                let i = Int(ins.value)
                s[sp] = i < parameters.count ? parameters[i] : .zero
                sp += 1
            case .imaginaryUnit: s[sp] = .i; sp += 1
            case .add: sp -= 1; s[sp - 1] = s[sp - 1] + s[sp]
            case .sub: sp -= 1; s[sp - 1] = s[sp - 1] - s[sp]
            case .mul: sp -= 1; s[sp - 1] = s[sp - 1] * s[sp]
            case .div: sp -= 1; s[sp - 1] = s[sp - 1] / s[sp]
            case .pow: sp -= 1; s[sp - 1] = Complex.pow(s[sp - 1], s[sp])
            case .neg: s[sp - 1] = -s[sp - 1]
            case .powInt: s[sp - 1] = Complex.powInt(s[sp - 1], Int(ins.value))
            case .square: s[sp - 1] = s[sp - 1] * s[sp - 1]
            case .cube: s[sp - 1] = s[sp - 1] * s[sp - 1] * s[sp - 1]
            case .recip: s[sp - 1] = Complex.one / s[sp - 1]
            case .sqrt: s[sp - 1] = Complex.sqrt(s[sp - 1])
            case .cbrt: s[sp - 1] = Complex.pow(s[sp - 1], Complex(1.0 / 3.0, 0))
            case .rootN: sp -= 1; s[sp - 1] = Complex.pow(s[sp - 1], Complex.one / s[sp])
            case .abs: s[sp - 1] = Complex(s[sp - 1].magnitude, 0)
            case .exp: s[sp - 1] = Complex.exp(s[sp - 1])
            case .ln: s[sp - 1] = Complex.log(s[sp - 1])
            case .log10: s[sp - 1] = Complex.log(s[sp - 1]) / Foundation.log(10.0)
            case .log2: s[sp - 1] = Complex.log(s[sp - 1]) / Foundation.log(2.0)
            case .logBase: sp -= 1; s[sp - 1] = Complex.log(s[sp]) / Complex.log(s[sp - 1])
            case .sin: s[sp - 1] = Complex.sin(s[sp - 1])
            case .cos: s[sp - 1] = Complex.cos(s[sp - 1])
            case .tan: s[sp - 1] = Complex.tan(s[sp - 1])
            case .cot: s[sp - 1] = Complex.one / Complex.tan(s[sp - 1])
            case .sec: s[sp - 1] = Complex.one / Complex.cos(s[sp - 1])
            case .csc: s[sp - 1] = Complex.one / Complex.sin(s[sp - 1])
            case .asin: s[sp - 1] = Complex.asin(s[sp - 1])
            case .acos: s[sp - 1] = Complex.acos(s[sp - 1])
            case .atan: s[sp - 1] = Complex.atan(s[sp - 1])
            case .acot: s[sp - 1] = Complex.atan(Complex.one / s[sp - 1])
            case .asec: s[sp - 1] = Complex.acos(Complex.one / s[sp - 1])
            case .acsc: s[sp - 1] = Complex.asin(Complex.one / s[sp - 1])
            case .sinh: s[sp - 1] = Complex.sinh(s[sp - 1])
            case .cosh: s[sp - 1] = Complex.cosh(s[sp - 1])
            case .tanh: s[sp - 1] = Complex.tanh(s[sp - 1])
            case .coth: s[sp - 1] = Complex.one / Complex.tanh(s[sp - 1])
            case .sech: s[sp - 1] = Complex.one / Complex.cosh(s[sp - 1])
            case .csch: s[sp - 1] = Complex.one / Complex.sinh(s[sp - 1])
            case .asinh: s[sp - 1] = Complex.asinh(s[sp - 1])
            case .acosh: s[sp - 1] = Complex.acosh(s[sp - 1])
            case .atanh: s[sp - 1] = Complex.atanh(s[sp - 1])
            case .acoth: s[sp - 1] = Complex.atanh(Complex.one / s[sp - 1])
            case .asech: s[sp - 1] = Complex.acosh(Complex.one / s[sp - 1])
            case .acsch: s[sp - 1] = Complex.asinh(Complex.one / s[sp - 1])
            case .gamma: s[sp - 1] = Complex.gamma(s[sp - 1])
            case .factorial: s[sp - 1] = Complex.gamma(s[sp - 1] + .one)
            case .zeta: s[sp - 1] = Complex.zeta(s[sp - 1])
            case .re: s[sp - 1] = Complex(s[sp - 1].re, 0)
            case .im: s[sp - 1] = Complex(s[sp - 1].im, 0)
            case .arg: s[sp - 1] = Complex(s[sp - 1].argument, 0)
            case .conj: s[sp - 1] = s[sp - 1].conjugate
            case .sign, .floor, .ceil, .round, .frac, .trunc, .erf, .normcdf:
                // Applied to the real part (plots). In the calculator sgn, erf and Φ of a non-real value are
                // undefined (erf(i) is not erf(0) = 0); rounding keeps the real part for now.
                if requiresRealArguments && (ins.op == .sign || ins.op == .erf || ins.op == .normcdf)
                    && !ComplexVM.isNearlyReal(s[sp - 1]) {
                    s[sp - 1] = Complex(.nan, .nan)
                } else {
                    let r = RealVM(program: Program(instructions: [Instruction(.x), Instruction(ins.op)], maxStackDepth: 1))
                    s[sp - 1] = Complex(r.evaluate(x: s[sp - 1].re), 0)
                }
            case .mod, .min, .max, .nCr, .nPr, .gcd, .lcm:
                sp -= 1
                if requiresRealArguments && !(ComplexVM.isNearlyReal(s[sp - 1]) && ComplexVM.isNearlyReal(s[sp])) {
                    s[sp - 1] = Complex(.nan, .nan)
                } else {
                    let r = RealVM(program: Program(instructions: [Instruction(.x), Instruction(.y), Instruction(ins.op)], maxStackDepth: 2))
                    s[sp - 1] = Complex(r.evaluate(x: s[sp - 1].re, y: s[sp].re), 0)
                }
            case .lt, .le, .gt, .ge, .eq, .ne:
                // Conditions compare real parts (plots). In the calculator = and ≠ compare complex numbers,
                // and non-real numbers have no order.
                sp -= 1
                let a = s[sp - 1], b = s[sp]
                if !requiresRealArguments || (ComplexVM.isNearlyReal(a) && ComplexVM.isNearlyReal(b)) {
                    s[sp - 1] = Complex(RealVM.compare(ins.op, a.re, b.re) ? 1 : 0, 0)
                } else if (ins.op == .eq || ins.op == .ne) && a.isFinite && b.isFinite {
                    // Divided by the largest part first: |a|, |b| and |a − b| overflow for parts near 10³⁰⁸.
                    let scale = Swift.max(1, Swift.abs(a.re), Swift.abs(a.im), Swift.abs(b.re), Swift.abs(b.im))
                    let x = a / scale, y = b / scale
                    let equal = (x - y).magnitude <= 1e-12 * Swift.max(1 / scale, x.magnitude, y.magnitude)
                    s[sp - 1] = Complex(equal == (ins.op == .eq) ? 1 : 0, 0)
                } else {
                    s[sp - 1] = Complex(.nan, .nan)
                }
            case .select:
                sp -= 2
                if requiresRealArguments && s[sp + 1].isNaN {
                    s[sp - 1] = Complex(.nan, .nan)
                } else {
                    s[sp - 1] = s[sp + 1].re != 0 ? s[sp] : s[sp - 1]
                }
            }
        }
        return sp > 0 ? s[0] : Complex(.nan, .nan)
    }
}
