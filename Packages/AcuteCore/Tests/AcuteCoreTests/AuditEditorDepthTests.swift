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

    /// The error of converting `row` to an expression, nil when it converts.
    static func conversionError(_ row: MathRow) -> MathError? {
        do throws(MathError) {
            _ = try MathRowConverter.expr(from: row)
            return nil
        } catch {
            return error
        }
    }

    /// Runs `body` on a thread with an 8 MB stack, the way AuditDeepInputTests.onWorkerStack runs its work on
    /// 512 KB. The app saves and converts rows in an optimised build; the frames of this unoptimised test build
    /// (with AddressSanitizer in one CI run) are several times larger, and encoding, decoding and converting a
    /// row at the depth limit go through a few of them per level.
    static func onLargeStack<Value: Sendable>(_ body: @escaping @Sendable () -> Value) async -> Value {
        await withCheckedContinuation { (continuation: CheckedContinuation<Value, Never>) in
            let thread = Thread { continuation.resume(returning: body()) }
            thread.stackSize = 8 << 20
            thread.start()
        }
    }

    /// What became of a row nested by a held key.
    struct HeldRow: Sendable {
        var depth: Int
        var caretDepth: Int
        var savedAndLoaded: Bool
        var conversionError: MathError?
    }

    @Test(arguments: NestingKey.allCases)
    func aHeldKeyStopsAtTheDepthLimit(key: NestingKey) async {
        // Unfixed, 300 repeats nested 300 levels, and JSONEncoder (at most 512 nested containers, four per
        // level here) threw, so the data file was not saved any more.
        let result = await Self.onLargeStack { () -> HeldRow in
            let editor = Self.held(key, 300)
            let data = try? JSONEncoder().encode(editor.root)
            let loaded = data.flatMap { try? JSONDecoder().decode(MathRow.self, from: $0) }
            return HeldRow(depth: editor.root.nestingDepth, caretDepth: editor.cursor.path.count,
                           savedAndLoaded: loaded == editor.root, conversionError: Self.conversionError(editor.root))
        }
        #expect(result.depth == MathEditor.maximumDepth)
        #expect(result.caretDepth == MathEditor.maximumDepth)
        #expect(result.savedAndLoaded)
        // The row at the limit still converts: its innermost slot is empty, it is not refused as too deep.
        #expect(result.conversionError == .incomplete)
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

    @Test func wrappingASelectionStopsAtTheLimit() async {
        // ⌘A followed by |, √ or /: the whole row goes a level down while the caret stays at the top. At the
        // limit nothing changes, and the selection stays. Comparing two editors at the limit recurses once per
        // level through MathNode's synthesized ==, a large frame in this unoptimised build, so it runs on 8 MB.
        let unchanged = await Self.onLargeStack { () -> [Bool] in
            var editor = Self.held(.fraction, 300)
            editor.selectAll()
            let selected = editor
            var results: [Bool] = []
            editor.insertWrapping(.absoluteValue(MathRow()))
            results.append(editor == selected)
            editor.insertWrapping(.squareRoot(MathRow()))
            results.append(editor == selected)
            editor.insertFraction()
            results.append(editor == selected)
            return results
        }
        #expect(unchanged == [true, true, true])
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
        // refused the tree, which can be more than the 512 KB stack of a worker thread holds in an unoptimised
        // build. The row is built and released on that thread too.
        let error = await AuditDeepInputTests.onWorkerStack { Self.conversionError(Self.nestedFractions(200)) }
        #expect(error == .tooComplex)
        // Such a row can still be edited: digits go in, a structure does not. (On 8 MB: comparing the two
        // editors recurses through all 40 levels.)
        let edited = await Self.onLargeStack { () -> [Bool] in
            let path = Array(repeating: MathCursor.Step(node: 0, slot: 0), count: 40)
            var editor = MathEditor(root: Self.nestedFractions(40))
            editor.setCursor(path: path, index: 1)
            editor.insert(.digit(2))
            let digitTyped = editor.currentRow == MathRow([.symbol(.digit(1)), .symbol(.digit(2))])
            let typed = editor
            editor.insertFraction()
            editor.insertWrapping(.squareRoot(MathRow()))
            return [digitTyped, editor == typed]
        }
        #expect(edited == [true, true])
    }
}
