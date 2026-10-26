import AcuteCore
import Testing
@testable import AcuteCalc

/// A11Y-04: the editor tells VoiceOver where the caret is, so the adjustable action (swipe up or
/// down = moveRight / moveLeft) lets a VoiceOver user leave a denominator: typing 1, fraction, 2
/// and moving right gives 1/2 + … instead of 1/(2 + …).
@MainActor
@Suite struct EditorCaretDescriptionTests {
    let style = MathStyle(decimalSeparator: ",")

    @Test func caretInTheDenominatorAndBackOut() {
        var editor = MathEditor()
        #expect(MathAccessibility.caretDescription(editor, style: style) == "Kazalec v praznem izrazu")
        editor.insert(.digit(1))
        editor.insertFraction()
        #expect(MathAccessibility.caretDescription(editor, style: style) == "Kazalec v imenovalcu ulomka, prazno polje")
        editor.insert(.digit(2))
        #expect(MathAccessibility.caretDescription(editor, style: style) == "Kazalec v imenovalcu ulomka, na koncu")
        // The adjustable action's increment.
        editor.moveRight()
        #expect(MathAccessibility.caretDescription(editor, style: style) == "Kazalec na koncu izraza")
        editor.insert(.plus)
        editor.insert(.digit(1))
        #expect(MathRowConverter.plainText(editor.root) == "(1)/(2)+1")
    }

    @Test func caretBetweenSymbolsAndInsideAFunction() {
        var editor = MathEditor()
        editor.insert(.digit(3))
        editor.insert(.decimalPoint)
        editor.insert(.digit(5))
        editor.moveLeft()
        #expect(MathAccessibility.caretDescription(editor, style: style) == "Kazalec za ,")
        editor.moveLeft()
        editor.moveLeft()
        #expect(MathAccessibility.caretDescription(editor, style: style) == "Kazalec na začetku izraza")
        var sine = MathEditor()
        sine.insertNode(.function(.sin, argument: MathRow()))
        #expect(MathAccessibility.caretDescription(sine, style: style) == "Kazalec v argumentu funkcije sin, prazno polje")
    }

    @Test func caretInAMatrixCell() {
        var editor = MathEditor()
        editor.insertMatrix(rows: 2, columns: 2)
        editor.moveRight()
        #expect(MathAccessibility.caretDescription(editor, style: style) == "Kazalec v matriki, vrstica 1, stolpec 2, prazno polje")
    }

    @Test func selectionIsDescribed() {
        var editor = MathEditor(root: MathRow.text("2+3"))
        editor.selectAll()
        #expect(MathAccessibility.caretDescription(editor, style: style) == "Izbrano: 2+3")
    }
}
