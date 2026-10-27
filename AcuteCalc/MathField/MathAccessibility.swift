import AcuteCore
import Foundation

/// VoiceOver text for math. The structure follows `MathRowConverter.plainText`, which stays the
/// clipboard and parser format, but numbers, the multiplication sign, the imaginary unit, argument
/// separators and function names are written the way the screen shows them (decimal comma, tg or
/// tan …), not as machine text with a decimal point and English names.
enum MathAccessibility {
    /// The display settings that matter for speech.
    static func style(_ settings: AppSettings) -> MathStyle {
        MathStyle(multiplication: settings.multiplication.symbol, decimalSeparator: settings.decimalSeparator,
                  slovenianNames: settings.notation == .slovenian, showPlaceholders: false, imaginaryUnit: settings.imaginaryUnit)
    }

    static func label(_ row: MathRow, style: MathStyle) -> String {
        row.nodes.map { text(for: $0, style: style) }.joined()
    }

    /// 1,5·10⁻⁸ (mantissa, ·10 and a raised exponent on screen) as "1,5 krat 10 na −8".
    static func number(_ formatted: FormattedNumber) -> String {
        guard let exponent = formatted.exponent else { return formatted.mantissa }
        return "\(formatted.mantissa) krat 10 na \(String(exponent).replacingOccurrences(of: "-", with: "−"))"
    }

    /// Where the editor's caret is, for VoiceOver: "Kazalec v imenovalcu ulomka, na koncu".
    static func caretDescription(_ editor: MathEditor, style: MathStyle) -> String {
        if let selected = editor.selectedRow { return "Izbrano: " + label(selected, style: style) }
        let row = editor.currentRow
        let index = editor.cursor.index
        let atRoot = editor.cursor.path.isEmpty
        let position: String = if row.isEmpty {
            atRoot ? "v praznem izrazu" : "prazno polje"
        } else if index <= 0 {
            atRoot ? "na začetku izraza" : "na začetku"
        } else if index >= row.nodes.count {
            atRoot ? "na koncu izraza" : "na koncu"
        } else {
            "za " + label(MathRow([row.nodes[index - 1]]), style: style)
        }
        guard let step = editor.cursor.path.last, let parent = editor.subrow(at: Array(editor.cursor.path.dropLast())),
              step.node < parent.nodes.count else { return "Kazalec " + position }
        return "Kazalec " + slotDescription(parent.nodes[step.node], slot: step.slot, style: style) + ", " + position
    }

    /// The slot of a structure that holds the caret: "v imenovalcu ulomka", "pod korenom" …
    private static func slotDescription(_ node: MathNode, slot: Int, style: MathStyle) -> String {
        func name(_ f: MathFunction) -> String { functionName(f, style: style) }
        func bounds(_ structure: String, body: String) -> String {
            switch slot {
            case 0: "v spodnji meji \(structure)"
            case 1: "v zgornji meji \(structure)"
            default: body
            }
        }
        switch node {
        case .symbol: return "v izrazu"
        case .fraction: return slot == 0 ? "v števcu ulomka" : "v imenovalcu ulomka"
        case .power: return "v eksponentu"
        case .subscriptRow: return "v indeksu"
        case .squareRoot: return "pod korenom"
        case .nthRoot: return slot == 0 ? "v stopnji korena" : "pod korenom"
        case .absoluteValue: return "v absolutni vrednosti"
        case .function(let f, _): return "v argumentu funkcije \(name(f))"
        case .logarithm: return slot == 0 ? "v osnovi logaritma" : "v argumentu logaritma"
        case .derivative: return slot == 0 ? "v odvajanem izrazu" : "v točki odvoda"
        case .integral: return bounds("integrala", body: "v integrandu")
        case .summation: return bounds("vsote", body: "v členu vsote")
        case .bigProduct: return bounds("produkta", body: "v faktorju produkta")
        case .binomial: return slot == 0 ? "zgoraj v binomskem simbolu" : "spodaj v binomskem simbolu"
        case .function2(let f, _, _), .functionN(let f, _): return "v \(slot + 1). argumentu funkcije \(name(f))"
        case .limit: return slot == 0 ? "v točki limite" : "v izrazu limite"
        case .matrix(_, let columns, _):
            let c = max(1, columns)
            return "v matriki, vrstica \(slot / c + 1), stolpec \(slot % c + 1)"
        case .piecewise:
            return "v odsekoma definirani funkciji, vrstica \(slot / 2 + 1), " + (slot % 2 == 0 ? "vrednost" : "pogoj")
        case .vectorArrow: return "pod puščico vektorja"
        case .partialDerivative: return slot == 0 ? "v spremenljivki parcialnega odvoda" : "v odvajanem izrazu"
        case .poweredFunction(let f, _, _): return slot == 0 ? "v eksponentu funkcije \(name(f))" : "v argumentu funkcije \(name(f))"
        }
    }

    static func functionName(_ f: MathFunction, style: MathStyle) -> String {
        style.slovenianNames ? f.slovenianName : f.internationalName
    }

    private static func text(for node: MathNode, style: MathStyle) -> String {
        func t(_ row: MathRow) -> String { label(row, style: style) }
        func list(_ rows: [MathRow]) -> String { rows.map(t).joined(separator: "; ") }
        func name(_ f: MathFunction) -> String { functionName(f, style: style) }
        switch node {
        case .symbol(let s):
            return s == .constant(.i) ? style.imaginaryUnit : s.text(multiplication: style.multiplication, decimalSeparator: style.decimalSeparator)
        case .fraction(let n, let d): return "(\(t(n)))/(\(t(d)))"
        case .power(let e): return "^(\(t(e)))"
        case .subscriptRow(let s): return "_\(t(s))"
        case .squareRoot(let r): return "√(\(t(r)))"
        case .nthRoot(let i, let r): return "root(\(t(i)); \(t(r)))"
        case .absoluteValue(let r): return "|\(t(r))|"
        case .function(let f, let a): return f.arity == 0 ? name(f) : "\(name(f))(\(t(a)))"
        case .logarithm(let b, let a): return "log(\(t(b)); \(t(a)))"
        case .derivative(let b, let p): return "d/dx(\(t(b)))" + (p.map { "|x=\(t($0))" } ?? "")
        case .integral(let l, let u, let b):
            return l.isEmpty && u.isEmpty ? "∫(\(t(b)))dx" : "∫[\(t(l)); \(t(u))](\(t(b)))dx"
        case .summation(let l, let u, let b): return "Σ[n=\(t(l)); \(t(u))](\(t(b)))"
        case .binomial(let n, let k): return "C(\(t(n)); \(t(k)))"
        case .function2(let f, let a, let b): return "\(name(f))(\(t(a)); \(t(b)))"
        case .limit(let p, let b, _): return "lim[x→\(t(p))](\(t(b)))"
        case .matrix(let rows, let columns, let cells):
            let lines = (0..<rows).map { r in
                "[" + (0..<columns).map { c in r * columns + c < cells.count ? t(cells[r * columns + c]) : "" }.joined(separator: "; ") + "]"
            }
            return "[" + lines.joined(separator: "; ") + "]"
        case .piecewise(let cells): return "piecewise(" + cells.map(t).filter { !$0.isEmpty }.joined(separator: "; ") + ")"
        case .bigProduct(let l, let u, let b): return "Π[n=\(t(l)); \(t(u))](\(t(b)))"
        case .vectorArrow(let r): return t(r) + "\u{20D7}"
        case .functionN(let f, let args): return "\(name(f))(\(list(args)))"
        case .partialDerivative(let v, let b): return "∂/∂\(t(v))(\(t(b)))"
        case .poweredFunction(let f, let e, let a): return "\(name(f))^(\(t(e)))(\(t(a)))"
        }
    }
}
