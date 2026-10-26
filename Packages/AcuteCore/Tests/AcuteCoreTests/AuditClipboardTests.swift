import Foundation
import Testing
@testable import AcuteCore

// MARK: LaTeX export → import (audit MAT-24, A11Y-02)

@Suite struct AuditLaTeXRoundTripTests {
    static let angle = MathRow([.symbol(.digit(3)), .symbol(.digit(0)), .symbol(.degreeMark), .symbol(.digit(1)), .symbol(.digit(5)),
                                .symbol(.minuteMark), .symbol(.digit(2)), .symbol(.secondMark)])

    /// Rows as the editor builds them; "Kopiraj kot LaTeX" followed by paste must give each back unchanged.
    static let rows: [MathRow] = [
        // Fractions, roots and powers
        MathRow([.fraction(numerator: .text("1"), denominator: .text("2"))]),
        MathRow([.fraction(numerator: .text("1,5"), denominator: .text("2"))]),
        MathRow([.squareRoot(.text("2"))]),
        MathRow([.nthRoot(index: .text("3"), radicand: .text("8"))]),
        MathRow([.symbol(.variable("x")), .power(exponent: .text("2,5"))]),
        // Decimals (the comma at the start, inside and at the end of a row)
        .text("2,5"), .text(",5"), .text("1,"), .text("-12,75"),
        MathRow([.absoluteValue(.text("-1,5"))]),
        // D°M′S″
        AuditLaTeXRoundTripTests.angle,
        MathRow([.symbol(.digit(1)), .symbol(.digit(2)), .symbol(.degreeMark), .symbol(.digit(0)), .symbol(.minuteMark),
                 .symbol(.digit(7)), .symbol(.decimalPoint), .symbol(.digit(5)), .symbol(.secondMark)]),
        // nCr, nPr and other functions exported under their international names
        MathRow([.function2(.nCr, .text("5"), .text("2"))]),
        MathRow([.function2(.nPr, .text("5"), .text("2"))]),
        MathRow([.binomial(.text("5"), .text("2"))]),
        MathRow([.function2(.randInt, .text("1"), .text("6"))]),
        MathRow([.function2(.idiv, .text("7"), .text("2"))]),
        MathRow([.function(.rand, argument: MathRow()), .symbol(.times), .symbol(.digit(6))]),
        MathRow([.function(.log2, argument: .text("8"))]),
        MathRow([.logarithm(base: .text("2"), argument: .text("8"))]),
        MathRow([.function2(.chi2pdf, .text("1"), .text("2"))]),
        MathRow([.functionN(.binompdf, [.text("10"), .text("0,5"), .text("3")])]),
        MathRow([.functionN(.normpdf, [.text("x"), .text("0"), .text("1")])]),
        // Matrices and vectors
        MathRow([.matrix(rows: 2, columns: 2, cells: [.text("1"), .text("2,5"), .text("3"), .text("-4")])]),
        MathRow([.matrix(rows: 3, columns: 1, cells: [.text("1"), .text("0,5"), .text("2")])]),
    ]

    @Test func exportThenImportGivesTheSameRow() {
        for decimalComma in [true, false] {
            for row in Self.rows {
                let latex = LaTeXConverter.latex(row, decimalComma: decimalComma)
                let back = try? LaTeXConverter.row(fromLaTeX: latex)
                #expect(back == row, "\(latex)")
            }
        }
    }

    @Test func exportedDecimalCommaImportsAsDecimalPoint() throws {
        let row = MathRow.text("1,5")
        let latex = LaTeXConverter.latex(row, decimalComma: true)
        #expect(latex == "1{,}5")
        let back = try LaTeXConverter.row(fromLaTeX: latex)
        #expect(back == row)   // was 1;5 (the comma read as a separator)
    }

    @Test func decimalCommaInLaTeXEvaluates() throws {
        // 1,5/2 = 0,75 and ,5 = 0,5 (both exact in binary); unfixed, the rows hold a separator and do not parse.
        let fraction = try LaTeXConverter.row(fromLaTeX: #"\frac{1{,}5}{2}"#)
        let half = try RealEvaluator.evaluate(try MathRowConverter.expr(from: fraction))
        #expect(half == 0.75)
        let leading = try LaTeXConverter.row(fromLaTeX: "{,}5")
        let value = try RealEvaluator.evaluate(try MathRowConverter.expr(from: leading))
        #expect(value == 0.5)
    }

    @Test func secondsImportAsOneMark() throws {
        let latex = LaTeXConverter.latex(Self.angle)
        #expect(latex == #"30^{\circ}15'2''"#)
        let back = try LaTeXConverter.row(fromLaTeX: latex)
        #expect(back == Self.angle)   // was 30°15′2′′
        let seconds = try LaTeXConverter.row(fromLaTeX: "2″")
        #expect(seconds == MathRow([.symbol(.digit(2)), .symbol(.secondMark)]))
        let minutes = try LaTeXConverter.row(fromLaTeX: "15'")
        #expect(minutes == MathRow([.symbol(.digit(1)), .symbol(.digit(5)), .symbol(.minuteMark)]))
    }

    @Test func exportedFunctionNamesImportAndEvaluate() throws {
        // C(5, 2) = 10, log₂ 8 = 3, P(X = 3) for X ~ B(10; 0,5) = C(10, 3)/2¹⁰ = 120/1024 (all exact in binary).
        let combinations = try LaTeXConverter.row(fromLaTeX: #"\operatorname{C}\left(5;2\right)"#)
        #expect(combinations == MathRow([.function2(.nCr, .text("5"), .text("2"))]))
        let c = try RealEvaluator.evaluate(try MathRowConverter.expr(from: combinations))
        #expect(c == 10)
        let logarithm = try LaTeXConverter.row(fromLaTeX: #"\operatorname{log₂}\left(8\right)"#)
        #expect(logarithm == MathRow([.function(.log2, argument: .text("8"))]))
        let l = try RealEvaluator.evaluate(try MathRowConverter.expr(from: logarithm))
        #expect(l == 3)
        let binomial = try LaTeXConverter.row(fromLaTeX: #"\operatorname{binompdf}\left(10;0{,}5;3\right)"#)
        #expect(binomial == MathRow([.functionN(.binompdf, [.text("10"), .text("0,5"), .text("3")])]))
        let p = try RealEvaluator.evaluate(try MathRowConverter.expr(from: binomial))
        #expect(p == 120.0 / 1024.0)
    }
}

// MARK: Pasting the app's own copied numbers (audit A11Y-01)

@Suite struct AuditDisplayedNumberPasteTests {
    /// What paste does with the text (MathClipboardItem(text:) in the app): parse it and keep its structure.
    func pastedValue(_ text: String) throws -> Double {
        let row = MathRowConverter.rowPreservingStructure(for: try Parser.parse(text))
        return try RealEvaluator.evaluate(try MathRowConverter.expr(from: row))
    }

    @Test func groupedResultPastesAsSameNumber() throws {
        let copied = NumberFormatting.format(12345, options: NumberFormatOptions(decimalSeparator: ",", groupingSeparator: "\u{2009}")).plainText
        #expect(copied == "12\u{2009}345")
        let machine = try #require(DisplayedNumber.machineText(copied))
        #expect(machine == "12345")
        let value = try pastedValue(machine)
        #expect(value == 12345)   // the copied text itself parses as 12·345 = 4140
    }

    @Test func negativeGroupedDecimalPastes() throws {
        let copied = NumberFormatting.format(-1234567.5, options: NumberFormatOptions(decimalSeparator: ",", groupingSeparator: "\u{2009}")).plainText
        #expect(copied == "−1\u{2009}234\u{2009}567,5")
        let machine = try #require(DisplayedNumber.machineText(copied))
        #expect(machine == "-1234567.5")
        let value = try pastedValue(machine)
        #expect(value == -1234567.5)
    }

    @Test func scientificResultWithDecimalCommaPastes() throws {
        let copied = NumberFormatting.format(1.5e-8, options: NumberFormatOptions(mode: .sci, places: 1, decimalSeparator: ",")).plainText
        #expect(copied == "1,5×10^-8")
        let machine = try #require(DisplayedNumber.machineText(copied))
        #expect(machine == "1.5×10^-8")   // what the app copies with a decimal point
        let value = try pastedValue(machine)
        // 1,5·10⁻⁸ evaluated as a product of two doubles: a few ulps (≈ 1e-16 relative) at most.
        #expect(abs(value / 1.5e-8 - 1) < 1e-14)
    }

    @Test func superscriptExponentPastes() throws {
        // The compact ·10ⁿ form (FormattedNumber.plainTextLocalized in the app), e.g. »Kopiraj« in the tools.
        let machine = try #require(DisplayedNumber.machineText("2,5·10⁻³"))
        #expect(machine == "2.5·10⁻³")
        let value = try pastedValue(machine)
        #expect(abs(value / 2.5e-3 - 1) < 1e-14)
    }

    @Test func otherTextKeepsItsMeaning() {
        // Ordinary spaces, malformed groups and expressions are not the app's number output.
        for text in ["12 345", "12\u{2009}34", "1\u{2009}2345", "12\u{2009}", "1,2,3", "sin(x)", "2·10", "1,5×10^", "", "−", ",5", "∞"] {
            #expect(DisplayedNumber.machineText(text) == nil, "\(text)")
        }
        #expect(DisplayedNumber.machineText("2,5") == "2.5")
        #expect(DisplayedNumber.machineText("1\u{202F}234\u{00A0}567,25") == "1234567.25")
    }
}

// MARK: normpdf and invNorm with one or three arguments (review of the audit fixes)

@Suite struct AuditVariableArityTests {
    // References (Python math/statistics): φ(z) = e^(−z²/2)/√(2π); φ(1) = 0.24197072451914337,
    // normpdf(2; 1; 2) = φ(0,5)/2 = 0.17603266338214976, Φ⁻¹(0,975) = 1.959963984540054.
    // Tolerances cover rounding in exp/√ (1e-14) and the existing invNorm accuracy test (1e-12).

    @Test func keypadNormalDensityWithMeanAndDeviationEvaluates() throws {
        // The normPdf(x; μ; σ) key builds .functionN; Parser.makeCall rejected three arguments.
        let row = MathRow([.functionN(.normpdf, [.text("2"), .text("1"), .text("2")])])
        let density = try RealEvaluator.evaluate(try MathRowConverter.expr(from: row))
        #expect(approx(density, 0.17603266338214976, 1e-14))
    }

    @Test func keypadInverseNormalWithMeanAndDeviationEvaluates() throws {
        // invNorm(0,975; 100; 15) = 100 + 15·Φ⁻¹(0,975) = 129.39945976810081
        let row = MathRow([.functionN(.invnorm, [.text("0,975"), .text("100"), .text("15")])])
        let quantile = try RealEvaluator.evaluate(try MathRowConverter.expr(from: row))
        #expect(approx(quantile, 129.39945976810081, 1e-12))
    }

    @Test func textCallsWithOneOrThreeArguments() throws {
        #expect(approx(try value("normpdf(1)"), 0.24197072451914337, 1e-14))
        #expect(approx(try value("normpdf(2; 1; 2)"), 0.17603266338214976, 1e-14))
        #expect(approx(try value("invnorm(0.975)"), 1.959963984540054, 1e-12))
        #expect(approx(try value("invNorm(0.975; 100; 15)"), 129.39945976810081, 1e-12))
        // Other counts stay errors (RealEvaluator supports only 1 and 3).
        #expect(throws: MathError.self) { try parse("normpdf(1; 2)") }
        #expect(throws: MathError.self) { try parse("invnorm(0.5; 1; 2; 3)") }
    }
}
