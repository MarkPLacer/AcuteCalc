import Foundation

/// Stack-machine opcodes shared by the CPU virtual machines and the Metal shaders.
///
/// The raw values are part of the GPU contract: they must match `BCOp` in
/// `AcuteCalc/Rendering/Shaders/ShaderTypes.h`. All angles are radians.
public enum Opcode: UInt32, Sendable, Hashable, Codable, CaseIterable {
    case end = 0
    case const = 1
    case x = 2
    case y = 3
    case t = 4
    case param = 5
    case z = 6
    case imaginaryUnit = 7

    case add = 16, sub = 17, mul = 18, div = 19, pow = 20, neg = 21, mod = 22, powInt = 23
    case square = 24, cube = 25, recip = 26, sqrt = 27, cbrt = 28, rootN = 29
    case abs = 30, sign = 31, floor = 32, ceil = 33, round = 34, frac = 35, trunc = 36
    case min = 37, max = 38

    case exp = 48, ln = 49, log10 = 50, log2 = 51, logBase = 52

    case sin = 64, cos = 65, tan = 66, cot = 67, sec = 68, csc = 69
    case asin = 70, acos = 71, atan = 72, acot = 73, asec = 74, acsc = 75

    case sinh = 80, cosh = 81, tanh = 82, coth = 83, sech = 84, csch = 85
    case asinh = 86, acosh = 87, atanh = 88, acoth = 89, asech = 90, acsch = 91

    case gamma = 96, factorial = 97, zeta = 98, erf = 99, normcdf = 100
    case nCr = 101, nPr = 102, gcd = 103, lcm = 104

    case re = 112, im = 113, arg = 114, conj = 115

    /// Comparisons push 1 or 0; `select` pops (else, then, condition) and pushes the chosen value.
    case lt = 120, le = 121, gt = 122, ge = 123, eq = 124, ne = 125, select = 126

    /// Number of stack values consumed and produced.
    public var stackEffect: (pop: Int, push: Int) {
        switch self {
        case .end: (0, 0)
        case .const, .x, .y, .t, .param, .z, .imaginaryUnit: (0, 1)
        case .add, .sub, .mul, .div, .pow, .mod, .rootN, .min, .max, .logBase, .nCr, .nPr, .gcd, .lcm: (2, 1)
        case .lt, .le, .gt, .ge, .eq, .ne: (2, 1)
        case .select: (3, 1)
        default: (1, 1)
        }
    }

    static func comparison(_ op: RelationOperator) -> Opcode {
        switch op {
        case .less: .lt
        case .lessOrEqual: .le
        case .greater: .gt
        case .greaterOrEqual: .ge
        case .equal: .eq
        case .notEqual: .ne
        }
    }
}

public struct Instruction: Sendable, Hashable, Codable {
    public var op: Opcode
    public var value: Double

    public init(_ op: Opcode, _ value: Double = 0) {
        self.op = op
        self.value = value
    }
}

/// A compiled expression.
public struct Program: Sendable, Hashable, Codable {
    public var instructions: [Instruction]
    public var maxStackDepth: Int

    public static let maximumStackDepth = 24
    public static let maximumLength = 512

    public var uses: Set<Opcode> { Set(instructions.map(\.op)) }
    public var usesY: Bool { uses.contains(.y) }
    public var usesX: Bool { uses.contains(.x) }
    public var isEmpty: Bool { instructions.isEmpty }

    /// Rough GPU cost (used to pick a render resolution for heavy plots such as ζ).
    public var estimatedCost: Int {
        instructions.reduce(0) { acc, ins in
            switch ins.op {
            case .zeta: acc + 400
            case .gamma, .factorial: acc + 40
            case .pow, .exp, .ln, .sin, .cos, .tan, .asin, .acos, .atan: acc + 8
            default: acc + 1
            }
        }
    }
}

/// Where each free variable of an expression comes from when the program runs.
public enum VariableSlot: Sendable, Hashable {
    case x, y, t, z
    case parameter(Int)
}

/// Compiles an `Expr` into a `Program`. Sub-expressions without free variables are
/// folded to constants; derivatives are differentiated symbolically first.
public struct BytecodeCompiler {
    public var slots: [String: VariableSlot]
    public var angleUnit: AngleUnit
    /// Values for variables that are not slots (user memories), folded as constants.
    public var constants: [String: Double]
    public var complexMode: Bool

    public init(slots: [String: VariableSlot], angleUnit: AngleUnit = .radians, constants: [String: Double] = [:], complexMode: Bool = false) {
        self.slots = slots
        self.angleUnit = angleUnit
        self.constants = constants
        self.complexMode = complexMode
    }

    public func compile(_ expr: Expr) throws(MathError) -> Program {
        var out: [Instruction] = []
        try emit(expr, &out)
        // Compute stack depth.
        var depth = 0
        var maxDepth = 0
        for ins in out {
            let (pop, push) = ins.op.stackEffect
            depth -= pop
            guard depth >= 0 else { throw .syntax("notranja napaka pri prevajanju") }
            depth += push
            maxDepth = Swift.max(maxDepth, depth)
        }
        guard depth == 1 else { throw .syntax("notranja napaka pri prevajanju") }
        guard maxDepth <= Program.maximumStackDepth, out.count <= Program.maximumLength else { throw .tooComplex }
        return Program(instructions: out, maxStackDepth: maxDepth)
    }

    private func dependsOnSlots(_ e: Expr) -> Bool {
        e.freeVariables.contains { slots[$0] != nil } || e.containsImaginaryUnit && complexMode
            || e.contains { if case .function(let f, _) = $0 { f.isRandom } else { false } }
    }

    private func emit(_ e: Expr, _ out: inout [Instruction]) throws(MathError) {
        // Constant folding
        if !dependsOnSlots(e) {
            if !complexMode || !e.containsImaginaryUnit {
                var context = EvaluationContext(angleUnit: angleUnit, variables: constants)
                context.randomSeed = 1
                var evaluator = RealEvaluator(context: context)
                if let v = try? evaluator.eval(e), !v.isNaN {
                    out.append(Instruction(.const, v))
                    return
                }
                if case .variable(let name) = e { throw .undefinedVariable(name) }
            }
        }
        switch e {
        case .number(let r):
            out.append(Instruction(.const, r.doubleValue))
        case .decimal(let d):
            out.append(Instruction(.const, d))
        case .constant(let c):
            switch c {
            case .pi: out.append(Instruction(.const, .pi))
            case .e: out.append(Instruction(.const, M_E))
            case .infinity: out.append(Instruction(.const, .infinity))
            case .i:
                guard complexMode else { throw .notReal }
                out.append(Instruction(.imaginaryUnit))
            }
        case .variable(let name):
            if let slot = slots[name] {
                switch slot {
                case .x: out.append(Instruction(.x))
                case .y: out.append(Instruction(.y))
                case .t: out.append(Instruction(.t))
                case .z: out.append(Instruction(.z))
                case .parameter(let i): out.append(Instruction(.param, Double(i)))
                }
            } else if let v = constants[name] {
                out.append(Instruction(.const, v))
            } else {
                throw .undefinedVariable(name)
            }
        case .sum(let terms):
            guard let first = terms.first else { out.append(Instruction(.const, 0)); return }
            try emit(first, &out)
            for t in terms.dropFirst() {
                if case .negation(let inner) = t {
                    try emit(inner, &out)
                    out.append(Instruction(.sub))
                } else {
                    try emit(t, &out)
                    out.append(Instruction(.add))
                }
            }
        case .product(let factors):
            guard let first = factors.first else { out.append(Instruction(.const, 1)); return }
            try emit(first, &out)
            for f in factors.dropFirst() {
                try emit(f, &out)
                out.append(Instruction(.mul))
            }
        case .negation(let inner):
            try emit(inner, &out)
            out.append(Instruction(.neg))
        case .quotient(let a, let b):
            try emit(a, &out)
            try emit(b, &out)
            out.append(Instruction(.div))
        case .power(let base, let exponent):
            try emitPower(base, exponent, &out)
        case .percent(let inner):
            try emit(inner, &out)
            out.append(Instruction(.const, 0.01))
            out.append(Instruction(.mul))
        case .factorial(let inner):
            try emit(inner, &out)
            out.append(Instruction(.factorial))
        case .function(let f, let args):
            try emitFunction(f, args, &out)
        case .derivative(let body, let variable, let at):
            let derived = try Differentiator.derivative(of: body, withRespectTo: variable, angleUnit: angleUnit)
            if let at {
                try emit(derived.substituting(variable, with: at), &out)
            } else {
                try emit(derived, &out)
            }
        case .summation(let body, let variable, let lower, let upper):
            try emitSeries(body, variable, lower, upper, product: false, &out)
        case .productSeries(let body, let variable, let lower, let upper):
            try emitSeries(body, variable, lower, upper, product: true, &out)
        case .piecewise(let parts):
            // Nested selects from the last case to the first; NaN where no case applies.
            if parts.count % 2 == 1, let otherwise = parts.last {
                try emit(otherwise, &out)
            } else {
                out.append(Instruction(.const, .nan))
            }
            for k in stride(from: parts.count / 2 - 1, through: 0, by: -1) {
                try emit(parts[2 * k], &out)
                try emitCondition(parts[2 * k + 1], &out)
                out.append(Instruction(.select))
            }
        case .integral, .limit:
            throw .unsupported("integral ali limita z zunanjo spremenljivko")
        case .relation, .plusMinus:
            throw .unsupported("relacija")
        case .matrix:
            throw .unsupported("matrika")
        }
    }

    /// A comparison such as a < b, a chain a < b <= c (product of the comparisons) or a non-zero value.
    private func emitCondition(_ e: Expr, _ out: inout [Instruction]) throws(MathError) {
        guard case .relation(let lhs, let op, let rhs) = e else {
            try emit(e, &out)
            out.append(Instruction(.const, 0))
            out.append(Instruction(.ne))
            return
        }
        if case .relation(_, _, let middle) = lhs {
            try emitCondition(lhs, &out)
            try emit(middle, &out)
            try emit(rhs, &out)
            out.append(Instruction(Opcode.comparison(op)))
            out.append(Instruction(.mul))
            return
        }
        try emit(lhs, &out)
        try emit(rhs, &out)
        out.append(Instruction(Opcode.comparison(op)))
    }

    /// Short sums and products with constant integer bounds are unrolled (Taylor partial sums).
    private func emitSeries(_ body: Expr, _ variable: String, _ lower: Expr, _ upper: Expr, product: Bool, _ out: inout [Instruction]) throws(MathError) {
        let context = EvaluationContext(angleUnit: angleUnit, variables: constants)
        guard !dependsOnSlots(lower), !dependsOnSlots(upper),
              let lo = try? RealEvaluator.evaluate(lower, context: context), let hi = try? RealEvaluator.evaluate(upper, context: context),
              let a = RealEvaluator.exactInt(lo), let b = RealEvaluator.exactInt(hi) else {
            throw .unsupported("vsota z neskončno ali spremenljivo mejo")
        }
        guard b >= a else {
            out.append(Instruction(.const, product ? 1 : 0))
            return
        }
        guard b - a < 64 else { throw .tooComplex }
        for k in a...b {
            try emit(body.substituting(variable, with: .int(k)), &out)
            if k > a { out.append(Instruction(product ? .mul : .add)) }
        }
    }

    private func emitPower(_ base: Expr, _ exponent: Expr, _ out: inout [Instruction]) throws(MathError) {
        try emit(base, &out)
        if !dependsOnSlots(exponent), let value = try? RealEvaluator.evaluate(exponent, context: EvaluationContext(angleUnit: angleUnit, variables: constants)) {
            switch value {
            case 2: out.append(Instruction(.square)); return
            case 3: out.append(Instruction(.cube)); return
            case -1: out.append(Instruction(.recip)); return
            case 0.5: out.append(Instruction(.sqrt)); return
            default: break
            }
            if value == value.rounded(), Swift.abs(value) <= 64 {
                out.append(Instruction(.powInt, value))
                return
            }
            // Real odd roots of negative bases: x^(1/3) → cbrt, x^(p/q) with odd q handled by VM via rootN.
            if let r = RealEvaluator.exactRationalExponent(exponent, fallback: value), r.denominator % 2 == 1, !complexMode {
                if r.numerator != 1 { out.append(Instruction(.powInt, Double(r.numerator))) }
                out.append(Instruction(.const, Double(r.denominator)))
                // rootN expects (n, x): swap by emitting n then using a dedicated order.
                // We pushed x first, so compute x^(1/n) as rootN with operands (x, n).
                out.append(Instruction(.rootN, 1))
                return
            }
        }
        try emit(exponent, &out)
        out.append(Instruction(.pow))
    }

    private func emitFunction(_ f: MathFunction, _ args: [Expr], _ out: inout [Instruction]) throws(MathError) {
        let toRadians = angleUnit.radiansPerUnit
        func emitArgsAngle() throws(MathError) {
            try emit(args[0], &out)
            if toRadians != 1 {
                out.append(Instruction(.const, toRadians))
                out.append(Instruction(.mul))
            }
        }
        func emitArgs() throws(MathError) {
            for a in args { try emit(a, &out) }
        }
        func fromRadians() {
            if toRadians != 1 {
                out.append(Instruction(.const, 1 / toRadians))
                out.append(Instruction(.mul))
            }
        }
        let simple: [MathFunction: Opcode] = [
            .sinh: .sinh, .cosh: .cosh, .tanh: .tanh, .coth: .coth, .sech: .sech, .csch: .csch,
            .asinh: .asinh, .acosh: .acosh, .atanh: .atanh, .acoth: .acoth, .asech: .asech, .acsch: .acsch,
            .exp: .exp, .ln: .ln, .log10: .log10, .log2: .log2, .sqrt: .sqrt, .cbrt: .cbrt,
            .abs: .abs, .sign: .sign, .floor: .floor, .ceil: .ceil, .round: .round, .frac: .frac, .ipart: .trunc,
            .gamma: .gamma, .zeta: .zeta, .erf: .erf, .normcdf: .normcdf,
            .re: .re, .im: .im, .conj: .conj,
        ]
        let binary: [MathFunction: Opcode] = [
            .log: .logBase, .mod: .mod, .nCr: .nCr, .nPr: .nPr, .gcd: .gcd, .lcm: .lcm, .min: .min, .max: .max,
        ]
        switch f {
        case .sin, .cos, .tan, .cot, .sec, .csc:
            try emitArgsAngle()
            out.append(Instruction(Opcode(rawValue: Opcode.sin.rawValue + UInt32([MathFunction.sin, .cos, .tan, .cot, .sec, .csc].firstIndex(of: f)!))!))
        case .asin, .acos, .atan, .acot, .asec, .acsc:
            try emitArgs()
            out.append(Instruction(Opcode(rawValue: Opcode.asin.rawValue + UInt32([MathFunction.asin, .acos, .atan, .acot, .asec, .acsc].firstIndex(of: f)!))!))
            fromRadians()
        case .arg:
            try emitArgs()
            out.append(Instruction(.arg))
            fromRadians()
        case .root:
            // root(n, x): push x, then n → rootN(x, n)
            try emit(args[1], &out)
            try emit(args[0], &out)
            out.append(Instruction(.rootN, 1))
        case .degrees:
            try emit(args[0], &out)
            let factor = AngleUnit.degrees.convert(1, to: angleUnit)
            if factor != 1 {
                out.append(Instruction(.const, factor))
                out.append(Instruction(.mul))
            }
        case .idiv:
            try emitArgs()
            out.append(Instruction(.div))
            out.append(Instruction(.trunc))
        case .min, .max:
            try emit(args[0], &out)
            for a in args.dropFirst() {
                try emit(a, &out)
                out.append(Instruction(binary[f]!))
            }
        case .pol:
            // r = √(x² + y²)
            try emit(args[0], &out); out.append(Instruction(.square))
            try emit(args[1], &out); out.append(Instruction(.square))
            out.append(Instruction(.add)); out.append(Instruction(.sqrt))
        case .rec:
            try emit(args[0], &out)
            try emit(args[1], &out)
            if toRadians != 1 { out.append(Instruction(.const, toRadians)); out.append(Instruction(.mul)) }
            out.append(Instruction(.cos))
            out.append(Instruction(.mul))
        case .rand, .dice, .coin, .randInt:
            throw .unsupported("naključna števila v grafu")
        case .normpdf:
            // e^(-((x - mu)/sigma)^2 / 2) / (sigma * sqrt(2 pi))
            let z: Expr = args.count == 3 ? .quotient(.sum([args[0], .negation(args[1])]), args[2]) : args[0]
            let sigma: Expr = args.count == 3 ? args[2] : .one
            let density = Expr.quotient(.power(.constant(.e), .negation(.quotient(.power(z, .int(2)), .int(2)))),
                                        .product([sigma, .power(.product([.int(2), .constant(.pi)]), .number(.half))]))
            try emit(density, &out)
        default:
            if let op = simple[f] {
                try emitArgs()
                out.append(Instruction(op))
            } else if let op = binary[f] {
                try emitArgs()
                out.append(Instruction(op))
            } else {
                throw .unsupported(f.internationalName)
            }
        }
    }
}
