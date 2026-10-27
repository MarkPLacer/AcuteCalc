import Foundation
import Testing
@testable import AcuteCore

// MARK: χ² names typed on a hardware keyboard (audit GAP-gap-keyboard-e-i-2)

/// What the keypad and a hardware keyboard type through KeypadTarget.apply: letters go through insertLetter,
/// digits through insertTypedDigit, "." is the decimal point; "→" stands for the right arrow, which moves to
/// the next argument slot.
private func typedKeys(_ keys: String) -> MathEditor {
    var editor = MathEditor()
    for c in keys {
        if c.isASCII, let digit = c.wholeNumberValue {
            editor.insertTypedDigit(digit)
        } else if c == "." {
            editor.insert(.decimalPoint)
        } else if c == "→" {
            editor.moveRight()
        } else if c.isLetter {
            editor.insertLetter(String(c))
        }
    }
    return editor
}

/// chi2pdf, chi2cdf, invchi2 and chi2Pdf, chi2Cdf, invChi2 typed key by key became χ·2·p·d·f, i·n·v·χ·2 and
/// i·n·v·C·h·i·2: the search for typed words stopped at the digit, and a typed digit never looked back. The
/// text parser reads each as one function name (Lexer: "Function names with digits inside").
@Suite struct AuditTypedChiSquareNameTests {
    @Test func typedChiSquareNamesAreTheTextParsersFunctions() throws {
        let inputs: [(keys: String, text: String)] = [
            ("chi2pdf3→2", "chi2pdf(3, 2)"),
            ("chi2cdf3→2", "chi2cdf(3, 2)"),
            ("chi2Pdf3→2", "chi2Pdf(3, 2)"),
            ("chi2Cdf3→2", "chi2Cdf(3, 2)"),
            ("invchi20.95→3", "invchi2(0.95, 3)"),
            ("invChi20.95→3", "invChi2(0.95, 3)"),
            ("2chi2cdf1→2", "2chi2cdf(1, 2)"),
        ]
        for input in inputs {
            let typedExpr = try MathRowConverter.expr(from: typedKeys(input.keys).root)
            let textExpr = try Parser.parse(input.text)
            #expect(typedExpr == textExpr, "\(input.keys)")
        }
    }

    /// The structures of the palette keys (.function2), with the caret in the first slot.
    @Test func typedChiSquareNamesGetTheKeypadSlots() {
        let empty = MathRow()
        let inside = MathCursor(path: [MathCursor.Step(node: 0, slot: 0)], index: 0)
        let cases: [(keys: String, node: MathNode)] = [
            ("chi2pdf", .function2(.chi2pdf, empty, empty)),
            ("chi2Pdf", .function2(.chi2pdf, empty, empty)),
            ("chi2cdf", .function2(.chi2cdf, empty, empty)),
            ("chi2Cdf", .function2(.chi2cdf, empty, empty)),
            ("invchi2", .function2(.invchi2, empty, empty)),
            ("invChi2", .function2(.invchi2, empty, empty)),
        ]
        for c in cases {
            let editor = typedKeys(c.keys)
            #expect(editor.root.nodes == [c.node], "\(c.keys)")
            #expect(editor.cursor == inside, "\(c.keys)")
        }
    }

    @Test func typedChiSquareDistributionHasItsValue() throws {
        // χ² with k = 2 degrees of freedom: P(X ≤ x) = 1 − e^(−x/2); Python: 1 - math.exp(-1.5).
        let expr = try MathRowConverter.expr(from: typedKeys("chi2cdf3→2").root)
        let value = try RealEvaluator.evaluate(expr)
        #expect(abs(value - 0.7768698398515702) < 1e-12, "\(value)")
    }
}

/// What already worked stays: before a name is complete the letters and digits stay a product, as in the
/// text parser, and a typed 2 after other letters is only a digit. These rows are the same as on main, where
/// digits went through insert(.digit).
@Suite struct AuditTypedChiSquareUnchangedTests {
    @Test func unfinishedNamesStayProducts() throws {
        let chi: MathNode = .symbol(.variable("χ")), two: MathNode = .symbol(.digit(2))
        let p: MathNode = .symbol(.variable("p")), d: MathNode = .symbol(.variable("d")), f: MathNode = .symbol(.variable("f"))
        #expect(typedKeys("chi2").root.nodes == [chi, two])
        #expect(typedKeys("chi2pd").root.nodes == [chi, two, p, d])
        #expect(typedKeys("chi22pdf").root.nodes == [chi, two, two, p, d, f])
        for keys in ["chi2", "chi2p", "chi2pd", "chi12pdf"] {
            let typedExpr = try MathRowConverter.expr(from: typedKeys(keys).root)
            let textExpr = try Parser.parse(keys)
            #expect(typedExpr == textExpr, "\(keys)")
        }
    }

    @Test func otherWordsAroundADigitAreUnchanged() {
        let i: MathNode = .symbol(.variable("i")), n: MathNode = .symbol(.variable("n")), v: MathNode = .symbol(.variable("v"))
        let chi: MathNode = .symbol(.variable("χ"))
        #expect(typedKeys("invchi3").root.nodes == [i, n, v, chi, .symbol(.digit(3))])
        #expect(typedKeys("2pi").root.nodes == [.symbol(.digit(2)), .symbol(.constant(.pi))])
        #expect(typedKeys("2sin").root.nodes == [.symbol(.digit(2)), .function(.sin, argument: MathRow())])
        #expect(typedKeys("x2").root.nodes == [.symbol(.variable("x")), .symbol(.digit(2))])
    }
}
