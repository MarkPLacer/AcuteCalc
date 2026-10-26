import AcuteCore

/// Anything the keypad and symbol palette can type into (the calculator, the graph editors).
protocol KeypadTarget: AnyObject {
    var paletteExpanded: Bool { get set }
    var selectedPage: SymbolPage { get set }
    /// The enter key shows "=" (otherwise a check mark that confirms a definition).
    var enterShowsEquals: Bool { get }
    /// STO is armed: the next variable key stores into that variable.
    var storeMode: Bool { get }
    func press(_ key: KeypadKey)
}

extension MathEditor {
    /// Applies a key that only edits the expression. Returns `false` for keys
    /// whose meaning depends on the owner (clear, enter, memories, modes).
    mutating func apply(_ key: KeypadKey) -> Bool {
        switch key {
        case .digit(let d): insert(.digit(d))
        case .point: insert(.decimalPoint)
        case .symbol(let s): insert(s)
        case .delete: deleteBackward()
        case .left: moveLeft()
        case .right: moveRight()
        case .up: moveUp()
        case .down: moveDown()
        case .fraction: insertFraction()
        case .power: insertPower()
        case .square: insertPower(.text("2"))
        case .cube: insertPower(.text("3"))
        case .inverse: insertPower(MathRow([.symbol(.minus), .symbol(.digit(1))]))
        case .tenPower:
            insert(.digit(1)); insert(.digit(0)); insertPower()
        case .ePower:
            insert(.constant(.e)); insertPower()
        case .sqrt: insertWrapping(.squareRoot(MathRow()))
        case .cbrt: insertWrapping(.nthRoot(index: .text("3"), radicand: MathRow()))
        case .nthRoot: insertWrapping(.nthRoot(index: MathRow(), radicand: MathRow()))
        case .abs: insertWrapping(.absoluteValue(MathRow()))
        case .logBase: insertWrapping(.logarithm(base: MathRow(), argument: MathRow()))
        case .function(let f):
            if f == .degrees { insert(.degreeMark) } else { insertWrapping(.function(f, argument: MathRow())) }
        case .function2(let f): insertWrapping(.function2(f, MathRow(), MathRow()))
        case .functionN(let f, let count): insertWrapping(.functionN(f, Array(repeating: MathRow(), count: count)))
        case .derivative: insertWrapping(.derivative(body: MathRow(), point: nil))
        case .derivativeAt: insertWrapping(.derivative(body: MathRow(), point: MathRow()))
        case .partialDerivative: insertWrapping(.partialDerivative(variable: .text("x"), body: MathRow()))
        case .integral, .indefiniteIntegral: insertWrapping(.integral(lower: MathRow(), upper: MathRow(), body: MathRow()))
        case .summation: insertWrapping(.summation(lower: MathRow(), upper: MathRow(), body: MathRow()))
        case .product: insertWrapping(.bigProduct(lower: MathRow(), upper: MathRow(), body: MathRow()))
        case .limit: insertWrapping(.limit(point: MathRow(), body: MathRow(), direction: .both))
        case .limitLeft: insertWrapping(.limit(point: MathRow(), body: MathRow(), direction: .left))
        case .limitRight: insertWrapping(.limit(point: MathRow(), body: MathRow(), direction: .right))
        case .binomial: insertWrapping(.binomial(MathRow(), MathRow()))
        case .variable(let name): insert(.variable(name))
        case .memoryRecall: insert(.variable("M"))
        case .subscriptKey: insertNode(.subscriptRow(MathRow()))
        case .matrix(let rows, let columns): insertMatrix(rows: rows, columns: columns)
        case .piecewise: insertPiecewise()
        case .vectorArrow: insertWrapping(.vectorArrow(MathRow()))
        case .negate: toggleSign()
        case .selectAll: selectAll()
        case .typedLetter(let letter): insertLetter(letter)
        case .clear, .enter, .angleMode, .store, .memoryPlus, .memoryMinus, .change, .expand, .undo, .redo, .modify:
            return false
        }
        return true
    }
}

extension AppSettings {
    /// DRG: RAD → DEG → GRAD → RAD.
    func cycleAngleUnit() {
        let all = AngleUnit.allCases
        guard let index = all.firstIndex(of: angleUnit) else { return }
        angleUnit = all[(index + 1) % all.count]
    }
}
