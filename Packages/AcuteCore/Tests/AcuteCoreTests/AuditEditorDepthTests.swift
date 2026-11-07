import Foundation
import Testing
@testable import AcuteCore

// MARK: Nesting depth of the editor (health audit concurrency:1, audit GAP-recursion-2)

/// Serialized, so that a stack overflow is reported in the test that caused it.
@Suite(.serialized) struct AuditEditorDepthTests {
    /// The keys that nest a structure when held on a hardware keyboard: KeyboardInput maps "/", "^" and "|"
    /// to them and handles the .repeat phase, so a held key presses them again and again.
    enum NestingKey: CaseIterable, Sendable {
        case fraction, power, absoluteValue
    }

    static func press(_ key: NestingKey, _ editor: inout MathEditor) {
        switch key {
        case .fraction: editor.insertFraction()
        case .power: editor.insertPower()
        case .absoluteValue: editor.insertWrapping(.absoluteValue(MathRow()))
        }
    }

    /// The editor after `key` is held for `count` repeats, starting from an empty row.
    static func held(_ key: NestingKey, _ count: Int) -> MathEditor {
        var editor = MathEditor()
        for _ in 0..<count { press(key, &editor) }
        return editor
    }

    /// 1 in `depth` fractions nested in their numerators, built without the editor (an old data file).
    static func nestedFractions(_ depth: Int) -> MathRow {
        var row = MathRow([.symbol(.digit(1))])
        for _ in 0..<depth { row = MathRow([.fraction(numerator: row, denominator: .text("2"))]) }
        return row
    }

    /// The error of converting `row` to an expression (nil when it converts), on the 512 KB stack of the
    /// worker threads where the calculator evaluates.
    static func conversionError(_ row: MathRow) async -> MathError? {
        await AuditDeepInputTests.onWorkerStack { () -> MathError? in
            do throws(MathError) {
                _ = try MathRowConverter.expr(from: row)
                return nil
            } catch {
                return error
            }
        }
    }

    @Test(arguments: NestingKey.allCases)
    func aHeldKeyStopsAtTheDepthLimit(key: NestingKey) async throws {
        // Unfixed, 300 repeats nested 300 levels, and JSONEncoder (at most 512 nested containers, four per
        // level here) threw, so the data file was not saved any more.
        let editor = Self.held(key, 300)
        #expect(editor.root.nestingDepth == MathEditor.maximumDepth)
        #expect(editor.cursor.path.count == MathEditor.maximumDepth)
        let data = try JSONEncoder().encode(editor.root)
        let decoded = try JSONDecoder().decode(MathRow.self, from: data)
        #expect(decoded == editor.root)
        // The row at the limit still converts: its innermost slot is empty, it is not refused as too deep.
        let error = await Self.conversionError(editor.root)
        #expect(error == .incomplete)
    }

    @Test func operandsTypedOverFractionBarsStopAtTheLimit() {
        // 1/1/1/…: each fraction takes the 1 before it as its numerator (the operand branch of insertFraction,
        // which does not go through insertNode) and nests in the denominator of the one before.
        var editor = MathEditor()
        for _ in 0..<100 {
            editor.insert(.digit(1))
            editor.insertFraction()
        }
        #expect(editor.root.nestingDepth == MathEditor.maximumDepth)
    }

    @Test func wrappingASelectionStopsAtTheLimit() {
        // ⌘A followed by |, √ or /: the whole row goes a level down while the caret stays at the top. At the
        // limit nothing changes, and the selection stays.
        var editor = Self.held(.fraction, 300)
        editor.selectAll()
        let selected = editor
        editor.insertWrapping(.absoluteValue(MathRow()))
        #expect(editor == selected)
        editor.insertWrapping(.squareRoot(MathRow()))
        #expect(editor == selected)
        editor.insertFraction()
        #expect(editor == selected)
        // A level less is wrapped as before.
        var shallower = Self.held(.fraction, MathEditor.maximumDepth - 1)
        shallower.selectAll()
        shallower.insertWrapping(.absoluteValue(MathRow()))
        #expect(shallower.root.nestingDepth == MathEditor.maximumDepth)
        #expect(shallower.selection == nil)
    }

    @Test func aRowPastedIntoItsOwnInnermostSlotIsRefused() {
        // Holding "/" leaves the caret in the innermost numerator, where the copied row doubled the depth.
        var editor = Self.held(.fraction, 20)
        let unchanged = editor
        editor.paste(editor.root)
        #expect(editor == unchanged)
        // A row that fits is pasted.
        editor.paste(Self.held(.fraction, MathEditor.maximumDepth - 20).root)
        #expect(editor.root.nestingDepth == MathEditor.maximumDepth)
    }

    @Test func aWordTypedAtTheLimitStaysLetters() {
        // s, q, r, t in the innermost slot would become √□ a level deeper: the letters stay as typed, none is lost.
        var editor = Self.held(.fraction, MathEditor.maximumDepth)
        for letter in ["s", "q", "r", "t"] { editor.insertLetter(letter) }
        let letters = MathRow(["s", "q", "r", "t"].map { MathNode.symbol(.variable($0)) })
        #expect(editor.currentRow == letters)
        #expect(editor.root.nestingDepth == MathEditor.maximumDepth)
    }

    @Test func aDeeperRowOfAnOldDataFile() async {
        // Unfixed, converting 200 nested fractions recursed 200 levels deep before the parser's height limit
        // refused the tree, which can be more than the 512 KB stack holds in an unoptimised build.
        let error = await Self.conversionError(Self.nestedFractions(200))
        #expect(error == .tooComplex)
        // Such a row can still be edited: digits go in, a structure does not.
        let path = Array(repeating: MathCursor.Step(node: 0, slot: 0), count: 40)
        var editor = MathEditor(root: Self.nestedFractions(40))
        editor.setCursor(path: path, index: 1)
        editor.insert(.digit(2))
        #expect(editor.currentRow == MathRow([.symbol(.digit(1)), .symbol(.digit(2))]))
        let typed = editor
        editor.insertFraction()
        editor.insertWrapping(.squareRoot(MathRow()))
        #expect(editor == typed)
    }
}
