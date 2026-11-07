import AcuteCore
import Testing
@testable import AcuteCalc

/// Health audit concurrency:1: the editor nests structures at most MathEditor.maximumDepth levels deep. The keys
/// 10ˣ and eˣ type their base and then its power; at the limit the power did not fit, so 10 or e was typed alone.
/// There such a key now types nothing, and a level higher it types the whole power, as before.
@MainActor
@Suite struct CompositeKeyDepthTests {
    /// The editor after the fraction key is pressed `count` times on an empty row: each fraction takes the caret
    /// into its empty numerator, a level deeper.
    private func nested(_ count: Int) -> MathEditor {
        var editor = MathEditor()
        for _ in 0..<count { _ = editor.apply(.fraction) }
        return editor
    }

    @Test func powerKeysAtTheDepthLimitTypeNothing() {
        for key: KeypadKey in [.tenPower, .ePower] {
            var editor = nested(MathEditor.maximumDepth)
            let unchanged = editor
            let handled = editor.apply(key)
            #expect(handled, "\(key)")
            #expect(editor == unchanged, "\(key)")
            // A level higher, the base goes in with its power, and the caret into the empty exponent.
            var shallower = nested(MathEditor.maximumDepth - 1)
            _ = shallower.apply(key)
            #expect(shallower.root.nestingDepth == MathEditor.maximumDepth, "\(key)")
            #expect(shallower.cursor.path.count == MathEditor.maximumDepth, "\(key)")
            // The row of the base holds 10 or e and then the power, not the power alone.
            let base: [MathNode] = key == .tenPower ? [.symbol(.digit(1)), .symbol(.digit(0))] : [.symbol(.constant(.e))]
            let typed = MathRow(base + [MathNode.power(exponent: MathRow())])
            #expect(shallower.subrow(at: Array(shallower.cursor.path.dropLast())) == typed, "\(key)")
        }
    }
}
