import Foundation

/// Mathematical constants understood by the engine.
public enum MathConstant: String, Hashable, Sendable, Codable, CaseIterable {
    case pi
    case e
    /// Imaginary unit.
    case i
    /// Infinity (only used for limits and integration bounds).
    case infinity

    public var symbol: String {
        switch self {
        case .pi: "π"
        case .e: "e"
        case .i: "i"
        case .infinity: "∞"
        }
    }

    public var doubleValue: Double {
        switch self {
        case .pi: .pi
        case .e: M_E
        case .i: .nan
        case .infinity: .infinity
        }
    }
}

/// Relations allowed at the top level of an input (`y = x²`, `x² + y² ≤ 4`).
public enum RelationOperator: String, Hashable, Sendable, Codable, CaseIterable {
    case equal = "="
    case less = "<"
    case greater = ">"
    case lessOrEqual = "≤"
    case greaterOrEqual = "≥"
    case notEqual = "≠"

    public var isInequality: Bool { self != .equal && self != .notEqual }
    public var isStrict: Bool { self == .less || self == .greater }

    /// The operator after swapping both sides (`a < b` ⇔ `b > a`).
    public var flipped: RelationOperator {
        switch self {
        case .less: .greater
        case .greater: .less
        case .lessOrEqual: .greaterOrEqual
        case .greaterOrEqual: .lessOrEqual
        case .equal, .notEqual: self
        }
    }
}

/// Built-in functions. Arity is fixed except for `min`/`max`.
public enum MathFunction: String, Hashable, Sendable, Codable, CaseIterable {
    // Trigonometric
    case sin, cos, tan, cot, sec, csc
    case asin, acos, atan, acot, asec, acsc
    // Hyperbolic
    case sinh, cosh, tanh, coth, sech, csch
    case asinh, acosh, atanh, acoth, asech, acsch
    // Exponential & logarithmic
    case exp, ln, log10, log2
    /// `log(base, x)`
    case log
    // Roots
    case sqrt, cbrt
    /// `root(n, x)` = ⁿ√x
    case root
    // Rounding & misc
    case abs, sign, floor, ceil, round, frac
    /// Integer part (truncation toward zero), like `ipart` on scientific calculators.
    case ipart
    case min, max
    // Number theory & combinatorics
    case gcd, lcm, mod
    /// Integer division `a int÷ b`; the calculator shows quotient and remainder.
    case idiv
    case nCr, nPr
    // Special functions
    case gamma, zeta, erf
    /// Standard normal cumulative distribution Φ(x).
    case normcdf
    // Complex parts
    case re, im, arg, conj
    // Angles: `x°` (value in degrees, converted to the active angle unit).
    case degrees
    // Coordinate conversion (→rθ and →xy). Numerically they evaluate to r and x.
    case pol, rec
    // Random numbers (Sharp EL-W531: Rand, RanDice, RanCoin, R.Int).
    case rand, dice, coin, randInt
    // Matrices and vectors
    case det, transpose, trace, rank, inv
    /// Dot product, cross product, length, angle between two vectors, unit vector.
    case dot, cross, norm, angle, unit
    /// Eigenvalues with eigenvectors, det(A − λI), reduced row echelon form, null space.
    case eig, charpoly, rref, kernel
    // Probability distributions
    /// binompdf(n; p; k) = P(X = k), binomcdf(n; p; k) = P(X ≤ k) for X ~ B(n, p).
    case binompdf, binomcdf
    /// poissonpdf(λ; k), poissoncdf(λ; k)
    case poissonpdf, poissoncdf
    /// normpdf(x) or normpdf(x; μ; σ); invnorm(p) or invnorm(p; μ; σ).
    case normpdf, invnorm
    /// Student t: tpdf(x; ν), tcdf(x; ν) = P(T ≤ x), invt(p; ν).
    case tpdf, tcdf, invt
    /// χ²: chi2pdf(x; k), chi2cdf(x; k) = P(X ≤ x), invchi2(p; k).
    case chi2pdf, chi2cdf, invchi2
    /// Fisher F: fpdf(x; d₁; d₂), fcdf(x; d₁; d₂), invf(p; d₁; d₂).
    case fpdf, fcdf, invf

    public var arity: Int {
        switch self {
        case .log, .root, .gcd, .lcm, .mod, .idiv, .nCr, .nPr, .pol, .rec, .randInt: 2
        case .dot, .cross, .angle, .poissonpdf, .poissoncdf: 2
        case .tpdf, .tcdf, .invt, .chi2pdf, .chi2cdf, .invchi2: 2
        case .binompdf, .binomcdf, .fpdf, .fcdf, .invf: 3
        case .rand, .dice, .coin: 0
        case .min, .max, .normpdf, .invnorm: -1
        default: 1
        }
    }

    /// Functions that take or return matrices and vectors.
    public var isMatrixFunction: Bool {
        switch self {
        case .det, .transpose, .trace, .rank, .inv, .dot, .cross, .norm, .angle, .unit, .eig, .charpoly, .rref, .kernel: true
        default: false
        }
    }

    /// Inverse function written as f⁻¹ on calculators (sin⁻¹ = arcsin).
    public var inverseFunction: MathFunction? {
        switch self {
        case .sin: .asin
        case .cos: .acos
        case .tan: .atan
        case .cot: .acot
        case .sec: .asec
        case .csc: .acsc
        case .sinh: .asinh
        case .cosh: .acosh
        case .tanh: .atanh
        case .coth: .acoth
        case .sech: .asech
        case .csch: .acsch
        default: nil
        }
    }

    /// Functions whose value changes on every evaluation.
    public var isRandom: Bool {
        switch self {
        case .rand, .dice, .coin, .randInt: true
        default: false
        }
    }

    public var isTrigonometric: Bool {
        switch self {
        case .sin, .cos, .tan, .cot, .sec, .csc: true
        default: false
        }
    }

    public var isInverseTrigonometric: Bool {
        switch self {
        case .asin, .acos, .atan, .acot, .asec, .acsc: true
        default: false
        }
    }

    /// Display name using international notation (`tan`, `arcsin`).
    public var internationalName: String {
        switch self {
        case .asin: "arcsin"
        case .acos: "arccos"
        case .atan: "arctan"
        case .acot: "arccot"
        case .asec: "arcsec"
        case .acsc: "arccsc"
        case .asinh: "arsinh"
        case .acosh: "arcosh"
        case .atanh: "artanh"
        case .acoth: "arcoth"
        case .asech: "arsech"
        case .acsch: "arcsch"
        case .log10: "log"
        case .log2: "log₂"
        case .normcdf: "Φ"
        case .gamma: "Γ"
        case .zeta: "ζ"
        case .re: "Re"
        case .im: "Im"
        case .nCr: "C"
        case .nPr: "V"
        case .conj: "conj"
        case .idiv: "int÷"
        case .pol: "Pol"
        case .rec: "Rec"
        case .rand: "Rand"
        case .dice: "Dice"
        case .coin: "Coin"
        case .randInt: "R.Int"
        case .degrees: "°"
        case .transpose: "transp"
        case .inv: "inv"
        case .norm: "‖·‖"
        case .unit: "enot"
        case .kernel: "ker"
        case .angle: "∢"
        case .invnorm: "invNorm"
        case .invt: "invT"
        case .chi2pdf: "χ²pdf"
        case .chi2cdf: "χ²cdf"
        case .invchi2: "invχ²"
        case .invf: "invF"
        default: rawValue
        }
    }

    /// Display name using the notation of Slovenian textbooks (`tg`, `ctg`, `arc sin`).
    public var slovenianName: String {
        switch self {
        case .tan: "tg"
        case .cot: "ctg"
        case .atan: "arc tg"
        case .acot: "arc ctg"
        case .asin: "arc sin"
        case .acos: "arc cos"
        case .tanh: "th"
        case .coth: "cth"
        case .sinh: "sh"
        case .cosh: "ch"
        default: internationalName
        }
    }

    /// Names accepted by the text parser.
    public static let parserNames: [String: MathFunction] = {
        var map: [String: MathFunction] = [:]
        for f in MathFunction.allCases { map[f.rawValue] = f }
        let aliases: [String: MathFunction] = [
            "arcsin": .asin, "arccos": .acos, "arctan": .atan, "arccot": .acot,
            "arcsec": .asec, "arccsc": .acsc, "tg": .tan, "ctg": .cot, "cotg": .cot,
            "arctg": .atan, "arcctg": .acot, "arsinh": .asinh, "arcosh": .acosh,
            "artanh": .atanh, "arcoth": .acoth, "sh": .sinh, "ch": .cosh, "th": .tanh,
            "cth": .coth, "lg": .log10, "lb": .log2, "ld": .log2, "Γ": .gamma, "ζ": .zeta,
            "Φ": .normcdf, "phi": .normcdf, "binom": .nCr, "ncr": .nCr, "npr": .nPr,
            "Re": .re, "Im": .im, "sgn": .sign, "signum": .sign,
            "int": .ipart, "fpart": .frac, "ranint": .randInt, "rint": .randInt,
            "random": .rand, "rec": .rec, "pol": .pol, "intdiv": .idiv,
            "trans": .transpose, "transp": .transpose, "inverse": .inv, "tr": .trace, "sl": .trace,
            "rang": .rank, "eigen": .eig, "lastne": .eig, "karpol": .charpoly, "ker": .kernel, "jedro": .kernel, "null": .kernel, "skalarni": .dot, "vektorski": .cross, "length": .norm, "abs2": .norm,
            "invNorm": .invnorm, "binomPdf": .binompdf, "binomCdf": .binomcdf, "normPdf": .normpdf,
            "poissonPdf": .poissonpdf, "poissonCdf": .poissoncdf,
            "tPdf": .tpdf, "tCdf": .tcdf, "invT": .invt, "chi2Pdf": .chi2pdf, "chi2Cdf": .chi2cdf, "invChi2": .invchi2,
            "fPdf": .fpdf, "fCdf": .fcdf, "invF": .invf,
        ]
        map.merge(aliases) { current, _ in current }
        return map
    }()
}

/// One- or two-sided limits.
public enum LimitDirection: String, Hashable, Sendable, Codable {
    case both
    /// x → a⁻
    case left
    /// x → a⁺
    case right
}

/// The expression tree shared by parsing, evaluation, the CAS and rendering.
///
/// `negation` and `quotient` keep the user's structure for display; the
/// simplifier rewrites them to canonical `sum`/`product`/`power` forms.
public indirect enum Expr: Hashable, Sendable, Codable {
    case number(Rational)
    case decimal(Double)
    case constant(MathConstant)
    case variable(String)
    case sum([Expr])
    case product([Expr])
    case negation(Expr)
    case quotient(Expr, Expr)
    case power(Expr, Expr)
    case function(MathFunction, [Expr])
    case factorial(Expr)
    case percent(Expr)
    /// `d/dx body`, optionally evaluated at a point.
    case derivative(Expr, variable: String, at: Expr?)
    /// Indefinite (bounds `nil`) or definite integral.
    case integral(Expr, variable: String, lower: Expr?, upper: Expr?)
    /// `Σ_{variable=lower}^{upper} body`
    case summation(Expr, variable: String, lower: Expr, upper: Expr)
    /// `lim_{variable → point} body` (point may be ±∞)
    case limit(Expr, variable: String, point: Expr, direction: LimitDirection)
    case relation(Expr, RelationOperator, Expr)
    /// `a ± b` — display only (formula sheets).
    case plusMinus(Expr, Expr)
    /// A matrix (row-major entries). Vectors are n×1 matrices.
    case matrix(rows: Int, columns: Int, entries: [Expr])
    /// Piecewise function: value, condition, value, condition, … and an optional
    /// trailing value used "otherwise". Undefined when no condition holds.
    case piecewise([Expr])
    /// `Π_{variable=lower}^{upper} body`
    case productSeries(Expr, variable: String, lower: Expr, upper: Expr)

    // MARK: Convenience constructors

    public static func int(_ value: Int) -> Expr { .number(Rational(value)) }
    public static func frac(_ n: Int, _ d: Int) -> Expr { .number(Rational(n, d) ?? .zero) }
    public static let zero = Expr.number(.zero)
    public static let one = Expr.number(.one)
    public static let x = Expr.variable("x")
    public static let y = Expr.variable("y")
    public static let pi = Expr.constant(.pi)
    public static let e = Expr.constant(.e)

    public static func fn(_ f: MathFunction, _ args: Expr...) -> Expr { .function(f, args) }

    public static func + (lhs: Expr, rhs: Expr) -> Expr { .sum([lhs, rhs]) }
    public static func - (lhs: Expr, rhs: Expr) -> Expr { .sum([lhs, .negation(rhs)]) }
    public static func * (lhs: Expr, rhs: Expr) -> Expr { .product([lhs, rhs]) }
    public static func / (lhs: Expr, rhs: Expr) -> Expr { .quotient(lhs, rhs) }
    public static prefix func - (operand: Expr) -> Expr { .negation(operand) }

    // MARK: Inspection

    public var isNumberLiteral: Bool {
        switch self {
        case .number, .decimal: true
        default: false
        }
    }

    public var rationalValue: Rational? {
        switch self {
        case .number(let r): r
        case .negation(let inner): inner.rationalValue?.negated()
        default: nil
        }
    }

    /// Direct children, in order.
    public var children: [Expr] {
        switch self {
        case .number, .decimal, .constant, .variable: []
        case .sum(let terms), .product(let terms): terms
        case .negation(let e), .factorial(let e), .percent(let e): [e]
        case .quotient(let a, let b), .power(let a, let b), .relation(let a, _, let b), .plusMinus(let a, let b): [a, b]
        case .function(_, let args): args
        case .derivative(let body, _, let at): [body] + (at.map { [$0] } ?? [])
        case .integral(let body, _, let lower, let upper): [body] + [lower, upper].compactMap { $0 }
        case .summation(let body, _, let lower, let upper): [body, lower, upper]
        case .limit(let body, _, let point, _): [body, point]
        case .matrix(_, _, let entries): entries
        case .piecewise(let parts): parts
        case .productSeries(let body, _, let lower, let upper): [body, lower, upper]
        }
    }

    /// All free variable names (bound variables of calculus nodes are excluded).
    public var freeVariables: Set<String> {
        switch self {
        case .variable(let name):
            return [name]
        case .derivative(let body, let v, let at):
            var inner = body.freeVariables
            if at != nil { inner.remove(v) }
            return inner.union(at?.freeVariables ?? [])
        case .integral(let body, let v, let lower, let upper):
            var inner = body.freeVariables
            if lower != nil || upper != nil { inner.remove(v) }
            return inner.union(lower?.freeVariables ?? []).union(upper?.freeVariables ?? [])
        case .summation(let body, let v, let lower, let upper), .productSeries(let body, let v, let lower, let upper):
            var inner = body.freeVariables
            inner.remove(v)
            return inner.union(lower.freeVariables).union(upper.freeVariables)
        case .limit(let body, let v, let point, _):
            var inner = body.freeVariables
            inner.remove(v)
            return inner.union(point.freeVariables)
        default:
            return children.reduce(into: Set<String>()) { $0.formUnion($1.freeVariables) }
        }
    }

    public func contains(where predicate: (Expr) -> Bool) -> Bool {
        if predicate(self) { return true }
        return children.contains { $0.contains(where: predicate) }
    }

    public var containsImaginaryUnit: Bool {
        contains { if case .constant(.i) = $0 { true } else { false } }
    }

    public func dependsOn(_ variable: String) -> Bool { freeVariables.contains(variable) }

    /// Number of nodes; used to bound the work of the simplifier.
    public var nodeCount: Int { 1 + children.reduce(0) { $0 + $1.nodeCount } }

    /// Replaces every free occurrence of `name` with `replacement`.
    public func substituting(_ name: String, with replacement: Expr) -> Expr {
        switch self {
        case .variable(let v) where v == name:
            return replacement
        case .derivative(let body, let v, let at) where v == name:
            return .derivative(body, variable: v, at: at?.substituting(name, with: replacement))
        case .integral(let body, let v, let lo, let hi) where v == name && (lo != nil || hi != nil):
            return .integral(body, variable: v, lower: lo?.substituting(name, with: replacement), upper: hi?.substituting(name, with: replacement))
        case .summation(let body, let v, let lo, let hi) where v == name:
            return .summation(body, variable: v, lower: lo.substituting(name, with: replacement), upper: hi.substituting(name, with: replacement))
        case .productSeries(let body, let v, let lo, let hi) where v == name:
            return .productSeries(body, variable: v, lower: lo.substituting(name, with: replacement), upper: hi.substituting(name, with: replacement))
        case .limit(let body, let v, let point, let direction) where v == name:
            return .limit(body, variable: v, point: point.substituting(name, with: replacement), direction: direction)
        default:
            return mapChildren { $0.substituting(name, with: replacement) }
        }
    }

    /// Rebuilds the node with transformed children.
    public func mapChildren(_ transform: (Expr) -> Expr) -> Expr {
        switch self {
        case .number, .decimal, .constant, .variable: self
        case .sum(let t): .sum(t.map(transform))
        case .product(let t): .product(t.map(transform))
        case .negation(let e): .negation(transform(e))
        case .factorial(let e): .factorial(transform(e))
        case .percent(let e): .percent(transform(e))
        case .quotient(let a, let b): .quotient(transform(a), transform(b))
        case .power(let a, let b): .power(transform(a), transform(b))
        case .relation(let a, let op, let b): .relation(transform(a), op, transform(b))
        case .plusMinus(let a, let b): .plusMinus(transform(a), transform(b))
        case .function(let f, let args): .function(f, args.map(transform))
        case .derivative(let body, let v, let at): .derivative(transform(body), variable: v, at: at.map(transform))
        case .integral(let body, let v, let lo, let hi): .integral(transform(body), variable: v, lower: lo.map(transform), upper: hi.map(transform))
        case .summation(let body, let v, let lo, let hi): .summation(transform(body), variable: v, lower: transform(lo), upper: transform(hi))
        case .limit(let body, let v, let point, let direction): .limit(transform(body), variable: v, point: transform(point), direction: direction)
        case .matrix(let rows, let columns, let entries): .matrix(rows: rows, columns: columns, entries: entries.map(transform))
        case .piecewise(let parts): .piecewise(parts.map(transform))
        case .productSeries(let body, let v, let lo, let hi): .productSeries(transform(body), variable: v, lower: transform(lo), upper: transform(hi))
        }
    }

    /// True when the expression contains a matrix literal or a matrix function.
    public var containsMatrix: Bool {
        contains { node in
            switch node {
            case .matrix: true
            case .function(let f, _): f.isMatrixFunction
            default: false
            }
        }
    }
}
