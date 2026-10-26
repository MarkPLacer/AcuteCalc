import Foundation

/// Evaluates expressions exactly when the result is a rational number, a simplified
/// surd, a multiple of π, or a short combination of those.
///
/// Returns `nil` (via `ExactEvaluator.Failure`) as soon as anything can't stay exact,
/// so callers show only the decimal result in that case.
public enum ExactEvaluator {
    struct Failure: Error {}

    public static func evaluate(_ expr: Expr, angleUnit: AngleUnit, variables: [String: ExactReal] = [:]) throws -> ExactReal {
        try eval(expr, angleUnit, variables)
    }

    /// Convenience returning `nil` instead of throwing.
    public static func value(_ expr: Expr, angleUnit: AngleUnit, variables: [String: ExactReal] = [:]) -> ExactReal? {
        try? eval(expr, angleUnit, variables)
    }

    static func eval(_ e: Expr, _ unit: AngleUnit, _ vars: [String: ExactReal]) throws -> ExactReal {
        func ev(_ x: Expr) throws -> ExactReal { try eval(x, unit, vars) }
        func need<T>(_ v: T?) throws -> T {
            guard let v else { throw Failure() }
            return v
        }
        switch e {
        case .number(let r):
            return ExactReal(r)
        case .decimal:
            throw Failure()
        case .constant(.pi):
            return .pi
        case .constant:
            throw Failure()
        case .variable(let name):
            return try need(vars[name])
        case .sum(let terms):
            var acc = ExactReal.zero
            for t in terms { acc = try need(acc.adding(try ev(t))) }
            return acc
        case .product(let factors):
            var acc = ExactReal.one
            for f in factors { acc = try need(acc.multiplied(by: try ev(f))) }
            return acc
        case .negation(let inner):
            return try need(try ev(inner).negated())
        case .quotient(let a, let b):
            let denominator = try ev(b)
            guard !denominator.isZero else { throw Failure() }
            return try need(try ev(a).divided(by: denominator))
        case .power(let base, let exponent):
            let b = try ev(base)
            let x = try ev(exponent)
            guard let r = x.rational else { throw Failure() }
            if b.isZero && !r.isPositive { throw Failure() }
            if b.signum < 0 && !r.isInteger {
                // Odd roots of negative rationals: (−8)^(1/3) = −2
                guard r.denominator % 2 == 1, let neg = b.negated(), let p = neg.power(r) else { throw Failure() }
                return r.numerator % 2 == 0 ? p : try need(p.negated())
            }
            return try need(b.power(r))
        case .percent(let inner):
            return try need(try ev(inner).multiplied(by: ExactReal(Rational(1, 100)!)))
        case .factorial(let inner):
            guard let n = try ev(inner).rational?.integerValue, n >= 0, n <= 20 else { throw Failure() }
            var p = 1
            if n > 1 { for k in 2...n { p *= k } }
            return ExactReal(p)
        case .function(let f, let args):
            return try function(f, args.map(ev), unit)
        case .derivative, .integral, .summation, .limit, .relation, .plusMinus, .matrix, .piecewise, .productSeries:
            throw Failure()
        }
    }

    // MARK: Functions

    static func function(_ f: MathFunction, _ args: [ExactReal], _ unit: AngleUnit) throws -> ExactReal {
        func need<T>(_ v: T?) throws -> T {
            guard let v else { throw Failure() }
            return v
        }
        guard f.arity == -1 || args.count == f.arity || f.arity == 0 else { throw Failure() }
        switch f {
        case .sqrt:
            return try need(args[0].squareRoot())
        case .cbrt:
            return try need(cubeRoot(args[0]))
        case .root:
            guard let n = args[0].rational?.integerValue, n >= 1 else { throw Failure() }
            if n == 2 { return try need(args[1].squareRoot()) }
            guard let r = args[1].rational else { throw Failure() }
            if r.isNegative {
                guard n % 2 == 1, let pos = r.negated()?.root(n), let neg = pos.negated() else { throw Failure() }
                return ExactReal(neg)
            }
            return ExactReal(try need(r.root(n)))
        case .abs:
            return args[0].signum < 0 ? try need(args[0].negated()) : args[0]
        case .sign:
            return ExactReal(args[0].signum)
        case .sin, .cos, .tan, .cot, .sec, .csc:
            return try trig(f, args[0], unit)
        case .asin, .acos, .atan, .acot:
            return try inverseTrig(f, args[0], unit)
        case .ln:
            guard args[0] == .one else { throw Failure() }
            return .zero
        case .log10:
            return try logarithm(base: Rational(10), args[0])
        case .log2:
            return try logarithm(base: Rational(2), args[0])
        case .log:
            guard let base = args[0].rational else { throw Failure() }
            return try logarithm(base: base, args[1])
        case .exp:
            guard args[0].isZero else { throw Failure() }
            return .one
        case .floor, .ceil, .round, .ipart, .frac:
            guard let r = args[0].rational else {
                // Non-rational exact values: fall back to the numeric value, which is safe for floor/ceil
                // while whole numbers are exact in Double (beyond, `Int(_:)` traps: floor(2⁶²·π)).
                let d = args[0].doubleValue
                guard abs(d) < 9e15 else { throw Failure() }
                switch f {
                case .floor: return ExactReal(Int(Foundation.floor(d)))
                case .ceil: return ExactReal(Int(Foundation.ceil(d)))
                default: throw Failure()
                }
            }
            // Integer arithmetic: the quotient in Double rounds (floor(2,99999999999999999) gave 3) and
            // traps next to Int.max.
            let whole = r.numerator / r.denominator
            let remainder = r.numerator % r.denominator
            switch f {
            case .floor: return ExactReal(remainder < 0 ? whole - 1 : whole)
            case .ceil: return ExactReal(remainder > 0 ? whole + 1 : whole)
            case .round:
                // Half away from zero: the magnitude rounds up when the remainder is at least half the denominator.
                let up = abs(remainder) >= r.denominator - abs(remainder)
                return ExactReal(up ? (r.isNegative ? whole - 1 : whole + 1) : whole)
            case .ipart: return ExactReal(whole)
            default:
                return ExactReal(try need(r.subtracting(Rational(whole))))
            }
        case .gcd, .lcm, .mod, .idiv, .nCr, .nPr:
            let ints = try args.map { a -> Int in
                guard let i = a.rational?.integerValue else { throw Failure() }
                return i
            }
            switch f {
            case .gcd: return ExactReal(ints.dropFirst().reduce(ints[0], RealEvaluator.greatestCommonDivisor))
            case .lcm:
                var result = ints[0]
                for v in ints.dropFirst() { result = try need(Rational.lcm(result, v)) }
                return ExactReal(result)
            case .mod:
                guard ints[1] != 0 else { throw Failure() }
                let r = ints[0] % ints[1]
                return ExactReal((r != 0 && (r < 0) != (ints[1] < 0)) ? r + ints[1] : r)
            case .idiv:
                guard ints[1] != 0 else { throw Failure() }
                return ExactReal(ints[0] / ints[1])
            default:
                return ExactReal(try need(combinatorics(f, ints[0], ints[1])))
            }
        case .min, .max:
            guard let first = args.first else { throw Failure() }
            return args.dropFirst().reduce(first) { acc, v in
                (f == .min) == (v.doubleValue < acc.doubleValue) ? v : acc
            }
        case .degrees:
            // x° in the active unit
            switch unit {
            case .degrees: return args[0]
            case .radians: return try need(args[0].multiplied(by: ExactReal.pi)?.multiplied(by: ExactReal(Rational(1, 180)!)))
            case .gradians: return try need(args[0].multiplied(by: ExactReal(Rational(10, 9)!)))
            }
        case .re, .conj:
            return args[0]
        case .im:
            return .zero
        default:
            throw Failure()
        }
    }

    /// nCr and nPr in integer arithmetic; the `Double` loop of `RealEvaluator.combinatorics` can miss the
    /// last digit (nCr(57, 24) gave …476 instead of 7 522 327 487 513 475). `nil` outside the domain and
    /// from 9·10¹⁵ on, where results stay decimal as before.
    static func combinatorics(_ f: MathFunction, _ n: Int, _ r: Int) -> Int? {
        let limit = 9_000_000_000_000_000
        guard n >= 0, r >= 0, n < limit, r < limit else { return nil }
        guard r <= n else { return 0 }
        var result = 1
        if f == .nPr {
            var factor = n
            while factor > n - r {
                let (p, overflow) = result.multipliedReportingOverflow(by: factor)
                guard !overflow, p < limit else { return nil }
                result = p
                factor -= 1
            }
            return result
        }
        let k = min(r, n - r)
        var i = 1
        while i <= k {
            // C(m, i) = C(m − 1, i − 1)·m/i with m = n − k + i; i/gcd divides m, so the product is the result itself.
            let g = Rational.gcd(result, i)
            let (p, overflow) = (result / g).multipliedReportingOverflow(by: (n - k + i) / (i / g))
            guard !overflow, p < limit else { return nil }
            result = p
            i += 1
        }
        return result
    }

    static func cubeRoot(_ x: ExactReal) -> ExactReal? {
        guard let r = x.rational else { return nil }
        if r.isNegative {
            guard let pos = r.negated()?.root(3), let neg = pos.negated() else { return nil }
            return ExactReal(neg)
        }
        return r.root(3).map(ExactReal.init)
    }

    /// `log_base(x)` when `x = base^(p/q)` for small q.
    static func logarithm(base: Rational, _ x: ExactReal) throws -> ExactReal {
        guard let value = x.rational, value.isPositive, base.isPositive, base != .one else { throw Failure() }
        if value == .one { return .zero }
        let estimate = Foundation.log(value.doubleValue) / Foundation.log(base.doubleValue)
        for q in 1...6 {
            let p = (estimate * Double(q)).rounded()
            guard abs(p) < 200 else { continue }
            let pi = Int(p)
            // base^p == value^q ?
            if let lhs = base.power(pi), let rhs = value.power(q), lhs == rhs, let result = Rational(pi, q) {
                return ExactReal(result)
            }
        }
        throw Failure()
    }

    // MARK: Trigonometry at special angles

    /// The angle as a rational number of degrees, if it is exact.
    static func degreesOf(_ angle: ExactReal, _ unit: AngleUnit) -> Rational? {
        switch unit {
        case .degrees:
            return angle.rational
        case .gradians:
            return angle.rational?.multiplied(by: Rational(9, 10)!)
        case .radians:
            if angle.isZero { return .zero }
            // c·π  → 180c degrees
            guard angle.terms.count == 1, let c = angle.terms[ExactReal.Basis(radicand: 1, piPower: 1)] else { return nil }
            return c.multiplied(by: Rational(180))
        }
    }

    static func trig(_ f: MathFunction, _ angle: ExactReal, _ unit: AngleUnit) throws -> ExactReal {
        guard let deg = degreesOf(angle, unit) else { throw Failure() }
        // Only whole degrees have exact values (sinCos). Reduce them to [0, 360) with integer arithmetic:
        // floor(turns)·360 in Double overflowed for huge angles such as sin(Int.max°).
        guard let wholeDegrees = deg.integerValue else { throw Failure() }
        let turn = wholeDegrees % 360
        let reduced = Rational(turn < 0 ? turn + 360 : turn)
        guard let (sinV, cosV) = sinCos(degrees: reduced) else { throw Failure() }
        func ratio(_ a: ExactReal, _ b: ExactReal) throws -> ExactReal {
            guard !b.isZero, let r = a.divided(by: b) else { throw Failure() }
            return r
        }
        switch f {
        case .sin: return sinV
        case .cos: return cosV
        case .tan: return try ratio(sinV, cosV)
        case .cot: return try ratio(cosV, sinV)
        case .sec: return try ratio(.one, cosV)
        default: return try ratio(.one, sinV)
        }
    }

    /// Exact sine and cosine for multiples of 15° in [0°, 360°).
    static func sinCos(degrees: Rational) -> (ExactReal, ExactReal)? {
        guard degrees.isInteger else { return nil }
        let d = degrees.numerator
        guard d % 15 == 0 else { return nil }
        func s(_ a: Int) -> ExactReal? { firstQuadrantSine(a) }
        let quadrant = d / 90
        let rest = d % 90
        guard let sr = s(rest), let cr = s(90 - rest) else { return nil }
        switch quadrant {
        case 0: return (sr, cr)
        case 1: return (cr, sr.negated() ?? sr)
        case 2: return (sr.negated() ?? sr, cr.negated() ?? cr)
        default: return (cr.negated() ?? cr, sr)
        }
    }

    static func firstQuadrantSine(_ degrees: Int) -> ExactReal? {
        let half = Rational(1, 2)!
        let quarter = Rational(1, 4)!
        func surd(_ c: Rational, _ r: Int) -> ExactReal? { ExactReal(validating: [ExactReal.Basis(radicand: r, piPower: 0): c]) }
        switch degrees {
        case 0: return .zero
        case 15: return ExactReal(validating: [ExactReal.Basis(radicand: 6, piPower: 0): quarter, ExactReal.Basis(radicand: 2, piPower: 0): Rational(-1, 4)!])
        case 30: return ExactReal(half)
        case 45: return surd(half, 2)
        case 60: return surd(half, 3)
        case 75: return ExactReal(validating: [ExactReal.Basis(radicand: 6, piPower: 0): quarter, ExactReal.Basis(radicand: 2, piPower: 0): quarter])
        case 90: return .one
        default: return nil
        }
    }

    static func inverseTrig(_ f: MathFunction, _ value: ExactReal, _ unit: AngleUnit) throws -> ExactReal {
        // Search the special angles in the principal range.
        let candidates: [Int]
        switch f {
        case .asin, .atan: candidates = Array(stride(from: -90, through: 90, by: 15))
        default: candidates = Array(stride(from: 0, through: 180, by: 15))
        }
        for d in candidates {
            guard let (s, c) = sinCos(degrees: Rational(d < 0 ? d + 360 : d)) else { continue }
            let matches: Bool
            switch f {
            case .asin: matches = s == value
            case .acos: matches = c == value
            case .atan:
                guard !c.isZero, let t = s.divided(by: c) else { continue }
                matches = t == value && abs(d) != 90
            default: // acot
                guard !s.isZero, let t = c.divided(by: s) else { continue }
                matches = t == value && d != 0 && d != 180
            }
            if matches {
                switch unit {
                case .degrees: return ExactReal(d)
                case .gradians: return ExactReal(Rational(d * 10, 9) ?? .zero)
                case .radians:
                    guard let c = Rational(d, 180) else { throw Failure() }
                    return ExactReal(validating: [ExactReal.Basis(radicand: 1, piPower: 1): c]) ?? .zero
                }
            }
        }
        throw Failure()
    }
}

extension ExactReal {
    /// Expression form for display and further simplification, e.g. `√3/2`, `5π/6`, `1 + √2`.
    public var expr: Expr {
        if terms.isEmpty { return .number(.zero) }
        // Rational part first, then surds, then π terms: 1 + √2, ½ + π/3.
        let parts: [Expr] = sortedTerms.map { term in
            let c = term.coefficient
            var factors: [Expr] = []
            if term.basis.radicand > 1 { factors.append(.function(.sqrt, [.number(Rational(term.basis.radicand))])) }
            if term.basis.piPower == 1 { factors.append(.constant(.pi)) } else if term.basis.piPower != 0 {
                factors.append(.power(.constant(.pi), .number(Rational(term.basis.piPower))))
            }
            let magnitude = c.magnitude
            var numerator: Expr
            if factors.isEmpty {
                numerator = .number(Rational(magnitude.numerator))
            } else if magnitude.numerator == 1 {
                numerator = factors.count == 1 ? factors[0] : .product(factors)
            } else {
                numerator = .product([.number(Rational(magnitude.numerator))] + factors)
            }
            var value: Expr = magnitude.denominator == 1 ? numerator : .quotient(numerator, .number(Rational(magnitude.denominator)))
            if c.isNegative { value = .negation(value) }
            return value
        }
        return parts.count == 1 ? parts[0] : .sum(parts)
    }
}
