import Foundation
import Testing
@testable import AcuteCore

/// Exact forms with e, ln and √π (owner-approved feature). A numeric result was recognised only as a fraction,
/// a multiple of π or π², or a surd, so on origin/main (b025358, CI probe of 187 limits and integrals)
/// lim (2ˣ − 1)/x showed 0,693147181, lim (1 + x)^(1/x) 2,718281828, ∫₀¹ eˣ dx 1,718281828 and
/// ∫ e^(−x²) dx 1,772453851 over ℝ and 0,886226926 over [0, ∞), with no exact form above the decimal.
/// The new forms are only shown (`NumericResult.closedForm`): `exact` stays nil, so Ans and memory keep the
/// decimal value. References are the exact constants (Foundation exp, log, sqrt).
@Suite struct AuditExactFormsTests {
    // MARK: Helpers

    /// The exact form ResultView draws above "≈ decimal" (MathText of `displayExact`), as plain text.
    static func shown(_ r: NumericResult) -> String? {
        r.displayExact.map { MathRowConverter.plainText(MathRowConverter.row(for: $0)) }
    }

    /// The result of a row as CalculatorModel calculates it (app defaults: radians, complex results on).
    static func number(_ row: MathRow) -> NumericResult? {
        let calculation = CalculationEngine.calculate(row, variables: [:], exactVariables: [:], settings: CalculationSettings())
        guard case .number(let r) = calculation.outcome else { return nil }
        return r
    }

    /// lim x→point body from the keypad's lim key, the slots typed as text. `inSum` puts "0 +" before it:
    /// a limit at ±∞ on its own stops at "Prevelika vrednost" on origin/main, inside a sum it is evaluated.
    static func limit(_ point: String, _ body: String, inSum: Bool = false) throws -> MathRow {
        let pointRow = try MathRowConverter.row(fromText: point)
        let bodyRow = try MathRowConverter.row(fromText: body)
        let node = MathNode.limit(point: pointRow, body: bodyRow, direction: .both)
        return MathRow(inSum ? [.symbol(.digit(0)), .symbol(.plus), node] : [node])
    }

    /// ∫ₐᵇ f dx as typed in the text dialog (the keypad ∫ with both bounds).
    static func integral(_ body: String, _ lower: String, _ upper: String) throws -> MathRow {
        try MathRowConverter.row(fromText: "integral(\(body), x, \(lower), \(upper))")
    }

    /// What the calculator makes of the value of a limit or an integral.
    static func numeric(_ x: Double) -> NumericResult {
        CalculationEngine.numeric(x, expr: nil, context: EvaluationContext())
    }

    func expectForm(_ row: MathRow, _ form: String, value reference: Double, _ name: String) {
        guard let r = Self.number(row) else {
            Issue.record("\(name): not a number")
            return
        }
        #expect(Self.shown(r) == form, "\(name)")
        // Only shown: Ans and memory read `value` and `exact`.
        #expect(r.exact == nil, "\(name)")
        #expect(abs(r.value - reference) <= 1e-9 * max(1, abs(reference)), "\(name): \(r.value)")
    }

    // MARK: Probe cases that showed only the decimal

    @Test func limitOfTwoToTheXMinusOneOverXIsLnTwo() throws {
        // owner-L07: lim x→0 (2ˣ − 1)/x = ln 2 = 0,6931471805599453; the limit gives 0,69314718056813.
        let row = try Self.limit("0", "(2^x-1)/x")
        expectForm(row, "ln(2)", value: log(2.0), "lim (2ˣ − 1)/x")
    }

    @Test func limitOfOnePlusXToTheOneOverXIsE() throws {
        // owner-L11: lim x→0 (1 + x)^(1/x) = e = 2,718281828459045; the limit gives 2,7182818284778.
        let row = try Self.limit("0", "(1+x)^(1/x)")
        expectForm(row, "e", value: M_E, "lim (1 + x)^(1/x)")
    }

    @Test func integralOfEToTheXFromZeroToOneIsEMinusOne() throws {
        // std-D23: ∫₀¹ eˣ dx = e − 1 = 1,718281828459045.
        let row = try Self.integral("e^x", "0", "1")
        expectForm(row, "e−1", value: M_E - 1, "∫₀¹ eˣ dx")
    }

    @Test func gaussianIntegralOverTheRealLineIsRootPi() throws {
        // std-D02: ∫ e^(−x²) dx over ℝ = √π = 1,772453850905516.
        let row = try Self.integral("e^(-x^2)", "-inf", "inf")
        expectForm(row, "√(π)", value: Double.pi.squareRoot(), "∫ e^(−x²) dx over ℝ")
    }

    @Test func gaussianIntegralFromZeroToInfinityIsHalfRootPi() throws {
        // std-D01: ∫₀^∞ e^(−x²) dx = √π/2 = 0,886226925452758.
        let row = try Self.integral("e^(-x^2)", "0", "inf")
        expectForm(row, "(√(π))/(2)", value: Double.pi.squareRoot() / 2, "∫₀^∞ e^(−x²) dx")
    }

    @Test func moreLimitsAndIntegralsShowTheirForm() throws {
        let e = M_E
        let cases: [(row: MathRow, form: String, value: Double, name: String)] = try [
            // Probe: owner-L08, owner-L09, wiki-L055, wiki-L056, wiki-L037, std-D24.
            (Self.limit("0", "(3^x-1)/x"), "ln(3)", log(3.0), "lim (3ˣ − 1)/x"),
            (Self.limit("0", "(10^x-1)/x"), "ln(10)", log(10.0), "lim (10ˣ − 1)/x"),
            (Self.limit("0", "(1+2*x)^(3/x)"), "e^(6)", exp(6.0), "lim (1 + 2x)^(3/x)"),
            (Self.limit("0", "(1-x)^(2/x)"), "(1)/(e^(2))", exp(-2.0), "lim (1 − x)^(2/x)"),
            (Self.limit("2", "e^x"), "e^(2)", exp(2.0), "lim x→2 eˣ"),
            (Self.integral("tan(x)", "0", "pi/4"), "(ln(2))/(2)", log(2.0) / 2, "∫₀^(π/4) tan x dx"),
            // owner-L12, inside a sum (see `limit`): e^(1/3) = ∛e, the limit gives 1,3956124250427.
            (Self.limit("inf", "(1+1/(3*x))^x", inSum: true), "root(3, e)", exp(1.0 / 3), "0 + lim x→∞ (1 + 1/(3x))^x"),
            // Definite integrals of the matura.
            (Self.integral("1/x", "2", "3"), "ln((3)/(2))", log(1.5), "∫₂³ dx/x"),
            (Self.integral("x*e^(x^2)", "0", "1"), "(e−1)/(2)", (e - 1) / 2, "∫₀¹ x·e^(x²) dx"),
            (Self.integral("x*ln(x)", "1", "e"), "(e^(2)+1)/(4)", (exp(2.0) + 1) / 4, "∫₁ᵉ x·ln x dx"),
            (Self.integral("e^(-x)", "0", "1"), "1−(1)/(e)", 1 - 1 / e, "∫₀¹ e^(−x) dx"),
            (Self.integral("x*e^(-x)", "0", "1"), "1−(2)/(e)", 1 - 2 / e, "∫₀¹ x·e^(−x) dx"),
            (Self.integral("e^(2*x)", "0", "1"), "(e^(2)−1)/(2)", (exp(2.0) - 1) / 2, "∫₀¹ e^(2x) dx"),
        ]
        for c in cases {
            expectForm(c.row, c.form, value: c.value, c.name)
        }
    }

    @Test func formsRenderInTextAndLaTeX() throws {
        let e = M_E, pi = Double.pi
        let cases: [(value: Double, text: String, latex: String)] = [
            (exp(1.0 / 3), "root(3, e)", #"\sqrt[3]{e}"#),
            (exp(2.0 / 3), "e^((2)/(3))", #"e^{\frac{2}{3}}"#),
            (exp(-2.0), "(1)/(e^(2))", #"\frac{1}{e^{2}}"#),
            (exp(0.5), "√(e)", #"\sqrt{e}"#),
            (e, "e", "e"),
            (1 / e, "(1)/(e)", #"\frac{1}{e}"#),
            (log(2.0), "ln(2)", #"\ln\left(2\right)"#),
            (log(2.0) / 2, "(ln(2))/(2)", #"\frac{\ln\left(2\right)}{2}"#),
            (2 * log(3.0), "2ln(3)", #"2\ln\left(3\right)"#),
            (log(1.5), "ln((3)/(2))", #"\ln\left(\frac{3}{2}\right)"#),
            (pi.squareRoot(), "√(π)", #"\sqrt{\pi }"#),
            (pi.squareRoot() / 2, "(√(π))/(2)", #"\frac{\sqrt{\pi }}{2}"#),
            (e - 1, "e−1", "e-1"),
            (e / 2, "(e)/(2)", #"\frac{e}{2}"#),
            (1 - 2 / e, "1−(2)/(e)", #"1-\frac{2}{e}"#),
            ((exp(2.0) - 1) / 2, "(e^(2)−1)/(2)", #"\frac{e^{2}-1}{2}"#),
        ]
        for c in cases {
            guard let form = Self.numeric(c.value).displayExact else {
                Issue.record("\(c.text): no exact form for \(c.value)")
                continue
            }
            let row = MathRowConverter.row(for: form)
            #expect(MathRowConverter.plainText(row) == c.text)
            let latex = LaTeXConverter.latex(row)
            #expect(latex == c.latex, "\(c.text)")
            // The row ("Vstavi rezultat" in the history) and the LaTeX pasted back mean the same number.
            let inserted = try RealEvaluator.evaluate(try MathRowConverter.expr(from: row))
            #expect(abs(inserted - c.value) <= 1e-12 * max(1, abs(c.value)), "\(c.text)")
            let pastedRow = try LaTeXConverter.row(fromLaTeX: latex)
            let pasted = try RealEvaluator.evaluate(try MathRowConverter.expr(from: pastedRow))
            #expect(abs(pasted - c.value) <= 1e-12 * max(1, abs(c.value)), "\(latex)")
        }
    }

    // MARK: Guards: what stays as it was

    @Test func ansKeepsTheDecimalValue() throws {
        // CalculatorModel passes Ans as `value` and only an `exact` as an exact variable. After ∫₀¹ eˣ dx = e − 1,
        // Ans is the decimal 1,718281828459 (13 digits), so Ans + 1 is the decimal 2,718281828, not e.
        let row = try Self.integral("e^x", "0", "1")
        let r = try #require(Self.number(row))
        #expect(r.exact == nil)
        let ansPlusOne = MathRow([.symbol(.ans), .symbol(.plus), .symbol(.digit(1))])
        let calculation = CalculationEngine.calculate(ansPlusOne, variables: ["Ans": r.value], exactVariables: [:], settings: CalculationSettings())
        guard case .number(let next) = calculation.outcome else {
            Issue.record("Ans + 1 gave \(calculation.outcome)")
            return
        }
        #expect(next.displayExact == nil)
        #expect(abs(next.value - M_E) < 1e-12)
    }

    @Test func ordinaryDecimalsStayDecimals() throws {
        let e = M_E, pi = Double.pi, third = exp(1.0 / 3)
        let values: [Double] = [
            // Near e^(1/3) = 1,3956124250860895, e, ln 2 and √π, but not within 1e-9.
            1.3956, 1.39561242, third * (1 + 3e-9), third * (1 - 3e-9), e * (1 + 2e-9), log(2.0) + 2e-9, pi.squareRoot() * (1 + 2e-9),
            // Values of other functions and constants.
            sin(1.0), cos(1.0), sin(2.0), cos(2.0), tan(1.0), atan(2.0), log10(2.0), log2(3.0), (2 * pi).squareRoot(),
            pow(pi, 3) / 32, 0.5772156649015329, 1.2020569031595942, 1 / log(2.0), e - 1 / e, pi / e, e * pi, pi / 3.0.squareRoot(),
            // The probe's wrong results (0,500000627 for 1/2, 0,999991403 for 1, 1,570707111 for π/2).
            0.50000062712940996, 0.99999140327113001, 1.5707071111494999,
        ]
        for x in values {
            let r = Self.numeric(x)
            #expect(r.closedForm == nil, "\(x)")
            #expect(r.displayExact == nil, "\(x)")
        }
        // wiki-L089, wiki-L092 through the calculator: sin 1 and cos 2 stay decimals.
        for (point, body) in [("1", "sin(x)"), ("2", "cos(x)")] {
            let row = try Self.limit(point, body)
            let r = try #require(Self.number(row))
            #expect(Self.shown(r) == nil, "lim x→\(point) \(body)")
        }
    }

    @Test func deterministicSequencesStayDecimals() {
        // 2 × 10 000 values spread like random ones, uniform in [−10, 10) and log-uniform in [10⁻⁶, 10⁶). None is
        // within 1e-9 of a new form (Python port of the recogniser; on 1,2 million random doubles none was either).
        var matched: [Double] = []
        for k in 1...10_000 {
            let t = (Double(k) * 0.6180339887498949).truncatingRemainder(dividingBy: 1)
            for x in [t * 20 - 10, pow(10, t * 12 - 6)] where Self.numeric(x).closedForm != nil {
                matched.append(x)
            }
        }
        #expect(matched.isEmpty, "\(matched)")
    }

    @Test func existingFormsComeFirstAndAreUnchanged() throws {
        // π, fractions, surds and integers keep their ExactReal (and so Ans keeps them exact) and get no closed form.
        let sincRow = try Self.integral("sin(x)/x", "-inf", "inf")
        let sinc = try #require(Self.number(sincRow))
        #expect(sinc.exact == ExactReal.pi)
        #expect(sinc.closedForm == nil)
        let oneRow = try Self.limit("0", "sin(x)/x")
        let one = try #require(Self.number(oneRow))
        #expect(one.exact == ExactReal(1))
        #expect(one.displayExact == nil)
        let rootRow = try Self.limit("2", "x^(1/2)")
        let root = try #require(Self.number(rootRow))
        #expect(Self.shown(root) == "√(2)")
        #expect(root.closedForm == nil)
        let half = Self.numeric(0.5)
        #expect(half.exact == ExactReal(Rational.half))
        #expect(half.closedForm == nil)
    }

    @Test func finiteSumsKeepTheDecimal() throws {
        // A finite Σ of rational terms is a rational number, not e or ln 2, but it can come within 1e-9 of one:
        // Σ_{n=0}^{11} 1/n! = 13563139/4989600 = 2,718281826198493 is 2,26·10⁻⁹ below e (the tolerance is
        // 2,72·10⁻⁹) and showed "= e ≈ 2,718281826". origin/main showed only the decimal, as here. The references
        // are the exact sums (Python fractions) as doubles; RealEvaluator's loop of doubles is within 2·10⁻¹⁵.
        let cases: [(text: String, value: Double)] = [
            ("sum(1/n!, n, 0, 11)", 13563139.0 / 4989600),           // e − 2,3·10⁻⁹
            ("sum((-1)^n/n!, n, 0, 12)", 16019531.0 / 43545600),      // 1/e + 1,5·10⁻¹⁰
            ("sum(2^n/n!, n, 0, 15)", 4718007451.0 / 638512875),      // e² − 3,5·10⁻⁹
            ("sum(1/(n*2^n), n, 1, 26)", 0.6931471800265223),         // ln 2 − 5,3·10⁻¹⁰
        ]
        for c in cases {
            let row = try MathRowConverter.row(fromText: c.text)
            guard let r = Self.number(row) else {
                Issue.record("\(c.text): not a number")
                continue
            }
            #expect(r.closedForm == nil, "\(c.text)")
            #expect(r.displayExact == nil, "\(c.text)")
            #expect(abs(r.value - c.value) <= 1e-12, "\(c.text): \(r.value)")
        }
    }

    @Test func seriesToInfinityKeepsItsForm() throws {
        // Σ to ∞ is a limit: Σ_{n=0}^{∞} 1/n! = e (the series stops at n = 30, within an ulp or so of e).
        let row = try MathRowConverter.row(fromText: "sum(1/n!, n, 0, inf)")
        expectForm(row, "e", value: M_E, "Σ_{n=0}^{∞} 1/n!")
    }

    @Test func truncatedIntegralsKeepTheDecimal() throws {
        // An ∫ over a finite range is computed to 1e-11 and can come within 1e-9 of a form it is not:
        // ∫₋₂₀¹ eˣ dx = e − e⁻²⁰ = 2,7182818263978916 is 2,06·10⁻⁹ below e (the tolerance was 1e-9·e = 2,72·10⁻⁹)
        // and showed "= e ≈ 2,718281826"; ∫₀^(9/2) e^(−x²) dx = (√π/2)·erf(9/2) is 1,7·10⁻¹⁰ below √π/2 and showed
        // "= √π/2". origin/main showed only the decimal, as here: such forms now need 1e-11. References: Foundation
        // exp and erf; the Integrator's 13-digit value is within 1e-14 of them (Python port of the G7/K15 rule).
        let cases: [(row: MathRow, value: Double, name: String)] = try [
            (Self.integral("e^x", "-20", "1"), M_E - exp(-20.0), "∫₋₂₀¹ eˣ dx"),
            (Self.integral("e^(-x^2)", "0", "9/2"), Double.pi.squareRoot() / 2 * Foundation.erf(4.5), "∫₀^(9/2) e^(−x²) dx"),
        ]
        for c in cases {
            guard let r = Self.number(c.row) else {
                Issue.record("\(c.name): not a number")
                continue
            }
            #expect(r.closedForm == nil, "\(c.name)")
            #expect(r.displayExact == nil, "\(c.name)")
            #expect(abs(r.value - c.value) <= 1e-11 * max(1, abs(c.value)), "\(c.name): \(r.value)")
        }
        // The forms of finite ranges stay: ∫₀¹ eˣ dx (std-D23) is 1,718281828459, 2,6·10⁻¹⁴ from e − 1.
        let row = try Self.integral("e^x", "0", "1")
        expectForm(row, "e−1", value: M_E - 1, "∫₀¹ eˣ dx")
    }

    @Test func eMinusAQuarterIsAForm() throws {
        // e ± a/c was a form only for halves and thirds ((a + b·e)/c had |b| ≤ 3, and e + a/c needs b = c), so
        // ∫₀¹ (eˣ + x³) dx = e − 3/4 = 1,968281828459045 showed only 1,968281828. It is drawn like e − 1/2, which
        // shows (2e − 1)/2. References: e − k/(k + 1) for ∫₀¹ (eˣ + xᵏ) dx.
        let cases: [(row: MathRow, form: String, value: Double, name: String)] = try [
            (Self.integral("e^x+x^3", "0", "1"), "(4e−3)/(4)", M_E - 3.0 / 4, "∫₀¹ (eˣ + x³) dx"),
            (Self.integral("e^x+x^4", "0", "1"), "(5e−4)/(5)", M_E - 4.0 / 5, "∫₀¹ (eˣ + x⁴) dx"),
            (Self.integral("e^x+x^5", "0", "1"), "(6e−5)/(6)", M_E - 5.0 / 6, "∫₀¹ (eˣ + x⁵) dx"),
        ]
        for c in cases {
            expectForm(c.row, c.form, value: c.value, c.name)
        }
        // 3·10⁻⁹ away, beyond the 1e-9 (relative) of a limit: stays a decimal.
        let near = Self.numeric(M_E - 3.0 / 4 + 3e-9)
        #expect(near.closedForm == nil)
        #expect(near.displayExact == nil)
    }
}
