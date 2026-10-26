import Foundation

/// Atomic symbols of the structured editor (one key press each).
public enum MathSymbol: Hashable, Sendable, Codable {
    case digit(Int)
    case decimalPoint
    case plus, minus, times, divide
    case equals, less, greater, lessOrEqual, greaterOrEqual, notEqual
    case leftParenthesis, rightParenthesis
    case comma
    case variable(String)
    case constant(MathConstant)
    case factorial, percent
    /// Scientific notation separator (EE / Exp): `1.5ᴇ3`.
    case exponent10
    case degreeMark, minuteMark, secondMark
    case ans
    /// ± (display only, used by formula sheets)
    case plusMinus
    /// Vector (cross) product a⃗ × b⃗.
    case crossProduct
    /// Transpose mark Aᵀ (postfix).
    case transposeMark
    /// Phasor angle: 10∠30° = 10·(cos 30° + i·sin 30°).
    case angleSign
    /// Parallel connection: R₁∥R₂ = R₁R₂/(R₁ + R₂).
    case parallel

    /// Text shown for the symbol (operators use typographic glyphs).
    public func text(multiplication: String = "·", decimalSeparator: String = ",") -> String {
        switch self {
        case .digit(let d): String(d)
        case .decimalPoint: decimalSeparator
        case .plus: "+"
        case .minus: "−"
        case .times: multiplication
        case .divide: "÷"
        case .equals: "="
        case .less: "<"
        case .greater: ">"
        case .lessOrEqual: "≤"
        case .greaterOrEqual: "≥"
        case .notEqual: "≠"
        case .leftParenthesis: "("
        case .rightParenthesis: ")"
        case .comma: ";"
        case .variable(let name): MathSymbol.displayName(name)
        case .constant(let c): c.symbol
        case .factorial: "!"
        case .percent: "%"
        case .exponent10: "ᴇ"
        case .degreeMark: "°"
        case .minuteMark: "′"
        case .secondMark: "″"
        case .ans: "Ans"
        case .plusMinus: "±"
        case .crossProduct: "×"
        case .transposeMark: "ᵀ"
        case .angleSign: "∠"
        case .parallel: "∥"
        }
    }

    /// `v_0` → `v₀`
    public static func displayName(_ name: String) -> String {
        guard let underscore = name.firstIndex(of: "_") else { return name }
        let base = name[..<underscore]
        let sub = name[name.index(after: underscore)...]
        let map: [Character: Character] = ["0": "₀", "1": "₁", "2": "₂", "3": "₃", "4": "₄", "5": "₅", "6": "₆", "7": "₇", "8": "₈", "9": "₉"]
        if sub.allSatisfy({ map[$0] != nil }) { return base + String(sub.map { map[$0]! }) }
        return String(base) + "_" + sub
    }

    public var isOperator: Bool {
        switch self {
        case .plus, .minus, .times, .divide, .equals, .less, .greater, .lessOrEqual, .greaterOrEqual, .notEqual, .comma, .plusMinus, .crossProduct,
             .angleSign, .parallel: true
        default: false
        }
    }
}

/// A horizontal list of nodes — a "field" that can hold the cursor.
public struct MathRow: Hashable, Sendable, Codable {
    public var nodes: [MathNode]

    public init(_ nodes: [MathNode] = []) { self.nodes = nodes }

    public var isEmpty: Bool { nodes.isEmpty }

    public static func text(_ s: String) -> MathRow {
        MathRow(s.compactMap { c -> MathNode? in
            if let d = c.wholeNumberValue { return .symbol(.digit(d)) }
            switch c {
            case ".", ",": return .symbol(.decimalPoint)
            case "+": return .symbol(.plus)
            case "-", "−": return .symbol(.minus)
            case "*", "·", "×": return .symbol(.times)
            case "/", "÷": return .symbol(.divide)
            case "=": return .symbol(.equals)
            case "(": return .symbol(.leftParenthesis)
            case ")": return .symbol(.rightParenthesis)
            case "π": return .symbol(.constant(.pi))
            case " ": return nil
            default: return c.isLetter ? .symbol(.variable(String(c))) : nil
            }
        })
    }

    /// True when any slot (recursively) is still an empty placeholder.
    public var hasEmptyPlaceholder: Bool {
        nodes.contains { node in node.slots.contains { $0.isEmpty || $0.hasEmptyPlaceholder } }
    }
}

/// Structured editor nodes. Slots are the editable child rows.
public indirect enum MathNode: Hashable, Sendable, Codable {
    case symbol(MathSymbol)
    case fraction(numerator: MathRow, denominator: MathRow)
    /// Exponent applied to the preceding node.
    case power(exponent: MathRow)
    /// Subscript applied to the preceding node (`x₁`).
    case subscriptRow(MathRow)
    case squareRoot(MathRow)
    case nthRoot(index: MathRow, radicand: MathRow)
    case absoluteValue(MathRow)
    /// A function with its argument shown in parentheses: sin(…)
    case function(MathFunction, argument: MathRow)
    /// log_base(argument)
    case logarithm(base: MathRow, argument: MathRow)
    /// d/dx(body), optionally evaluated at a point: d/dx(body)|ₓ₌ₐ
    case derivative(body: MathRow, point: MathRow?)
    /// ∫ₐᵇ body dx (both bounds empty → indefinite)
    case integral(lower: MathRow, upper: MathRow, body: MathRow)
    /// Σ_{n=lower}^{upper} body
    case summation(lower: MathRow, upper: MathRow, body: MathRow)
    /// Binomial coefficient (n over k)
    case binomial(MathRow, MathRow)
    /// Two-argument functions written f(a; b): gcd, lcm, mod, R.Int, int÷, Pol, Rec
    case function2(MathFunction, MathRow, MathRow)
    /// lim_{x→point} body
    case limit(point: MathRow, body: MathRow, direction: LimitDirection)
    /// An m×n matrix (vectors are n×1); cells are row-major.
    case matrix(rows: Int, columns: Int, cells: [MathRow])
    /// A piecewise function: rows of (value, condition); an empty condition in the last row means "otherwise".
    case piecewise(cells: [MathRow])
    /// Π_{n=lower}^{upper} body
    case bigProduct(lower: MathRow, upper: MathRow, body: MathRow)
    /// Vector arrow over the content (a⃗).
    case vectorArrow(MathRow)
    /// Functions with any number of arguments, written f(a; b; c).
    case functionN(MathFunction, [MathRow])
    /// ∂/∂v body
    case partialDerivative(variable: MathRow, body: MathRow)
    /// sin²(x) or sin⁻¹(x): an exponent written on the function name.
    case poweredFunction(MathFunction, exponent: MathRow, argument: MathRow)

    public var slots: [MathRow] {
        switch self {
        case .symbol: []
        case .fraction(let n, let d): [n, d]
        case .power(let e): [e]
        case .subscriptRow(let s): [s]
        case .squareRoot(let r): [r]
        case .nthRoot(let i, let r): [i, r]
        case .absoluteValue(let r): [r]
        case .function(_, let a): [a]
        case .logarithm(let b, let a): [b, a]
        case .derivative(let b, let p): p.map { [b, $0] } ?? [b]
        case .integral(let l, let u, let b): [l, u, b]
        case .summation(let l, let u, let b): [l, u, b]
        case .binomial(let a, let b): [a, b]
        case .function2(_, let a, let b): [a, b]
        case .limit(let p, let b, _): [p, b]
        case .matrix(_, _, let cells): cells
        case .piecewise(let cells): cells
        case .bigProduct(let l, let u, let b): [l, u, b]
        case .vectorArrow(let r): [r]
        case .functionN(_, let args): args
        case .partialDerivative(let v, let b): [v, b]
        case .poweredFunction(_, let e, let a): [e, a]
        }
    }

    /// Slot that receives the cursor when the node is inserted.
    public var firstEditableSlot: Int {
        switch self {
        case .nthRoot: 1
        case .logarithm: 0
        case .integral: 2
        case .summation, .bigProduct: 2
        case .partialDerivative: 1
        case .poweredFunction: 1
        default: 0
        }
    }

    public func replacingSlot(_ index: Int, with row: MathRow) -> MathNode {
        switch self {
        case .symbol: self
        case .fraction(let n, let d): index == 0 ? .fraction(numerator: row, denominator: d) : .fraction(numerator: n, denominator: row)
        case .power: .power(exponent: row)
        case .subscriptRow: .subscriptRow(row)
        case .squareRoot: .squareRoot(row)
        case .nthRoot(let i, let r): index == 0 ? .nthRoot(index: row, radicand: r) : .nthRoot(index: i, radicand: row)
        case .absoluteValue: .absoluteValue(row)
        case .function(let f, _): .function(f, argument: row)
        case .logarithm(let b, let a): index == 0 ? .logarithm(base: row, argument: a) : .logarithm(base: b, argument: row)
        case .derivative(let b, let p): index == 0 ? .derivative(body: row, point: p) : .derivative(body: b, point: row)
        case .integral(let l, let u, let b):
            switch index {
            case 0: .integral(lower: row, upper: u, body: b)
            case 1: .integral(lower: l, upper: row, body: b)
            default: .integral(lower: l, upper: u, body: row)
            }
        case .summation(let l, let u, let b):
            switch index {
            case 0: .summation(lower: row, upper: u, body: b)
            case 1: .summation(lower: l, upper: row, body: b)
            default: .summation(lower: l, upper: u, body: row)
            }
        case .binomial(let a, let b): index == 0 ? .binomial(row, b) : .binomial(a, row)
        case .function2(let f, let a, let b): index == 0 ? .function2(f, row, b) : .function2(f, a, row)
        case .limit(let p, let b, let d): index == 0 ? .limit(point: row, body: b, direction: d) : .limit(point: p, body: row, direction: d)
        case .matrix(let r, let c, let cells): .matrix(rows: r, columns: c, cells: cells.replacingElement(at: index, with: row))
        case .piecewise(let cells): .piecewise(cells: cells.replacingElement(at: index, with: row))
        case .bigProduct(let l, let u, let b):
            switch index {
            case 0: .bigProduct(lower: row, upper: u, body: b)
            case 1: .bigProduct(lower: l, upper: row, body: b)
            default: .bigProduct(lower: l, upper: u, body: row)
            }
        case .vectorArrow: .vectorArrow(row)
        case .functionN(let f, let args): .functionN(f, args.replacingElement(at: index, with: row))
        case .partialDerivative(let v, let b): index == 0 ? .partialDerivative(variable: row, body: b) : .partialDerivative(variable: v, body: row)
        case .poweredFunction(let f, let e, let a): index == 0 ? .poweredFunction(f, exponent: row, argument: a) : .poweredFunction(f, exponent: e, argument: row)
        }
    }

    /// Up/down navigation between slots (fraction numerator ↔ denominator, bounds ↔ body).
    public func slot(above index: Int) -> Int? {
        switch self {
        case .fraction: index == 1 ? 0 : nil
        case .integral, .summation, .bigProduct: index == 0 || index == 2 ? 1 : nil
        case .nthRoot: index == 1 ? 0 : nil
        case .binomial: index == 1 ? 0 : nil
        case .matrix(_, let columns, _): index >= columns ? index - columns : nil
        case .piecewise: index >= 2 ? index - 2 : nil
        case .poweredFunction: index == 1 ? 0 : nil
        default: nil
        }
    }

    public func slot(below index: Int) -> Int? {
        switch self {
        case .fraction: index == 0 ? 1 : nil
        case .integral, .summation, .bigProduct: index == 1 || index == 2 ? 0 : nil
        case .nthRoot: index == 0 ? 1 : nil
        case .binomial: index == 0 ? 1 : nil
        case .matrix(_, let columns, let cells): index + columns < cells.count ? index + columns : nil
        case .piecewise(let cells): index + 2 < cells.count ? index + 2 : nil
        case .poweredFunction: index == 0 ? 1 : nil
        default: nil
        }
    }

    /// Rows and columns of a grid node (matrix or piecewise function).
    public var gridShape: (rows: Int, columns: Int)? {
        switch self {
        case .matrix(let r, let c, _): (r, c)
        case .piecewise(let cells): (cells.count / 2, 2)
        default: nil
        }
    }

    public var isScript: Bool {
        switch self {
        case .power, .subscriptRow: true
        default: false
        }
    }
}

extension Array {
    /// A copy with the element at `index` replaced (unchanged when out of range).
    func replacingElement(at index: Int, with value: Element) -> [Element] {
        guard indices.contains(index) else { return self }
        var copy = self
        copy[index] = value
        return copy
    }
}
