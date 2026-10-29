import Foundation
import Testing
@testable import AcuteCore

// MAT-07 (values): LimitEvaluator's samples gave wrong digits at a finite point in two classes, which the owner
// approved fixing narrowly. Rounding inside f that the extrapolation amplifies: lim x→0 (1 − cos x)/x² showed
// 0,500000627 (true 1/2). A part that is no power of the step: lim x→0⁺ x·ln x showed −0,000008596 (true 0) and
// lim x→0⁺ xˣ 0,999991403 (true 1). The limits are built as the keypad builds them and go through
// CalculationEngine.calculate, the call CalculatorModel makes; other values and errors stay as they were.

@Suite struct AuditLimitValueTests {
    /// lim, lim⁻ or lim⁺ from the keypad with the point and the body typed as text.
    func limitNode(_ point: String, _ body: String, _ direction: LimitDirection) throws -> MathNode {
        .limit(point: try MathRowConverter.row(fromText: point), body: try MathRowConverter.row(fromText: body), direction: direction)
    }

    func outcome(_ point: String, _ body: String, _ direction: LimitDirection) throws -> CalculationOutcome {
        let row = MathRow([try limitNode(point, body, direction)])
        return CalculationEngine.calculate(row, variables: [:], exactVariables: [:], settings: CalculationSettings()).outcome
    }

    /// The decimal the calculator shows by default (NORM1, 10 digits, decimal comma).
    func shown(_ value: Double) -> String {
        NumberFormatting.format(value, options: NumberFormatOptions()).plainText
    }

    /// References from the Taylor series at the point: 1 − cos x = x²/2 − x⁴/24 + …, x − sin x = x³/6 − …,
    /// 1 − cos 2x = 2x² − …, x·sin x = x² − …, tan x − sin x = x³/2 + …, eˣ − 1 − x = x²/2 + …
    @Test func cancellationAtAPointShowsTheLimit() throws {
        let cases: [(point: String, body: String, direction: LimitDirection, shown: String)] = [
            ("0", "(1-cos(x))/x^2", .both, "0,5"), ("0", "(1-cos(x))/x^2", .right, "0,5"), ("0", "(1-cos(x))/x^2", .left, "0,5"),
            ("0", "(x-sin(x))/x^3", .right, "0,166666667"), ("0", "(1-cos(2*x))/x^2", .right, "2"),
            ("0", "(1-cos(x))/(x*sin(x))", .right, "0,5"), ("1", "(1-cos(x-1))/(x-1)^2", .right, "0,5"),
        ]
        for c in cases {
            let result = try outcome(c.point, c.body, c.direction)
            guard case .number(let number) = result else {
                Issue.record("lim x→\(c.point) (\(c.direction)) \(c.body) gave \(result)")
                continue
            }
            #expect(shown(number.value) == c.shown, "lim x→\(c.point) (\(c.direction)) \(c.body) = \(number.value)")
        }
    }

    /// References: xᵖ·ln x → 0 for p > 0 (so sin x·ln x → 0 too), and xˣ = e^(x·ln x), x^(sin x) = e^(sin x·ln x) → e⁰ = 1.
    /// Only the right side of 0 is defined for these, so lim x→0 is the right-hand limit.
    @Test func slowConvergenceAtZeroShowsTheLimit() throws {
        let cases: [(body: String, direction: LimitDirection, shown: String)] = [
            ("x*ln(x)", .right, "0"), ("x^x", .right, "1"), ("x^2*ln(x)", .right, "0"), ("x^sin(x)", .right, "1"),
            ("sin(x)*ln(x)", .right, "0"), ("x*ln(x)", .both, "0"), ("x^x", .both, "1"),
        ]
        for c in cases {
            let result = try outcome("0", c.body, c.direction)
            guard case .number(let number) = result else {
                Issue.record("lim x→0 (\(c.direction)) \(c.body) gave \(result)")
                continue
            }
            #expect(shown(number.value) == c.shown, "lim x→0 (\(c.direction)) \(c.body) = \(number.value)")
        }
        // Inside an expression (0 + lim …) the same value.
        let nested = MathRow([.symbol(.digit(0)), .symbol(.plus), try limitNode("0", "x^x", .right)])
        let result = CalculationEngine.calculate(nested, variables: [:], exactVariables: [:], settings: CalculationSettings()).outcome
        guard case .number(let number) = result else {
            Issue.record("0 + lim x→0⁺ xˣ gave \(result)")
            return
        }
        #expect(shown(number.value) == "1", "0 + lim x→0⁺ xˣ = \(number.value)")
    }

    /// The owner's examples get their exact form again: 1/2 and 1 (main's 0,500000627 and 0,999991403 got none).
    @Test func ownerExamplesHaveTheirExactForm() throws {
        let half = try outcome("0", "(1-cos(x))/x^2", .both)
        guard case .number(let h) = half else {
            Issue.record("lim x→0 (1 − cos x)/x² gave \(half)")
            return
        }
        #expect(h.exact == ExactReal(Rational.half), "lim x→0 (1 − cos x)/x² = \(h.value)")
        let one = try outcome("0", "x^x", .right)
        guard case .number(let o) = one else {
            Issue.record("lim x→0⁺ xˣ gave \(one)")
            return
        }
        #expect(o.exact == ExactReal(1), "lim x→0⁺ xˣ = \(o.value)")
        let zero = try outcome("0", "x*ln(x)", .right)
        guard case .number(let z) = zero else {
            Issue.record("lim x→0⁺ x·ln x gave \(zero)")
            return
        }
        #expect(z.value == 0, "lim x→0⁺ x·ln x = \(z.value)")
    }

    /// Where the samples' value is not proven wrong it stays bit for bit: values main shows right (eˣ − 1 over x is
    /// 0,99999999996533 from the right, shown 1), and a body whose constant sets a scale below the samples
    /// ((1 − cos x)/(x² + 10⁻²⁰) → 0 and (1 − cos x)/x² + x/(x + 10⁻²⁰) → 1/2 look like 1/2 and 3/2 on all of them).
    @Test func otherValuesAreKept() throws {
        let cases: [(point: Double, body: String, direction: LimitDirection)] = [
            (0, "sin(x)/x", .right), (0, "(e^x-1)/x", .right), (0, "(e^x-1)/x", .left), (0, "ln(1+x)/x", .right),
            (2, "(x^3-8)/(x-2)", .right), (0, "(1+x)^(1/x)", .right),
            (0, "(1-cos(x))/(x^2+10^(-20))", .right), (0, "(1-cos(x))/x^2+x/(x+10^(-20))", .right),
            (0, "sin(x)/x", .both), (2, "x^(1/2)", .both), (0, "(2^x-1)/x", .both), (0, "(1+2*x)^(3/x)", .both),
        ]
        for c in cases {
            let body = try parse(c.body)
            let f = FunctionAnalyzer.makeFunction(body, variable: "x", context: EvaluationContext())
            let expected: Double
            switch c.direction {
            case .left: expected = try #require(LimitEvaluator.oneSided(f, c.point, -1))
            case .right: expected = try #require(LimitEvaluator.oneSided(f, c.point, 1))
            case .both:
                let l = try #require(LimitEvaluator.oneSided(f, c.point, -1))
                let r = try #require(LimitEvaluator.oneSided(f, c.point, 1))
                expected = NumericCalculus.clean(0.5 * (l + r))
            }
            let limit = try LimitEvaluator.limit(body, variable: "x", at: c.point, direction: c.direction, context: EvaluationContext())
            #expect(limit == expected, "\(c.body) at \(c.point) (\(c.direction))")
        }
    }

    /// Errors stay errors: sides that disagree on the samples ((eˣ − 1 − x)/x², (x − ln(1 + x))/x²,
    /// (√(1 + x) − 1 − x/2)/x² at 0) and samples that do not settle (√x·ln x and x·ln²x at 0⁺).
    @Test func errorsAreKept() throws {
        for body in ["(e^x-1-x)/x^2", "(x-ln(1+x))/x^2", "(sqrt(1+x)-1-x/2)/x^2"] {
            let expr = try parse(body)
            let f = FunctionAnalyzer.makeFunction(expr, variable: "x", context: EvaluationContext())
            let l = try #require(LimitEvaluator.oneSided(f, 0, -1))
            let r = try #require(LimitEvaluator.oneSided(f, 0, 1))
            // Main's rule for two sides; where its sides agree here, the value is main's and not this test's concern.
            guard abs(l - r) > 1e-7 * max(1, abs(l)) else { continue }
            #expect(throws: MathError.self, "\(body) at 0") {
                try LimitEvaluator.limit(expr, variable: "x", at: 0, direction: .both, context: EvaluationContext())
            }
        }
        for body in ["sqrt(x)*ln(x)", "x*ln(x)^2"] {
            let expr = try parse(body)
            let f = FunctionAnalyzer.makeFunction(expr, variable: "x", context: EvaluationContext())
            guard LimitEvaluator.oneSided(f, 0, 1) == nil else { continue }
            #expect(throws: MathError.self, "\(body) at 0⁺") {
                try LimitEvaluator.limit(expr, variable: "x", at: 0, direction: .right, context: EvaluationContext())
            }
        }
    }
}
