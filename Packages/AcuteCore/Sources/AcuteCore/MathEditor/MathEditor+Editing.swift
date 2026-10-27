import Foundation

/// A selection of consecutive nodes in one row of the editor.
public struct MathSelection: Hashable, Sendable, Codable {
    public var path: [MathCursor.Step]
    public var range: Range<Int>

    public init(path: [MathCursor.Step], range: Range<Int>) {
        self.path = path
        self.range = range
    }
}

extension MathEditor {
    // MARK: Parentheses

    /// "(" inserts a pair with the caret inside (or wraps the selection).
    public mutating func insertLeftParenthesis() {
        if let selected = takeSelection() {
            let path = cursor.path
            let index = cursor.index
            modifyRow(at: path) { row in
                row.nodes.insert(contentsOf: [.symbol(.leftParenthesis)] + selected.nodes + [.symbol(.rightParenthesis)], at: index)
            }
            cursor.index = index + selected.nodes.count + 2
            return
        }
        let path = cursor.path
        let index = cursor.index
        modifyRow(at: path) { row in
            row.nodes.insert(contentsOf: [.symbol(.leftParenthesis), .symbol(.rightParenthesis)], at: min(index, row.nodes.count))
        }
        cursor.index = index + 1
    }

    /// ")" steps over an auto-inserted closing parenthesis instead of adding another one.
    public mutating func insertRightParenthesis() {
        let row = currentRow
        if cursor.index < row.nodes.count, case .symbol(.rightParenthesis) = row.nodes[cursor.index] {
            cursor.index += 1
            return
        }
        insertNode(.symbol(.rightParenthesis))
    }

    // MARK: Sign

    /// ± key: toggles the sign of the operand left of the caret (−3 ↔ 3, −(x+1) ↔ (x+1)).
    public mutating func toggleSign() {
        selection = nil
        let row = currentRow
        let start = MathEditor.operandStart(in: row, before: cursor.index)
        let path = cursor.path
        if start > 0, case .symbol(.minus) = row.nodes[start - 1], MathEditor.isUnaryPosition(in: row, at: start - 1) {
            modifyRow(at: path) { $0.nodes.remove(at: start - 1) }
            cursor.index -= 1
        } else {
            modifyRow(at: path) { $0.nodes.insert(.symbol(.minus), at: start) }
            cursor.index += 1
        }
    }

    static func isUnaryPosition(in row: MathRow, at index: Int) -> Bool {
        guard index > 0 else { return true }
        if case .symbol(let s) = row.nodes[index - 1] { return s.isOperator || s == .leftParenthesis }
        return false
    }

    // MARK: Matrices and piecewise functions

    public mutating func insertMatrix(rows: Int, columns: Int) {
        let r = max(1, min(rows, MathEditor.maximumMatrixSize)), c = max(1, min(columns, MathEditor.maximumMatrixSize))
        insertWrapping(.matrix(rows: r, columns: c, cells: Array(repeating: MathRow(), count: r * c)))
    }

    public mutating func insertPiecewise(rows: Int = 2) {
        insertNode(.piecewise(cells: Array(repeating: MathRow(), count: 2 * max(1, rows))))
    }

    public static let maximumMatrixSize = 10

    /// Changes the size of the grid node at `path`/`index`, keeping the cells that still fit.
    public mutating func resizeGrid(at path: [MathCursor.Step], index: Int, rows: Int, columns: Int) {
        guard let row = subrow(at: path), index < row.nodes.count else { return }
        let node = row.nodes[index]
        let newRows = max(1, min(rows, MathEditor.maximumMatrixSize))
        switch node {
        case .matrix(let oldRows, let oldColumns, let cells):
            let newColumns = max(1, min(columns, MathEditor.maximumMatrixSize))
            guard newRows != oldRows || newColumns != oldColumns else { return }
            var newCells: [MathRow] = []
            for r in 0..<newRows {
                for c in 0..<newColumns {
                    newCells.append(r < oldRows && c < oldColumns ? cells[r * oldColumns + c] : MathRow())
                }
            }
            modifyRow(at: path) { $0.nodes[index] = .matrix(rows: newRows, columns: newColumns, cells: newCells) }
            fixCursorAfterResize(path: path, index: index, keep: { slot in
                let r = slot / oldColumns, c = slot % oldColumns
                return r < newRows && c < newColumns ? r * newColumns + c : nil
            }, lastSlot: newRows * newColumns - 1)
        case .piecewise(let cells):
            let oldRows = cells.count / 2
            guard newRows != oldRows else { return }
            var newCells = Array(cells.prefix(2 * newRows))
            while newCells.count < 2 * newRows { newCells.append(MathRow()) }
            modifyRow(at: path) { $0.nodes[index] = .piecewise(cells: newCells) }
            fixCursorAfterResize(path: path, index: index, keep: { $0 < 2 * newRows ? $0 : nil }, lastSlot: 2 * newRows - 1)
        default:
            return
        }
    }

    private mutating func fixCursorAfterResize(path: [MathCursor.Step], index: Int, keep: (Int) -> Int?, lastSlot: Int) {
        guard cursor.path.count > path.count, Array(cursor.path.prefix(path.count)) == path,
              cursor.path[path.count].node == index else { return }
        let oldSlot = cursor.path[path.count].slot
        if let newSlot = keep(oldSlot) {
            var newPath = cursor.path
            newPath[path.count] = MathCursor.Step(node: index, slot: newSlot)
            cursor.path = newPath
        } else {
            let target = path + [MathCursor.Step(node: index, slot: lastSlot)]
            cursor = MathCursor(path: target, index: subrow(at: target)?.nodes.count ?? 0)
        }
    }

    // MARK: Selection

    /// Selects nodes `range` of the row at `path`.
    public mutating func select(path: [MathCursor.Step], range: Range<Int>) {
        guard let row = subrow(at: path) else { return }
        let lower = max(0, min(range.lowerBound, row.nodes.count))
        let upper = max(lower, min(range.upperBound, row.nodes.count))
        cursor = MathCursor(path: path, index: upper)
        selection = upper > lower ? MathSelection(path: path, range: lower..<upper) : nil
    }

    public mutating func selectAll() {
        select(path: [], range: 0..<root.nodes.count)
    }

    /// Selection between two caret positions (e.g. the ends of a drag). Positions inside
    /// different structures select whole nodes of the innermost row containing both.
    public mutating func select(from a: MathCursor, to b: MathCursor) {
        var common = 0
        while common < a.path.count, common < b.path.count, a.path[common] == b.path[common] { common += 1 }
        func span(_ c: MathCursor) -> Range<Int> {
            if c.path.count == common { return c.index..<c.index }
            let node = c.path[common].node
            return node..<(node + 1)
        }
        let first = span(a), second = span(b)
        let lower = min(first.lowerBound, second.lowerBound)
        let upper = max(first.upperBound, second.upperBound)
        select(path: Array(a.path.prefix(common)), range: lower..<upper)
    }

    public var selectedRow: MathRow? {
        guard let selection, let row = subrow(at: selection.path),
              selection.range.upperBound <= row.nodes.count else { return nil }
        return MathRow(Array(row.nodes[selection.range]))
    }

    /// Removes the selected nodes and returns them (the caret goes where they were).
    @discardableResult
    public mutating func takeSelection() -> MathRow? {
        guard let selection, let selected = selectedRow else {
            self.selection = nil
            return nil
        }
        modifyRow(at: selection.path) { $0.nodes.removeSubrange(selection.range) }
        cursor = MathCursor(path: selection.path, index: selection.range.lowerBound)
        self.selection = nil
        return selected
    }

    public mutating func deleteSelection() -> Bool {
        takeSelection() != nil
    }

    /// Inserts a node; when text is selected, the selection becomes the node's first slot
    /// (select x+1 then press √ → √(x+1)).
    public mutating func insertWrapping(_ node: MathNode) {
        guard let selected = takeSelection() else {
            insertNode(node)
            return
        }
        let slots = node.slots
        guard !slots.isEmpty else {
            insertNode(node)
            return
        }
        let target = node.firstEditableSlot < slots.count ? node.firstEditableSlot : 0
        insertNode(node.replacingSlot(target, with: selected))
    }

    /// Pastes a row at the caret (replacing the selection).
    public mutating func paste(_ row: MathRow) {
        _ = takeSelection()
        let path = cursor.path
        let index = cursor.index
        modifyRow(at: path) { $0.nodes.insert(contentsOf: row.nodes, at: min(index, $0.nodes.count)) }
        cursor.index = index + row.nodes.count
    }

    // MARK: Typing names on a hardware keyboard

    /// Words that turn into structures when typed letter by letter (sin, sqrt, pi, alpha …).
    static let typedWords: [String: MathNode] = {
        var map: [String: MathNode] = [:]
        let functions: [String: MathFunction] = [
            "sin": .sin, "cos": .cos, "tan": .tan, "cot": .cot, "tg": .tan, "ctg": .cot, "sec": .sec, "csc": .csc,
            "arcsin": .asin, "arccos": .acos, "arctan": .atan, "arccot": .acot, "asin": .asin, "acos": .acos, "atan": .atan,
            "sinh": .sinh, "cosh": .cosh, "tanh": .tanh, "coth": .coth, "arsinh": .asinh, "arcosh": .acosh, "artanh": .atanh,
            "ln": .ln, "log": .log10, "exp": .exp, "floor": .floor, "ceil": .ceil, "round": .round, "sign": .sign, "sgn": .sign,
            "det": .det, "rank": .rank, "trace": .trace, "eig": .eig, "rref": .rref, "ker": .kernel, "charpoly": .charpoly, "norm": .norm, "erf": .erf, "zeta": .zeta, "gamma": .gamma,
        ]
        for (word, f) in functions { map[word] = .function(f, argument: MathRow()) }
        let pairs: [String: MathFunction] = ["gcd": .gcd, "lcm": .lcm, "mod": .mod, "nCr": .nCr, "nPr": .nPr, "dot": .dot, "cross": .cross, "angle": .angle]
        for (word, f) in pairs { map[word] = .function2(f, MathRow(), MathRow()) }
        map["sqrt"] = .squareRoot(MathRow())
        map["cbrt"] = .nthRoot(index: .text("3"), radicand: MathRow())
        map["root"] = .nthRoot(index: MathRow(), radicand: MathRow())
        map["abs"] = .absoluteValue(MathRow())
        map["pi"] = .symbol(.constant(.pi))
        map["inf"] = .symbol(.constant(.infinity))
        map["int"] = .integral(lower: MathRow(), upper: MathRow(), body: MathRow())
        map["sum"] = .summation(lower: MathRow(), upper: MathRow(), body: MathRow())
        map["prod"] = .bigProduct(lower: MathRow(), upper: MathRow(), body: MathRow())
        map["lim"] = .limit(point: MathRow(), body: MathRow(), direction: .both)
        map["vec"] = .vectorArrow(MathRow())
        map["bold"] = .vectorArrow(MathRow())
        // Distributions under the names the text parser knows (normcdf, binomPdf, invNorm …), with the slots of
        // their keypad keys (normpdf and invnorm in the one-argument form). Left out: phi, which the parser reads
        // as φ unless "(" follows, and chi2pdf, chi2cdf, invchi2, whose digit never reaches insertLetter.
        let distributions: Set<MathFunction> = [.binompdf, .binomcdf, .poissonpdf, .poissoncdf, .normcdf, .normpdf, .invnorm,
                                                .tpdf, .tcdf, .invt, .fpdf, .fcdf, .invf]
        for (word, f) in MathFunction.parserNames where distributions.contains(f) && word.count > 1 && word != "phi" {
            switch f.arity {
            case 2: map[word] = .function2(f, MathRow(), MathRow())
            case 3: map[word] = .functionN(f, Array(repeating: MathRow(), count: 3))
            default: map[word] = .function(f, argument: MathRow())
            }
        }
        // Γ, ζ and Φ typed as characters are functions, as in the text parser (γ and φ stay variables).
        map["Γ"] = .function(.gamma, argument: MathRow())
        map["ζ"] = .function(.zeta, argument: MathRow())
        map["Φ"] = .function(.normcdf, argument: MathRow())
        // ξ is left out: "xi" is usually x·i.
        for (word, letter) in Parser.greekLetters where !["gamma", "zeta", "xi", "Xi"].contains(word) {
            map[word] = .symbol(.variable(letter))
        }
        return map
    }()

    /// Inserts a typed letter; when the letters before the caret spell a known word, they become
    /// that structure (s-i-n → sin(□), then h → sinh(□)).
    public mutating func insertLetter(_ letter: String) {
        // sin(□) + "h" → sinh(□); norm(□) + "c", "d", "f" → norm(c·d) → normcdf(□): letters typed into the
        // argument right after a name continue it when they complete a longer one.
        if selection == nil, let step = cursor.path.last,
           let parent = subrow(at: Array(cursor.path.dropLast())), step.node < parent.nodes.count,
           case .function(let f, let argument) = parent.nodes[step.node], cursor.index == argument.nodes.count,
           let typed = MathEditor.typedLetters(argument),
           let upgraded = MathEditor.typedWords[f.rawValue + typed + letter], case .function = upgraded {
            let parentPath = Array(cursor.path.dropLast())
            modifyRow(at: parentPath) { $0.nodes[step.node] = upgraded }
            cursor.index = 0
            return
        }
        insert(.variable(letter))
        // Look for the longest typed word ending at the caret: up to 10 letters (poissonpdf, varepsilon),
        // or the single letters Γ, ζ, Φ.
        let row = currentRow
        var letters: [String] = []
        var i = cursor.index - 1
        while i >= 0, letters.count < 10, case .symbol(.variable(let v)) = row.nodes[i], v.count == 1 {
            letters.insert(v, at: 0)
            i -= 1
        }
        for length in stride(from: letters.count, through: 1, by: -1) {
            let word = letters.suffix(length).joined()
            guard let node = MathEditor.typedWords[word] else { continue }
            let start = cursor.index - length
            let path = cursor.path
            modifyRow(at: path) { $0.nodes.removeSubrange(start..<(start + length)) }
            cursor.index = start
            insertNode(node)
            return
        }
    }

    /// The letters of a row that holds only single-letter variables ("" for an empty row), otherwise nil.
    static func typedLetters(_ row: MathRow) -> String? {
        var letters = ""
        for node in row.nodes {
            guard case .symbol(.variable(let v)) = node, v.count == 1 else { return nil }
            letters += v
        }
        return letters
    }
}
