import Foundation

/// Evaluates an expression to a `Double` with calculator semantics
/// (angle units, exact zeros of trigonometric functions at quarter turns,
/// real odd roots of negative numbers, domain errors instead of NaN).
public struct RealEvaluator {
    public var context: EvaluationContext
    private var rng: SplitMix64

    public init(context: EvaluationContext = EvaluationContext()) {
        self.context = context
        self.rng = SplitMix64(seed: context.randomSeed)
    }

    /// Convenience for one-off evaluations.
    public static func evaluate(_ expr: Expr, context: EvaluationContext = EvaluationContext()) throws(MathError) -> Double {
        var evaluator = RealEvaluator(context: context)
        return try evaluator.evaluate(expr)
    }

    public mutating func evaluate(_ expr: Expr) throws(MathError) -> Double {
        let value = try eval(expr)
        if value.isNaN { throw .domain("rezultat ni definiran") }
        if value.isInfinite { throw .overflow }
        return value
    }

    // MARK: Core

    mutating func eval(_ expr: Expr) throws(MathError) -> Double {
        switch expr {
        case .number(let r):
            return r.doubleValue
        case .decimal(let d):
            return d
        case .constant(let c):
            switch c {
            case .pi: return .pi
            case .e: return M_E
            case .infinity: return .infinity
            case .i: throw .notReal
            }
        case .variable(let name):
            if let v = context.variables[name] { return v }
            if let exact = context.exactVariables[name] { return exact.doubleValue }
            throw .undefinedVariable(name)
        case .sum(let terms):
            var total = 0.0
            for t in terms { total += try eval(t) }
            return total
        case .product(let factors):
            var total = 1.0
            for f in factors { total *= try eval(f) }
            return total
        case .negation(let inner):
            return -(try eval(inner))
        case .quotient(let a, let b):
            let numerator = try eval(a)
            let denominator = try eval(b)
            if denominator == 0 { throw .divisionByZero }
            return numerator / denominator
        case .power(let base, let exponent):
            return try evalPower(base, exponent)
        case .function(let f, let args):
            return try evalFunction(f, args)
        case .factorial(let inner):
            return try RealEvaluator.factorial(try eval(inner))
        case .percent(let inner):
            return try eval(inner) / 100
        case .derivative(let body, let variable, let at):
            let point: Double
            if let at {
                point = try eval(at)
            } else if let v = context.variables[variable] {
                point = v
            } else {
                throw .undefinedVariable(variable)
            }
            return try derivative(of: body, variable: variable, at: point)
        case .integral(let body, let variable, let lower, let upper):
            guard let lower, let upper else { throw .unsupported("nedoločeni integral nima števila") }
            let a = try eval(lower)
            let b = try eval(upper)
            return try Integrator.integrate(body, variable: variable, from: a, to: b, context: context)
        case .summation(let body, let variable, let lower, let upper):
            return try summation(body, variable: variable, lower: lower, upper: upper)
        case .limit(let body, let variable, let point, let direction):
            let a = try eval(point)
            let value = try LimitEvaluator.limit(body, variable: variable, at: a, direction: direction, context: context)
            guard value.isFinite else { throw .overflow }
            return value
        case .relation:
            throw .unsupported("enačbe nimajo številske vrednosti")
        case .plusMinus:
            throw .unsupported("±")
        case .matrix:
            throw .unsupported("matrika")
        case .piecewise(let parts):
            return try piecewise(parts)
        case .productSeries(let body, let variable, let lower, let upper):
            return try productSeries(body, variable: variable, lower: lower, upper: upper)
        }
    }

    // MARK: Conditions and piecewise functions

    /// Truth value of a condition: `x < 2`, chained `0 ≤ x < 2`, or a non-zero value.
    public mutating func condition(_ e: Expr) throws(MathError) -> Bool {
        guard case .relation(let lhs, let op, let rhs) = e else { return try eval(e) != 0 }
        let left: Double
        if case .relation(_, _, let middle) = lhs {
            guard try condition(lhs) else { return false }
            left = try eval(middle)
        } else {
            left = try eval(lhs)
        }
        let right = try eval(rhs)
        return RealEvaluator.compare(left, op, right)
    }

    static func compare(_ a: Double, _ op: RelationOperator, _ b: Double) -> Bool {
        let tolerance = 1e-12 * Swift.max(1, Swift.abs(a), Swift.abs(b))
        switch op {
        case .equal: return Swift.abs(a - b) <= tolerance
        case .notEqual: return Swift.abs(a - b) > tolerance
        case .less: return a < b
        case .lessOrEqual: return a <= b + tolerance
        case .greater: return a > b
        case .greaterOrEqual: return a >= b - tolerance
        }
    }

    private mutating func piecewise(_ parts: [Expr]) throws(MathError) -> Double {
        var k = 0
        while k + 1 < parts.count {
            if try condition(parts[k + 1]) { return try eval(parts[k]) }
            k += 2
        }
        if parts.count % 2 == 1, let otherwise = parts.last { return try eval(otherwise) }
        // No case applies: the function is undefined here (a gap in the graph).
        return .nan
    }

    private mutating func productSeries(_ body: Expr, variable: String, lower: Expr, upper: Expr) throws(MathError) -> Double {
        let lo = try eval(lower)
        let hi = try eval(upper)
        guard let start = RealEvaluator.exactInt(lo), let end = RealEvaluator.exactInt(hi) else {
            throw .domain("meje produkta morajo biti cela števila")
        }
        guard end >= start else { return 1 }
        guard end - start <= 1_000_000 else { throw .tooComplex }
        var total = 1.0
        for n in start...end {
            var inner = RealEvaluator(context: context.with(variable, Double(n)))
            total *= try inner.eval(body)
            if total == 0 || !total.isFinite { break }
        }
        return total
    }

    // MARK: Powers

    private mutating func evalPower(_ base: Expr, _ exponent: Expr) throws(MathError) -> Double {
        let b = try eval(base)
        let e = try eval(exponent)
        if b == 0 && e == 0 { throw .domain("0⁰ ni definirano") }
        if b == 0 && e < 0 { throw .divisionByZero }
        if b < 0 && e != e.rounded() {
            // Real odd roots: (−8)^(1/3) = −2 when the exponent is p/q with odd q.
            if let r = RealEvaluator.exactRationalExponent(exponent, fallback: e), r.denominator % 2 == 1 {
                let magnitude = Foundation.pow(-b, e)
                return r.numerator % 2 == 0 ? magnitude : -magnitude
            }
            throw .notReal
        }
        return Foundation.pow(b, e)
    }

    static func exactRationalExponent(_ exponent: Expr, fallback: Double) -> Rational? {
        if let r = exponent.rationalValue { return r }
        if case .quotient(let n, let d) = exponent, let rn = n.rationalValue, let rd = d.rationalValue {
            return rn.divided(by: rd)
        }
        return Rational.approximating(fallback, maxDenominator: 99, tolerance: 1e-13)
    }

    // MARK: Functions

    private func angle(_ x: Double) -> Double { x * context.angleUnit.radiansPerUnit }

    /// Position of `x` in quarter turns when it is (numerically) a multiple of a quarter turn.
    private func quarterTurns(_ x: Double) -> Int? {
        let q = x / (context.angleUnit.fullTurn / 4)
        let r = q.rounded()
        guard abs(q - r) <= 1e-12 * Swift.max(1, abs(q)), abs(r) < 1e15 else { return nil }
        let m = Int(r) % 4
        return m < 0 ? m + 4 : m
    }

    private mutating func evalFunction(_ f: MathFunction, _ args: [Expr]) throws(MathError) -> Double {
        if f.arity == 0 { return try evalRandom(f, []) }
        if f == .randInt { return try evalRandom(f, args) }
        var values: [Double] = []
        values.reserveCapacity(args.count)
        for a in args { values.append(try eval(a)) }
        guard let x = values.first else { throw .incomplete }

        switch f {
        // Trigonometric (argument in the active angle unit)
        case .sin:
            if let q = quarterTurns(x) { return [0.0, 1.0, 0.0, -1.0][q] }
            return Foundation.sin(angle(x))
        case .cos:
            if let q = quarterTurns(x) { return [1.0, 0.0, -1.0, 0.0][q] }
            return Foundation.cos(angle(x))
        case .tan:
            if let q = quarterTurns(x) {
                if q % 2 == 1 { throw .domain("tan ni definiran") }
                return 0
            }
            return Foundation.tan(angle(x))
        case .cot:
            if let q = quarterTurns(x) {
                if q % 2 == 0 { throw .domain("cot ni definiran") }
                return 0
            }
            return 1 / Foundation.tan(angle(x))
        case .sec:
            if let q = quarterTurns(x), q % 2 == 1 { throw .domain("sec ni definiran") }
            return 1 / Foundation.cos(angle(x))
        case .csc:
            if let q = quarterTurns(x), q % 2 == 0 { throw .domain("csc ni definiran") }
            return 1 / Foundation.sin(angle(x))
        case .asin:
            guard abs(x) <= 1 else { throw .domain("arcsin zahteva |x| ≤ 1") }
            return Foundation.asin(x) / context.angleUnit.radiansPerUnit
        case .acos:
            guard abs(x) <= 1 else { throw .domain("arccos zahteva |x| ≤ 1") }
            return Foundation.acos(x) / context.angleUnit.radiansPerUnit
        case .atan:
            return Foundation.atan(x) / context.angleUnit.radiansPerUnit
        case .acot:
            let r = x == 0 ? Double.pi / 2 : Foundation.atan(1 / x) + (x < 0 ? Double.pi : 0)
            return r / context.angleUnit.radiansPerUnit
        case .asec:
            guard abs(x) >= 1 else { throw .domain("arcsec zahteva |x| ≥ 1") }
            return Foundation.acos(1 / x) / context.angleUnit.radiansPerUnit
        case .acsc:
            guard abs(x) >= 1 else { throw .domain("arccsc zahteva |x| ≥ 1") }
            return Foundation.asin(1 / x) / context.angleUnit.radiansPerUnit
        // Hyperbolic
        case .sinh: return Foundation.sinh(x)
        case .cosh: return Foundation.cosh(x)
        case .tanh: return Foundation.tanh(x)
        case .coth:
            if x == 0 { throw .divisionByZero }
            return 1 / Foundation.tanh(x)
        case .sech: return 1 / Foundation.cosh(x)
        case .csch:
            if x == 0 { throw .divisionByZero }
            return 1 / Foundation.sinh(x)
        case .asinh: return Foundation.asinh(x)
        case .acosh:
            guard x >= 1 else { throw .domain("arcosh zahteva x ≥ 1") }
            return Foundation.acosh(x)
        case .atanh:
            guard abs(x) < 1 else { throw .domain("artanh zahteva |x| < 1") }
            return Foundation.atanh(x)
        case .acoth:
            guard abs(x) > 1 else { throw .domain("arcoth zahteva |x| > 1") }
            return 0.5 * Foundation.log((x + 1) / (x - 1))
        case .asech:
            guard x > 0 && x <= 1 else { throw .domain("arsech zahteva 0 < x ≤ 1") }
            return Foundation.acosh(1 / x)
        case .acsch:
            if x == 0 { throw .divisionByZero }
            return Foundation.asinh(1 / x)
        // Exponential & logarithms
        case .exp: return Foundation.exp(x)
        case .ln:
            guard x > 0 else { throw .domain("ln zahteva x > 0") }
            return Foundation.log(x)
        case .log10:
            guard x > 0 else { throw .domain("log zahteva x > 0") }
            return Foundation.log10(x)
        case .log2:
            guard x > 0 else { throw .domain("log₂ zahteva x > 0") }
            return Foundation.log2(x)
        case .log:
            let base = x
            let value = values[1]
            guard base > 0, base != 1 else { throw .domain("osnova logaritma mora biti > 0 in ≠ 1") }
            guard value > 0 else { throw .domain("logaritem zahteva x > 0") }
            return Foundation.log(value) / Foundation.log(base)
        // Roots
        case .sqrt:
            guard x >= 0 else { throw .notReal }
            return x.squareRoot()
        case .cbrt:
            return Foundation.cbrt(x)
        case .root:
            let n = x
            let radicand = values[1]
            guard n != 0 else { throw .domain("korenski eksponent 0") }
            if radicand < 0 {
                // Odd index, tested without Int(_:), which traps for a huge or infinite index (root(10²⁰; −8)).
                guard n.isFinite, n == n.rounded(), n.truncatingRemainder(dividingBy: 2) != 0 else { throw .notReal }
                return -Foundation.pow(-radicand, 1 / n)
            }
            return Foundation.pow(radicand, 1 / n)
        // Rounding & misc
        case .abs: return Swift.abs(x)
        case .sign: return x > 0 ? 1 : (x < 0 ? -1 : 0)
        case .floor: return Foundation.floor(x)
        case .ceil: return Foundation.ceil(x)
        case .round: return x.rounded(.toNearestOrAwayFromZero)
        case .ipart: return x.rounded(.towardZero)
        case .frac: return x - x.rounded(.towardZero)
        case .min: return values.min() ?? x
        case .max: return values.max() ?? x
        // Number theory
        case .gcd, .lcm:
            var ints: [Int] = []
            for v in values {
                guard let i = RealEvaluator.exactInt(v) else { throw .domain("\(f.rawValue) zahteva cela števila") }
                ints.append(i)
            }
            if f == .gcd { return Double(ints.dropFirst().reduce(ints[0], RealEvaluator.greatestCommonDivisor)) }
            var result = ints[0]
            for v in ints.dropFirst() {
                guard let l = Rational.lcm(result, v) else { throw .overflow }
                result = l
            }
            return Double(result)
        case .mod:
            let b = values[1]
            if b == 0 { throw .divisionByZero }
            let r = x.truncatingRemainder(dividingBy: b)
            return (r != 0 && (r < 0) != (b < 0)) ? r + b : r
        case .idiv:
            let b = values[1]
            if b == 0 { throw .divisionByZero }
            return (x / b).rounded(.towardZero)
        case .nCr, .nPr:
            return try RealEvaluator.combinatorics(f, x, values[1])
        // Special functions
        case .gamma:
            if x <= 0 && x == x.rounded() { throw .domain("Γ ni definirana za cela števila ≤ 0") }
            return Foundation.tgamma(x)
        case .zeta:
            if x == 1 { throw .domain("ζ ima pol v 1") }
            return Complex.zeta(Complex(x, 0)).re
        case .erf: return Foundation.erf(x)
        case .normcdf: return 0.5 * (1 + Foundation.erf(x / 2.0.squareRoot()))
        // Complex parts of a real number
        case .re, .conj: return x
        case .im: return 0
        case .arg: return (x < 0 ? Double.pi : 0) / context.angleUnit.radiansPerUnit
        // Angles and coordinates
        case .degrees:
            return AngleUnit.degrees.convert(x, to: context.angleUnit)
        case .pol:
            return hypot(x, values[1])
        case .rec:
            return x * Foundation.cos(angle(values[1]))
        case .rand, .dice, .coin, .randInt:
            return try evalRandom(f, args)
        // Matrices are evaluated by `MatrixEvaluator`.
        case .det, .transpose, .trace, .rank, .inv, .dot, .cross, .norm, .angle, .unit, .eig, .charpoly, .rref, .kernel:
            throw .unsupported("funkcija za matrike in vektorje")
        // Probability distributions
        case .binompdf, .binomcdf:
            guard values.count == 3 else { throw .syntax("\(f.rawValue)(n; p; k)") }
            return try f == .binompdf
                ? Distributions.binomialPMF(n: values[0], p: values[1], k: values[2])
                : Distributions.binomialCDF(n: values[0], p: values[1], k: values[2])
        case .poissonpdf, .poissoncdf:
            guard values.count == 2 else { throw .syntax("\(f.rawValue)(λ; k)") }
            return try f == .poissonpdf
                ? Distributions.poissonPMF(lambda: values[0], k: values[1])
                : Distributions.poissonCDF(lambda: values[0], k: values[1])
        case .normpdf:
            switch values.count {
            case 1: return Distributions.normalPDF(x)
            case 3: return try Distributions.normalPDF(x, mean: values[1], standardDeviation: values[2])
            default: throw .syntax("normpdf(x) ali normpdf(x; μ; σ)")
            }
        case .invnorm:
            switch values.count {
            case 1: return try Distributions.inverseNormal(x)
            case 3: return try Distributions.inverseNormal(x, mean: values[1], standardDeviation: values[2])
            default: throw .syntax("invNorm(p) ali invNorm(p; μ; σ)")
            }
        case .tpdf, .tcdf, .invt:
            guard values.count == 2 else { throw .syntax("\(f.internationalName)(x; ν)") }
            switch f {
            case .tpdf: return try Distributions.studentPDF(x, degrees: values[1])
            case .tcdf: return try Distributions.studentCDF(x, degrees: values[1])
            default: return try Distributions.inverseStudent(x, degrees: values[1])
            }
        case .chi2pdf, .chi2cdf, .invchi2:
            guard values.count == 2 else { throw .syntax("\(f.internationalName)(x; k)") }
            switch f {
            case .chi2pdf: return try Distributions.chiSquarePDF(x, degrees: values[1])
            case .chi2cdf: return try Distributions.chiSquareCDF(x, degrees: values[1])
            default: return try Distributions.inverseChiSquare(x, degrees: values[1])
            }
        case .fpdf, .fcdf, .invf:
            guard values.count == 3 else { throw .syntax("\(f.internationalName)(x; d₁; d₂)") }
            switch f {
            case .fpdf: return try Distributions.fisherPDF(x, values[1], values[2])
            case .fcdf: return try Distributions.fisherCDF(x, values[1], values[2])
            default: return try Distributions.inverseFisher(x, values[1], values[2])
            }
        }
    }

    private mutating func evalRandom(_ f: MathFunction, _ args: [Expr]) throws(MathError) -> Double {
        switch f {
        case .rand:
            // Sharp: three decimal places in [0, 0.999]
            return Double(Int.random(in: 0...999, using: &rng)) / 1000
        case .dice:
            return Double(Int.random(in: 1...6, using: &rng))
        case .coin:
            return Double(Int.random(in: 0...1, using: &rng))
        default:
            guard args.count == 2 else { throw .incomplete }
            let lo = try eval(args[0])
            let hi = try eval(args[1])
            guard let a = RealEvaluator.exactInt(lo), let b = RealEvaluator.exactInt(hi), a <= b else {
                throw .domain("R.Int zahteva cela števila a ≤ b")
            }
            return Double(Int.random(in: a...b, using: &rng))
        }
    }

    // MARK: Helpers

    public static func exactInt(_ x: Double) -> Int? {
        guard x == x.rounded(), abs(x) < 9.0e15 else { return nil }
        return Int(x)
    }

    /// gcd as the calculator shows it, with gcd(0, 0) = 0; `Rational.gcd` gives 1 there, which suits
    /// normalising fractions.
    static func greatestCommonDivisor(_ a: Int, _ b: Int) -> Int {
        a == 0 && b == 0 ? 0 : Rational.gcd(a, b)
    }

    public static func factorial(_ x: Double) throws(MathError) -> Double {
        if let n = exactInt(x) {
            guard n >= 0 else { throw .domain("faktoriela negativnega celega števila") }
            guard n <= 170 else { throw .overflow }
            var r = 1.0
            if n > 1 { for k in 2...n { r *= Double(k) } }
            return r
        }
        // Non-integers: Γ(x + 1)
        return Foundation.tgamma(x + 1)
    }

    public static func combinatorics(_ f: MathFunction, _ nValue: Double, _ rValue: Double) throws(MathError) -> Double {
        guard let n = exactInt(nValue), let r = exactInt(rValue), n >= 0, r >= 0 else {
            throw .domain("n in r morata biti nenegativni celi števili")
        }
        guard r <= n else { return 0 }
        if f == .nPr {
            var result = 1.0
            if r > 0 { for k in (n - r + 1)...n { result *= Double(k) } }
            return result
        }
        let k = Swift.min(r, n - r)
        var result = 1.0
        if k > 0 {
            for i in 1...k {
                result = result * Double(n - k + i) / Double(i)
            }
        }
        return result.rounded()
    }

    mutating func derivative(of body: Expr, variable: String, at point: Double) throws(MathError) -> Double {
        if let symbolic = try? Differentiator.derivative(of: body, withRespectTo: variable) {
            var inner = RealEvaluator(context: context.with(variable, point))
            if let value = try? inner.eval(symbolic), value.isFinite { return value }
        }
        return try NumericCalculus.derivative(body, variable: variable, at: point, context: context)
    }

    private mutating func summation(_ body: Expr, variable: String, lower: Expr, upper: Expr) throws(MathError) -> Double {
        let lo = try eval(lower)
        let hi = try eval(upper)
        guard let start = RealEvaluator.exactInt(lo) else { throw .domain("meje vsote morajo biti cela števila") }
        var total = 0.0
        if hi.isInfinite && hi > 0 {
            // Compiled term (bytecode) keeps long series fast.
            let term = FunctionAnalyzer.makeFunction(body, variable: variable, context: context)
            return try SeriesSummation.sum(from: start) { term(Double($0)) }
        }
        guard let end = RealEvaluator.exactInt(hi) else { throw .domain("meje vsote morajo biti cela števila") }
        guard end >= start else { return 0 }
        guard end - start <= 5_000_000 else { throw .tooComplex }
        for n in start...end {
            var inner = RealEvaluator(context: context.with(variable, Double(n)))
            total += try inner.eval(body)
        }
        return total
    }
}
