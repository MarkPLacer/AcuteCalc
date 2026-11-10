import Foundation
import Testing
@testable import AcuteCore

// MARK: Pasted structured math (health audit critic:2)

@Suite struct AuditPastedMatrixTests {
    /// Matrices another app can put on the pasteboard as com.markplacer.acutecalc.math (any app may write that
    /// type, and SE-0295 gives its keys): −1 rows, 2 × 2 with one cell, no columns, and a size whose product
    /// overflows Int. The editor builds none of them.
    static let malformed: [MathNode] = [
        .matrix(rows: -1, columns: 1, cells: [.text("1")]),
        .matrix(rows: 2, columns: 2, cells: [.text("1")]),
        .matrix(rows: 1, columns: 0, cells: [.text("1")]),
        .matrix(rows: 1 << 62, columns: 2, cells: [.text("1"), .text("2")]),
    ]

    @Test func validMatrixSizes() {
        #expect(MathNode.isValidMatrix(rows: 2, columns: 3, cellCount: 6))
        #expect(MathNode.isValidMatrix(rows: 12, columns: 1, cellCount: 12))
        #expect(!MathNode.isValidMatrix(rows: 2, columns: 2, cellCount: 1))
        #expect(!MathNode.isValidMatrix(rows: 0, columns: 0, cellCount: 0))
        #expect(!MathNode.isValidMatrix(rows: -1, columns: -1, cellCount: 1))
        // 2⁶² · 4 wraps around to 0 cells: only the overflow tells it apart.
        #expect(!MathNode.isValidMatrix(rows: 1 << 62, columns: 4, cellCount: 0))
    }

    @Test(arguments: AuditPastedMatrixTests.malformed)
    func aMalformedMatrixIsNotPasted(matrix: MathNode) {
        // Unfixed, it went into the editor unchecked: −1 rows trapped in the VoiceOver label built on every
        // render, 2 × 2 with one cell on ⌘C, "Kopiraj kot LaTeX" or resizing.
        var editor = MathEditor(root: .text("1+"))
        let unchanged = editor
        editor.paste(MathRow([matrix]))
        #expect(editor == unchanged)
        // Also inside another structure.
        editor.paste(MathRow([.squareRoot(MathRow([matrix]))]))
        #expect(editor == unchanged)
    }

    @Test func pasteboardDataIsCheckedAsDecoded() throws {
        // MathRow in the keys SE-0295 gives it, as another app writes it: a 2 × 2 matrix with one cell.
        let json = #"{"nodes":[{"matrix":{"rows":2,"columns":2,"cells":[{"nodes":[]}]}}]}"#
        let row = try JSONDecoder().decode(MathRow.self, from: Data(json.utf8))
        #expect(!row.isWellFormed)
        var editor = MathEditor()
        editor.paste(row)
        #expect(editor.root.isEmpty)
    }

    @Test func matricesLargerThanTheEditorBuildsStillPaste() throws {
        // The editor inserts and resizes up to 10 × 10, but the LaTeX import (and a result) gives larger ones,
        // which the app copies as structured math.
        let latex = #"\begin{bmatrix}"# + (1...12).map { String($0) }.joined(separator: #"\\"#) + #"\end{bmatrix}"#
        let column = try LaTeXConverter.row(fromLaTeX: latex)
        guard case .matrix(12, 1, _)? = column.nodes.first else {
            Issue.record("the LaTeX import did not give a 12 × 1 matrix: \(column)")
            return
        }
        #expect(column.isWellFormed)
        var editor = MathEditor()
        editor.paste(column)
        #expect(editor.root == column)
    }

    @Test(arguments: AuditPastedMatrixTests.malformed)
    func aMalformedMatrixIsReadWithoutTrapping(matrix: MathNode) {
        // A row of an older version can hold such a matrix (pasted unchecked, saved with a graph). Unfixed, ⌘C,
        // the detail sheet of Grafi and the history (plainText), "Kopiraj kot LaTeX" (latex) and resizing read
        // cells[r * columns + c] past the cells, and the checks of the conversion and the layout trapped on the
        // overflowing product. It is read as one row of its cells, as MathLayout shows it.
        let row = MathRow([matrix])
        guard case .matrix(_, _, let cells) = matrix else { return }
        #expect(MathRowConverter.plainText(row) == "[[" + cells.map(MathRowConverter.plainText).joined(separator: ", ") + "]]")
        let latexCells = cells.map { LaTeXConverter.latex($0) }.joined(separator: " & ")
        #expect(LaTeXConverter.latex(row) == #"\begin{bmatrix} "# + latexCells + #" \end{bmatrix}"#)
        #expect(throws: MathError.syntax("neveljavna matrika")) { try MathRowConverter.expr(from: row) }
        var editor = MathEditor(root: row)
        editor.resizeGrid(at: [], index: 0, rows: 3, columns: 3)
        #expect(editor.root == row)
    }
}
