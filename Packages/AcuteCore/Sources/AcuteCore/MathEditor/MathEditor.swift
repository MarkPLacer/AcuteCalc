import Foundation

/// Cursor position: a path of (node index, slot index) steps from the root row to the
/// row holding the caret, plus the caret index inside that row.
public struct MathCursor: Hashable, Sendable, Codable {
    public struct Step: Hashable, Sendable, Codable {
        public var node: Int
        public var slot: Int

        public init(node: Int, slot: Int) {
            self.node = node
            self.slot = slot
        }
    }

    public var path: [Step]
    public var index: Int

    public init(path: [Step] = [], index: Int = 0) {
        self.path = path
        self.index = index
    }
}

/// The structured ("WriteView"-style) expression editor: fractions, roots, powers,
/// integrals … with a caret that moves between their slots.
public struct MathEditor: Hashable, Sendable, Codable {
    public var root: MathRow
    public var cursor: MathCursor
    /// Selected nodes (drag to select, select all); typing replaces them.
    public var selection: MathSelection?

    public init(root: MathRow = MathRow(), cursor: MathCursor? = nil) {
        self.root = root
        self.cursor = cursor ?? MathCursor(path: [], index: root.nodes.count)
    }

    public var isEmpty: Bool { root.isEmpty }

    // MARK: Row access

    public func subrow(at path: [MathCursor.Step]) -> MathRow? {
        var row = root
        for step in path {
            guard step.node < row.nodes.count else { return nil }
            let slots = row.nodes[step.node].slots
            guard step.slot < slots.count else { return nil }
            row = slots[step.slot]
        }
        return row
    }

    public var currentRow: MathRow { subrow(at: cursor.path) ?? root }

    mutating func modifyRow(at path: [MathCursor.Step], _ body: (inout MathRow) -> Void) {
        func recurse(_ row: inout MathRow, _ remaining: ArraySlice<MathCursor.Step>) {
            guard let step = remaining.first else {
                body(&row)
                return
            }
            guard step.node < row.nodes.count else { return }
            let node = row.nodes[step.node]
            let slots = node.slots
            guard step.slot < slots.count else { return }
            var child = slots[step.slot]
            recurse(&child, remaining.dropFirst())
            row.nodes[step.node] = node.replacingSlot(step.slot, with: child)
        }
        recurse(&root, path[...])
    }

    /// Sets the caret, clamping invalid positions (used by tap-to-place).
    public mutating func setCursor(path: [MathCursor.Step], index: Int) {
        guard let row = subrow(at: path) else { return }
        selection = nil
        cursor = MathCursor(path: path, index: max(0, min(index, row.nodes.count)))
    }

    public mutating func clear() {
        root = MathRow()
        cursor = MathCursor()
        selection = nil
    }

    // MARK: Insertion

    public mutating func insert(_ symbol: MathSymbol) {
        switch symbol {
        case .leftParenthesis: insertLeftParenthesis()
        case .rightParenthesis: insertRightParenthesis()
        default: insertNode(.symbol(symbol))
        }
    }

    /// Inserts a node at the caret (replacing a selection). Structures put the caret into their first empty slot.
    public mutating func insertNode(_ node: MathNode) {
        if selection != nil { _ = takeSelection() }
        let path = cursor.path
        let index = cursor.index
        modifyRow(at: path) { row in row.nodes.insert(node, at: min(index, row.nodes.count)) }
        let slots = node.slots
        if slots.isEmpty {
            cursor.index = index + 1
            return
        }
        // Enter the first empty slot (in editing order), otherwise move past the node.
        let order = MathEditor.slotOrder(node)
        let preferred = node.firstEditableSlot
        let target = slots[preferred].isEmpty ? preferred : (order.first { slots[$0].isEmpty })
        if let slot = target {
            cursor = MathCursor(path: path + [MathCursor.Step(node: index, slot: slot)], index: 0)
        } else {
            cursor.index = index + 1
        }
    }

    /// Inserts a fraction; the selection or the operand left of the caret becomes the numerator.
    public mutating func insertFraction() {
        if let selected = takeSelection() {
            insertNode(.fraction(numerator: selected, denominator: MathRow()))
            return
        }
        let row = currentRow
        let start = MathEditor.operandStart(in: row, before: cursor.index)
        if start < cursor.index {
            let numerator = MathRow(Array(row.nodes[start..<cursor.index]))
            let path = cursor.path
            let end = cursor.index
            modifyRow(at: path) { r in
                r.nodes.replaceSubrange(start..<end, with: [.fraction(numerator: numerator, denominator: MathRow())])
            }
            cursor = MathCursor(path: path + [MathCursor.Step(node: start, slot: 1)], index: 0)
        } else {
            insertNode(.fraction(numerator: MathRow(), denominator: MathRow()))
        }
    }

    /// Wraps the operand left of the caret in a function-like structure, e.g. √(x+1) after `(x+1)`.
    /// Inserts an empty structure when there is no operand.
    public mutating func insertPower(_ exponent: MathRow? = nil) {
        if let selected = takeSelection() {
            // (selection)ⁿ
            let path = cursor.path
            let index = cursor.index
            let wrapped: [MathNode] = selected.nodes.count == 1 && !selected.nodes[0].slots.isEmpty
                ? selected.nodes
                : [.symbol(.leftParenthesis)] + selected.nodes + [.symbol(.rightParenthesis)]
            modifyRow(at: path) { $0.nodes.insert(contentsOf: wrapped, at: index) }
            cursor.index = index + wrapped.count
        }
        // An exponent typed right after a function name inside its empty argument goes on the name: sin²(x).
        if cursor.index == 0, currentRow.isEmpty, let step = cursor.path.last, step.slot == 0,
           let parent = subrow(at: Array(cursor.path.dropLast())), step.node < parent.nodes.count,
           case .function(let f, _) = parent.nodes[step.node], f.arity == 1 {
            let parentPath = Array(cursor.path.dropLast())
            modifyRow(at: parentPath) { $0.nodes[step.node] = .poweredFunction(f, exponent: exponent ?? MathRow(), argument: MathRow()) }
            let slot = exponent == nil ? 0 : 1
            cursor = MathCursor(path: parentPath + [MathCursor.Step(node: step.node, slot: slot)], index: 0)
            return
        }
        insertNode(.power(exponent: exponent ?? MathRow()))
    }

    // MARK: Deletion

    public mutating func deleteBackward() {
        if selection != nil {
            _ = takeSelection()
            return
        }
        let path = cursor.path
        let index = cursor.index
        let row = currentRow
        // An empty auto-closed pair "()" disappears together.
        if index > 0, index < row.nodes.count, case .symbol(.leftParenthesis) = row.nodes[index - 1],
           case .symbol(.rightParenthesis) = row.nodes[index] {
            modifyRow(at: path) { $0.nodes.removeSubrange((index - 1)...index) }
            cursor.index = index - 1
            return
        }
        if index > 0 {
            let previous = row.nodes[index - 1]
            let slots = previous.slots
            if slots.isEmpty || slots.allSatisfy(\.isEmpty) {
                modifyRow(at: path) { $0.nodes.remove(at: index - 1) }
                cursor.index = index - 1
            } else {
                // Step into the structure instead of destroying its contents.
                let order = MathEditor.slotOrder(previous)
                let last = order.last ?? 0
                cursor = MathCursor(path: path + [MathCursor.Step(node: index - 1, slot: last)], index: slots[last].nodes.count)
            }
            return
        }
        // At the start of a slot.
        guard let step = path.last else { return }
        let parentPath = Array(path.dropLast())
        guard let parentRow = subrow(at: parentPath) else { return }
        let node = parentRow.nodes[step.node]
        let order = MathEditor.slotOrder(node)
        if let position = order.firstIndex(of: step.slot), position > 0, !node.slots.allSatisfy(\.isEmpty) {
            // Move to the end of the previous slot (e.g. denominator → numerator).
            let previousSlot = order[position - 1]
            cursor = MathCursor(path: parentPath + [MathCursor.Step(node: step.node, slot: previousSlot)], index: node.slots[previousSlot].nodes.count)
            return
        }
        // Grids with content are selected first, so a second ⌫ removes them.
        if node.gridShape != nil, !node.slots.allSatisfy(\.isEmpty) {
            select(path: parentPath, range: step.node..<(step.node + 1))
            return
        }
        // Unwrap: replace the structure by its contents.
        let contents = MathEditor.unwrappedContents(node)
        modifyRow(at: parentPath) { r in
            r.nodes.replaceSubrange(step.node...step.node, with: contents)
        }
        cursor = MathCursor(path: parentPath, index: step.node)
    }

    /// Contents kept when a structure is deleted from its first slot.
    static func unwrappedContents(_ node: MathNode) -> [MathNode] {
        switch node {
        case .fraction(let n, let d):
            if d.isEmpty { return n.nodes }
            if n.isEmpty { return d.nodes }
            return n.nodes + [.symbol(.divide)] + d.nodes
        case .nthRoot(_, let r):
            return r.nodes
        case .logarithm(_, let a):
            return a.nodes
        case .integral(_, _, let b), .summation(_, _, let b):
            return b.nodes
        case .limit(_, let b, _):
            return b.nodes
        case .derivative(let b, _):
            return b.nodes
        case .poweredFunction(let f, _, let a):
            return [.function(f, argument: a)]
        case .partialDerivative(_, let b), .bigProduct(_, _, let b):
            return b.nodes
        default:
            return node.slots.flatMap(\.nodes)
        }
    }

    // MARK: Movement

    /// Order in which ←/→ visit the slots of a node.
    static func slotOrder(_ node: MathNode) -> [Int] {
        Array(node.slots.indices)
    }

    public mutating func moveLeft() {
        if let selection {
            // Collapse the selection to its start.
            self.selection = nil
            cursor = MathCursor(path: selection.path, index: selection.range.lowerBound)
            return
        }
        let row = currentRow
        if cursor.index > 0 {
            let node = row.nodes[cursor.index - 1]
            if !node.slots.isEmpty, let last = MathEditor.slotOrder(node).last {
                cursor = MathCursor(path: cursor.path + [MathCursor.Step(node: cursor.index - 1, slot: last)], index: node.slots[last].nodes.count)
            } else {
                cursor.index -= 1
            }
            return
        }
        guard let step = cursor.path.last else { return }
        let parentPath = Array(cursor.path.dropLast())
        guard let parentRow = subrow(at: parentPath) else { return }
        let node = parentRow.nodes[step.node]
        let order = MathEditor.slotOrder(node)
        if let position = order.firstIndex(of: step.slot), position > 0 {
            let previous = order[position - 1]
            cursor = MathCursor(path: parentPath + [MathCursor.Step(node: step.node, slot: previous)], index: node.slots[previous].nodes.count)
        } else {
            cursor = MathCursor(path: parentPath, index: step.node)
        }
    }

    public mutating func moveRight() {
        if let selection {
            self.selection = nil
            cursor = MathCursor(path: selection.path, index: selection.range.upperBound)
            return
        }
        let row = currentRow
        if cursor.index < row.nodes.count {
            let node = row.nodes[cursor.index]
            if !node.slots.isEmpty, let first = MathEditor.slotOrder(node).first {
                cursor = MathCursor(path: cursor.path + [MathCursor.Step(node: cursor.index, slot: first)], index: 0)
            } else {
                cursor.index += 1
            }
            return
        }
        guard let step = cursor.path.last else { return }
        let parentPath = Array(cursor.path.dropLast())
        guard let parentRow = subrow(at: parentPath) else { return }
        let node = parentRow.nodes[step.node]
        let order = MathEditor.slotOrder(node)
        if let position = order.firstIndex(of: step.slot), position + 1 < order.count {
            cursor = MathCursor(path: parentPath + [MathCursor.Step(node: step.node, slot: order[position + 1])], index: 0)
        } else {
            cursor = MathCursor(path: parentPath, index: step.node + 1)
        }
    }

    public mutating func moveUp() { moveVertically(up: true) }
    public mutating func moveDown() { moveVertically(up: false) }

    private mutating func moveVertically(up: Bool) {
        selection = nil
        // Innermost structure that has a slot in that direction.
        for depth in stride(from: cursor.path.count - 1, through: 0, by: -1) {
            let parentPath = Array(cursor.path.prefix(depth))
            let step = cursor.path[depth]
            guard let parentRow = subrow(at: parentPath) else { continue }
            let node = parentRow.nodes[step.node]
            if let target = up ? node.slot(above: step.slot) : node.slot(below: step.slot) {
                cursor = MathCursor(path: parentPath + [MathCursor.Step(node: step.node, slot: target)], index: node.slots[target].nodes.count)
                return
            }
            // Leaving an exponent downwards: continue after the power node.
            if !up, case .power = node {
                cursor = MathCursor(path: parentPath, index: step.node + 1)
                return
            }
        }
        // Entering an exponent upwards from the base line.
        if up, cursor.index > 0, case .power(let e) = currentRow.nodes[cursor.index - 1] {
            cursor = MathCursor(path: cursor.path + [MathCursor.Step(node: cursor.index - 1, slot: 0)], index: e.nodes.count)
        }
    }

    // MARK: Operand detection

    /// Start index of the operand ending at `end` (digits, names, closed brackets, structures).
    public static func operandStart(in row: MathRow, before end: Int) -> Int {
        var i = end
        var depth = 0
        while i > 0 {
            let node = row.nodes[i - 1]
            switch node {
            case .symbol(let s):
                switch s {
                case .rightParenthesis:
                    depth += 1
                case .leftParenthesis:
                    if depth == 0 { return i }
                    depth -= 1
                    if depth == 0 {
                        i -= 1
                        // Include a function name written as symbols before "(" is not possible; stop here.
                        return i
                    }
                case .digit, .decimalPoint, .variable, .constant, .ans, .factorial, .percent, .exponent10, .degreeMark, .minuteMark, .secondMark:
                    break
                default:
                    if depth == 0 { return i }
                }
            default:
                break
            }
            i -= 1
        }
        return depth == 0 ? 0 : end
    }

    /// True when the caret is at a position where a binary operator would have no left operand.
    public var caretNeedsOperand: Bool {
        let row = currentRow
        guard cursor.index > 0 else { return true }
        if case .symbol(let s) = row.nodes[cursor.index - 1] {
            return s.isOperator || s == .leftParenthesis
        }
        return false
    }

    /// Plain text approximation used for accessibility and copying.
    public var plainText: String { MathRowConverter.plainText(root) }
}
