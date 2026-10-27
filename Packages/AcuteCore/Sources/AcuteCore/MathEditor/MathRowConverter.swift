import Foundation

/// Converts between editor rows and expressions.
public enum MathRowConverter {
    // MARK: Row → Expr

    /// Parses a structured row. Empty placeholders raise `.incomplete`.
    public static func expr(from row: MathRow, options: ParserOptions = ParserOptions()) throws(MathError) -> Expr {
        let tokens = try tokens(from: row, options: options)
        guard !tokens.isEmpty else { throw .incomplete }
        return try Parser.parse(tokens: tokens, options: options)
    }

    /// Relations separated by commas: a system (see `Parser.parseSystem`); nil for anything else.
    public static func system(from row: MathRow, options: ParserOptions = ParserOptions()) -> [Expr]? {
        guard let list = try? tokens(from: row, options: options), !list.isEmpty else { return nil }
        return Parser.parseSystem(tokens: list, options: options)
    }

    static func sub(_ row: MathRow, _ options: ParserOptions) throws(MathError) -> Expr {
        guard !row.isEmpty else { throw .incomplete }
        return try expr(from: row, options: options)
    }

    static func tokens(from row: MathRow, options: ParserOptions) throws(MathError) -> [Token] {
        var tokens: [Token] = []
        var number = ""
        func flushNumber() {
            if !number.isEmpty {
                tokens.append(.number(number))
                number = ""
            }
        }
        var i = 0
        let nodes = row.nodes
        while i < nodes.count {
            let node = nodes[i]
            switch node {
            case .symbol(let s):
                switch s {
                case .digit(let d):
                    number.append(String(d))
                case .decimalPoint:
                    if number.isEmpty { number = "0" }
                    number.append(".")
                case .exponent10:
                    if number.isEmpty { number = "1" }
                    number.append("E")
                    // Optional sign directly after ᴇ
                    if i + 1 < nodes.count, case .symbol(.minus) = nodes[i + 1] {
                        number.append("-")
                        i += 1
                    }
                default:
                    flushNumber()
                    tokens.append(contentsOf: symbolTokens(s))
                }
            default:
                flushNumber()
                tokens.append(try structureToken(node, options))
            }
            i += 1
        }
        flushNumber()
        // Subscripts rename the preceding variable (x₁ → x_1)
        var merged: [Token] = []
        for t in tokens {
            if case .sub(let s) = t, case .structure(.variable(let name)) = merged.last {
                merged[merged.count - 1] = .structure(.variable("\(name)_\(s)"))
            } else {
                merged.append(t)
            }
        }
        return merged
    }

    static func symbolTokens(_ s: MathSymbol) -> [Token] {
        switch s {
        case .digit, .decimalPoint, .exponent10: []
        case .plus: [.op("+")]
        case .minus: [.op("-")]
        case .times: [.op("*")]
        case .divide: [.op("/")]
        case .equals: [.op("=")]
        case .less: [.op("<")]
        case .greater: [.op(">")]
        case .lessOrEqual: [.op("≤")]
        case .greaterOrEqual: [.op("≥")]
        case .notEqual: [.op("≠")]
        case .leftParenthesis: [.op("(")]
        case .rightParenthesis: [.op(")")]
        case .comma: [.op(",")]
        // ∈ and … are kept as letters in rows (keys, LaTeX \in, \dots) but read like typed text.
        case .variable("∈"): [.op("∈")]
        case .variable("…"), .variable("⋯"): [.op("…")]
        case .variable(let name): [.structure(.variable(name))]
        case .constant(let c): [.structure(.constant(c))]
        case .factorial: [.op("!")]
        case .percent: [.op("%")]
        case .degreeMark: [.op("°")]
        case .minuteMark: [.op("'")]
        case .secondMark: [.op("\"")]
        case .ans: [.structure(.variable("Ans"))]
        case .plusMinus: [.op("±")]
        case .crossProduct: [.op("⨯")]
        case .angleSign: [.op("∠")]
        case .parallel: [.op("∥")]
        case .transposeMark: [.op("ᵀ")]
        }
    }

    static func structureToken(_ node: MathNode, _ o: ParserOptions) throws(MathError) -> Token {
        switch node {
        case .symbol:
            return .op("")
        case .fraction(let n, let d):
            return .structure(.quotient(try sub(n, o), try sub(d, o)))
        case .power(let e):
            return .superscript(try sub(e, o))
        case .subscriptRow(let s):
            return .sub(plainText(s))
        case .squareRoot(let r):
            return .structure(.function(.sqrt, [try sub(r, o)]))
        case .nthRoot(let index, let radicand):
            return .structure(.function(.root, [try sub(index, o), try sub(radicand, o)]))
        case .absoluteValue(let r):
            return .structure(.function(.abs, [try sub(r, o)]))
        case .function(let f, let argument):
            if f.arity == 0 { return .structure(.function(f, [])) }
            return .structure(.function(f, [try sub(argument, o)]))
        case .logarithm(let base, let argument):
            return .structure(.function(.log, [try sub(base, o), try sub(argument, o)]))
        case .derivative(let body, let point):
            var at: Expr?
            if let point, !point.isEmpty { at = try sub(point, o) }
            return .structure(.derivative(try sub(body, o), variable: o.defaultVariable, at: at))
        case .integral(let lower, let upper, let body):
            let b = try sub(body, o)
            if lower.isEmpty && upper.isEmpty {
                return .structure(.integral(b, variable: o.defaultVariable, lower: nil, upper: nil))
            }
            return .structure(.integral(b, variable: o.defaultVariable, lower: try sub(lower, o), upper: try sub(upper, o)))
        case .summation(let lower, let upper, let body):
            return .structure(.summation(try sub(body, o), variable: "n", lower: try sub(lower, o), upper: try sub(upper, o)))
        case .binomial(let n, let k):
            return .structure(.function(.nCr, [try sub(n, o), try sub(k, o)]))
        case .function2(let f, let a, let b):
            return .structure(.function(f, [try sub(a, o), try sub(b, o)]))
        case .limit(let point, let body, let direction):
            return .structure(.limit(try sub(body, o), variable: o.defaultVariable, point: try sub(point, o), direction: direction))
        case .matrix(let rows, let columns, let cells):
            guard rows > 0, columns > 0, cells.count == rows * columns else { throw .syntax("neveljavna matrika") }
            var entries: [Expr] = []
            for cell in cells { entries.append(try sub(cell, o)) }
            return .structure(.matrix(rows: rows, columns: columns, entries: entries))
        case .piecewise(let cells):
            var parts: [Expr] = []
            let rows = cells.count / 2
            for r in 0..<rows {
                let value = try sub(cells[2 * r], o)
                let condition = cells[2 * r + 1]
                if condition.isEmpty {
                    // "otherwise" is only allowed in the last row.
                    guard r == rows - 1 else { throw .incomplete }
                    parts.append(value)
                } else {
                    parts.append(value)
                    parts.append(try sub(condition, o))
                }
            }
            return .structure(.piecewise(parts))
        case .bigProduct(let lower, let upper, let body):
            return .structure(.productSeries(try sub(body, o), variable: "n", lower: try sub(lower, o), upper: try sub(upper, o)))
        case .vectorArrow(let content):
            // The arrow is notation: a⃗ evaluates like a.
            return .structure(try sub(content, o))
        case .functionN(let f, let args):
            var values: [Expr] = []
            for a in args { values.append(try sub(a, o)) }
            return .structure(try Parser.makeCall(f, values))
        case .partialDerivative(let variable, let body):
            let name = plainText(variable).trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { throw .incomplete }
            return .structure(.derivative(try sub(body, o), variable: name, at: nil))
        case .poweredFunction(let f, let exponent, let argument):
            let e = try sub(exponent, o)
            let a = try sub(argument, o)
            // sin⁻¹(x) is arcsin(x) on calculators; other exponents apply to the value: sin²x = (sin x)².
            if e.rationalValue == .minusOne, let inverse = f.inverseFunction {
                return .structure(.function(inverse, [a]))
            }
            return .structure(.power(.function(f, [a]), e))
        }
    }

    // MARK: Plain text

    public static func plainText(_ row: MathRow) -> String {
        row.nodes.map { node -> String in
            switch node {
            case .symbol(let s): s.text(multiplication: "·", decimalSeparator: ".")
            case .fraction(let n, let d): "(\(plainText(n)))/(\(plainText(d)))"
            case .power(let e): "^(\(plainText(e)))"
            case .subscriptRow(let s): "_\(plainText(s))"
            case .squareRoot(let r): "√(\(plainText(r)))"
            case .nthRoot(let i, let r): "root(\(plainText(i)), \(plainText(r)))"
            case .absoluteValue(let r): "|\(plainText(r))|"
            case .function(let f, let a): "\(f.internationalName)(\(plainText(a)))"
            case .logarithm(let b, let a): "log(\(plainText(b)), \(plainText(a)))"
            case .derivative(let b, let p): "d/dx(\(plainText(b)))" + (p.map { "|x=\(plainText($0))" } ?? "")
            case .integral(let l, let u, let b): "∫[\(plainText(l)), \(plainText(u))](\(plainText(b)))dx"
            case .summation(let l, let u, let b): "Σ[n=\(plainText(l)), \(plainText(u))](\(plainText(b)))"
            case .binomial(let n, let k): "C(\(plainText(n)), \(plainText(k)))"
            case .function2(let f, let a, let b): "\(f.internationalName)(\(plainText(a)), \(plainText(b)))"
            case .limit(let p, let b, _): "lim[x→\(plainText(p))](\(plainText(b)))"
            case .matrix(let rows, let columns, let cells):
                "[" + (0..<rows).map { r in "[" + (0..<columns).map { c in plainText(cells[r * columns + c]) }.joined(separator: ", ") + "]" }.joined(separator: ", ") + "]"
            case .piecewise(let cells):
                "piecewise(" + cells.map(plainText).filter { !$0.isEmpty }.joined(separator: ", ") + ")"
            case .bigProduct(let l, let u, let b): "Π[n=\(plainText(l)), \(plainText(u))](\(plainText(b)))"
            case .vectorArrow(let r): plainText(r) + "\u{20D7}"
            case .functionN(let f, let args): "\(f.internationalName)(" + args.map(plainText).joined(separator: ", ") + ")"
            case .partialDerivative(let v, let b): "∂/∂\(plainText(v))(\(plainText(b)))"
            case .poweredFunction(let f, let e, let a): "\(f.internationalName)^(\(plainText(e)))(\(plainText(a)))"
            }
        }.joined()
    }

    // MARK: Expr → Row (pretty printing)

    /// Renders an expression as an editor row (used for results, CAS output and formulas).
    public static func row(for expr: Expr) -> MathRow {
        MathRow(nodes(for: DisplayForm.prettify(expr), context: .top))
    }

    /// Renders without prettifying (keeps the user's structure).
    public static func rowPreservingStructure(for expr: Expr) -> MathRow {
        MathRow(nodes(for: expr, context: .top))
    }

    /// A row for typed text, kept as written: the parts of a system (`x ≥ 0, y ≥ 0` or
    /// `(cos t, sin t), 0 ≤ t ≤ π`) stay separated by commas, and a pair (x, y) or a point
    /// A(x, y) stays a pair in brackets instead of becoming a column vector.
    public static func row(fromText text: String, options: ParserOptions = ParserOptions()) throws(MathError) -> MathRow {
        let tokens = try Lexer().tokenize(text)
        if let indexed = try Parser.parseIndexedSystem(tokens: tokens, options: options) {
            // (x − n)² + y² ≤ 2^(−n−1), n in N: the parts, then the condition as the keys type it.
            return MathRow(indexed.parts.flatMap { nodes(for: $0, context: .top) + [.symbol(.comma)] } + indexNodes(indexed))
        }
        let parts: [Expr]
        if let system = Parser.parseSystem(tokens: tokens, options: options) {
            parts = system
        } else {
            parts = [try Parser.parse(tokens: tokens, options: options)]
        }
        var result: [MathNode] = []
        for part in parts {
            if !result.isEmpty { result.append(.symbol(.comma)) }
            if let point = PlaneSets.point(part) {
                // (x, y) and A(x, y) as written, not as column vectors.
                if let name = point.name { result.append(.symbol(.variable(name))) }
                result += parenthesized(nodes(for: point.x, context: .top) + [.symbol(.comma)] + nodes(for: point.y, context: .top))
            } else {
                result += nodes(for: part, context: .top)
            }
        }
        return MathRow(result)
    }

    /// n ∈ ℕ, n ∈ ℕ₀ or n = a, a + 1, … as editor nodes.
    static func indexNodes(_ system: IndexedSystem) -> [MathNode] {
        let index = MathNode.symbol(.variable(system.index))
        let element = MathNode.symbol(.variable("∈"))
        switch system.start {
        case 1:
            return [index, element, .symbol(.variable("ℕ"))]
        case 0:
            return [index, element, .symbol(.variable("ℕ")), .subscriptRow(MathRow([.symbol(.digit(0))]))]
        default:
            var run: [MathNode] = [index, .symbol(.equals)]
            run += digits(String(system.start))
            run.append(.symbol(.comma))
            run += digits(String(system.start + 1))
            run += [.symbol(.comma), .symbol(.variable("…"))]
            return run
        }
    }

    enum Context { case top, sumTerm, factor, base, exponent, argument }

    public static func digits(_ text: String) -> [MathNode] {
        text.compactMap { c -> MathNode? in
            if let d = c.wholeNumberValue { return .symbol(.digit(d)) }
            if c == "." { return .symbol(.decimalPoint) }
            if c == "-" { return .symbol(.minus) }
            return nil
        }
    }

    static func numberNodes(_ r: Rational) -> [MathNode] {
        if r.isInteger { return digits(String(r.numerator)) }
        let fraction = MathNode.fraction(numerator: MathRow(digits(String(abs(r.numerator)))), denominator: MathRow(digits(String(r.denominator))))
        return r.isNegative ? [.symbol(.minus), fraction] : [fraction]
    }

    static func decimalNodes(_ d: Double) -> [MathNode] {
        if d.isInfinite { return d > 0 ? [.symbol(.constant(.infinity))] : [.symbol(.minus), .symbol(.constant(.infinity))] }
        let formatted = NumberFormatting.plain(d)
        if let eIndex = formatted.firstIndex(of: "E") {
            let mantissa = String(formatted[..<eIndex])
            let exponent = String(formatted[formatted.index(after: eIndex)...])
            return digits(mantissa) + [.symbol(.times)] + digits("10") + [.power(exponent: MathRow(digits(exponent)))]
        }
        return digits(formatted)
    }

    static func parenthesized(_ inner: [MathNode]) -> [MathNode] {
        [.symbol(.leftParenthesis)] + inner + [.symbol(.rightParenthesis)]
    }

    static func needsParentheses(_ e: Expr, in context: Context) -> Bool {
        switch e {
        case .sum, .plusMinus, .relation:
            return context == .factor || context == .base
        case .negation:
            return context == .factor || context == .base
        case .product, .quotient:
            return context == .base
        case .number(let r):
            return context == .base && (!r.isInteger || r.isNegative)
        case .decimal(let d):
            return context == .base && d < 0
        case .power:
            return context == .base
        default:
            return false
        }
    }

    static func nodes(for e: Expr, context: Context) -> [MathNode] {
        let inner = rawNodes(for: e, context: context)
        return needsParentheses(e, in: context) ? parenthesized(inner) : inner
    }

    static func rawNodes(for e: Expr, context: Context) -> [MathNode] {
        switch e {
        case .number(let r):
            return numberNodes(r)
        case .decimal(let d):
            return decimalNodes(d)
        case .constant(let c):
            return [.symbol(.constant(c))]
        case .variable(let name):
            return [.symbol(name == "Ans" ? .ans : .variable(name))]
        case .sum(let terms):
            var out: [MathNode] = []
            for (i, t) in terms.enumerated() {
                if case .negation(let inner) = t {
                    out.append(.symbol(.minus))
                    out += nodes(for: inner, context: .sumTerm)
                } else if case .number(let r) = t, r.isNegative, i > 0 {
                    out.append(.symbol(.minus))
                    out += numberNodes(r.magnitude)
                } else {
                    if i > 0 { out.append(.symbol(.plus)) }
                    out += nodes(for: t, context: .sumTerm)
                }
            }
            return out
        case .product(let factors):
            var out: [MathNode] = []
            var previous: Expr?
            for f in factors {
                let rendered = nodes(for: f, context: .factor)
                if let p = previous, needsExplicitTimes(p, f) { out.append(.symbol(.times)) }
                out += rendered
                previous = f
            }
            return out
        case .negation(let inner):
            return [.symbol(.minus)] + nodes(for: inner, context: .factor)
        case .quotient(let a, let b):
            return [.fraction(numerator: MathRow(nodes(for: a, context: .top)), denominator: MathRow(nodes(for: b, context: .top)))]
        case .power(let base, let exponent):
            if case .function(let f, let args) = base, args.count == 1, f != .sqrt, f != .abs {
                // sin²(x) style is ambiguous for students; keep (sin x)².
                return parenthesized(rawNodes(for: base, context: .top)) + [.power(exponent: MathRow(nodes(for: exponent, context: .exponent)))]
            }
            return nodes(for: base, context: .base) + [.power(exponent: MathRow(nodes(for: exponent, context: .exponent)))]
        case .function(let f, let args):
            return functionNodes(f, args)
        case .factorial(let inner):
            let atomic = inner.isAtomic
            let body = nodes(for: inner, context: .top)
            return (atomic ? body : parenthesized(body)) + [.symbol(.factorial)]
        case .percent(let inner):
            let body = nodes(for: inner, context: .top)
            return (inner.isAtomic ? body : parenthesized(body)) + [.symbol(.percent)]
        case .derivative(let body, _, let at):
            return [.derivative(body: MathRow(nodes(for: body, context: .top)), point: at.map { MathRow(nodes(for: $0, context: .top)) })]
        case .integral(let body, _, let lower, let upper):
            return [.integral(lower: MathRow(lower.map { nodes(for: $0, context: .top) } ?? []),
                              upper: MathRow(upper.map { nodes(for: $0, context: .top) } ?? []),
                              body: MathRow(nodes(for: body, context: .top)))]
        case .summation(let body, _, let lower, let upper):
            return [.summation(lower: MathRow(nodes(for: lower, context: .top)), upper: MathRow(nodes(for: upper, context: .top)), body: MathRow(nodes(for: body, context: .top)))]
        case .limit(let body, _, let point, let direction):
            return [.limit(point: MathRow(nodes(for: point, context: .top)), body: MathRow(nodes(for: body, context: .top)), direction: direction)]
        case .relation(let a, let op, let b):
            let symbol: MathSymbol = switch op {
            case .equal: .equals
            case .less: .less
            case .greater: .greater
            case .lessOrEqual: .lessOrEqual
            case .greaterOrEqual: .greaterOrEqual
            case .notEqual: .notEqual
            }
            return nodes(for: a, context: .top) + [.symbol(symbol)] + nodes(for: b, context: .top)
        case .plusMinus(let a, let b):
            if a == .number(.zero) { return [.symbol(.plusMinus)] + nodes(for: b, context: .sumTerm) }
            return nodes(for: a, context: .sumTerm) + [.symbol(.plusMinus)] + nodes(for: b, context: .sumTerm)
        case .matrix(let rows, let columns, let entries):
            return [.matrix(rows: rows, columns: columns, cells: entries.map { MathRow(nodes(for: $0, context: .top)) })]
        case .piecewise(let parts):
            var cells: [MathRow] = []
            var k = 0
            while k < parts.count {
                cells.append(MathRow(nodes(for: parts[k], context: .top)))
                cells.append(k + 1 < parts.count ? MathRow(nodes(for: parts[k + 1], context: .top)) : MathRow())
                k += 2
            }
            return [.piecewise(cells: cells)]
        case .productSeries(let body, _, let lower, let upper):
            return [.bigProduct(lower: MathRow(nodes(for: lower, context: .top)), upper: MathRow(nodes(for: upper, context: .top)), body: MathRow(nodes(for: body, context: .top)))]
        }
    }

    static func functionNodes(_ f: MathFunction, _ args: [Expr]) -> [MathNode] {
        func row(_ i: Int) -> MathRow { MathRow(i < args.count ? nodes(for: args[i], context: .top) : []) }
        switch f {
        case .sqrt: return [.squareRoot(row(0))]
        case .cbrt: return [.nthRoot(index: MathRow(digits("3")), radicand: row(0))]
        case .root: return [.nthRoot(index: row(0), radicand: row(1))]
        case .abs: return [.absoluteValue(row(0))]
        case .log: return [.logarithm(base: row(0), argument: row(1))]
        case .nCr: return [.binomial(row(0), row(1))]
        case .exp: return [.symbol(.constant(.e)), .power(exponent: row(0))]
        case .degrees: return nodes(for: args[0], context: .factor) + [.symbol(.degreeMark)]
        case .rand, .dice, .coin: return [.function(f, argument: MathRow())]
        case .transpose: return nodes(for: args[0], context: .base) + [.symbol(.transposeMark)]
        case .inv: return nodes(for: args[0], context: .base) + [.power(exponent: MathRow([.symbol(.minus), .symbol(.digit(1))]))]
        case .norm: return [.absoluteValue(row(0))]
        case .cross where args.count == 2:
            return nodes(for: args[0], context: .factor) + [.symbol(.crossProduct)] + nodes(for: args[1], context: .factor)
        default:
            if args.count >= 3 { return [.functionN(f, args.indices.map(row))] }
            if args.count == 2 { return [.function2(f, row(0), row(1))] }
            return [.function(f, argument: row(0))]
        }
    }

    /// Whether `a·b` needs a visible multiplication sign (2·3, 2·(−1)) or can be juxtaposed (2x, 3√2, xy).
    static func needsExplicitTimes(_ a: Expr, _ b: Expr) -> Bool {
        switch b {
        case .number, .decimal, .negation:
            return true
        case .quotient:
            return true
        case .power(let base, _):
            if base.isNumberLiteral { return true }
            return false
        default:
            break
        }
        if case .function(.degrees, _) = b { return true }
        return false
    }
}

extension Expr {
    /// Atoms don't need parentheses before `!` or `%`.
    var isAtomic: Bool {
        switch self {
        case .number(let r): r.isInteger && !r.isNegative
        case .decimal(let d): d >= 0
        case .constant, .variable, .function: true
        default: false
        }
    }
}
