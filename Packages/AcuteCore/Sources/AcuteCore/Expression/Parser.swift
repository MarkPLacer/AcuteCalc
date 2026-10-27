import Foundation

public struct ParserOptions: Hashable, Sendable {
    /// Multi-letter variable names that must not be split into products (`v0`, `Δt`, user variables).
    public var knownVariables: Set<String>
    /// Interpret `a + b%` as `a·(1 + b/100)` like a pocket calculator.
    public var relativePercent: Bool
    /// Variable used by `d/dx`, `∫ … dx` written in text.
    public var defaultVariable: String
    /// Functions defined elsewhere (`f(x) = …` in the graph list), by name → body in x:
    /// `f(x − 2) + 1` then means the body with x replaced by x − 2.
    public var functions: [String: Expr]
    /// Electrical engineering: j is the imaginary unit.
    public var imaginaryUnitJ: Bool

    public init(knownVariables: Set<String> = [], relativePercent: Bool = true, defaultVariable: String = "x",
                functions: [String: Expr] = [:], imaginaryUnitJ: Bool = false) {
        self.knownVariables = knownVariables
        self.relativePercent = relativePercent
        self.defaultVariable = defaultVariable
        self.functions = functions
        self.imaginaryUnitJ = imaginaryUnitJ
    }
}

/// Recursive-descent parser with implicit multiplication.
///
/// Precedence (low → high): relation, `+ − ±`, `· / implicit`, unary `−`, `^`, postfix `! % °`.
public struct Parser {
    private var tokens: [Token]
    private var position = 0
    private var absDepth = 0
    /// Grammar calls on the current path (parseSum, parseTerm, parseUnary, parsePower, parsePostfix,
    /// parsePrimary, parseImplicitArgument, parseIdentifier, parseSpecialForm, parseFunctionCall): every
    /// recursion passes them, with at most a few small frames between (parseSingleArgument, parseArguments,
    /// parseRelationChain).
    private var nesting = 0
    private let options: ParserOptions

    /// The parser and every consumer of its tree (evaluators, CAS, rows for display) recurse once per
    /// level, on worker threads with a 512 KB stack, while held keys and pasted text have no length
    /// limit; deeper input gives .tooComplex. The limits leave room even in an unoptimised build, whose
    /// frames are several times larger: estimated from the code at up to ~10 KB per parenthesis (six
    /// grammar frames) and ~5 KB per tree level in an evaluator, both stay under half of 512 KB.
    /// AddressSanitizer frames are larger still: sin^sin^… (parsePostfix, parsePrimary and the large
    /// parseIdentifier and parseFunctionCall per level) overflowed 512 KB at 34 levels, so a prefix
    /// exponent counts two calls more and such a chain stops after 15 levels, under half of that.
    ///
    /// Grammar calls: 96 are 15 nested parentheses, 11 nested function calls (eight calls each), 14
    /// functions without parentheses (sin sin … x) or with a prefix exponent (sin^sin^…, six each), or
    /// 45 chained ^ or roots (two each).
    public static let maximumNesting = 96
    /// Tree levels: 48, more than twice the tallest real input (each nested sign is a level).
    public static let maximumHeight = 48

    public init(tokens: [Token], options: ParserOptions = ParserOptions()) {
        self.tokens = tokens
        self.options = options
    }

    public static func parse(_ text: String, options: ParserOptions = ParserOptions()) throws(MathError) -> Expr {
        let tokens = try Lexer().tokenize(text)
        var parser = Parser(tokens: tokens, options: options)
        return try parser.parseInput()
    }

    public static func parse(tokens: [Token], options: ParserOptions = ParserOptions()) throws(MathError) -> Expr {
        var parser = Parser(tokens: tokens, options: options)
        return try parser.parseInput()
    }

    /// Two or more relations or points separated by commas (or ∧) outside brackets: a system
    /// such as `x ≥ 0, y ≥ 0, x + y ≤ 4`, `y = 2x + 1, y = −x + 4` or `A(1, 2), B(4, 5), C(6, 1)`.
    /// Nil for anything else.
    public static func parseSystem(tokens: [Token], options: ParserOptions = ParserOptions()) -> [Expr]? {
        let parts = systemParts(tokens)
        guard parts.count >= 2, parts.allSatisfy({ !$0.isEmpty }) else { return nil }
        var relations: [Expr] = []
        for part in parts {
            guard let expr = try? parse(tokens: part, options: options) else { return nil }
            if case .relation = expr {
                relations.append(expr)
            } else if PlaneSets.point(expr) != nil {
                relations.append(expr)
            } else {
                return nil
            }
        }
        return relations
    }

    /// The tokens between commas (or ∧) outside brackets and |…|.
    static func systemParts(_ tokens: [Token]) -> [[Token]] {
        var parts: [[Token]] = [[]]
        var depth = 0
        var insideAbs = false
        for token in tokens {
            if let op = token.opValue {
                if (op == "," || op == "∧") && depth == 0 && !insideAbs {
                    parts.append([])
                    continue
                }
                switch op {
                case "(", "[", "{": depth += 1
                case ")", "]", "}": depth -= 1
                case "|": insideAbs.toggle()
                default: break
                }
            }
            parts[parts.count - 1].append(token)
        }
        return parts
    }

    // MARK: Token helpers

    private var current: Token? { position < tokens.count ? tokens[position] : nil }
    private var isAtEnd: Bool { position >= tokens.count }
    private mutating func advance() { position += 1 }

    private func isOp(_ s: String) -> Bool { current?.opValue == s }

    private mutating func consumeOp(_ s: String) -> Bool {
        if isOp(s) { advance(); return true }
        return false
    }

    /// One recursive grammar call deeper, or `calls` (undone with `defer { nesting -= calls }`).
    private mutating func descend(_ calls: Int = 1) throws(MathError) {
        guard nesting + calls <= Parser.maximumNesting else { throw .tooComplex }
        nesting += calls
    }

    /// Loops nest their result without recursing (3!!!…, a/b/c…, x²²…, a < b < c, ±, a + b%):
    /// the tree they build may not grow taller than the limit either.
    private static func bounded(_ e: Expr) throws(MathError) -> Expr {
        guard height(e) <= maximumHeight else { throw .tooComplex }
        return e
    }

    /// Levels of `e` (an atom is 1), counted with an explicit stack so any height is safe.
    static func height(_ e: Expr) -> Int {
        var deepest = 0
        var pending: [(expr: Expr, level: Int)] = [(e, 1)]
        while let item = pending.popLast() {
            deepest = Swift.max(deepest, item.level)
            for child in item.expr.children { pending.append((child, item.level + 1)) }
        }
        return deepest
    }

    private static let relationOps: [String: RelationOperator] = [
        "=": .equal, "<": .less, ">": .greater, "≤": .lessOrEqual, "≥": .greaterOrEqual, "≠": .notEqual,
    ]

    // MARK: Grammar

    mutating func parseInput() throws(MathError) -> Expr {
        guard !tokens.isEmpty else { throw .incomplete }
        if let definition = try parseFunctionDefinition() { return try Parser.bounded(definition) }
        let result = try parseRelationChain()
        guard isAtEnd else { throw unexpected() }
        return try Parser.bounded(result)
    }

    /// The head of a definition `f(x) = …` / `f₁(t) = …`: the function's name (with subscript),
    /// its variable and where the body starts.
    public static func definitionHead(_ tokens: [Token], options: ParserOptions = ParserOptions()) -> (name: String, variable: String, bodyStart: Int)? {
        // Typed text gives identifiers, the math editor gives variable structures.
        func name(_ token: Token) -> String? {
            switch token {
            case .identifier(let n): n
            case .structure(.variable(let n)): n
            default: nil
            }
        }
        guard let first = tokens.first, var fullName = name(first) else { return nil }
        var index = 1
        if case .sub(let s)? = tokens.dropFirst(index).first {
            fullName += "_\(s)"
            index += 1
        }
        let base = String(fullName.split(separator: "_").first ?? "")
        guard base.count == 1, MathFunction.parserNames[base] == nil, !["x", "y", "z", "e", "i"].contains(base),
              !options.knownVariables.contains(fullName), !options.knownVariables.contains(base),
              tokens.count > index + 4, tokens[index].opValue == "(",
              let variable = name(tokens[index + 1]), variable.count == 1,
              !["y", "z", "e", "i"].contains(variable), !options.knownVariables.contains(variable),
              tokens[index + 2].opValue == ")", tokens[index + 3].opValue == "=" else { return nil }
        return (fullName, variable, index + 4)
    }

    /// `f(x) = …`, `g(t) = …`, `f₁(x) = …`: how functions are given in exercises. The head only
    /// names the function, so the result is `y = body`, with the variable renamed to x for graphing.
    private mutating func parseFunctionDefinition() throws(MathError) -> Expr? {
        guard let head = Parser.definitionHead(tokens, options: options) else { return nil }
        let name = head.name.split(separator: "_").first.map(String.init) ?? head.name
        let variable = head.variable
        position = head.bodyStart
        let body = try parseSum()
        guard isAtEnd else { throw unexpected() }
        // a(n) = … is a sequence a_n.
        if variable == "n" { return .relation(.variable("\(name)_n"), .equal, body) }
        return .relation(.y, .equal, variable == "x" ? body : body.substituting(variable, with: .x))
    }

    /// `a`, `a = b`, or a chain `a ≤ b < c` (nested relations, used by piecewise conditions).
    private mutating func parseRelationChain() throws(MathError) -> Expr {
        var result = try parseSum()
        while let op = current?.opValue, let relation = Parser.relationOps[op] {
            advance()
            guard !isAtEnd else { throw .incomplete }
            result = try Parser.bounded(.relation(result, relation, try parseSum()))
        }
        return result
    }

    private func unexpected() -> MathError {
        switch current {
        case .op(let s): .syntax("nepričakovan »\(s)«")
        case .number(let s): .syntax("nepričakovano število \(s)")
        case .identifier(let s): .syntax("nepričakovan »\(s)«")
        default: .syntax("nepričakovan simbol")
        }
    }

    private mutating func parseSum() throws(MathError) -> Expr {
        try descend()
        defer { nesting -= 1 }
        var terms: [Expr] = [try parseTerm()]
        while let op = current?.opValue, op == "+" || op == "-" || op == "±" {
            advance()
            guard !isAtEnd, !(current?.opValue.map { $0 == ")" || $0 == "," } ?? false) else { throw .incomplete }
            let rhs = try parseTerm()
            let base = terms.count == 1 ? terms[0] : Expr.sum(terms)
            switch op {
            case "±":
                terms = [try Parser.bounded(.plusMinus(base, rhs))]
            case "+":
                if options.relativePercent, case .percent = rhs {
                    terms.append(try Parser.bounded(.product([base, rhs])))
                } else {
                    terms.append(rhs)
                }
            default:
                if options.relativePercent, case .percent = rhs {
                    terms.append(try Parser.bounded(.negation(.product([base, rhs]))))
                } else {
                    terms.append(.negation(rhs))
                }
            }
        }
        return terms.count == 1 ? terms[0] : .sum(terms)
    }

    private mutating func parseTerm() throws(MathError) -> Expr {
        try descend()
        defer { nesting -= 1 }
        var result = try parseUnary()
        while true {
            if consumeOp("*") {
                guard !isAtEnd else { throw .incomplete }
                result = Parser.appendFactor(result, try parseUnary())
            } else if consumeOp("/") {
                guard !isAtEnd else { throw .incomplete }
                result = try Parser.bounded(.quotient(result, try parseUnary()))
            } else if consumeOp("⨯") {
                guard !isAtEnd else { throw .incomplete }
                result = try Parser.bounded(.function(.cross, [result, try parseUnary()]))
            } else if consumeOp("∥") {
                // Parallel connection: a∥b = ab/(a + b)
                guard !isAtEnd else { throw .incomplete }
                let other = try parseUnary()
                result = try Parser.bounded(.quotient(.product([result, other]), .sum([result, other])))
            } else if canStartImplicitFactor() {
                result = Parser.appendFactor(result, try parsePower())
            } else {
                break
            }
        }
        return result
    }

    private static func appendFactor(_ lhs: Expr, _ rhs: Expr) -> Expr {
        if case .product(var factors) = lhs {
            factors.append(rhs)
            return .product(factors)
        }
        return .product([lhs, rhs])
    }

    private func canStartImplicitFactor() -> Bool {
        guard let token = current else { return false }
        switch token {
        case .number, .identifier, .structure:
            return true
        case .op(let s):
            switch s {
            case "(", "π", "∞", "√", "∛": return true
            case "|": return absDepth == 0
            default: return false
            }
        case .superscript, .sub:
            return false
        }
    }

    private mutating func parseUnary() throws(MathError) -> Expr {
        try descend()
        defer { nesting -= 1 }
        if consumeOp("-") {
            guard !isAtEnd else { throw .incomplete }
            return .negation(try parseUnary())
        }
        if consumeOp("+") {
            guard !isAtEnd else { throw .incomplete }
            return try parseUnary()
        }
        if consumeOp("±") {
            // y = ±√(r² − x²): both branches
            guard !isAtEnd else { throw .incomplete }
            return .plusMinus(.number(.zero), try parseUnary())
        }
        return try parsePower()
    }

    private mutating func parsePower() throws(MathError) -> Expr {
        try descend()
        defer { nesting -= 1 }
        var base = try parsePostfix()
        while true {
            if case .superscript(let exponent) = current {
                advance()
                base = try Parser.bounded(.power(base, exponent))
                base = try parsePostfixOperators(base)
                continue
            }
            if consumeOp("^") {
                guard !isAtEnd else { throw .incomplete }
                let exponent = try parseUnary()
                return .power(base, exponent)
            }
            if consumeOp("∠") {
                // Phasor r∠φ = r·(cos φ + i·sin φ), φ in the angle unit (or with °).
                guard !isAtEnd else { throw .incomplete }
                let angle = try parseUnary()
                return .product([base, .sum([.function(.cos, [angle]), .product([.constant(.i), .function(.sin, [angle])])])])
            }
            return base
        }
    }

    private mutating func parsePostfix() throws(MathError) -> Expr {
        try descend()
        defer { nesting -= 1 }
        let primary = try parsePrimary()
        return try parsePostfixOperators(primary)
    }

    private mutating func parsePostfixOperators(_ operand: Expr) throws(MathError) -> Expr {
        var result = operand
        while let op = current?.opValue {
            switch op {
            case "!":
                advance()
                result = try Parser.bounded(.factorial(result))
            case "ᵀ":
                advance()
                result = try Parser.bounded(.function(.transpose, [result]))
            case "%":
                advance()
                result = try Parser.bounded(.percent(result))
            case "°":
                advance()
                result = try Parser.bounded(.function(.degrees, [try parseSexagesimalTail(degrees: result)]))
            case "'":
                advance()
                // Minutes without degrees: 30' = 0.5°
                result = try Parser.bounded(.function(.degrees, [try parseSexagesimalTail(degrees: .quotient(result, .int(60)), minutesDone: true)]))
            default:
                return result
            }
        }
        return result
    }

    /// Continues `12°34'56"`: optional minutes and seconds after a degree mark.
    private mutating func parseSexagesimalTail(degrees: Expr, minutesDone: Bool = false) throws(MathError) -> Expr {
        var parts = [degrees]
        func lookahead(_ mark: String) -> Bool {
            guard case .number = current, position + 1 < tokens.count, tokens[position + 1].opValue == mark else { return false }
            return true
        }
        if !minutesDone, lookahead("'") {
            let minutes = try parsePrimary()
            advance()
            parts.append(.quotient(minutes, .int(60)))
        }
        if lookahead("\"") {
            let seconds = try parsePrimary()
            advance()
            parts.append(.quotient(seconds, .int(3600)))
        }
        return parts.count == 1 ? parts[0] : .sum(parts)
    }

    private mutating func parsePrimary() throws(MathError) -> Expr {
        try descend()
        defer { nesting -= 1 }
        guard let token = current else { throw .incomplete }
        switch token {
        case .number(let text):
            advance()
            return Parser.numberLiteral(text)
        case .structure(let expr):
            advance()
            if options.imaginaryUnitJ, case .variable("j") = expr { return .constant(.i) }
            // Letters typed on a hardware keyboard arrive as single-letter variables (MathEditor.insertLetter):
            // e and i are the constants, as in typed text (parseIdentifier) and on the keypad.
            if case .variable("e") = expr { return .constant(.e) }
            if case .variable("i") = expr { return .constant(.i) }
            // Editor variables arrive as structures: f(x − 2) for a function defined elsewhere.
            if case .variable(let name) = expr, let body = options.functions[name], isOp("(") {
                return body.substituting("x", with: try parseSingleArgument())
            }
            return expr
        case .superscript:
            throw .syntax("potenca brez osnove")
        case .sub:
            throw .syntax("indeks brez imena")
        case .identifier(let name):
            advance()
            return try parseIdentifier(name)
        case .op(let op):
            switch op {
            case "(":
                advance()
                let inner = try parseSum()
                if isOp(",") {
                    // (1, 2, 3) is a column vector; ((1, 2), (3, 4)) a matrix given by its rows.
                    var items = [inner]
                    while consumeOp(",") {
                        guard !isAtEnd else { throw .incomplete }
                        items.append(try parseSum())
                    }
                    try expectClosingParenthesis()
                    return try Parser.vectorOrMatrix(items)
                }
                try expectClosingParenthesis()
                return inner
            case "|":
                advance()
                absDepth += 1
                let inner = try parseSum()
                absDepth -= 1
                if !consumeOp("|") && !isAtEnd { throw .syntax("manjka »|«") }
                return .function(.abs, [inner])
            case "√":
                advance()
                return .function(.sqrt, [try parsePostfix()])
            case "∛":
                advance()
                return .function(.cbrt, [try parsePostfix()])
            case "π":
                advance()
                return .constant(.pi)
            case "∞":
                advance()
                return .constant(.infinity)
            case ")":
                throw .syntax("odvečen »)«")
            default:
                throw .incomplete
            }
        }
    }

    /// Calculator-friendly: a missing `)` at the very end is accepted.
    private mutating func expectClosingParenthesis() throws(MathError) {
        if consumeOp(")") { return }
        if isAtEnd { return }
        throw .syntax("manjka »)«")
    }

    static func numberLiteral(_ text: String) -> Expr {
        if let exact = Rational(decimalString: text) { return .number(exact) }
        return .decimal(Double(text.replacingOccurrences(of: ",", with: ".")) ?? .nan)
    }

    // MARK: Identifiers, functions and special forms

    private mutating func parseIdentifier(_ name: String) throws(MathError) -> Expr {
        try descend()
        defer { nesting -= 1 }
        var subscriptText: String?
        if case .sub(let s) = current {
            subscriptText = s
            advance()
        }

        if subscriptText == nil {
            switch name {
            case "pi": return .constant(.pi)
            case "e": return .constant(.e)
            case "i": return .constant(.i)
            case "j" where options.imaginaryUnitJ: return .constant(.i)
            case "inf", "infinity": return .constant(.infinity)
            default: break
            }
            if let special = try parseSpecialForm(name) { return special }
            if let greek = Parser.greekLetters[name], MathFunction.parserNames[name] == nil || !isOp("(") {
                return .variable(greek)
            }
        }

        let fullName = subscriptText.map { "\(name)_\($0)" } ?? name
        // A function defined elsewhere: f(x − 2) is its body with x → x − 2.
        if let body = options.functions[fullName], isOp("(") {
            let argument = try parseSingleArgument()
            return body.substituting("x", with: argument)
        }

        if let function = MathFunction.parserNames[name] {
            return try parseFunctionCall(function, subscriptText: subscriptText)
        }

        if name.count == 1 || options.knownVariables.contains(fullName) || options.knownVariables.contains(name) {
            return .variable(fullName)
        }

        // Split unknown words: "xy" → x·y, "xsin" → x·sin, keeping known names intact.
        let parts = splitIdentifier(name)
        var replacement: [Token] = parts.map { .identifier($0) }
        if let s = subscriptText { replacement.append(.sub(s)) }
        tokens.replaceSubrange((position - (subscriptText == nil ? 1 : 2))..<position, with: replacement)
        position -= (subscriptText == nil ? 1 : 2)
        // Parse the first split part as the primary; the rest follow as implicit factors.
        guard case .identifier(let first) = current else { throw .syntax("neznano ime \(name)") }
        advance()
        if parts.count == 1 { return .variable(first) }
        return try parseIdentifier(first)
    }

    private func splitIdentifier(_ name: String) -> [String] {
        let chars = Array(name)
        var parts: [String] = []
        var i = 0
        while i < chars.count {
            var matched: String?
            var length = chars.count - i
            while length >= 2 {
                let candidate = String(chars[i..<(i + length)])
                if MathFunction.parserNames[candidate] != nil || options.knownVariables.contains(candidate)
                    || candidate == "pi" || candidate == "inf" {
                    matched = candidate
                    break
                }
                length -= 1
            }
            if let m = matched {
                parts.append(m)
                i += m.count
            } else {
                parts.append(String(chars[i]))
                i += 1
            }
        }
        return parts
    }

    private mutating func parseArguments() throws(MathError) -> [Expr] {
        guard consumeOp("(") else { return [] }
        var args: [Expr] = []
        if consumeOp(")") { return args }
        while true {
            args.append(try parseRelationChain())
            if consumeOp(",") { continue }
            try expectClosingParenthesis()
            return args
        }
    }

    private mutating func parseFunctionCall(_ function: MathFunction, subscriptText: String?) throws(MathError) -> Expr {
        try descend()
        defer { nesting -= 1 }
        // sin²(x), sin^2 x
        var outerExponent: Expr?
        if case .superscript(let e) = current {
            advance()
            outerExponent = e
        } else if isOp("^"), function.arity == 1 {
            advance()
            // sin^-1 x, sin^2 x. A chain sin^sin^… recurses through the large frames of parseIdentifier and
            // this function with only parsePostfix and parsePrimary between: two calls more per level.
            try descend(2)
            defer { nesting -= 2 }
            outerExponent = consumeOp("-") ? .negation(try parsePostfix()) : try parsePostfix()
        }

        var call: Expr
        if function == .log, let base = subscriptText {
            let baseExpr = Parser.numberLiteral(base)
            let argument = try isOp("(") ? parseSingleArgument() : parseImplicitArgument()
            call = .function(.log, [baseExpr, argument])
        } else if isOp("(") {
            let args = try parseArguments()
            call = try Parser.makeCall(function, args)
        } else if function.arity == 0 {
            call = .function(function, [])
        } else if function.arity == 1 || function == .log {
            let arg = try parseImplicitArgument()
            call = function == .log ? .function(.log10, [arg]) : .function(function, [arg])
        } else {
            throw .syntax("\(function.internationalName) potrebuje oklepaje")
        }
        if let e = outerExponent {
            // sin⁻¹(x) means arcsin(x), like on calculators.
            if e.rationalValue == .minusOne, let inverse = function.inverseFunction, case .function(_, let args) = call {
                return .function(inverse, args)
            }
            call = .power(call, e)
        }
        return call
    }

    /// Builds a column vector from a tuple, or a matrix when every item is a row vector of the same length.
    static func vectorOrMatrix(_ items: [Expr]) throws(MathError) -> Expr {
        var rows: [[Expr]] = []
        for item in items {
            if case .matrix(let r, 1, let entries) = item, r > 1 { rows.append(entries) } else { rows.append([item]) }
        }
        let width = rows[0].count
        if width > 1 {
            guard rows.allSatisfy({ $0.count == width }) else { throw .syntax("vrstice matrike morajo biti enako dolge") }
            return .matrix(rows: rows.count, columns: width, entries: rows.flatMap { $0 })
        }
        return .matrix(rows: items.count, columns: 1, entries: items)
    }

    private mutating func parseSingleArgument() throws(MathError) -> Expr {
        let args = try parseArguments()
        guard args.count == 1 else { throw .syntax("pričakovan en argument") }
        return args[0]
    }

    static func makeCall(_ function: MathFunction, _ args: [Expr]) throws(MathError) -> Expr {
        switch function {
        case .log:
            if args.count == 1 { return .function(.log10, args) }
            if args.count == 2 { return .function(.log, args) }
        case .root:
            if args.count == 1 { return .function(.sqrt, args) }
            if args.count == 2 { return .function(.root, args) }
        case .min, .max, .gcd, .lcm:
            if args.count >= 2 { return .function(function, args) }
        case .normpdf, .invnorm:
            // normpdf(x) or normpdf(x; μ; σ), invNorm(p) or invNorm(p; μ; σ), as the evaluators accept them.
            if args.count == 1 || args.count == 3 { return .function(function, args) }
        case .round:
            if args.count == 1 { return .function(.round, args) }
        default:
            if args.count == function.arity { return .function(function, args) }
        }
        if args.isEmpty { throw .incomplete }
        throw .syntax("napačno število argumentov za \(function.internationalName)")
    }

    /// Argument without parentheses: `sin 2x` → sin(2x), stops before the next function.
    private mutating func parseImplicitArgument() throws(MathError) -> Expr {
        try descend()
        defer { nesting -= 1 }
        guard !isAtEnd else { throw .incomplete }
        if isOp("-") {
            advance()
            return .negation(try parseImplicitArgument())
        }
        var factors = [try parsePower()]
        while let token = current {
            var continues = false
            switch token {
            case .number, .structure: continues = true
            case .identifier(let n): continues = MathFunction.parserNames[n] == nil
            case .op(let s): continues = s == "π"
            default: continues = false
            }
            if !continues { break }
            factors.append(try parsePower())
        }
        return factors.count == 1 ? factors[0] : .product(factors)
    }

    /// `integral(f, x, a, b)`, `diff(f, x[, a])`, `sum(f, n, a, b)` for text formulas.
    private mutating func parseSpecialForm(_ name: String) throws(MathError) -> Expr? {
        try descend()
        defer { nesting -= 1 }
        guard ["integral", "diff", "derivative", "sum", "prod", "product", "piecewise"].contains(name), isOp("(") else { return nil }
        let args = try parseArguments()
        func variableName(_ e: Expr) throws(MathError) -> String {
            guard case .variable(let v) = e else { throw .syntax("pričakovana spremenljivka") }
            return v
        }
        switch name {
        case "integral":
            switch args.count {
            case 1: return .integral(args[0], variable: options.defaultVariable, lower: nil, upper: nil)
            case 2: return .integral(args[0], variable: try variableName(args[1]), lower: nil, upper: nil)
            case 4: return .integral(args[0], variable: try variableName(args[1]), lower: args[2], upper: args[3])
            default: throw .syntax("integral(f, x, a, b)")
            }
        case "diff", "derivative":
            switch args.count {
            case 1: return .derivative(args[0], variable: options.defaultVariable, at: nil)
            case 2: return .derivative(args[0], variable: try variableName(args[1]), at: nil)
            case 3: return .derivative(args[0], variable: try variableName(args[1]), at: args[2])
            default: throw .syntax("diff(f, x)")
            }
        case "prod", "product":
            guard args.count == 4 else { throw .syntax("prod(f, n, a, b)") }
            return .productSeries(args[0], variable: try variableName(args[1]), lower: args[2], upper: args[3])
        case "piecewise":
            guard args.count >= 2 else { throw .syntax("piecewise(vrednost, pogoj, …)") }
            return .piecewise(args)
        default:
            guard args.count == 4 else { throw .syntax("sum(f, n, a, b)") }
            return .summation(args[0], variable: try variableName(args[1]), lower: args[2], upper: args[3])
        }
    }

    /// Names of Greek letters accepted in text input (alpha → α).
    static let greekLetters: [String: String] = [
        "alpha": "α", "beta": "β", "gamma": "γ", "delta": "δ", "Delta": "Δ", "epsilon": "ε", "varepsilon": "ε",
        "zeta": "ζ", "eta": "η", "theta": "θ", "Theta": "Θ", "vartheta": "ϑ", "iota": "ι", "kappa": "κ",
        "lambda": "λ", "Lambda": "Λ", "mu": "μ", "nu": "ν", "xi": "ξ", "Xi": "Ξ", "rho": "ρ", "sigma": "σ",
        "tau": "τ", "upsilon": "υ", "phi": "φ", "varphi": "φ", "Phi": "Φ", "chi": "χ", "psi": "ψ", "Psi": "Ψ",
        "omega": "ω", "Omega": "Ω",
    ]
}
