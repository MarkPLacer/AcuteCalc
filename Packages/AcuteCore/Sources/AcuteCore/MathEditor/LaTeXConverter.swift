import Foundation

/// LaTeX export and import for editor rows (copy into notes, paste formulas from the web).
public enum LaTeXConverter {
    // MARK: Export

    public static func latex(_ row: MathRow, decimalComma: Bool = true) -> String {
        var out = ""
        let nodes = row.nodes
        var i = 0
        while i < nodes.count {
            let node = nodes[i]
            if case .symbol(.exponent10) = node {
                // 1,5ᴇ−3 → 1{,}5\cdot 10^{-3}
                var exponent = ""
                var j = i + 1
                while j < nodes.count {
                    if case .symbol(.digit(let d)) = nodes[j] { exponent += String(d) } else if case .symbol(.minus) = nodes[j], exponent.isEmpty { exponent += "-" } else { break }
                    j += 1
                }
                out += "\\cdot 10^{\(exponent)}"
                i = j
                continue
            }
            out += latex(node, decimalComma: decimalComma)
            i += 1
        }
        return out
    }

    static func group(_ row: MathRow, _ decimalComma: Bool) -> String { "{" + latex(row, decimalComma: decimalComma) + "}" }

    static func latex(_ node: MathNode, decimalComma: Bool) -> String {
        func g(_ row: MathRow) -> String { group(row, decimalComma) }
        func paren(_ row: MathRow) -> String { "\\left(" + latex(row, decimalComma: decimalComma) + "\\right)" }
        switch node {
        case .symbol(let s): return symbol(s, decimalComma: decimalComma)
        case .fraction(let n, let d): return "\\frac" + g(n) + g(d)
        case .power(let e): return "^" + g(e)
        case .subscriptRow(let s): return "_" + g(s)
        case .squareRoot(let r): return "\\sqrt" + g(r)
        case .nthRoot(let i, let r): return "\\sqrt[" + latex(i, decimalComma: decimalComma) + "]" + g(r)
        case .absoluteValue(let r): return "\\left|" + latex(r, decimalComma: decimalComma) + "\\right|"
        case .function(let f, let a): return functionName(f) + (f.arity == 0 ? "" : paren(a))
        case .logarithm(let b, let a): return "\\log_" + g(b) + paren(a)
        case .derivative(let b, let p):
            var s = "\\frac{d}{dx}" + paren(b)
            if let p { s += "\\bigg|_{x=" + latex(p, decimalComma: decimalComma) + "}" }
            return s
        case .integral(let l, let u, let b):
            if l.isEmpty && u.isEmpty { return "\\int " + latex(b, decimalComma: decimalComma) + "\\,dx" }
            return "\\int_" + g(l) + "^" + g(u) + " " + latex(b, decimalComma: decimalComma) + "\\,dx"
        case .summation(let l, let u, let b):
            return "\\sum_{n=" + latex(l, decimalComma: decimalComma) + "}^" + g(u) + " " + latex(b, decimalComma: decimalComma)
        case .bigProduct(let l, let u, let b):
            return "\\prod_{n=" + latex(l, decimalComma: decimalComma) + "}^" + g(u) + " " + latex(b, decimalComma: decimalComma)
        case .binomial(let n, let k): return "\\binom" + g(n) + g(k)
        case .function2(let f, let a, let b):
            return functionName(f) + "\\left(" + latex(a, decimalComma: decimalComma) + ";" + latex(b, decimalComma: decimalComma) + "\\right)"
        case .functionN(let f, let args):
            return functionName(f) + "\\left(" + args.map { latex($0, decimalComma: decimalComma) }.joined(separator: ";") + "\\right)"
        case .limit(let p, let b, let direction):
            let side = direction == .left ? "^{-}" : (direction == .right ? "^{+}" : "")
            return "\\lim_{x\\to " + latex(p, decimalComma: decimalComma) + side + "} " + latex(b, decimalComma: decimalComma)
        case .matrix(let rows, let columns, let cells):
            let body = (0..<rows).map { r in
                (0..<columns).map { c in latex(cells[r * columns + c], decimalComma: decimalComma) }.joined(separator: " & ")
            }.joined(separator: " \\\\ ")
            return "\\begin{bmatrix} " + body + " \\end{bmatrix}"
        case .piecewise(let cells):
            let rows = cells.count / 2
            let body = (0..<rows).map { r in
                let condition = cells[2 * r + 1]
                return latex(cells[2 * r], decimalComma: decimalComma) + " & " + (condition.isEmpty ? "\\text{sicer}" : latex(condition, decimalComma: decimalComma))
            }.joined(separator: " \\\\ ")
            return "\\begin{cases} " + body + " \\end{cases}"
        case .vectorArrow(let r): return "\\vec" + g(r)
        case .partialDerivative(let v, let b): return "\\frac{\\partial}{\\partial " + latex(v, decimalComma: decimalComma) + "}" + paren(b)
        case .poweredFunction(let f, let e, let a): return functionName(f) + "^" + g(e) + paren(a)
        }
    }

    static func symbol(_ s: MathSymbol, decimalComma: Bool) -> String {
        switch s {
        case .digit(let d): String(d)
        case .decimalPoint: decimalComma ? "{,}" : "."
        case .plus: "+"
        case .minus: "-"
        case .times: "\\cdot "
        case .divide: "\\div "
        case .equals: "="
        case .less: "<"
        case .greater: ">"
        case .lessOrEqual: "\\le "
        case .greaterOrEqual: "\\ge "
        case .notEqual: "\\ne "
        case .leftParenthesis: "("
        case .rightParenthesis: ")"
        case .comma: ";"
        case .variable(let name): variableName(name)
        case .constant(.pi): "\\pi "
        case .constant(.e): "e"
        case .constant(.i): "i"
        case .constant(.infinity): "\\infty "
        case .factorial: "!"
        case .percent: "\\%"
        case .exponent10: "\\cdot 10^"
        case .degreeMark: "^{\\circ}"
        case .minuteMark: "'"
        case .secondMark: "''"
        case .ans: "\\mathrm{Ans}"
        case .plusMinus: "\\pm "
        case .crossProduct: "\\times "
        case .transposeMark: "^{\\mathsf{T}}"
        case .angleSign: "\\angle "
        case .parallel: "\\parallel "
        }
    }

    static let greekCommands: [String: String] = {
        var map: [String: String] = [:]
        for (name, letter) in Parser.greekLetters where !name.hasPrefix("var") { map[letter] = "\\" + name + " " }
        return map
    }()

    static func variableName(_ name: String) -> String {
        if let underscore = name.firstIndex(of: "_") {
            let base = String(name[..<underscore])
            let sub = String(name[name.index(after: underscore)...])
            return variableName(base) + "_{" + sub + "}"
        }
        if let greek = greekCommands[name] { return greek }
        // n ∈ ℕ, n = 1, 2, … (as \in, \mathbb{N} and \dots read them)
        switch name {
        case "∈": return "\\in "
        case "…": return "\\dots "
        case "ℕ": return "\\mathbb{N}"
        default: break
        }
        return name.count == 1 ? name : "\\mathrm{" + name + "}"
    }

    static func functionName(_ f: MathFunction) -> String {
        switch f {
        case .sin, .cos, .tan, .cot, .sec, .csc, .sinh, .cosh, .tanh, .coth, .ln, .exp, .det, .gcd, .min, .max:
            return "\\" + f.rawValue
        case .asin: return "\\arcsin"
        case .acos: return "\\arccos"
        case .atan: return "\\arctan"
        case .log10: return "\\log"
        case .lcm: return "\\operatorname{lcm}"
        default: return "\\operatorname{" + f.internationalName + "}"
        }
    }

    // MARK: Import

    /// Parses a LaTeX formula into an editor row (a practical subset: fractions, roots,
    /// scripts, functions, Greek letters, ∫ Σ Π lim, matrices and cases).
    public static func row(fromLaTeX text: String) throws(MathError) -> MathRow {
        var parser = LaTeXParser(Array(text))
        let row = try parser.parseRow(until: nil)
        return row
    }
}

/// Recursive-descent reader for LaTeX math.
struct LaTeXParser {
    let chars: [Character]
    var i = 0
    /// Reader calls on the current path: every recursion passes parseItem, parseArgument, parseCommand
    /// or parseFunctionArgument.
    var nesting = 0

    /// Deepest nesting accepted (.tooComplex beyond). Pasted text has no length limit, and the reader,
    /// the editor and the conversion to expressions recurse once per level. 36 calls are 12 nested
    /// \frac or \sqrt (three calls each), 12 nested function arguments or 36 braces, above real formulas;
    /// unoptimised, estimated from the code at up to ~15 KB per structure (parseCommand is large), that
    /// stays under half of a 512 KB worker stack.
    static let maximumNesting = 36

    init(_ chars: [Character]) { self.chars = chars }

    /// One reader call deeper (undone with `defer { nesting -= 1 }`).
    mutating func descend() throws(MathError) {
        guard nesting < LaTeXParser.maximumNesting else { throw .tooComplex }
        nesting += 1
    }

    var atEnd: Bool { i >= chars.count }
    var current: Character? { i < chars.count ? chars[i] : nil }

    mutating func skipSpaces() {
        while let c = current, c.isWhitespace { i += 1 }
    }

    /// Reads `\name` (letters) or a single-symbol command (`\,`, `\{`, `\\`).
    mutating func readCommand() -> String {
        // at "\"
        i += 1
        guard let c = current else { return "" }
        if c.isLetter {
            var name = ""
            while let d = current, d.isLetter { name.append(d); i += 1 }
            return name
        }
        i += 1
        return String(c)
    }

    /// `{…}` or a single token as a row.
    mutating func parseArgument() throws(MathError) -> MathRow {
        try descend()
        defer { nesting -= 1 }
        skipSpaces()
        guard let c = current else { throw .incomplete }
        if c == "{" {
            i += 1
            let row = try parseRow(until: "}")
            return row
        }
        // Single token: one character or one command with its own arguments (\frac{x}{2}, \varphi).
        if c == "\\" {
            var nodes: [MathNode] = []
            try parseCommand(into: &nodes)
            return MathRow(nodes)
        }
        i += 1
        return try LaTeXParser.single(c)
    }

    static func single(_ c: Character) throws(MathError) -> MathRow {
        var p = LaTeXParser([c])
        return try p.parseRow(until: nil)
    }

    /// Text up to the matching `]` (optional arguments).
    mutating func parseOptional() throws(MathError) -> MathRow? {
        skipSpaces()
        guard current == "[" else { return nil }
        i += 1
        return try parseRow(until: "]")
    }

    mutating func parseRow(until terminator: Character?, stopAtCell: Bool = false) throws(MathError) -> MathRow {
        var nodes: [MathNode] = []
        while let c = current {
            if let terminator, c == terminator {
                i += 1
                return MathRow(nodes)
            }
            if stopAtCell, c == "&" { return MathRow(nodes) }
            if stopAtCell, c == "\\", i + 1 < chars.count, chars[i + 1] == "\\" { return MathRow(nodes) }
            if stopAtCell, c == "\\", isAt("\\end") { return MathRow(nodes) }
            if c == "}" {
                if terminator == nil { i += 1; continue }
                throw .syntax("odvečen »}« v LaTeX-u")
            }
            try parseItem(into: &nodes)
        }
        if terminator != nil && terminator != "}" { throw .syntax("manjka »\(terminator!)« v LaTeX-u") }
        return MathRow(nodes)
    }

    func isAt(_ literal: String) -> Bool {
        let lit = Array(literal)
        guard i + lit.count <= chars.count else { return false }
        return Array(chars[i..<(i + lit.count)]) == lit
    }

    mutating func parseItem(into nodes: inout [MathNode]) throws(MathError) {
        try descend()
        defer { nesting -= 1 }
        guard let c = current else { return }
        if c.isWhitespace { i += 1; return }
        if c.isNumber && c.isASCII {
            nodes.append(.symbol(.digit(c.wholeNumberValue ?? 0)))
            i += 1
            return
        }
        switch c {
        case "{":
            if isAt("{,}") {
                // {,} is the decimal comma as the export writes it (2{,}5, {,}5), wherever it stands.
                nodes.append(.symbol(.decimalPoint))
                i += 3
            } else {
                i += 1
                nodes.append(contentsOf: try parseRow(until: "}").nodes)
            }
        case "^":
            i += 1
            let e = try parseArgument()
            if e.nodes == [.symbol(.variable("∘"))] || e.nodes == [.symbol(.degreeMark)] {
                nodes.append(.symbol(.degreeMark))
            } else {
                nodes.append(.power(exponent: e))
            }
        case "_":
            i += 1
            nodes.append(.subscriptRow(try parseArgument()))
        case "\\":
            try parseCommand(into: &nodes)
        case ".":
            nodes.append(.symbol(.decimalPoint))
            i += 1
        case ",":
            // 1,5 is a decimal comma between digits; otherwise a separator.
            if let last = nodes.last, case .symbol(.digit) = last, i + 1 < chars.count, chars[i + 1].isNumber {
                nodes.append(.symbol(.decimalPoint))
            } else {
                nodes.append(.symbol(.comma))
            }
            i += 1
        case "+": nodes.append(.symbol(.plus)); i += 1
        case "-", "−": nodes.append(.symbol(.minus)); i += 1
        case "*": nodes.append(.symbol(.times)); i += 1
        case "/": nodes.append(.symbol(.divide)); i += 1
        case "=": nodes.append(.symbol(.equals)); i += 1
        case "<": nodes.append(.symbol(.less)); i += 1
        case ">": nodes.append(.symbol(.greater)); i += 1
        case "(", "[": nodes.append(.symbol(.leftParenthesis)); i += 1
        case ")", "]": nodes.append(.symbol(.rightParenthesis)); i += 1
        case ";": nodes.append(.symbol(.comma)); i += 1
        case "!": nodes.append(.symbol(.factorial)); i += 1
        case "'":
            // 2'' (seconds, as exported) is one second mark, not two minute marks.
            if i + 1 < chars.count, chars[i + 1] == "'" {
                nodes.append(.symbol(.secondMark)); i += 2
            } else {
                nodes.append(.symbol(.minuteMark)); i += 1
            }
        case "″": nodes.append(.symbol(.secondMark)); i += 1
        case "|":
            i += 1
            let inner = try parseRow(until: "|")
            nodes.append(.absoluteValue(inner))
        case "e": nodes.append(.symbol(.constant(.e))); i += 1
        case "i": nodes.append(.symbol(.constant(.i))); i += 1
        case "π": nodes.append(.symbol(.constant(.pi))); i += 1
        case "&":
            i += 1
        default:
            if c.isLetter {
                nodes.append(.symbol(.variable(String(c))))
            }
            i += 1
        }
    }

    mutating func parseCommand(into nodes: inout [MathNode]) throws(MathError) {
        try descend()
        defer { nesting -= 1 }
        let name = readCommand()
        switch name {
        case ",", ";", "!", ":", " ", "quad", "qquad", "displaystyle", "textstyle", "left", "right", "big", "Big", "bigg", "Bigg", "bigl", "bigr":
            if ["left", "right", "big", "Big", "bigg", "Bigg", "bigl", "bigr"].contains(name) {
                // \left( … \right): the delimiter follows.
                skipSpaces()
                if current == "." { i += 1; return }
                if current == "|" {
                    if name == "left" {
                        i += 1
                        var inner: [MathNode] = []
                        while !atEnd && !isAt("\\right|") { try parseItem(into: &inner) }
                        if isAt("\\right|") { i += 7 }
                        nodes.append(.absoluteValue(MathRow(inner)))
                    } else {
                        i += 1
                    }
                    return
                }
                if current == "\\" {
                    // \left\{ etc.
                    let inner = readCommand()
                    if inner == "{" { nodes.append(.symbol(.leftParenthesis)) }
                    if inner == "}" { nodes.append(.symbol(.rightParenthesis)) }
                }
            }
        case "\\":
            break
        case "frac", "dfrac", "tfrac":
            let n = try parseArgument()
            let d = try parseArgument()
            if n.nodes == [.symbol(.variable("d"))], d.nodes.count == 2, case .symbol(.variable("d")) = d.nodes[0] {
                // d/dx (body)
                let body = try parseDerivativeBody()
                nodes.append(.derivative(body: body, point: nil))
            } else if n.nodes == [.symbol(.variable("∂"))] || LaTeXParser.isPartial(n) {
                let variable = MathRow(Array(d.nodes.dropFirst()))
                nodes.append(.partialDerivative(variable: variable, body: try parseDerivativeBody()))
            } else {
                nodes.append(.fraction(numerator: n, denominator: d))
            }
        case "sqrt":
            if let index = try parseOptional() {
                nodes.append(.nthRoot(index: index, radicand: try parseArgument()))
            } else {
                nodes.append(.squareRoot(try parseArgument()))
            }
        case "binom", "dbinom", "tbinom":
            let n = try parseArgument()
            nodes.append(.binomial(n, try parseArgument()))
        case "vec", "overrightarrow", "mathbf", "boldsymbol", "bm":
            nodes.append(.vectorArrow(try parseArgument()))
        case "mathrm", "text", "mathit", "operatorname", "textrm", "mathsf":
            if name == "operatorname", let f = readOperatorFunction() {
                try appendFunction(f, into: &nodes)
                return
            }
            let content = MathRowConverter.plainText(try parseArgument())
            if name == "operatorname", let f = MathFunction.parserNames[content] {
                try appendFunction(f, into: &nodes)
            } else if content == "Ans" {
                nodes.append(.symbol(.ans))
            } else if content == "e" {
                nodes.append(.symbol(.constant(.e)))
            } else if content == "T", name == "mathsf" {
                nodes.append(.symbol(.transposeMark))
            } else if !["sicer", "otherwise", "else", "drugače"].contains(content) {
                nodes.append(contentsOf: content.map { .symbol(.variable(String($0))) })
            }
        case "cdot", "ast": nodes.append(.symbol(.times))
        case "times": nodes.append(.symbol(.times))
        case "div": nodes.append(.symbol(.divide))
        case "angle", "measuredangle": nodes.append(.symbol(.angleSign))
        case "parallel": nodes.append(.symbol(.parallel))
        case "pm": nodes.append(.symbol(.plusMinus))
        case "le", "leq", "leqslant": nodes.append(.symbol(.lessOrEqual))
        case "ge", "geq", "geqslant": nodes.append(.symbol(.greaterOrEqual))
        case "ne", "neq": nodes.append(.symbol(.notEqual))
        case "lt": nodes.append(.symbol(.less))
        case "gt": nodes.append(.symbol(.greater))
        case "pi": nodes.append(.symbol(.constant(.pi)))
        case "infty": nodes.append(.symbol(.constant(.infinity)))
        case "circ": nodes.append(.symbol(.degreeMark))
        case "%": nodes.append(.symbol(.percent))
        case "{": nodes.append(.symbol(.leftParenthesis))
        case "}": nodes.append(.symbol(.rightParenthesis))
        case "partial": nodes.append(.symbol(.variable("∂")))
        case "int", "intop":
            try parseBigOperator(into: &nodes) { lower, upper, body in .integral(lower: lower, upper: upper, body: body) }
        case "sum":
            try parseBigOperator(into: &nodes) { lower, upper, body in .summation(lower: lower, upper: upper, body: body) }
        case "prod":
            try parseBigOperator(into: &nodes) { lower, upper, body in .bigProduct(lower: lower, upper: upper, body: body) }
        case "lim":
            skipSpaces()
            var point = MathRow()
            var direction = LimitDirection.both
            if current == "_" {
                i += 1
                let sub = try parseArgument()
                // x \to a, optionally a^{+}
                var subNodes = sub.nodes
                if let arrow = subNodes.firstIndex(of: .symbol(.variable("→"))) { subNodes = Array(subNodes[(arrow + 1)...]) }
                if case .power(let e)? = subNodes.last {
                    if e.nodes == [.symbol(.plus)] { direction = .right }
                    if e.nodes == [.symbol(.minus)] { direction = .left }
                    subNodes.removeLast()
                }
                point = MathRow(subNodes)
            }
            let body = try parseRow(until: nil, stopAtCell: true)
            nodes.append(.limit(point: point, body: body, direction: direction))
        case "to", "rightarrow":
            nodes.append(.symbol(.variable("→")))
        case "bar", "overline":
            // x̄, z̄: a combining macron on a single letter.
            let content = try parseArgument()
            if content.nodes.count == 1, case .symbol(.variable(let name)) = content.nodes[0] {
                nodes.append(.symbol(.variable(name + "\u{0304}")))
            } else {
                nodes.append(contentsOf: content.nodes)
            }
        case "mathbb":
            let content = MathRowConverter.plainText(try parseArgument())
            let map: [String: String] = ["R": "ℝ", "N": "ℕ", "Z": "ℤ", "Q": "ℚ", "C": "ℂ"]
            nodes.append(.symbol(.variable(map[content] ?? content)))
        case "mp": nodes.append(.symbol(.variable("∓")))
        case "mid", "vert": nodes.append(.symbol(.variable("∣")))
        case "dots", "ldots": nodes.append(.symbol(.variable("…")))
        case "cdots": nodes.append(.symbol(.variable("⋯")))
        case "approx": nodes.append(.symbol(.variable("≈")))
        case "sim": nodes.append(.symbol(.variable("∼")))
        case "propto": nodes.append(.symbol(.variable("∝")))
        case "cup": nodes.append(.symbol(.variable("∪")))
        case "cap": nodes.append(.symbol(.variable("∩")))
        case "in": nodes.append(.symbol(.variable("∈")))
        case "notin": nodes.append(.symbol(.variable("∉")))
        case "subset": nodes.append(.symbol(.variable("⊂")))
        case "Rightarrow", "implies": nodes.append(.symbol(.variable("⇒")))
        case "Leftrightarrow", "iff": nodes.append(.symbol(.variable("⇔")))
        case "perp": nodes.append(.symbol(.variable("⊥")))
        case "sphericalangle": nodes.append(.symbol(.variable("∢")))
        case "triangle": nodes.append(.symbol(.variable("△")))
        case "hbar": nodes.append(.symbol(.variable("ħ")))
        case "ell": nodes.append(.symbol(.variable("ℓ")))
        case "log":
            skipSpaces()
            if current == "_" {
                i += 1
                let base = try parseArgument()
                nodes.append(.logarithm(base: base, argument: try parseFunctionArgument()))
            } else {
                try appendFunction(.log10, into: &nodes)
            }
        case "begin":
            let environment = MathRowConverter.plainText(try parseArgument())
            try parseEnvironment(environment, into: &nodes)
        case "end":
            _ = try parseArgument()
        default:
            if let greek = Parser.greekLetters[name] {
                nodes.append(.symbol(.variable(greek)))
            } else if let f = LaTeXParser.functions[name] {
                try appendFunction(f, into: &nodes)
            } else {
                throw .syntax("neznan LaTeX ukaz \\\(name)")
            }
        }
    }

    static let functions: [String: MathFunction] = [
        "sin": .sin, "cos": .cos, "tan": .tan, "tg": .tan, "cot": .cot, "ctg": .cot, "sec": .sec, "csc": .csc,
        "arcsin": .asin, "arccos": .acos, "arctan": .atan, "sinh": .sinh, "cosh": .cosh, "tanh": .tanh, "coth": .coth,
        "ln": .ln, "exp": .exp, "det": .det, "gcd": .gcd, "min": .min, "max": .max, "arg": .arg,
    ]

    /// `\operatorname{…}` names written by the export (international names) that the text
    /// parser does not know: C, V, log₂, R.Int, int÷, Rand, …
    static let exportedFunctionNames: [String: MathFunction] = {
        var map: [String: MathFunction] = [:]
        for f in MathFunction.allCases where map[f.internationalName] == nil { map[f.internationalName] = f }
        return map
    }()

    /// The function named in `\operatorname{…}`, read verbatim (₂, ÷ and · would not survive
    /// parsing the name as a row); nil leaves the position for the general reading.
    mutating func readOperatorFunction() -> MathFunction? {
        skipSpaces()
        guard current == "{", let close = chars[i...].firstIndex(of: "}") else { return nil }
        let name = String(chars[(i + 1)..<close]).trimmingCharacters(in: .whitespaces)
        guard let f = MathFunction.parserNames[name] ?? LaTeXParser.exportedFunctionNames[name] else { return nil }
        i = close + 1
        return f
    }

    static func isPartial(_ row: MathRow) -> Bool {
        row.nodes == [.symbol(.variable("∂"))]
    }

    mutating func appendFunction(_ f: MathFunction, into nodes: inout [MathNode]) throws(MathError) {
        // Rand, Dice, Coin take no argument (the export writes no parentheses).
        if f.arity == 0 {
            nodes.append(.function(f, argument: MathRow()))
            return
        }
        skipSpaces()
        var exponent: MathRow?
        if current == "^" {
            i += 1
            exponent = try parseArgument()
        }
        let argument = try parseFunctionArgument()
        if let exponent {
            nodes.append(.poweredFunction(f, exponent: exponent, argument: argument))
        } else if f.arity == 2 {
            // gcd(a; b): split at the separator, keeping an empty slot in place (C(; 2) is C(□; 2))
            let parts = argument.nodes.split(separator: .symbol(.comma), maxSplits: 1, omittingEmptySubsequences: false).map { MathRow(Array($0)) }
            nodes.append(.function2(f, parts.first ?? MathRow(), parts.count > 1 ? parts[1] : MathRow()))
        } else if f.arity >= 3 || f.arity < 0 {
            // binompdf(n; p; k), normpdf(x; μ; σ): one slot per argument, as the editor and the text parser build them.
            var parts = argument.nodes.split(separator: .symbol(.comma), omittingEmptySubsequences: false).map { MathRow(Array($0)) }
            while parts.count < f.arity { parts.append(MathRow()) }
            switch parts.count {
            case 1: nodes.append(.function(f, argument: argument))
            case 2: nodes.append(.function2(f, parts[0], parts[1]))
            default: nodes.append(.functionN(f, parts))
            }
        } else {
            nodes.append(.function(f, argument: argument))
        }
    }

    /// `(…)`, `\left(…\right)`, `{…}` or the next single token.
    mutating func parseFunctionArgument() throws(MathError) -> MathRow {
        try descend()
        defer { nesting -= 1 }
        skipSpaces()
        if current == "(" {
            i += 1
            return try parseRow(until: ")")
        }
        if current == "|" {
            i += 1
            return MathRow([.absoluteValue(try parseRow(until: "|"))])
        }
        if isAt("\\left|") {
            i += 6
            var inner: [MathNode] = []
            while !atEnd && !isAt("\\right|") { try parseItem(into: &inner) }
            if isAt("\\right|") { i += 7 }
            return MathRow([.absoluteValue(MathRow(inner))])
        }
        if isAt("\\left(") {
            i += 6
            var inner: [MathNode] = []
            while !atEnd && !isAt("\\right)") { try parseItem(into: &inner) }
            if isAt("\\right)") { i += 7 }
            return MathRow(inner)
        }
        return try parseArgument()
    }

    mutating func parseDerivativeBody() throws(MathError) -> MathRow {
        try parseFunctionArgument()
    }

    mutating func parseBigOperator(into nodes: inout [MathNode], make: (MathRow, MathRow, MathRow) -> MathNode) throws(MathError) {
        var lower = MathRow(), upper = MathRow()
        for _ in 0..<2 {
            skipSpaces()
            if current == "_" { i += 1; lower = try parseArgument() } else if current == "^" { i += 1; upper = try parseArgument() }
        }
        // Σ_{n=1}: drop the "n=" written in the lower bound.
        if lower.nodes.count >= 2, case .symbol(.variable) = lower.nodes[0], case .symbol(.equals) = lower.nodes[1] {
            lower = MathRow(Array(lower.nodes.dropFirst(2)))
        }
        var body: [MathNode] = []
        while let c = current {
            if c == "}" || c == "&" || isAt("\\\\") || isAt("\\end") { break }
            // ∫ … dx ends the integrand.
            if isAt("dx") || isAt("\\,dx") || isAt("\\, dx") || isAt("\\;dx") {
                if isAt("\\") { _ = readCommand() }
                skipSpaces()
                i += 2
                break
            }
            try parseItem(into: &body)
        }
        nodes.append(make(lower, upper, MathRow(body)))
    }

    mutating func parseEnvironment(_ environment: String, into nodes: inout [MathNode]) throws(MathError) {
        var rows: [[MathRow]] = []
        var row: [MathRow] = []
        while !atEnd {
            skipSpaces()
            if isAt("\\end") {
                _ = readCommand()
                _ = try parseArgument()
                break
            }
            let cell = try parseRow(until: nil, stopAtCell: true)
            row.append(cell)
            if current == "&" {
                i += 1
            } else if isAt("\\\\") {
                i += 2
                rows.append(row)
                row = []
            }
        }
        if !row.isEmpty && !(row.count == 1 && row[0].isEmpty) { rows.append(row) }
        guard !rows.isEmpty else { throw .incomplete }
        switch environment {
        case "cases", "dcases":
            var cells: [MathRow] = []
            for r in rows {
                cells.append(r.first ?? MathRow())
                cells.append(r.count > 1 ? r[1] : MathRow())
            }
            nodes.append(.piecewise(cells: cells))
        default:
            let columns = rows.map(\.count).max() ?? 1
            var cells: [MathRow] = []
            for r in rows {
                cells.append(contentsOf: r)
                cells.append(contentsOf: Array(repeating: MathRow(), count: columns - r.count))
            }
            let matrix = MathNode.matrix(rows: rows.count, columns: columns, cells: cells)
            // |A| for vmatrix (determinant notation)
            nodes.append(environment == "vmatrix" ? .absoluteValue(MathRow([matrix])) : matrix)
        }
    }
}
