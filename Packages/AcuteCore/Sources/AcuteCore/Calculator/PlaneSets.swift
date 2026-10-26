import Foundation

/// Sets in the plane that are rewritten before they are drawn per pixel: sets of complex
/// numbers (z = x + iy, e.g. |z − 1| ≤ 2, Re z ≥ −2) and chains such as −1 ≤ y < 2.
public enum PlaneSets {
    // MARK: Complex plane

    /// A relation about complex numbers: it uses i, or z together with Re, Im, arg, conj or |…|.
    public static func isComplexSet(_ e: Expr) -> Bool {
        if e.containsImaginaryUnit { return true }
        guard e.freeVariables.contains("z") else { return false }
        return e.contains { node in
            guard case .function(let f, _) = node else { return false }
            return f == .re || f == .im || f == .arg || f == .conj || f == .abs
        }
    }

    /// `lhs op rhs` between real-valued expressions of z, as a relation in x and y.
    public static func complexRelation(_ lhs: Expr, _ rhs: Expr) -> (lhs: Expr, rhs: Expr)? {
        guard let a = realPart(lhs), let b = realPart(rhs) else { return nil }
        return (a, b)
    }

    /// The value of a real-valued expression of z as an expression in x and y (nil if it can be complex).
    static func realPart(_ e: Expr) -> Expr? {
        guard let (re, im) = split(e), isZero(im) else { return nil }
        return Simplifier.simplify(re)
    }

    /// Real and imaginary part of `e` with z = x + iy; x, y and parameters are real.
    public static func split(_ e: Expr) -> (re: Expr, im: Expr)? {
        if !e.containsImaginaryUnit && !e.freeVariables.contains("z") { return (e, .zero) }
        switch e {
        case .constant(.i):
            return (.zero, .one)
        case .variable("z"):
            return (.x, .y)
        case .sum(let terms):
            var re: [Expr] = [], im: [Expr] = []
            for term in terms {
                guard let (a, b) = split(term) else { return nil }
                re.append(a)
                if b != .zero { im.append(b) }
            }
            return (.sum(re), im.isEmpty ? .zero : im.count == 1 ? im[0] : .sum(im))
        case .negation(let inner):
            guard let (a, b) = split(inner) else { return nil }
            return (.negation(a), b == .zero ? .zero : .negation(b))
        case .product(let factors):
            var result: (re: Expr, im: Expr) = (.one, .zero)
            for factor in factors {
                guard let part = split(factor) else { return nil }
                result = multiply(result, part)
            }
            return result
        case .quotient(let numerator, let denominator):
            guard let n = split(numerator), let d = split(denominator) else { return nil }
            return divide(n, d)
        case .power(let base, let exponent):
            guard let b = split(base) else { return nil }
            if let n = exponent.rationalValue, n.isInteger, let count = Int(exactly: n.doubleValue), Swift.abs(count) <= 8 {
                if b.im == .zero { return (.power(b.re, exponent), .zero) }
                var result: (re: Expr, im: Expr) = (.one, .zero)
                for _ in 0..<Swift.abs(count) { result = multiply(result, b) }
                return count < 0 ? divide((.one, .zero), result) : result
            }
            guard b.im == .zero, let p = split(exponent), p.im == .zero else { return nil }
            return (.power(b.re, p.re), .zero)
        case .function(.abs, let args) where args.count == 1:
            guard let (a, b) = split(args[0]) else { return nil }
            if b == .zero { return (.function(.abs, [a]), .zero) }
            return (.function(.sqrt, [.sum([.power(a, .int(2)), .power(b, .int(2))])]), .zero)
        case .function(.re, let args) where args.count == 1:
            return split(args[0]).map { (re: $0.re, im: Expr.zero) }
        case .function(.im, let args) where args.count == 1:
            return split(args[0]).map { (re: $0.im, im: Expr.zero) }
        case .function(.conj, let args) where args.count == 1:
            return split(args[0]).map { (re: $0.re, im: $0.im == .zero ? Expr.zero : Expr.negation($0.im)) }
        case .function(.arg, let args) where args.count == 1:
            // arg(a + bi) = 2·atan(b / (|a + bi| + a)), continuous except on the negative real axis.
            guard let (a, b) = split(args[0]) else { return nil }
            let modulus = Expr.function(.sqrt, [.sum([.power(a, .int(2)), .power(b, .int(2))])])
            return (.product([.int(2), .function(.atan, [.quotient(b, .sum([modulus, a]))])]), .zero)
        case .function(let f, let args):
            // Real functions of real arguments only.
            var real: [Expr] = []
            for arg in args {
                guard let (a, b) = split(arg), isZero(b) else { return nil }
                real.append(a)
            }
            return (.function(f, real), .zero)
        default:
            return nil
        }
    }

    private static func multiply(_ p: (re: Expr, im: Expr), _ q: (re: Expr, im: Expr)) -> (re: Expr, im: Expr) {
        switch (p.im == .zero, q.im == .zero) {
        case (true, true): (p.re * q.re, Expr.zero)
        case (true, false): (p.re * q.re, p.re * q.im)
        case (false, true): (p.re * q.re, p.im * q.re)
        case (false, false): (p.re * q.re - p.im * q.im, p.re * q.im + p.im * q.re)
        }
    }

    private static func divide(_ n: (re: Expr, im: Expr), _ d: (re: Expr, im: Expr)) -> (re: Expr, im: Expr) {
        if d.im == .zero {
            return (n.re / d.re, n.im == .zero ? .zero : n.im / d.re)
        }
        let norm = Expr.sum([.power(d.re, .int(2)), .power(d.im, .int(2))])
        return ((n.re * d.re + n.im * d.im) / norm, (n.im * d.re - n.re * d.im) / norm)
    }

    private static func isZero(_ e: Expr) -> Bool {
        if e == .zero { return true }
        switch Simplifier.simplify(e) {
        case .number(let r): return r == .zero
        case .decimal(let d): return d == 0
        default: return false
        }
    }

    // MARK: Points

    /// `A(2, 3)` (a capital letter before a pair) or a bare pair `(2, 3)` as a point.
    public static func point(_ e: Expr) -> (name: String?, x: Expr, y: Expr)? {
        switch e {
        case .matrix(2, 1, let entries):
            return (nil, entries[0], entries[1])
        case .product(let factors):
            guard factors.count == 2, case .variable(let name) = factors[0], name.count == 1,
                  name.first?.isUppercase == true, case .matrix(2, 1, let entries) = factors[1] else { return nil }
            return (name, entries[0], entries[1])
        default:
            return nil
        }
    }

    // MARK: Chains

    /// `a < b ≤ c …` as one region `min(b − a, c − b, …) ≥ 0` (strict when every link is);
    /// chains about complex numbers (1 ≤ |z| ≤ 2) are rewritten in x and y first.
    public static func chainRegion(_ e: Expr) -> (lhs: Expr, relation: RelationOperator, rhs: Expr)? {
        var links: [(Expr, RelationOperator, Expr)] = []
        guard flatten(e, into: &links), links.count >= 2 else { return nil }
        let complex = isComplexSet(e)
        var gaps: [Expr] = []
        var strict = true
        for (a, op, b) in links {
            var left = a, right = b
            if complex {
                guard let l = realPart(a), let r = realPart(b) else { return nil }
                left = l
                right = r
            }
            switch op {
            case .less: gaps.append(right - left)
            case .lessOrEqual: gaps.append(right - left); strict = false
            case .greater: gaps.append(left - right)
            case .greaterOrEqual: gaps.append(left - right); strict = false
            case .equal, .notEqual: return nil
            }
        }
        return (.function(.min, gaps), strict ? .greater : .greaterOrEqual, .zero)
    }

    /// The links of a chain `a < b ≤ c …` as single relations (a < b, b ≤ c …).
    public static func links(_ e: Expr) -> [(Expr, RelationOperator, Expr)]? {
        var links: [(Expr, RelationOperator, Expr)] = []
        return flatten(e, into: &links) ? links : nil
    }

    private static func flatten(_ e: Expr, into links: inout [(Expr, RelationOperator, Expr)]) -> Bool {
        guard case .relation(let left, let op, let right) = e else { return false }
        if case .relation(_, _, let middle) = left {
            guard flatten(left, into: &links) else { return false }
            links.append((middle, op, right))
        } else {
            links.append((left, op, right))
        }
        return true
    }
}
