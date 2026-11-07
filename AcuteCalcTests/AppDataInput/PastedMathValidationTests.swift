import AcuteCore
import Foundation
import Testing
@testable import AcuteCalc

/// Health audit critic:2: structured math from the pasteboard (com.markplacer.acutecalc.math, a type any app
/// can write) went into the editor unchecked. A matrix of −1 rows trapped in the editor's VoiceOver label, which
/// its body builds on every render, and a size whose product overflows Int trapped in the layout.
@MainActor
@Suite struct PastedMathValidationTests {
    let style = MathStyle(decimalSeparator: ",")

    /// The clipboard item with one matrix of empty cells, in the keys SE-0295 gives it, decoded with JSONDecoder
    /// as the CodableRepresentation of MathClipboardItem decodes it.
    private func pasteboardItem(rows: Int, columns: Int, cells: Int) throws -> MathClipboardItem {
        let list = Array(repeating: #"{"nodes":[]}"#, count: cells).joined(separator: ",")
        let json = #"{"row":{"nodes":[{"matrix":{"rows":\#(rows),"columns":\#(columns),"cells":[\#(list)]}}]}}"#
        return try JSONDecoder().decode(MathClipboardItem.self, from: Data(json.utf8))
    }

    @Test func aMalformedMatrixFromThePasteboardIsNotPasted() throws {
        for (rows, columns, count) in [(-1, 1, 1), (2, 2, 1), (1 << 62, 2, 2)] {
            let item = try pasteboardItem(rows: rows, columns: columns, cells: count)
            // What ⌘V (pasteDestination) and the edit bar's PasteButton do with it.
            var editor = MathEditor(root: .text("1+"))
            let unchanged = editor
            editor.paste(item.row)
            #expect(editor == unchanged, "\(rows) × \(columns), \(count) cells")
            // A row of an older version that holds it is read and laid out as one row of its cells.
            let label = MathAccessibility.label(item.row, style: style)
            #expect(label == "[[" + Array(repeating: "", count: count).joined(separator: "; ") + "]]")
            let box = MathLayoutEngine(style: style).layout(item.row)
            #expect(box.width > 0)
        }
    }
}
