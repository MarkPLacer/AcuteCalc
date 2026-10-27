import Foundation
import Testing
@testable import AcuteCore

// MARK: Function names typed on a hardware keyboard (audit GAP-gap-keyboard-e-i-2)

/// What a hardware keyboard types (KeyboardInput, KeypadTarget.apply): letters go through insertLetter,
/// digits, "." and "=" are symbols; "→" stands for the right arrow, which moves to the next argument slot.
private func typed(_ keys: String) -> MathEditor {
    var editor = MathEditor()
    for c in keys {
        if c.isASCII, let digit = c.wholeNumberValue {
            editor.insert(.digit(digit))
        } else if c == "." {
            editor.insert(.decimalPoint)
        } else if c == "=" {
            editor.insert(.equals)
        } else if c == "→" {
            editor.moveRight()
        } else if c.isLetter {
            editor.insertLetter(String(c))
        }
    }
    return editor
}

/// Distribution names and the characters Γ, ζ, Φ typed letter by letter became products of variables
/// (normcdf → norm(c·d·f), binompdf → b·i·n·o·m·p·d·f, poissonpdf was longer than the 8-letter window,
/// Γ → the variable Γ), while the text parser reads them as functions.
@Suite struct AuditTypedFunctionNameTests {
    @Test func typedDistributionNamesAreTheTextParsersFunctions() throws {
        let inputs: [(keys: String, text: String)] = [
            ("binompdf10→0.5→3", "binompdf(10, 0.5, 3)"),
            ("binomcdf10→0.5→3", "binomcdf(10, 0.5, 3)"),
            ("binomPdf10→0.5→3", "binomPdf(10, 0.5, 3)"),
            ("binomCdf10→0.5→3", "binomCdf(10, 0.5, 3)"),
            ("poissonpdf4→2", "poissonpdf(4, 2)"),
            ("poissoncdf4→2", "poissoncdf(4, 2)"),
            ("poissonPdf4→2", "poissonPdf(4, 2)"),
            ("poissonCdf4→2", "poissonCdf(4, 2)"),
            ("normcdf1", "normcdf(1)"),
            ("normpdf0", "normpdf(0)"),
            ("normPdf0", "normPdf(0)"),
            ("invnorm0.975", "invnorm(0.975)"),
            ("invNorm0.975", "invNorm(0.975)"),
            ("tpdf1→5", "tpdf(1, 5)"),
            ("tcdf1→5", "tcdf(1, 5)"),
            ("invt0.9→5", "invt(0.9, 5)"),
            ("tPdf1→5", "tPdf(1, 5)"),
            ("tCdf1→5", "tCdf(1, 5)"),
            ("invT0.9→5", "invT(0.9, 5)"),
            ("fpdf1→2→3", "fpdf(1, 2, 3)"),
            ("fcdf1→2→3", "fcdf(1, 2, 3)"),
            ("invf0.5→2→3", "invf(0.5, 2, 3)"),
            ("fPdf1→2→3", "fPdf(1, 2, 3)"),
            ("fCdf1→2→3", "fCdf(1, 2, 3)"),
            ("invF0.5→2→3", "invF(0.5, 2, 3)"),
        ]
        for input in inputs {
            let typedExpr = try MathRowConverter.expr(from: typed(input.keys).root)
            let textExpr = try Parser.parse(input.text)
            #expect(typedExpr == textExpr, "\(input.keys)")
        }
    }

    @Test func typedGammaZetaAndPhiAreTheTextParsersFunctions() throws {
        for (keys, text) in [("Γ5", "Γ(5)"), ("ζ2", "ζ(2)"), ("Φ0", "Φ(0)"), ("2Φ1", "2Φ(1)")] {
            let typedExpr = try MathRowConverter.expr(from: typed(keys).root)
            let textExpr = try Parser.parse(text)
            #expect(typedExpr == textExpr, "\(keys)")
        }
    }

    /// The structures of the palette keys (KeypadTarget.apply), with the caret in the first slot.
    @Test func typedNamesGetTheKeypadSlots() {
        let empty = MathRow()
        let inside = MathCursor(path: [MathCursor.Step(node: 0, slot: 0)], index: 0)
        let cases: [(keys: String, node: MathNode)] = [
            ("binompdf", .functionN(.binompdf, [empty, empty, empty])),
            ("poissonpdf", .function2(.poissonpdf, empty, empty)),
            ("normcdf", .function(.normcdf, argument: empty)),
            ("normpdf", .function(.normpdf, argument: empty)),
            ("invnorm", .function(.invnorm, argument: empty)),
            ("tcdf", .function2(.tcdf, empty, empty)),
            ("fpdf", .functionN(.fpdf, [empty, empty, empty])),
            ("Γ", .function(.gamma, argument: empty)),
            ("ζ", .function(.zeta, argument: empty)),
            ("Φ", .function(.normcdf, argument: empty)),
        ]
        for c in cases {
            let editor = typed(c.keys)
            #expect(editor.root.nodes == [c.node], "\(c.keys)")
            #expect(editor.cursor == inside, "\(c.keys)")
        }
    }

    @Test func typedDistributionsHaveTheirValues() throws {
        // Python math: comb(10, 3)/2**10 = 120/1024; 0.5*(1 + erf(1/sqrt(2))); gamma(5) = 4!; Φ(0) = 1/2.
        let cases: [(keys: String, value: Double)] = [
            ("binompdf10→0.5→3", 0.1171875),
            ("normcdf1", 0.8413447460685429),
            ("Γ5", 24),
            ("Φ0", 0.5),
        ]
        for c in cases {
            let expr = try MathRowConverter.expr(from: typed(c.keys).root)
            let value = try RealEvaluator.evaluate(expr)
            #expect(abs(value - c.value) < 1e-12, "\(c.keys): \(value)")
        }
    }

    @Test func typedNormalDensityGraphHasNoSliders() throws {
        // Graphs: y = normpdf(x) was y = norm(p·d·f·x) with the sliders d, f, p. normpdf(0) = 1/√(2π).
        let request = try #require(try CalculationEngine.graphRequest(for: typed("y=normpdfx").root))
        #expect(request.parameters.isEmpty)
        guard case .explicit(let f)? = request.kinds.first else {
            Issue.record("y = normpdf(x) is not an explicit curve")
            return
        }
        let y = try RealEvaluator.evaluate(f, context: EvaluationContext(variables: ["x": 0]))
        #expect(abs(y - 1 / (2 * Double.pi).squareRoot()) < 1e-12)
    }
}

/// What already worked stays as it was: the early norm(□), sin → sinh, the Greek names, and variables
/// named with these letters where the text parser reads a variable too. These pass without the fix as well.
@Suite struct AuditTypedFunctionNameUnchangedTests {
    @Test func existingTypedWordsAreUnchanged() {
        let c: MathNode = .symbol(.variable("c")), d: MathNode = .symbol(.variable("d"))
        let v: MathNode = .symbol(.variable("v"))
        let x: MathNode = .symbol(.variable("x")), i: MathNode = .symbol(.variable("i"))
        let binom: [MathNode] = ["b", "i", "n", "o", "m"].map { MathNode.symbol(.variable($0)) }
        #expect(typed("norm").root.nodes == [.function(.norm, argument: MathRow())])
        #expect(typed("norm").cursor == MathCursor(path: [MathCursor.Step(node: 0, slot: 0)], index: 0))
        #expect(typed("normv").root.nodes == [.function(.norm, argument: MathRow([v]))])
        #expect(typed("normcd").root.nodes == [.function(.norm, argument: MathRow([c, d]))])
        #expect(typed("sinh").root.nodes == [.function(.sinh, argument: MathRow())])
        #expect(typed("tgh").root.nodes == [.function(.tanh, argument: MathRow())])
        #expect(typed("gamma").root.nodes == [.function(.gamma, argument: MathRow())])
        #expect(typed("zeta").root.nodes == [.function(.zeta, argument: MathRow())])
        #expect(typed("charpoly").root.nodes == [.function(.charpoly, argument: MathRow())])
        #expect(typed("xi").root.nodes == [x, i])
        #expect(typed("binom").root.nodes == binom)
    }

    @Test func greekVariablesStayVariables() throws {
        for (keys, name) in [("phi", "φ"), ("varphi", "φ"), ("Phi", "Φ"), ("chi", "χ"), ("φ", "φ"), ("γ", "γ")] {
            let variable: MathNode = .symbol(.variable(name))
            #expect(typed(keys).root.nodes == [variable], "\(keys)")
            // The text parser reads the same variable.
            let typedExpr = try MathRowConverter.expr(from: typed(keys).root)
            let textExpr = try Parser.parse(keys)
            #expect(typedExpr == textExpr, "\(keys)")
        }
    }
}
