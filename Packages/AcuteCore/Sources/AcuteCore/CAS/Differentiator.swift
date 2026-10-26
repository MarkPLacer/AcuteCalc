import Foundation

/// Symbolic differentiation with the usual rules (sum, product, quotient, power,
/// chain rule and a table of derivatives of elementary functions).
public enum Differentiator {
    /// d/d`variable` of `expr`, simplified. `angleUnit` matters for trigonometric
    /// functions whose argument is measured in degrees or gradians.
    public static func derivative(of expr: Expr, withRespectTo variable: String, angleUnit: AngleUnit = .radians) throws(MathError) -> Expr {
        let raw = try d(Simplifier.canonical(expr), variable, angleUnit)
        return Simplifier.simplify(raw)
    }

    /// n-th derivative.
    public static func derivative(of expr: Expr, withRespectTo variable: String, order: Int, angleUnit: AngleUnit = .radians) throws(MathError) -> Expr {
        var current = expr
        for _ in 0..<max(0, order) {
            current = try derivative(of: current, withRespectTo: variable, angleUnit: angleUnit)
        }
        return current
    }

    /// dy/dx of an implicit relation F(x, y) = G(x, y): −(∂H/∂x)/(∂H/∂y) with H = F − G.
    public static func implicitDerivative(of relation: Expr, x: String = "x", y: String = "y") throws(MathError) -> Expr {
        let h: Expr
        if case .relation(let lhs, _, let rhs) = relation { h = .sum([lhs, .negation(rhs)]) } else { h = relation }
        let hx = try derivative(of: h, withRespectTo: x)
        let hy = try derivative(of: h, withRespectTo: y)
        return Simplifier.simplify(.negation(.quotient(hx, hy)))
    }

    static func d(_ e: Expr, _ v: String, _ unit: AngleUnit) throws(MathError) -> Expr {
        if !e.dependsOn(v) { return .number(.zero) }
        switch e {
        case .variable(let name):
            return name == v ? .number(.one) : .number(.zero)
        case .number, .decimal, .constant:
            return .number(.zero)
        case .sum(let terms):
            var out: [Expr] = []
            for t in terms { out.append(try d(t, v, unit)) }
            return .sum(out)
        case .product(let factors):
            // Σ_i f_i' · Π_{j≠i} f_j
            var terms: [Expr] = []
            for i in factors.indices where factors[i].dependsOn(v) {
                var product = factors
                product[i] = try d(factors[i], v, unit)
                terms.append(.product(product))
            }
            return terms.count == 1 ? terms[0] : .sum(terms)
        case .negation(let inner):
            return .negation(try d(inner, v, unit))
        case .quotient(let a, let b):
            let da = try d(a, v, unit)
            let db = try d(b, v, unit)
            return .quotient(.sum([.product([da, b]), .negation(.product([a, db]))]), .power(b, .int(2)))
        case .power(let base, let exponent):
            let baseDepends = base.dependsOn(v)
            let expDepends = exponent.dependsOn(v)
            if baseDepends && !expDepends {
                // n·u^(n−1)·u'
                return .product([exponent, .power(base, .sum([exponent, .number(.minusOne)])), try d(base, v, unit)])
            }
            if !baseDepends {
                // a^u · ln a · u'
                let lnBase: Expr = base == .constant(.e) ? .number(.one) : .function(.ln, [base])
                return .product([e, lnBase, try d(exponent, v, unit)])
            }
            // u^w · (w'·ln u + w·u'/u)
            let du = try d(base, v, unit)
            let dw = try d(exponent, v, unit)
            return .product([e, .sum([.product([dw, .function(.ln, [base])]), .product([exponent, du, .power(base, .number(.minusOne))])])])
        case .function(let f, let args):
            return try function(f, args, v, unit)
        case .percent(let inner):
            return .product([.number(Rational(1, 100)!), try d(inner, v, unit)])
        case .piecewise(let parts):
            // Piece by piece with the same conditions: a(t) from a piecewise v(t).
            var out = parts
            for index in stride(from: 0, to: parts.count, by: 2) {
                out[index] = try d(parts[index], v, unit)
            }
            return .piecewise(out)
        case .factorial:
            throw .unsupported("odvod faktoriele")
        case .derivative(let body, let variable, let at) where at == nil:
            let inner = try derivative(of: body, withRespectTo: variable, angleUnit: unit)
            return try d(inner, v, unit)
        case .integral(let body, let variable, let lower, let upper) where lower != nil && upper != nil:
            // Leibniz rule for variable bounds: d/dv ∫_a(v)^b(v) f(t) dt = f(b)·b' − f(a)·a'
            guard let lower, let upper, !body.substituting(variable, with: .variable("__t")).dependsOn(v) || variable == v else {
                throw .unsupported("odvod integrala")
            }
            let fb = body.substituting(variable, with: upper)
            let fa = body.substituting(variable, with: lower)
            return .sum([.product([fb, try d(upper, v, unit)]), .negation(.product([fa, try d(lower, v, unit)]))])
        default:
            throw .unsupported("odvod tega izraza")
        }
    }

    static func function(_ f: MathFunction, _ args: [Expr], _ v: String, _ unit: AngleUnit) throws(MathError) -> Expr {
        if f.arity == 2 {
            switch f {
            case .log:
                // log_b(u) = ln u / ln b
                return try d(.quotient(.function(.ln, [args[1]]), .function(.ln, [args[0]])), v, unit)
            case .root:
                return try d(.power(args[1], .power(args[0], .number(.minusOne))), v, unit)
            default:
                throw .unsupported("odvod funkcije \(f.internationalName)")
            }
        }
        guard args.count == 1 else { throw .unsupported("odvod funkcije \(f.internationalName)") }
        let u = args[0]
        let du = try d(u, v, unit)
        // k converts the argument to radians (1 in RAD mode).
        let k: Expr = unit == .radians ? .number(.one) : .quotient(.constant(.pi), .int(unit == .degrees ? 180 : 200))
        let one = Expr.number(.one)
        func chain(_ outer: Expr) -> Expr { .product([outer, du]) }
        func sq(_ x: Expr) -> Expr { .power(x, .int(2)) }
        func sqrt(_ x: Expr) -> Expr { .power(x, .number(.half)) }

        switch f {
        case .sin: return chain(.product([k, .function(.cos, [u])]))
        case .cos: return chain(.negation(.product([k, .function(.sin, [u])])))
        case .tan: return chain(.quotient(k, sq(.function(.cos, [u]))))
        case .cot: return chain(.negation(.quotient(k, sq(.function(.sin, [u])))))
        case .sec: return chain(.product([k, .function(.sec, [u]), .function(.tan, [u])]))
        case .csc: return chain(.negation(.product([k, .function(.csc, [u]), .function(.cot, [u])])))
        case .asin: return chain(.quotient(one, .product([k, sqrt(.sum([one, .negation(sq(u))]))])))
        case .acos: return chain(.negation(.quotient(one, .product([k, sqrt(.sum([one, .negation(sq(u))]))]))))
        case .atan: return chain(.quotient(one, .product([k, .sum([one, sq(u)])])))
        case .acot: return chain(.negation(.quotient(one, .product([k, .sum([one, sq(u)])]))))
        case .asec: return chain(.quotient(one, .product([k, .function(.abs, [u]), sqrt(.sum([sq(u), .number(.minusOne)]))])))
        case .acsc: return chain(.negation(.quotient(one, .product([k, .function(.abs, [u]), sqrt(.sum([sq(u), .number(.minusOne)]))]))))
        case .sinh: return chain(.function(.cosh, [u]))
        case .cosh: return chain(.function(.sinh, [u]))
        case .tanh: return chain(.quotient(one, sq(.function(.cosh, [u]))))
        case .coth: return chain(.negation(.quotient(one, sq(.function(.sinh, [u])))))
        case .sech: return chain(.negation(.product([.function(.sech, [u]), .function(.tanh, [u])])))
        case .csch: return chain(.negation(.product([.function(.csch, [u]), .function(.coth, [u])])))
        case .asinh: return chain(.quotient(one, sqrt(.sum([sq(u), one]))))
        case .acosh: return chain(.quotient(one, sqrt(.sum([sq(u), .number(.minusOne)]))))
        case .atanh, .acoth: return chain(.quotient(one, .sum([one, .negation(sq(u))])))
        case .asech: return chain(.negation(.quotient(one, .product([u, sqrt(.sum([one, .negation(sq(u))]))]))))
        case .acsch: return chain(.negation(.quotient(one, .product([.function(.abs, [u]), sqrt(.sum([one, sq(u)]))]))))
        case .exp: return chain(.power(.constant(.e), u))
        case .ln: return chain(.quotient(one, u))
        case .log10: return chain(.quotient(one, .product([u, .function(.ln, [.int(10)])])))
        case .log2: return chain(.quotient(one, .product([u, .function(.ln, [.int(2)])])))
        case .sqrt: return chain(.quotient(one, .product([.int(2), sqrt(u)])))
        case .cbrt: return chain(.quotient(one, .product([.int(3), .power(u, .frac(2, 3))])))
        case .abs: return chain(.function(.sign, [u]))
        case .sign, .floor, .ceil, .round, .ipart: return .number(.zero)
        case .frac: return du
        case .erf: return chain(.product([.quotient(.int(2), sqrt(.constant(.pi))), .power(.constant(.e), .negation(sq(u)))]))
        case .normcdf:
            return chain(.quotient(.power(.constant(.e), .negation(.quotient(sq(u), .int(2)))), sqrt(.product([.int(2), .constant(.pi)]))))
        case .degrees:
            let factor: Expr = unit == .degrees ? one : (unit == .radians ? .quotient(.constant(.pi), .int(180)) : .frac(10, 9))
            return .product([factor, du])
        case .re, .conj: return du
        case .im: return .number(.zero)
        default:
            throw .unsupported("odvod funkcije \(f.internationalName)")
        }
    }
}
