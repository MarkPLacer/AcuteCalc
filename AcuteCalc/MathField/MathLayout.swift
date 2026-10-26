import AcuteCore
import CoreGraphics
import CoreText
import Foundation
import UIKit

/// Visual parameters of the math renderer.
struct MathStyle: Equatable {
    var fontSize: CGFloat = 32
    var multiplication = "·"
    var decimalSeparator = ","
    var slovenianNames = false
    /// Show empty slots as boxes (editor) or omit them (display).
    var showPlaceholders = true
    /// i, or j in electrical engineering.
    var imaginaryUnit = "i"
}

enum MathInk: Hashable {
    case primary, secondary, accent, placeholder
}

/// One drawable element, positioned in box coordinates (origin at the left baseline, y down).
nonisolated enum MathDrawItem {
    case text(CTLine, origin: CGPoint, ink: MathInk)
    case fill(CGPath, ink: MathInk)
    case stroke(CGPath, width: CGFloat, ink: MathInk)
    case placeholder(CGRect)
}

/// A caret position in the editor, in box coordinates.
nonisolated struct CaretSlot {
    var path: [MathCursor.Step]
    var index: Int
    var x: CGFloat
    var top: CGFloat
    var bottom: CGFloat
    var depth: Int { path.count }
}

/// Where a matrix or piecewise grid was laid out (for the resize handle).
nonisolated struct MathGridFrame {
    /// Row containing the grid node, and the node's index in it.
    var path: [MathCursor.Step]
    var index: Int
    var rect: CGRect
    var rows: Int
    var columns: Int
    /// Average cell pitch, used to turn drag distance into rows/columns.
    var cellSize: CGSize
}

/// A laid-out piece of math: metrics relative to its baseline plus draw items and caret slots.
nonisolated struct MathBox {
    var width: CGFloat = 0
    var ascent: CGFloat = 0
    var descent: CGFloat = 0
    var items: [MathDrawItem] = []
    var carets: [CaretSlot] = []
    var grids: [MathGridFrame] = []

    var height: CGFloat { ascent + descent }

    mutating func append(_ other: MathBox, at origin: CGPoint) {
        for item in other.items {
            switch item {
            case .text(let line, let o, let ink):
                items.append(.text(line, origin: CGPoint(x: o.x + origin.x, y: o.y + origin.y), ink: ink))
            case .fill(let path, let ink):
                var t = CGAffineTransform(translationX: origin.x, y: origin.y)
                if let moved = path.copy(using: &t) { items.append(.fill(moved, ink: ink)) }
            case .stroke(let path, let width, let ink):
                var t = CGAffineTransform(translationX: origin.x, y: origin.y)
                if let moved = path.copy(using: &t) { items.append(.stroke(moved, width: width, ink: ink)) }
            case .placeholder(let rect):
                items.append(.placeholder(rect.offsetBy(dx: origin.x, dy: origin.y)))
            }
        }
        for c in other.carets {
            carets.append(CaretSlot(path: c.path, index: c.index, x: c.x + origin.x, top: c.top + origin.y, bottom: c.bottom + origin.y))
        }
        for g in other.grids {
            var moved = g
            moved.rect = g.rect.offsetBy(dx: origin.x, dy: origin.y)
            grids.append(moved)
        }
    }
}

/// Fonts used by the renderer, cached per size.
final class MathFonts {
    static let shared = MathFonts()
    private var cache: [String: CTFont] = [:]

    func regular(_ size: CGFloat) -> CTFont { font("r", size) { UIFont.systemFont(ofSize: size, weight: .regular) } }
    func light(_ size: CGFloat) -> CTFont { font("l", size) { UIFont.systemFont(ofSize: size, weight: .light) } }

    /// Math italic for variables (New York italic, like the original's serif x and y).
    func italic(_ size: CGFloat) -> CTFont {
        font("i", size) {
            let base = UIFont.systemFont(ofSize: size, weight: .regular).fontDescriptor
            let serif = base.withDesign(.serif) ?? base
            let italic = serif.withSymbolicTraits(.traitItalic) ?? serif
            return UIFont(descriptor: italic, size: size)
        }
    }

    func serif(_ size: CGFloat) -> CTFont {
        font("s", size) {
            let base = UIFont.systemFont(ofSize: size, weight: .regular).fontDescriptor
            return UIFont(descriptor: base.withDesign(.serif) ?? base, size: size)
        }
    }

    private func font(_ kind: String, _ size: CGFloat, make: () -> UIFont) -> CTFont {
        let key = "\(kind)\(Int((size * 4).rounded()))"
        if let f = cache[key] { return f }
        let f = make() as CTFont
        cache[key] = f
        return f
    }
}

/// TeX-inspired box layout of `MathRow`s.
struct MathLayoutEngine {
    var style: MathStyle
    let fonts = MathFonts.shared

    init(style: MathStyle) {
        self.style = style
    }

    // MARK: Text

    func textBox(_ string: String, font: CTFont, ink: MathInk = .primary, leftPad: CGFloat = 0, rightPad: CGFloat = 0) -> MathBox {
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorFromContextAttributeName as String): true,
        ]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: string, attributes: attributes))
        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        var leading: CGFloat = 0
        let width = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, &leading))
        var box = MathBox()
        box.width = width + leftPad + rightPad
        // Tighter vertical metrics than the font's line metrics make fractions compact.
        let size = CTFontGetSize(font)
        box.ascent = min(ascent, size * 0.78)
        box.descent = min(descent, size * 0.24)
        box.items = [.text(line, origin: CGPoint(x: leftPad, y: 0), ink: ink)]
        return box
    }

    /// Height of the math axis (centre of operators and fraction bars) above the baseline.
    func axis(_ size: CGFloat) -> CGFloat { size * 0.27 }

    // MARK: Rows

    /// Lays out a row. `path` addresses it for caret slots; `size` is the font size.
    func layoutRow(_ row: MathRow, path: [MathCursor.Step], size: CGFloat) -> MathBox {
        if row.nodes.isEmpty {
            var box = MathBox()
            if style.showPlaceholders {
                let w = size * 0.62
                let h = size * 0.78
                box.width = w + size * 0.08
                box.ascent = h * 0.82
                box.descent = h * 0.18
                box.items = [.placeholder(CGRect(x: size * 0.04, y: -box.ascent, width: w, height: h))]
            } else {
                box.ascent = size * 0.5
                box.descent = size * 0.1
            }
            box.carets = [CaretSlot(path: path, index: 0, x: box.width / 2, top: -box.ascent, bottom: box.descent)]
            return box
        }

        // 1) Lay out every node (parentheses get sized afterwards).
        var boxes: [MathBox?] = Array(repeating: nil, count: row.nodes.count)
        for (i, node) in row.nodes.enumerated() {
            if case .symbol(.leftParenthesis) = node { continue }
            if case .symbol(.rightParenthesis) = node { continue }
            if case .power = node { continue }
            if case .subscriptRow = node { continue }
            boxes[i] = layoutNode(node, path: path, index: i, size: size, previous: row.nodes.indices.contains(i - 1) ? row.nodes[i - 1] : nil, next: row.nodes.indices.contains(i + 1) ? row.nodes[i + 1] : nil)
        }
        // 2) Scripts depend on the box they attach to.
        for (i, node) in row.nodes.enumerated() {
            switch node {
            case .power(let exponent):
                let base = i > 0 ? boxes[i - 1] : nil
                boxes[i] = layoutScript(exponent, superscript: true, base: base, path: path + [MathCursor.Step(node: i, slot: 0)], size: size)
            case .subscriptRow(let sub):
                let base = i > 0 ? boxes[i - 1] : nil
                boxes[i] = layoutScript(sub, superscript: false, base: base, path: path + [MathCursor.Step(node: i, slot: 0)], size: size)
            default:
                break
            }
        }
        // 3) Stretchy parentheses: match pairs and size them to their contents.
        var stack: [Int] = []
        var pairs: [Int: Int] = [:]
        for (i, node) in row.nodes.enumerated() {
            if case .symbol(.leftParenthesis) = node { stack.append(i) }
            if case .symbol(.rightParenthesis) = node, let open = stack.popLast() { pairs[open] = i; pairs[i] = open }
        }
        for (i, node) in row.nodes.enumerated() {
            let isLeft: Bool
            switch node {
            case .symbol(.leftParenthesis): isLeft = true
            case .symbol(.rightParenthesis): isLeft = false
            default: continue
            }
            var ascent = size * 0.72
            var descent = size * 0.22
            if let partner = pairs[i] {
                let range = isLeft ? (i + 1)..<partner : (partner + 1)..<i
                for j in range {
                    if let b = boxes[j] { ascent = max(ascent, b.ascent); descent = max(descent, b.descent) }
                }
            }
            boxes[i] = parenthesis(left: isLeft, ascent: ascent + size * 0.04, descent: descent + size * 0.04, size: size, ghost: pairs[i] == nil && !isLeft)
        }

        // 4) Place horizontally on the baseline.
        var result = MathBox()
        var x: CGFloat = 0
        for (i, maybeBox) in boxes.enumerated() {
            guard let box = maybeBox else { continue }
            result.carets.append(CaretSlot(path: path, index: i, x: x, top: -max(box.ascent, size * 0.75), bottom: max(box.descent, size * 0.2)))
            result.append(box, at: CGPoint(x: x, y: 0))
            result.ascent = max(result.ascent, box.ascent)
            result.descent = max(result.descent, box.descent)
            x += box.width
        }
        result.width = x
        result.carets.append(CaretSlot(path: path, index: row.nodes.count, x: x, top: -max(result.ascent, size * 0.75), bottom: max(result.descent, size * 0.2)))
        return result
    }

    // MARK: Nodes

    private func operatorSpacing(_ symbol: MathSymbol, previous: MathNode?) -> (CGFloat, CGFloat) {
        // Unary minus/plus (at the start or after an operator or "(") gets no spacing.
        let unary: Bool = {
            guard symbol == .minus || symbol == .plus || symbol == .plusMinus else { return false }
            guard let previous else { return true }
            if case .symbol(let s) = previous { return s.isOperator || s == .leftParenthesis }
            return false
        }()
        if unary { return (0, 0) }
        switch symbol {
        case .plus, .minus, .times, .divide, .plusMinus, .crossProduct: return (0.2, 0.2)
        case .equals, .less, .greater, .lessOrEqual, .greaterOrEqual, .notEqual: return (0.28, 0.28)
        case .comma: return (0, 0.25)
        default: return (0, 0)
        }
    }

    func layoutNode(_ node: MathNode, path: [MathCursor.Step], index: Int, size: CGFloat, previous: MathNode?, next: MathNode?) -> MathBox {
        func slotPath(_ slot: Int) -> [MathCursor.Step] { path + [MathCursor.Step(node: index, slot: slot)] }
        switch node {
        case .symbol(let s):
            let (l, r) = operatorSpacing(s, previous: previous)
            switch s {
            case .variable(let name):
                let display = MathSymbol.displayName(name)
                // Single letters (x, y, a, ω, v₀) in math italic, longer user names upright.
                let font = display.count <= 2 ? fonts.italic(size) : fonts.regular(size)
                return textBox(display, font: font, rightPad: size * 0.03)
            case .constant(.pi):
                return textBox("π", font: fonts.italic(size))
            case .constant(.e):
                return textBox("e", font: fonts.italic(size))
            case .constant(.i):
                return textBox("i", font: fonts.italic(size))
            case .ans:
                return textBox("Ans", font: fonts.regular(size * 0.86), ink: .accent)
            case .exponent10:
                return textBox("ᴇ", font: fonts.regular(size * 0.9), ink: .secondary)
            case .transposeMark:
                let t = textBox("T", font: fonts.regular(max(size * 0.62, style.fontSize * 0.4)), rightPad: size * 0.04)
                var raised = MathBox()
                raised.append(t, at: CGPoint(x: size * 0.02, y: -size * 0.42))
                raised.width = t.width + size * 0.02
                raised.ascent = size * 0.42 + t.ascent
                raised.descent = 0
                return raised
            default:
                let text = s == .constant(.i) ? style.imaginaryUnit : s.text(multiplication: style.multiplication, decimalSeparator: style.decimalSeparator)
                let font = s.isOperator ? fonts.light(size) : fonts.regular(size)
                return textBox(text, font: font, leftPad: l * size, rightPad: r * size)
            }
        case .fraction(let numerator, let denominator):
            let inner = max(size * 0.82, style.fontSize * 0.55)
            return fraction(layoutRow(numerator, path: slotPath(0), size: inner), layoutRow(denominator, path: slotPath(1), size: inner), size: size)
        case .squareRoot(let radicand):
            return radical(layoutRow(radicand, path: slotPath(0), size: size), index: nil, size: size)
        case .nthRoot(let indexRow, let radicand):
            let idx = layoutRow(indexRow, path: slotPath(0), size: max(size * 0.55, style.fontSize * 0.4))
            return radical(layoutRow(radicand, path: slotPath(1), size: size), index: idx, size: size)
        case .absoluteValue(let content):
            return fenced(layoutRow(content, path: slotPath(0), size: size), size: size, kind: .bars)
        case .function(let f, let argument):
            let name = style.slovenianNames ? f.slovenianName : f.internationalName
            var box = textBox(name, font: fonts.regular(size), rightPad: size * 0.04)
            if f.arity == 0 { return box }
            let arg = fenced(layoutRow(argument, path: slotPath(0), size: size), size: size, kind: .parentheses)
            box.ascent = max(box.ascent, arg.ascent)
            box.descent = max(box.descent, arg.descent)
            box.append(arg, at: CGPoint(x: box.width, y: 0))
            box.width += arg.width
            return box
        case .function2(let f, let a, let b):
            let name = f == .idiv ? "int÷" : (style.slovenianNames ? f.slovenianName : f.internationalName)
            var box = textBox(name, font: fonts.regular(size), rightPad: size * 0.04)
            var inner = layoutRow(a, path: slotPath(0), size: size)
            let sep = textBox(";", font: fonts.regular(size), rightPad: size * 0.2)
            inner.append(sep, at: CGPoint(x: inner.width, y: 0))
            inner.width += sep.width
            let second = layoutRow(b, path: slotPath(1), size: size)
            inner.append(second, at: CGPoint(x: inner.width, y: 0))
            inner.width += second.width
            inner.ascent = max(inner.ascent, second.ascent, sep.ascent)
            inner.descent = max(inner.descent, second.descent, sep.descent)
            let fencedBox = fenced(inner, size: size, kind: .parentheses)
            box.append(fencedBox, at: CGPoint(x: box.width, y: 0))
            box.width += fencedBox.width
            box.ascent = max(box.ascent, fencedBox.ascent)
            box.descent = max(box.descent, fencedBox.descent)
            return box
        case .logarithm(let base, let argument):
            var box = textBox("log", font: fonts.regular(size))
            let sub = layoutRow(base, path: slotPath(0), size: max(size * 0.62, style.fontSize * 0.45))
            box.append(sub, at: CGPoint(x: box.width + size * 0.02, y: size * 0.28))
            box.width += sub.width + size * 0.08
            box.descent = max(box.descent, size * 0.28 + sub.descent)
            let arg = fenced(layoutRow(argument, path: slotPath(1), size: size), size: size, kind: .parentheses)
            box.append(arg, at: CGPoint(x: box.width, y: 0))
            box.width += arg.width
            box.ascent = max(box.ascent, arg.ascent)
            box.descent = max(box.descent, arg.descent)
            return box
        case .derivative(let body, let point):
            let small = size * 0.62
            var d = fraction(textBox("d", font: fonts.italic(small)), textBox("dx", font: fonts.italic(small)), size: size)
            d.width += size * 0.06
            let bodyBox = fenced(layoutRow(body, path: slotPath(0), size: size), size: size, kind: .parentheses)
            d.append(bodyBox, at: CGPoint(x: d.width, y: 0))
            d.width += bodyBox.width
            d.ascent = max(d.ascent, bodyBox.ascent)
            d.descent = max(d.descent, bodyBox.descent)
            if let point {
                // Evaluation bar |ₓ₌ₐ
                let label = textBox("x=", font: fonts.italic(size * 0.55))
                let pointBox = layoutRow(point, path: slotPath(1), size: size * 0.55)
                let barHeight = d.ascent + d.descent
                var bar = MathBox()
                bar.width = size * 0.12
                let barPath = CGPath(rect: CGRect(x: size * 0.04, y: -d.ascent, width: size * 0.05, height: barHeight), transform: nil)
                bar.items = [.fill(barPath, ink: .primary)]
                d.append(bar, at: CGPoint(x: d.width, y: 0))
                d.width += bar.width
                d.append(label, at: CGPoint(x: d.width, y: d.descent * 0.9))
                d.append(pointBox, at: CGPoint(x: d.width + label.width, y: d.descent * 0.9))
                d.width += label.width + pointBox.width
                d.descent = max(d.descent, d.descent * 0.9 + pointBox.descent)
            }
            return d
        case .integral(let lower, let upper, let body):
            return bigOperator("∫", lower: layoutRow(lower, path: slotPath(0), size: size * 0.6),
                               upper: layoutRow(upper, path: slotPath(1), size: size * 0.6),
                               body: layoutRow(body, path: slotPath(2), size: size), size: size, limitsBeside: true, trailing: "dx")
        case .summation(let lower, let upper, let body):
            var lowerBox = textBox("n=", font: fonts.italic(size * 0.6))
            let lowerRow = layoutRow(lower, path: slotPath(0), size: size * 0.6)
            lowerBox.append(lowerRow, at: CGPoint(x: lowerBox.width, y: 0))
            lowerBox.width += lowerRow.width
            lowerBox.ascent = max(lowerBox.ascent, lowerRow.ascent)
            lowerBox.descent = max(lowerBox.descent, lowerRow.descent)
            return bigOperator("Σ", lower: lowerBox, upper: layoutRow(upper, path: slotPath(1), size: size * 0.6),
                               body: layoutRow(body, path: slotPath(2), size: size), size: size, limitsBeside: false, trailing: nil)
        case .limit(let point, let body, let direction):
            var lim = textBox("lim", font: fonts.regular(size))
            var sub = textBox("x→", font: fonts.italic(size * 0.58))
            let pointBox = layoutRow(point, path: slotPath(0), size: size * 0.58)
            sub.append(pointBox, at: CGPoint(x: sub.width, y: 0))
            sub.width += pointBox.width
            if direction != .both {
                let mark = textBox(direction == .left ? "⁻" : "⁺", font: fonts.regular(size * 0.58))
                sub.append(mark, at: CGPoint(x: sub.width, y: 0))
                sub.width += mark.width
            }
            sub.ascent = max(sub.ascent, pointBox.ascent)
            sub.descent = max(sub.descent, pointBox.descent)
            let column = max(lim.width, sub.width)
            var box = MathBox()
            box.append(lim, at: CGPoint(x: (column - lim.width) / 2, y: 0))
            box.append(sub, at: CGPoint(x: (column - sub.width) / 2, y: lim.descent + sub.ascent + size * 0.06))
            box.width = column + size * 0.15
            box.ascent = lim.ascent
            box.descent = lim.descent + sub.ascent + sub.descent + size * 0.06
            lim = box
            let bodyBox = layoutRow(body, path: slotPath(1), size: size)
            lim.append(bodyBox, at: CGPoint(x: lim.width, y: 0))
            lim.width += bodyBox.width
            lim.ascent = max(lim.ascent, bodyBox.ascent)
            lim.descent = max(lim.descent, bodyBox.descent)
            return lim
        case .binomial(let top, let bottom):
            let inner = max(size * 0.82, style.fontSize * 0.55)
            var stacked = fraction(layoutRow(top, path: slotPath(0), size: inner), layoutRow(bottom, path: slotPath(1), size: inner), size: size, drawBar: false)
            stacked.width += 0
            return fenced(stacked, size: size, kind: .parentheses)
        case .matrix(var rows, var columns, let cells):
            // Malformed data (e.g. pasted) is shown as a single row instead of crashing.
            if rows <= 0 || columns <= 0 || cells.count != rows * columns {
                rows = 1
                columns = max(1, cells.count)
            }
            var cellBoxes: [MathBox] = []
            for (k, cell) in cells.enumerated() { cellBoxes.append(layoutRow(cell, path: slotPath(k), size: size)) }
            if cellBoxes.isEmpty { cellBoxes = [layoutRow(MathRow(), path: slotPath(0), size: size)] }
            var box = grid(cellBoxes, rows: rows, columns: columns, size: size, columnGap: size * 0.62)
            let bracketed = brackets(box, size: size)
            box = bracketed.box
            box.grids.append(MathGridFrame(path: path, index: index, rect: bracketed.gridRect,
                                           rows: rows, columns: columns,
                                           cellSize: CGSize(width: bracketed.gridRect.width / CGFloat(columns), height: bracketed.gridRect.height / CGFloat(rows))))
            return box
        case .piecewise(let cells):
            let rows = cells.count / 2
            var cellBoxes: [MathBox] = []
            for (k, cell) in cells.enumerated() {
                if k % 2 == 1, cell.isEmpty, !style.showPlaceholders {
                    cellBoxes.append(textBox("sicer", font: fonts.regular(size * 0.86), ink: .secondary))
                } else {
                    cellBoxes.append(layoutRow(cell, path: slotPath(k), size: size))
                }
            }
            let inner = grid(cellBoxes, rows: rows, columns: 2, size: size, columnGap: size * 0.9, alignLeading: true)
            var box = MathBox()
            let brace = curlyBrace(height: inner.height + size * 0.2, size: size)
            let shift = -inner.ascent - size * 0.1
            box.append(brace, at: CGPoint(x: 0, y: shift + brace.ascent))
            box.append(inner, at: CGPoint(x: brace.width + size * 0.1, y: 0))
            box.width = brace.width + size * 0.1 + inner.width + size * 0.1
            box.ascent = inner.ascent + size * 0.1
            box.descent = inner.descent + size * 0.1
            box.grids.append(MathGridFrame(path: path, index: index,
                                           rect: CGRect(x: brace.width, y: -box.ascent, width: inner.width + size * 0.2, height: box.height),
                                           rows: rows, columns: 2,
                                           cellSize: CGSize(width: inner.width / 2, height: inner.height / CGFloat(max(1, rows)))))
            return box
        case .bigProduct(let lower, let upper, let body):
            var lowerBox = textBox("n=", font: fonts.italic(size * 0.6))
            let lowerRow = layoutRow(lower, path: slotPath(0), size: size * 0.6)
            lowerBox.append(lowerRow, at: CGPoint(x: lowerBox.width, y: 0))
            lowerBox.width += lowerRow.width
            lowerBox.ascent = max(lowerBox.ascent, lowerRow.ascent)
            lowerBox.descent = max(lowerBox.descent, lowerRow.descent)
            return bigOperator("Π", lower: lowerBox, upper: layoutRow(upper, path: slotPath(1), size: size * 0.6),
                               body: layoutRow(body, path: slotPath(2), size: size), size: size, limitsBeside: false, trailing: nil)
        case .vectorArrow(let content):
            let inner = layoutRow(content, path: slotPath(0), size: size)
            var box = MathBox()
            box.append(inner, at: .zero)
            let stroke = max(1, size * 0.05)
            let y = -inner.ascent - size * 0.12
            let x0 = size * 0.04, x1 = max(inner.width - size * 0.02, size * 0.4)
            let arrow = CGMutablePath()
            arrow.move(to: CGPoint(x: x0, y: y))
            arrow.addLine(to: CGPoint(x: x1, y: y))
            arrow.move(to: CGPoint(x: x1 - size * 0.14, y: y - size * 0.09))
            arrow.addLine(to: CGPoint(x: x1, y: y))
            arrow.addLine(to: CGPoint(x: x1 - size * 0.14, y: y + size * 0.09))
            box.items.append(.stroke(arrow, width: stroke, ink: .primary))
            box.width = max(inner.width, x1 + size * 0.04)
            box.ascent = inner.ascent + size * 0.24
            box.descent = inner.descent
            return box
        case .functionN(let f, let args):
            let name = style.slovenianNames ? f.slovenianName : f.internationalName
            var box = textBox(name, font: fonts.regular(size), rightPad: size * 0.04)
            var inner = MathBox()
            for (k, arg) in args.enumerated() {
                if k > 0 {
                    let sep = textBox(";", font: fonts.regular(size), rightPad: size * 0.2)
                    inner.append(sep, at: CGPoint(x: inner.width, y: 0))
                    inner.width += sep.width
                    inner.ascent = max(inner.ascent, sep.ascent)
                    inner.descent = max(inner.descent, sep.descent)
                }
                let a = layoutRow(arg, path: slotPath(k), size: size)
                inner.append(a, at: CGPoint(x: inner.width, y: 0))
                inner.width += a.width
                inner.ascent = max(inner.ascent, a.ascent)
                inner.descent = max(inner.descent, a.descent)
            }
            let fencedBox = fenced(inner, size: size, kind: .parentheses)
            box.append(fencedBox, at: CGPoint(x: box.width, y: 0))
            box.width += fencedBox.width
            box.ascent = max(box.ascent, fencedBox.ascent)
            box.descent = max(box.descent, fencedBox.descent)
            return box
        case .partialDerivative(let variable, let body):
            let small = size * 0.62
            var denominator = textBox("∂", font: fonts.italic(small))
            let v = layoutRow(variable, path: slotPath(0), size: small)
            denominator.append(v, at: CGPoint(x: denominator.width, y: 0))
            denominator.width += v.width
            denominator.ascent = max(denominator.ascent, v.ascent)
            denominator.descent = max(denominator.descent, v.descent)
            var d = fraction(textBox("∂", font: fonts.italic(small)), denominator, size: size)
            d.width += size * 0.06
            let bodyBox = fenced(layoutRow(body, path: slotPath(1), size: size), size: size, kind: .parentheses)
            d.append(bodyBox, at: CGPoint(x: d.width, y: 0))
            d.width += bodyBox.width
            d.ascent = max(d.ascent, bodyBox.ascent)
            d.descent = max(d.descent, bodyBox.descent)
            return d
        case .poweredFunction(let f, let exponent, let argument):
            let name = style.slovenianNames ? f.slovenianName : f.internationalName
            var box = textBox(name, font: fonts.regular(size))
            let script = layoutScript(exponent, superscript: true, base: box, path: slotPath(0), size: size)
            box.append(script, at: CGPoint(x: box.width, y: 0))
            box.width += script.width + size * 0.04
            box.ascent = max(box.ascent, script.ascent)
            let arg = fenced(layoutRow(argument, path: slotPath(1), size: size), size: size, kind: .parentheses)
            box.append(arg, at: CGPoint(x: box.width, y: 0))
            box.width += arg.width
            box.ascent = max(box.ascent, arg.ascent)
            box.descent = max(box.descent, arg.descent)
            return box
        case .power, .subscriptRow:
            return MathBox()
        }
    }

    /// Lays out cells (row-major) on a grid centred on the math axis.
    func grid(_ cells: [MathBox], rows: Int, columns: Int, size: CGFloat, columnGap: CGFloat, alignLeading: Bool = false) -> MathBox {
        var widths = [CGFloat](repeating: 0, count: columns)
        var ascents = [CGFloat](repeating: size * 0.6, count: rows)
        var descents = [CGFloat](repeating: size * 0.18, count: rows)
        for r in 0..<rows {
            for c in 0..<columns {
                let b = cells[r * columns + c]
                widths[c] = max(widths[c], b.width)
                ascents[r] = max(ascents[r], b.ascent)
                descents[r] = max(descents[r], b.descent)
            }
        }
        let rowGap = size * 0.28
        let totalHeight = zip(ascents, descents).reduce(0) { $0 + $1.0 + $1.1 } + rowGap * CGFloat(max(0, rows - 1))
        let totalWidth = widths.reduce(0, +) + columnGap * CGFloat(max(0, columns - 1))
        let axisY = -axis(size)
        var box = MathBox()
        var y = axisY - totalHeight / 2
        for r in 0..<rows {
            let baseline = y + ascents[r]
            var x: CGFloat = 0
            for c in 0..<columns {
                let b = cells[r * columns + c]
                let offset = alignLeading ? 0 : (widths[c] - b.width) / 2
                box.append(b, at: CGPoint(x: x + offset, y: baseline))
                x += widths[c] + columnGap
            }
            y = baseline + descents[r] + rowGap
        }
        box.width = totalWidth
        box.ascent = -(axisY - totalHeight / 2)
        box.descent = axisY + totalHeight / 2
        return box
    }

    /// Square brackets around a grid; returns the box and the grid's rectangle inside it.
    func brackets(_ content: MathBox, size: CGFloat) -> (box: MathBox, gridRect: CGRect) {
        let pad = size * 0.12
        let ascent = content.ascent + pad
        let descent = content.descent + pad
        let width = size * 0.3
        let stroke = max(1.2, size * 0.055)
        func bracket(left: Bool) -> MathBox {
            let path = CGMutablePath()
            let inner = left ? width * 0.85 : width * 0.15
            let outer = left ? width * 0.3 : width * 0.7
            path.move(to: CGPoint(x: inner, y: -ascent))
            path.addLine(to: CGPoint(x: outer, y: -ascent))
            path.addLine(to: CGPoint(x: outer, y: descent))
            path.addLine(to: CGPoint(x: inner, y: descent))
            var b = MathBox()
            b.items = [.stroke(path, width: stroke, ink: .primary)]
            b.width = width
            b.ascent = ascent
            b.descent = descent
            return b
        }
        var box = MathBox()
        box.append(bracket(left: true), at: .zero)
        box.append(content, at: CGPoint(x: width + size * 0.08, y: 0))
        box.append(bracket(left: false), at: CGPoint(x: width + content.width + size * 0.16, y: 0))
        box.width = width * 2 + content.width + size * 0.16
        box.ascent = ascent
        box.descent = descent
        let gridRect = CGRect(x: width, y: -ascent, width: content.width + size * 0.16, height: ascent + descent)
        return (box, gridRect)
    }

    /// A stretchy left curly brace.
    func curlyBrace(height: CGFloat, size: CGFloat) -> MathBox {
        let width = size * 0.42
        let h = height
        let path = CGMutablePath()
        let x0 = width * 0.75, xm = width * 0.38, xt = width * 0.1
        path.move(to: CGPoint(x: x0, y: -h / 2))
        path.addQuadCurve(to: CGPoint(x: xm, y: -h / 2 + h * 0.12), control: CGPoint(x: xm, y: -h / 2))
        path.addLine(to: CGPoint(x: xm, y: -h * 0.08))
        path.addQuadCurve(to: CGPoint(x: xt, y: 0), control: CGPoint(x: xm, y: 0))
        path.addQuadCurve(to: CGPoint(x: xm, y: h * 0.08), control: CGPoint(x: xm, y: 0))
        path.addLine(to: CGPoint(x: xm, y: h / 2 - h * 0.12))
        path.addQuadCurve(to: CGPoint(x: x0, y: h / 2), control: CGPoint(x: xm, y: h / 2))
        var box = MathBox()
        box.items = [.stroke(path, width: max(1.2, size * 0.055), ink: .primary)]
        box.width = width
        box.ascent = h / 2
        box.descent = h / 2
        return box
    }

    // MARK: Building blocks

    func layoutScript(_ row: MathRow, superscript: Bool, base: MathBox?, path: [MathCursor.Step], size: CGFloat) -> MathBox {
        let scriptSize = max(size * 0.66, style.fontSize * 0.42)
        let inner = layoutRow(row, path: path, size: scriptSize)
        var box = MathBox()
        let shift: CGFloat
        if superscript {
            let baseAscent = base?.ascent ?? size * 0.7
            shift = -max(baseAscent - inner.ascent * 0.45, size * 0.38)
        } else {
            shift = max((base?.descent ?? size * 0.2) * 0.6, size * 0.2) + inner.ascent * 0.35
        }
        box.append(inner, at: CGPoint(x: size * 0.03, y: shift))
        box.width = inner.width + size * 0.06
        box.ascent = max(0, -shift + inner.ascent)
        box.descent = max(0, shift + inner.descent)
        return box
    }

    func fraction(_ numerator: MathBox, _ denominator: MathBox, size: CGFloat, drawBar: Bool = true) -> MathBox {
        let thickness = max(1, size * 0.055)
        let gap = size * 0.12
        let padding = size * 0.12
        let width = max(numerator.width, denominator.width) + 2 * padding
        let axisY = -axis(size)
        var box = MathBox()
        box.width = width + size * 0.08
        let numBaseline = axisY - thickness / 2 - gap - numerator.descent
        let denBaseline = axisY + thickness / 2 + gap + denominator.ascent
        box.append(numerator, at: CGPoint(x: size * 0.04 + (width - numerator.width) / 2, y: numBaseline))
        box.append(denominator, at: CGPoint(x: size * 0.04 + (width - denominator.width) / 2, y: denBaseline))
        if drawBar {
            box.items.append(.fill(CGPath(rect: CGRect(x: size * 0.04, y: axisY - thickness / 2, width: width, height: thickness), transform: nil), ink: .primary))
        }
        box.ascent = -numBaseline + numerator.ascent
        box.descent = denBaseline + denominator.descent
        return box
    }

    func radical(_ content: MathBox, index: MathBox?, size: CGFloat) -> MathBox {
        let thickness = max(1.1, size * 0.055)
        let gap = size * 0.1
        let top = content.ascent + gap + thickness
        let bottom = content.descent
        let signWidth = size * 0.55
        let indexOffset = index.map { max(0, $0.width - signWidth * 0.45) } ?? 0
        let path = CGMutablePath()
        // Surd: small tick, long down-stroke, up-stroke, then the vinculum over the content.
        let x0 = indexOffset
        path.move(to: CGPoint(x: x0, y: -top * 0.42))
        path.addLine(to: CGPoint(x: x0 + signWidth * 0.22, y: -top * 0.5))
        path.addLine(to: CGPoint(x: x0 + signWidth * 0.52, y: bottom))
        path.addLine(to: CGPoint(x: x0 + signWidth * 0.92, y: -top))
        path.addLine(to: CGPoint(x: x0 + signWidth + content.width + size * 0.1, y: -top))
        var box = MathBox()
        box.items.append(.stroke(path, width: thickness, ink: .primary))
        if let index {
            box.append(index, at: CGPoint(x: 0, y: -top * 0.52 - index.descent - size * 0.02))
        }
        box.append(content, at: CGPoint(x: x0 + signWidth + size * 0.04, y: 0))
        box.width = x0 + signWidth + content.width + size * 0.16
        box.ascent = max(top + thickness, index.map { top * 0.52 + $0.height } ?? 0)
        box.descent = max(bottom, content.descent) + thickness
        return box
    }

    enum Fence { case parentheses, bars }

    func fenced(_ content: MathBox, size: CGFloat, kind: Fence) -> MathBox {
        let ascent = max(content.ascent, size * 0.72) + size * 0.04
        let descent = max(content.descent, size * 0.22) + size * 0.04
        let left = kind == .parentheses ? parenthesis(left: true, ascent: ascent, descent: descent, size: size, ghost: false) : bar(ascent: ascent, descent: descent, size: size)
        let right = kind == .parentheses ? parenthesis(left: false, ascent: ascent, descent: descent, size: size, ghost: false) : bar(ascent: ascent, descent: descent, size: size)
        var box = MathBox()
        box.append(left, at: .zero)
        box.append(content, at: CGPoint(x: left.width, y: 0))
        box.append(right, at: CGPoint(x: left.width + content.width, y: 0))
        box.width = left.width + content.width + right.width
        box.ascent = ascent
        box.descent = descent
        return box
    }

    func parenthesis(left: Bool, ascent: CGFloat, descent: CGFloat, size: CGFloat, ghost: Bool) -> MathBox {
        let height = ascent + descent
        let width = max(size * 0.3, min(size * 0.5, height * 0.18))
        let stroke = max(1.2, size * 0.06)
        let path = CGMutablePath()
        let inner = left ? width * 0.78 : width * 0.22
        let outer = left ? width * 0.18 : width * 0.82
        path.move(to: CGPoint(x: inner, y: -ascent))
        path.addQuadCurve(to: CGPoint(x: inner, y: descent), control: CGPoint(x: outer - (left ? width * 0.25 : -width * 0.25), y: (descent - ascent) / 2))
        var box = MathBox()
        box.items = [.stroke(path, width: stroke, ink: ghost ? .secondary : .primary)]
        box.width = width
        box.ascent = ascent
        box.descent = descent
        return box
    }

    func bar(ascent: CGFloat, descent: CGFloat, size: CGFloat) -> MathBox {
        let width = size * 0.22
        var box = MathBox()
        box.items = [.fill(CGPath(rect: CGRect(x: width * 0.42, y: -ascent, width: max(1.1, size * 0.055), height: ascent + descent), transform: nil), ink: .primary)]
        box.width = width
        box.ascent = ascent
        box.descent = descent
        return box
    }

    func bigOperator(_ symbol: String, lower: MathBox, upper: MathBox, body: MathBox, size: CGFloat, limitsBeside: Bool, trailing: String?) -> MathBox {
        let opSize = size * (limitsBeside ? 1.7 : 1.45)
        let op = textBox(symbol, font: fonts.serif(opSize))
        // Centre the operator on the math axis.
        let shift = (op.ascent - op.descent) / 2 - axis(size)
        var box = MathBox()
        if limitsBeside {
            box.append(op, at: CGPoint(x: 0, y: shift))
            let limitsX = op.width * 0.86
            box.append(upper, at: CGPoint(x: limitsX, y: -op.ascent + shift + upper.ascent * 0.9))
            box.append(lower, at: CGPoint(x: limitsX - size * 0.12, y: op.descent + shift + lower.descent * 0.2))
            let limitsWidth = max(upper.width, lower.width - size * 0.12)
            box.width = limitsX + limitsWidth + size * 0.12
            box.ascent = max(op.ascent - shift, op.ascent - shift - upper.ascent * 0.9 + upper.ascent)
            box.descent = max(op.descent + shift, op.descent + shift + lower.descent * 0.2 + lower.descent)
        } else {
            let column = max(op.width, upper.width, lower.width)
            box.append(upper, at: CGPoint(x: (column - upper.width) / 2, y: -op.ascent + shift - size * 0.05 - upper.descent))
            box.append(op, at: CGPoint(x: (column - op.width) / 2, y: shift))
            box.append(lower, at: CGPoint(x: (column - lower.width) / 2, y: op.descent + shift + size * 0.05 + lower.ascent))
            box.width = column + size * 0.12
            box.ascent = op.ascent - shift + size * 0.05 + upper.height
            box.descent = op.descent + shift + size * 0.05 + lower.height
        }
        box.append(body, at: CGPoint(x: box.width, y: 0))
        box.width += body.width
        box.ascent = max(box.ascent, body.ascent)
        box.descent = max(box.descent, body.descent)
        if let trailing {
            let d = textBox(" " + trailing, font: fonts.italic(size))
            box.append(d, at: CGPoint(x: box.width, y: 0))
            box.width += d.width
        }
        return box
    }

    // MARK: Entry points

    func layout(_ row: MathRow) -> MathBox {
        layoutRow(row, path: [], size: style.fontSize)
    }
}

nonisolated extension MathBox {
    /// Nearest caret slot to a point in box coordinates (deeper slots win when the point is inside them).
    func caretSlot(near point: CGPoint) -> CaretSlot? {
        let inside = carets.filter { point.y >= $0.top - 4 && point.y <= $0.bottom + 4 }
        let candidates = inside.isEmpty ? carets : inside
        return candidates.min { a, b in
            let da = abs(a.x - point.x) - CGFloat(a.depth) * 2
            let db = abs(b.x - point.x) - CGFloat(b.depth) * 2
            return da < db
        }
    }

    func caret(for cursor: MathCursor) -> CaretSlot? {
        carets.first { $0.path == cursor.path && $0.index == cursor.index }
    }
}
