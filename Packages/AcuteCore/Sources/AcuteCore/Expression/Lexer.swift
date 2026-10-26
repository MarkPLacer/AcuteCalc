import Foundation

/// Tokens shared by the text parser and the structured math editor.
public enum Token: Hashable, Sendable {
    case number(String)
    case identifier(String)
    case op(String)
    /// A complete sub-expression produced by a structured editor node (fraction, root, …).
    case structure(Expr)
    /// An exponent attached to the preceding operand (editor power node, `²`).
    case superscript(Expr)
    /// A subscript attached to the preceding identifier (`x₁`).
    case sub(String)

    public var opValue: String? {
        if case .op(let s) = self { return s }
        return nil
    }
}

/// Converts text such as `2x² − sin(πx)/3 ≤ |y|` into tokens.
public struct Lexer {
    public init() {}

    static let superscriptDigits: [Character: Character] = [
        "⁰": "0", "¹": "1", "²": "2", "³": "3", "⁴": "4", "⁵": "5", "⁶": "6", "⁷": "7", "⁸": "8", "⁹": "9", "⁻": "-",
    ]
    static let subscriptDigits: [Character: Character] = [
        "₀": "0", "₁": "1", "₂": "2", "₃": "3", "₄": "4", "₅": "5", "₆": "6", "₇": "7", "₈": "8", "₉": "9",
    ]

    static func isIdentifierStart(_ c: Character) -> Bool {
        if c == "π" || c == "∞" || c == "ᵀ" { return false }
        return c.isLetter
    }

    public func tokenize(_ text: String) throws(MathError) -> [Token] {
        var tokens: [Token] = []
        let chars = Array(text)
        var i = 0
        func peek(_ offset: Int = 0) -> Character? {
            let j = i + offset
            return j < chars.count ? chars[j] : nil
        }
        while i < chars.count {
            let c = chars[i]
            if c.isWhitespace { i += 1; continue }

            // Numbers: 12, 3.5, .5, 1.2E-3. A comma always separates arguments in text input;
            // the decimal comma is a display setting handled by the structured editor.
            if c.isASCII && (c.isNumber || (c == "." && (peek(1)?.isNumber ?? false))) {
                var s = ""
                var seenDot = false
                while let d = peek(), d.isASCII, d.isNumber || (d == "." && !seenDot && (peek(1)?.isNumber ?? false)) {
                    if d == "." { seenDot = true }
                    s.append(d)
                    i += 1
                }
                // Scientific exponent: E followed by optional sign and digits
                if let e = peek(), e == "E" || e == "ᴇ",
                   let n = peek(1), n.isNumber || ((n == "-" || n == "+" || n == "−") && (peek(2)?.isNumber ?? false)) {
                    s.append("E")
                    i += 1
                    if let sign = peek(), sign == "-" || sign == "−" { s.append("-"); i += 1 } else if peek() == "+" { i += 1 }
                    while let d = peek(), d.isASCII, d.isNumber { s.append(d); i += 1 }
                }
                tokens.append(.number(s))
                continue
            }

            if let digit = Lexer.superscriptDigits[c] {
                var s = String(digit)
                i += 1
                while let d = peek(), let mapped = Lexer.superscriptDigits[d] { s.append(mapped); i += 1 }
                let value: Expr = s.hasPrefix("-") ? .negation(.number(Rational(Int(s.dropFirst()) ?? 0))) : .number(Rational(Int(s) ?? 0))
                tokens.append(.superscript(value))
                continue
            }

            if Lexer.isIdentifierStart(c) {
                var s = String(c)
                i += 1
                while let d = peek(), d.isLetter, d != "π", d != "ᵀ" {
                    s.append(d)
                    i += 1
                }
                // Function names with digits inside: chi2cdf, invChi2.
                if let d = peek(), d.isASCII, d.isNumber, s != "log" {
                    var j = i, word = s
                    while j < chars.count, chars[j].isASCII, chars[j].isNumber { word.append(chars[j]); j += 1 }
                    var k = j, longer = word
                    while k < chars.count, chars[k].isLetter, chars[k] != "π", chars[k] != "ᵀ" { longer.append(chars[k]); k += 1 }
                    if k > j, MathFunction.parserNames[longer] != nil {
                        s = longer
                        i = k
                    } else if MathFunction.parserNames[word] != nil {
                        s = word
                        i = j
                    }
                }
                // Digits directly after short names form a subscript (v0, x1); `log2` is log base 2.
                if let d = peek(), d.isASCII, d.isNumber,
                   (s.count <= 2 && MathFunction.parserNames[s] == nil) || s == "log" {
                    var sub = ""
                    while let d2 = peek(), d2.isASCII, d2.isNumber { sub.append(d2); i += 1 }
                    tokens.append(.identifier(s))
                    tokens.append(.sub(sub))
                    continue
                }
                tokens.append(.identifier(s))
                // Explicit subscripts: x_1, x_{max}, v₀
                if peek() == "_" {
                    i += 1
                    var sub = ""
                    if peek() == "{" {
                        i += 1
                        while let d = peek(), d != "}" { sub.append(d); i += 1 }
                        i += 1
                    } else {
                        while let d = peek(), d.isLetter || d.isNumber { sub.append(d); i += 1 }
                    }
                    tokens.append(.sub(sub))
                } else if let d = peek(), Lexer.subscriptDigits[d] != nil {
                    var sub = ""
                    while let d2 = peek(), let mapped = Lexer.subscriptDigits[d2] { sub.append(mapped); i += 1 }
                    tokens.append(.sub(sub))
                }
                continue
            }

            // Multi-character operators
            let two = String(chars[i..<min(i + 2, chars.count)])
            switch two {
            case "<=": tokens.append(.op("≤")); i += 2; continue
            case ">=": tokens.append(.op("≥")); i += 2; continue
            case "!=", "<>": tokens.append(.op("≠")); i += 2; continue
            case "+-": tokens.append(.op("±")); i += 2; continue
            case "**": tokens.append(.op("^")); i += 2; continue
            default: break
            }

            switch c {
            case "+", "^", "(", ")", "[", "]", "{", "}", ",", ";", "|", "!", "%", "=", "<", ">", "≤", "≥", "≠", "±", "√", "∛", "°", "'", "\"", "′", "″", "∞", "π", "ᵀ", "⨯", "∧", "∠", "∥":
                tokens.append(.op(normalizedOperator(c)))
            case "-", "−", "–":
                tokens.append(.op("-"))
            case "*", "×", "·", "∙", "⋅":
                tokens.append(.op("*"))
            case "/", "÷", "∕":
                tokens.append(.op("/"))
            default:
                throw MathError.syntax("Neznan znak »\(c)«")
            }
            i += 1
        }
        return tokens
    }

    private func normalizedOperator(_ c: Character) -> String {
        switch c {
        case "[", "{": "("
        case "]", "}": ")"
        case ";": ","
        case "′": "'"
        case "″": "\""
        default: String(c)
        }
    }
}
