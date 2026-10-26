import Foundation

/// Number systems of the Sharp N-BASE mode.
public enum NumberBase: Int, CaseIterable, Identifiable, Sendable, Codable {
    case binary = 2, pental = 5, octal = 8, decimal = 10, hexadecimal = 16

    public var id: Int { rawValue }

    public var title: String {
        switch self {
        case .binary: "BIN"
        case .pental: "PEN"
        case .octal: "OCT"
        case .decimal: "DEC"
        case .hexadecimal: "HEX"
        }
    }

    /// Characters allowed in this base.
    public var digitCharacters: [Character] {
        Array("0123456789ABCDEF".prefix(rawValue))
    }
}

/// Bitwise operations of the N-BASE mode.
public enum LogicOperation: String, CaseIterable, Identifiable, Sendable {
    case and = "AND", or = "OR", xor = "XOR", xnor = "XNOR", not = "NOT", neg = "NEG"
    public var id: String { rawValue }
    public var isUnary: Bool { self == .not || self == .neg }
}

/// Integer arithmetic in BIN/PEN/OCT/DEC/HEX with two's complement for a chosen word size.
public enum BaseConversion {
    public static let wordSizes = [8, 16, 32, 64]

    /// Wraps to the word size as a signed (two's complement) value.
    public static func wrap(_ value: Int64, bits: Int) -> Int64 {
        guard bits < 64 else { return value }
        let mask = (Int64(1) << Int64(bits)) - 1
        let masked = value & mask
        let signBit = Int64(1) << Int64(bits - 1)
        return masked & signBit != 0 ? masked - (Int64(1) << Int64(bits)) : masked
    }

    /// BIN, OCT and HEX show the two's complement bit pattern; DEC and PEN are signed.
    public static func format(_ value: Int64, base: NumberBase, bits: Int) -> String {
        let v = wrap(value, bits: bits)
        switch base {
        case .decimal:
            return String(v)
        case .pental:
            return (v < 0 ? "−" : "") + String(v.magnitude, radix: 5)
        case .binary, .octal, .hexadecimal:
            let pattern: UInt64 = bits >= 64 ? UInt64(bitPattern: v) : UInt64(bitPattern: v) & ((UInt64(1) << UInt64(bits)) - 1)
            return String(pattern, radix: base.rawValue, uppercase: true)
        }
    }

    /// Groups binary digits by four (1010 1100) for readability.
    public static func grouped(_ text: String, base: NumberBase) -> String {
        guard base == .binary || base == .hexadecimal, text.count > 4 else { return text }
        var out = ""
        for (i, c) in text.reversed().enumerated() {
            if i > 0 && i % 4 == 0 { out.append(" ") }
            out.append(c)
        }
        return String(out.reversed())
    }

    /// Parses digits of `base`; BIN/OCT/HEX patterns with the top bit set are negative (two's complement).
    public static func parse(_ text: String, base: NumberBase, bits: Int) throws(MathError) -> Int64 {
        var s = text.replacingOccurrences(of: " ", with: "").uppercased()
        var negative = false
        if s.hasPrefix("-") || s.hasPrefix("−") {
            negative = true
            s.removeFirst()
        }
        guard !s.isEmpty else { throw .incomplete }
        guard s.allSatisfy({ base.digitCharacters.contains($0) }) else { throw .syntax("neveljavna števka za \(base.title)") }
        guard let magnitude = UInt64(s, radix: base.rawValue) else { throw .overflow }
        if bits < 64, magnitude >> UInt64(bits) != 0 { throw .overflow }
        let value: Int64
        switch base {
        case .decimal, .pental:
            guard magnitude <= UInt64(Int64.max) else { throw .overflow }
            value = Int64(magnitude)
        default:
            value = Int64(bitPattern: magnitude)
        }
        return wrap(negative ? 0 &- value : value, bits: bits)
    }

    public static func apply(_ operation: LogicOperation, _ a: Int64, _ b: Int64 = 0, bits: Int) -> Int64 {
        let result: Int64 = switch operation {
        case .and: a & b
        case .or: a | b
        case .xor: a ^ b
        case .xnor: ~(a ^ b)
        case .not: ~a
        case .neg: 0 &- a
        }
        return wrap(result, bits: bits)
    }

    // MARK: Expressions

    /// Evaluates integer expressions such as `1010 AND 1100 + 1` in the given base
    /// (precedence: NOT/NEG, × ÷, + −, AND, OR XOR XNOR; division truncates).
    public static func evaluate(_ text: String, base: NumberBase, bits: Int) throws(MathError) -> Int64 {
        var parser = NBaseParser(tokens: try tokenize(text, base: base), bits: bits, base: base)
        let value = try parser.parseOr()
        guard parser.isAtEnd else { throw .syntax("nepričakovan znak") }
        return wrap(value, bits: bits)
    }

    enum Token: Equatable {
        case number(String)
        case op(String)
    }

    static func tokenize(_ text: String, base: NumberBase) throws(MathError) -> [Token] {
        var tokens: [Token] = []
        let chars = Array(text.uppercased())
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if c.isWhitespace { i += 1; continue }
            // Keywords first (AND, OR, XOR, XNOR, NOT, NEG) — "A"–"F" are digits in HEX.
            var matched = false
            for word in ["XNOR", "XOR", "AND", "NOT", "NEG", "OR"] where i + word.count <= chars.count && String(chars[i..<(i + word.count)]) == word {
                tokens.append(.op(word))
                i += word.count
                matched = true
                break
            }
            if matched { continue }
            if base.digitCharacters.contains(c) {
                var number = ""
                while i < chars.count, base.digitCharacters.contains(chars[i]) {
                    number.append(chars[i])
                    i += 1
                }
                tokens.append(.number(number))
                continue
            }
            switch c {
            case "+", "(", ")": tokens.append(.op(String(c)))
            case "-", "−": tokens.append(.op("-"))
            case "*", "×", "·": tokens.append(.op("*"))
            case "/", "÷", ":": tokens.append(.op("/"))
            default: throw .syntax("neveljaven znak »\(c)« za \(base.title)")
            }
            i += 1
        }
        return tokens
    }

    struct NBaseParser {
        var tokens: [Token]
        var position = 0
        let bits: Int
        let base: NumberBase

        init(tokens: [Token], bits: Int, base: NumberBase) {
            self.tokens = tokens
            self.bits = bits
            self.base = base
        }

        var isAtEnd: Bool { position >= tokens.count }

        mutating func consume(_ op: String) -> Bool {
            guard position < tokens.count, tokens[position] == .op(op) else { return false }
            position += 1
            return true
        }

        mutating func parseOr() throws(MathError) -> Int64 {
            var value = try parseAnd()
            while true {
                if consume("OR") { value = BaseConversion.apply(.or, value, try parseAnd(), bits: bits) }
                else if consume("XOR") { value = BaseConversion.apply(.xor, value, try parseAnd(), bits: bits) }
                else if consume("XNOR") { value = BaseConversion.apply(.xnor, value, try parseAnd(), bits: bits) }
                else { return value }
            }
        }

        mutating func parseAnd() throws(MathError) -> Int64 {
            var value = try parseSum()
            while consume("AND") { value = BaseConversion.apply(.and, value, try parseSum(), bits: bits) }
            return value
        }

        mutating func parseSum() throws(MathError) -> Int64 {
            var value = try parseProduct()
            while true {
                if consume("+") { value = BaseConversion.wrap(value &+ (try parseProduct()), bits: bits) }
                else if consume("-") { value = BaseConversion.wrap(value &- (try parseProduct()), bits: bits) }
                else { return value }
            }
        }

        mutating func parseProduct() throws(MathError) -> Int64 {
            var value = try parseUnary()
            while true {
                if consume("*") { value = BaseConversion.wrap(value &* (try parseUnary()), bits: bits) }
                else if consume("/") {
                    let divisor = try parseUnary()
                    guard divisor != 0 else { throw .divisionByZero }
                    value = BaseConversion.wrap(value.dividedReportingOverflow(by: divisor).partialValue, bits: bits)
                } else { return value }
            }
        }

        mutating func parseUnary() throws(MathError) -> Int64 {
            if consume("NOT") { return BaseConversion.apply(.not, try parseUnary(), bits: bits) }
            if consume("NEG") || consume("-") { return BaseConversion.apply(.neg, try parseUnary(), bits: bits) }
            if consume("(") {
                let value = try parseOr()
                guard consume(")") || isAtEnd else { throw .syntax("manjka »)«") }
                return value
            }
            guard position < tokens.count, case .number(let digits) = tokens[position] else { throw .incomplete }
            position += 1
            return try BaseConversion.parse(digits, base: base, bits: bits)
        }
    }
}
