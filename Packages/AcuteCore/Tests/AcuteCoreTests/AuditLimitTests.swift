import Foundation
import Testing
@testable import AcuteCore

// MAT-07: limits that are ±∞ where LimitEvaluator said "limita ne obstaja" (its samples reach only
// |f| ≈ 4·10⁴ at 1/(x − 2) near 2, its rule for ±∞ wants 10⁶), and x → ±∞ typed on its own, which the
// calculator always answered with "Prevelika vrednost" (it evaluated the point ∞ with
// RealEvaluator.evaluate). The limits are built as the keypad builds them and go through
// CalculationEngine.calculate, the call CalculatorModel makes.

@Suite struct AuditLimitTests {
    /// lim, lim⁻ or lim⁺ from the keypad with the point and the body typed as text ("inf" is ∞).
    func limitNode(_ point: String, _ body: String, _ direction: LimitDirection) throws -> MathNode {
        .limit(point: try MathRowConverter.row(fromText: point), body: try MathRowConverter.row(fromText: body), direction: direction)
    }

    func outcome(_ point: String, _ body: String, _ direction: LimitDirection = .both) throws -> CalculationOutcome {
        let row = MathRow([try limitNode(point, body, direction)])
        return CalculationEngine.calculate(row, variables: [:], exactVariables: [:], settings: CalculationSettings()).outcome
    }

    /// The decimal the calculator shows by default (NORM1, 10 significant digits, decimal comma).
    func shown(_ value: Double) -> String {
        NumberFormatting.format(value, options: NumberFormatOptions()).plainText
    }

    /// References from the leading term at the point: K/(x − a)ᵐ, ln of a simple zero, tan at its poles
    /// (tan(πx + π/2) = −cot πx), 1/√(x − 2).
    @Test func infiniteLimitsAtFinitePoints() throws {
        let cases: [(point: String, body: String, direction: LimitDirection, positive: Bool)] = [
            ("2", "1/(x-2)", .right, true), ("2", "1/(x-2)", .left, false), ("2", "(x+1)/(x-2)", .right, true),
            ("0", "1/x", .right, true), ("0", "1/x", .left, false), ("0", "x^(-1)", .right, true),
            ("0", "ln(x)", .right, false), ("0", "ln(x)/ln(2)", .right, false),
            ("0", "ln(x)/ln(1/2)", .right, true), ("1", "1/ln(x)", .right, true), ("0", "1/(e^x-1)", .left, false),
            ("0", "tan(pi*x+pi/2)", .right, false), ("0", "tan(pi*x+pi/2)", .left, true),
            ("1", "tan(pi*x+pi/2)", .right, false), ("1", "tan(pi*x+pi/2)", .left, true),
            ("pi/2", "tan(x)", .left, true), ("pi/2", "tan(x)", .right, false),
            ("2", "1/sqrt(x-2)", .right, true), ("2", "1/(x^2-4)", .right, true),
        ]
        for c in cases {
            let result = try outcome(c.point, c.body, c.direction)
            guard case .infinite(let positive) = result else {
                Issue.record("lim x→\(c.point) (\(c.direction)) \(c.body) gave \(result)")
                continue
            }
            #expect(positive == c.positive, "lim x→\(c.point) (\(c.direction)) \(c.body)")
        }
    }

    /// References from the leading term: c·xᵖ (p > 0), c·ln x, aˣ with a > 1, e^(−x) at −∞.
    @Test func infiniteLimitsAtInfinityTypedAlone() throws {
        let cases: [(point: String, body: String, positive: Bool)] = [
            ("inf", "x", true), ("-inf", "x", false), ("inf", "sqrt(x)", true), ("inf", "x^(1/3)", true),
            ("inf", "ln(x)", true), ("inf", "ln(x)/ln(1/2)", false), ("inf", "e^x", true), ("inf", "2^x", true),
            ("inf", "x^2", true), ("inf", "x/2", true), ("inf", "x/(-2)", false), ("inf", "(x^2+1)/x", true),
            ("inf", "(2*x^2+1)/(x-1)", true), ("-inf", "x^3", false), ("-inf", "e^(-x)", true),
        ]
        for c in cases {
            let result = try outcome(c.point, c.body)
            guard case .infinite(let positive) = result else {
                Issue.record("lim x→\(c.point) \(c.body) gave \(result)")
                continue
            }
            #expect(positive == c.positive, "lim x→\(c.point) \(c.body)")
        }
    }

    /// References: e, e², e^(1/3), e⁻², e⁻¹, π/2, leading coefficients 2 and 3/7, x·sin(1/x) → 1,
    /// √(x² + x) − x → 1/2, and 0 for 2/x, (1/2)ˣ, x·e⁻ˣ, eˣ at −∞ — as shown.
    @Test func finiteLimitsAtInfinityTypedAlone() throws {
        let cases: [(point: String, body: String, shown: String)] = [
            ("inf", "(1+1/x)^x", "2,718281828"), ("-inf", "(1+2/x)^x", "7,389056099"),
            ("inf", "(1+1/(3*x))^x", "1,395612425"), ("inf", "(x/(x+2))^x", "0,135335283"),
            ("inf", "(1-1/x)^x", "0,367879441"), ("inf", "arctan(x)", "1,570796327"),
            ("inf", "(2*x+1)/(x-3)", "2"), ("inf", "(3*x^2+1)/(7*x^2-x)", "0,428571429"),
            ("inf", "x*sin(1/x)", "1"), ("inf", "sqrt(x^2+x)-x", "0,5"),
            ("inf", "2/x", "0"), ("inf", "(1/2)^x", "0"), ("inf", "x*e^(-x)", "0"), ("-inf", "e^x", "0"),
        ]
        for c in cases {
            let result = try outcome(c.point, c.body)
            guard case .number(let number) = result else {
                Issue.record("lim x→\(c.point) \(c.body) gave \(result)")
                continue
            }
            #expect(shown(number.value) == c.shown, "lim x→\(c.point) \(c.body) = \(number.value)")
        }
    }

    /// The owner's input on the device, lim x→∞ (3x + 1)/(x² + x + 1), showed "Prevelika vrednost" on origin/main.
    /// References from the leading terms: 3x/x² → 0 at ±∞, 2x²/x² → 2.
    @Test func rationalLimitsAtInfinityTypedAlone() throws {
        let cases: [(point: String, body: String, shown: String)] = [
            ("inf", "(3*x+1)/(x^2+x+1)", "0"), ("inf", "(2*x^2+1)/(x^2+3)", "2"), ("-inf", "(3*x+1)/(x^2+x+1)", "0"),
        ]
        for c in cases {
            let result = try outcome(c.point, c.body)
            guard case .number(let number) = result else {
                Issue.record("lim x→\(c.point) \(c.body) gave \(result)")
                continue
            }
            #expect(shown(number.value) == c.shown, "lim x→\(c.point) \(c.body) = \(number.value)")
        }
    }

    /// A body without x is its own limit. The constant-tail guard read lim x→∞ 3 as "limita ne obstaja"
    /// (review of #34); origin/main showed "Prevelika vrednost".
    @Test func constantBodiesAtInfinityAreTheirValue() throws {
        let cases: [(point: String, body: String, value: Double)] = [("inf", "3", 3), ("-inf", "2+5", 7), ("inf", "1/4", 0.25)]
        for c in cases {
            let result = try outcome(c.point, c.body)
            guard case .number(let number) = result else {
                Issue.record("lim x→\(c.point) \(c.body) gave \(result)")
                continue
            }
            #expect(shown(number.value) == shown(c.value), "lim x→\(c.point) \(c.body) = \(number.value)")
        }
    }

    /// The true limits (1 + a/x)^(bx) → e^(ab), ((x + a)/(x − b))^x = (1 + (a + b)/(x − b))^x → e^(a+b) and
    /// (1 + sin(c/x))^x → e^c (x·ln(1 + sin(c/x)) → c), computed to 50 digits, as shown. With only the grids'
    /// spread and 10⁻¹² as the margin the calculator showed the last digit one off for each (e¹⁵ as 3269017,373).
    /// An error is fine (main's), another value is not.
    @Test func finiteLimitsAtInfinityShowTheirDigitsOrAnError() throws {
        let cases: [(body: String, shown: String)] = [
            ("(1+3/(2*x))^(10*x)", "3269017,372"), ("(1+0.07/x)^(10*x)", "2,013752707"), ("(1+1.3/x)^(5*x)", "665,141633"),
            ("(1+7/(8*x))^(12*x)", "36315,50267"), ("((9*x-8)/(9*x-9))^(9*x)", "2,718281828"),
            ("((13*x+5)/(13*x+4))^(13*x)", "2,718281828"), ("((5*x+5)/(5*x-6))^(2*x)", "81,45086866"),
            ("(1+1/(3.9*x))^x", "1,292282786"), ("((x+1.3)/(x-1.3))^x", "13,46373804"),
            ("((11*x+4)/(11*x-5))^(11*x)", "8103,083928"), ("(1+1.7412/x)^x", "5,704184339"), ("(1+sin(4.5744/x))^x", "96,96983978"),
            // 2 + 10⁻⁹: the second term is 10⁻⁹·x⁴/(x⁴ + 10²⁰) → 10⁻⁹, but only 10⁻¹³ at x = 10 240.
            ("(2*x+1)/(x-3)+0.000000001*x^4/(x^4+10^20)", "2,000000001"),
        ]
        for c in cases {
            let result = try outcome("inf", c.body)
            switch result {
            case .error:
                continue
            case .number(let number):
                #expect(shown(number.value) == c.shown, "lim x→∞ \(c.body) = \(number.value)")
            default:
                Issue.record("lim x→∞ \(c.body) gave \(result)")
            }
        }
    }

    /// e¹⁴ and e¹³ (((x + a)/(x − b))^x = (1 + (a + b)/(x − b))^x → e^(a+b)) are transcendental, so no p/q,
    /// (p/q)·√n or (p/q)·π² is their exact form: numeric's tolerance of 10⁻⁹·|x| fitted 3436728√6/7 to e¹⁴.
    /// π/2 and 3/7 keep theirs.
    @Test func largeLimitsAtInfinityGetNoExactForm() throws {
        let cases: [(body: String, shown: String)] = [
            ("((x+7)/(x-7))^x", "1202604,284"), ("((x+1)/(x-6))^(2*x)", "1202604,284"), ("((x+6)/(x-7))^x", "442413,392"),
        ]
        for c in cases {
            let result = try outcome("inf", c.body)
            guard case .number(let number) = result else {
                Issue.record("lim x→∞ \(c.body) gave \(result)")
                continue
            }
            #expect(number.exact == nil, "lim x→∞ \(c.body) = \(String(describing: number.exact))")
            #expect(shown(number.value) == c.shown, "lim x→∞ \(c.body) = \(number.value)")
        }
        for (body, value) in [("arctan(x)", Double.pi / 2), ("(3*x^2+1)/(7*x^2-x)", 3.0 / 7)] {
            guard case .number(let number) = try outcome("inf", body), let exact = number.exact else {
                Issue.record("lim x→∞ \(body) has no exact form")
                continue
            }
            #expect(Swift.abs(exact.doubleValue - value) < 1e-15, "lim x→∞ \(body) = \(exact)")
        }
    }

    /// One lim on its own shows its e, ln or √π form (origin/main: lim x→0 (1 + x)^(1/x) = e), at ±∞ typed alone
    /// too: (1 + a/x)^(bx) → e^(ab), as ResultView draws it above the decimal. References: Foundation exp. Values
    /// of 10⁴ and more still get no form of either kind: (10⁷x + 1)/x → 10⁷, ((x + 7)/(x − 7))^x → e¹⁴.
    @Test func limitsAtInfinityShowTheFormOfOneLimit() throws {
        let cases: [(point: String, body: String, form: String, value: Double)] = [
            ("inf", "(1+1/x)^x", "e", M_E), ("inf", "(1+1/(3*x))^x", "root(3, e)", exp(1.0 / 3)),
            ("inf", "(1-1/x)^x", "(1)/(e)", exp(-1.0)), ("-inf", "(1+2/x)^x", "e^(2)", exp(2.0)),
        ]
        for c in cases {
            let result = try outcome(c.point, c.body)
            guard case .number(let number) = result else {
                Issue.record("lim x→\(c.point) \(c.body) gave \(result)")
                continue
            }
            let form = number.displayExact.map { MathRowConverter.plainText(MathRowConverter.row(for: $0)) }
            #expect(form == c.form, "lim x→\(c.point) \(c.body)")
            // Only shown: Ans and memory read `value` and `exact`.
            #expect(number.exact == nil, "lim x→\(c.point) \(c.body)")
            #expect(shown(number.value) == shown(c.value), "lim x→\(c.point) \(c.body) = \(number.value)")
        }
        for (body, value) in [("(10^7*x+1)/x", "10000000"), ("((x+7)/(x-7))^x", "1202604,284")] {
            let result = try outcome("inf", body)
            guard case .number(let number) = result else {
                Issue.record("lim x→∞ \(body) gave \(result)")
                continue
            }
            #expect(number.exact == nil, "lim x→∞ \(body) = \(String(describing: number.exact))")
            #expect(number.displayExact == nil, "lim x→∞ \(body) = \(String(describing: number.displayExact))")
            #expect(shown(number.value) == value, "lim x→∞ \(body) = \(number.value)")
        }
        // e^(1 + 2·10⁻¹⁰) = 2,7182818290027… is within 10⁻⁹·e of e, but its digits are not e's: no form (or an error).
        let near = try outcome("inf", "(1+1.0000000002/x)^x")
        switch near {
        case .error:
            break
        case .number(let number):
            #expect(number.displayExact == nil, "lim x→∞ (1+1.0000000002/x)^x = \(String(describing: number.displayExact))")
            #expect(shown(number.value) == "2,718281829", "lim x→∞ (1+1.0000000002/x)^x = \(number.value)")
        default:
            Issue.record("lim x→∞ (1+1.0000000002/x)^x gave \(near)")
        }
    }

    /// The finding's examples on LimitEvaluator itself: |1/(x − 2)| and (x² + 1)/x stay below 10⁶ on its samples.
    @Test func limitEvaluatorGivesInfinityWhereItsSamplesStopShort() throws {
        #expect(try LimitEvaluator.limit({ 1 / ($0 - 2) }, at: 2, direction: .right) == .infinity)
        #expect(try LimitEvaluator.limit({ 1 / ($0 - 2) }, at: 2, direction: .left) == -.infinity)
        // At ±∞ only a body known to be elementary is read as ±∞, so through the Expr entry point, as main has it.
        let atInfinity = try LimitEvaluator.limit(try parse("(x^2+1)/x"), variable: "x", at: .infinity, direction: .both, context: EvaluationContext())
        #expect(atInfinity == .infinity)
        #expect(try LimitEvaluator.limit({ log($0) }, at: 0, direction: .right) == -.infinity)
    }

    /// No limit: an oscillation (also of a growing or slowly turning sign), different or missing sides, a jump.
    /// Still an error, not a value.
    @Test func limitsThatDoNotExistStayErrors() throws {
        let cases: [(point: String, body: String, direction: LimitDirection)] = [
            ("0", "1/x", .both), ("pi/2", "tan(x)", .both), ("0", "e^(1/x)", .both), ("0", "sin(1/x)", .both),
            ("0", "sin(1/x)", .right), ("inf", "x*sin(x)", .both), ("2", "floor(x)", .both), ("2", "1/sqrt(x-2)", .left),
            ("inf", "x^0.5*sin(0.05*ln(x))", .both), ("0", "x^(-0.5)*sin(0.05*ln(x))", .right),
            ("inf", "e^x*cos(0.1*ln(x)+1)", .both), ("inf", "x*sin(2*pi*x)", .both), ("inf", "(-1)^floor(x)*x", .both),
            // Unbounded, but 0 at every zero of the factor (sin²x at nπ, 1 + sin x at 3π/2 + 2nπ, …), where the
            // samples only overflow to ∞.
            ("inf", "e^x*sin(x)^2", .both), ("inf", "e^x*(1+sin(x))", .both), ("inf", "2^x*(1+cos(x))", .both),
            ("inf", "e^x*abs(sin(x))", .both), ("inf", "e^(2*x)*sin(x)^2", .both), ("-inf", "e^(-x)*sin(x)^2", .both),
            ("0", "e^(0.1/sqrt(x))*sin(10/x)^2", .right),
            // Undefined on (0, 10⁻¹⁴].
            ("0", "1/sqrt(x-10^(-14))", .right),
            // Defined on both sides, +∞ at 0⁺ and −∞ at 0⁻ (or the other way), but one side overflows to NaN inside.
            ("0", "e^(45/x)/(e^(45/x)+1)+1/x", .both), ("0", "e^(-45/x)/(e^(-45/x)+1)+1/x", .both),
            ("0", "1/x+(e^(1000/x)-e^(1000/x))", .both), ("0", "1/x+e^(1/x^3)/(1+e^(1/x^3))", .both),
            // Periodic in log₂x: ±1 at x = 2^(n/2) and 2^(n/2 + 1/4) for cos, a full period of sin² every octave.
            ("inf", "cos(4*pi*ln(x)/ln(2))+1/x", .both), ("inf", "sin(4*pi*ln(x)/ln(2))+1/x", .both),
            ("inf", "sin(2*pi*ln(x)/ln(2))^2+1/x", .both),
            // x on x = 16·2ᵏ and on x = 22,6·3ᵏ, yet −x where both sin² are 1 (ln 2/ln 3 is irrational, so that
            // happens for arbitrarily large x).
            ("inf", "x*(1-2*sin(pi*ln(x)/ln(2))^2*sin(pi*ln(x/(16*sqrt(2)))/ln(3))^2)", .both),
        ]
        for c in cases {
            let result = try outcome(c.point, c.body, c.direction)
            guard case .error = result else {
                Issue.record("lim x→\(c.point) (\(c.direction)) \(c.body) gave \(result)")
                continue
            }
        }
    }

    /// Limits the samples cannot settle: slow convergence or divergence, total cancellation in a Taylor remainder,
    /// an overflow inside f, a pole 10⁻¹⁴…10⁻⁹ beside the point. An error today; the true value would do too, but
    /// no other value. References: x^(1/x) = e^(ln x/x), ln x/x, sin x/x and x¹⁵⁰e⁻ˣ → 0, x^0,01 = e^(0,01·ln x) → 0,
    /// x^p·ln x → 0 for p > 0, cos u − 1 + u²/2 = u⁴/24 − … with u = 10⁻⁸/x, a numerator that is 0, Stirling's
    /// Γ(x + 1)^(1/x) ~ x/e, and f(2) for the pole at 2,000000001.
    @Test func limitsTheSamplesCannotSettleGiveTheLimitOrAnError() throws {
        // f at the point, in Double as the calculator evaluates f.
        let at2: Double = 1 / (2 - 2.000000001), nearer2: Double = 1 / (2 - 2.0000000000001), besidePi: Double = 1 / sin(3.14159265359)
        let gap100: Double = 100 - 100.000000000001, at1000: Double = 1 / (1000 - 1000.00000000001)
        let at100: Double = 1 / (gap100 * gap100)
        let eMinus40: Double = exp(-40), eMinus50: Double = exp(-50), eMinus36: Double = exp(-36), piOver2e15: Double = Double.pi / 2e15
        let cases: [(point: String, body: String, direction: LimitDirection, limit: Double)] = [
            ("inf", "x^(1/x)", .both, 1), ("inf", "ln(x)/x", .both, 0), ("inf", "sin(x)/x", .both, 0), ("0", "1-x^0.01", .right, 1),
            ("inf", "ln(ln(x))", .both, .infinity), ("0", "2+x^0.000000001*ln(x)", .right, 2),
            ("inf", "x^4*(cos(0.00000001/x)-1+(0.00000001/x)^2/2)", .both, 1e-32 / 24),
            ("0", "((1+10^(-16)*x)-1-10^(-16)*x)/x^4", .right, 0), ("inf", "x^150*e^(-x)", .both, 0),
            ("inf", "x/gamma(x+1)^(1/x)", .both, M_E), ("2", "1/(x-2.000000001)", .left, at2),
            // (1 + eˣ)^(1/x) = e·(1 + e⁻ˣ)^(1/x) → e overflows inside; the added terms are below 1/x (x at 0⁺).
            ("inf", "(1+e^x)^(1/x)+sin(3*x+3)/x", .both, M_E), ("0", "(1+e^(1/x))^x+x*sin(3/x+3)", .right, M_E),
            // A pole 10⁻¹⁴…10⁻¹¹ beside the point: f is continuous there, so the limit is f at the point.
            ("2", "1/(x-2.0000000000001)", .right, nearer2), ("2", "1/(x-2.0000000000001)", .left, nearer2),
            ("3.14159265359", "1/sin(x)", .left, besidePi), ("100", "1/(x-100.000000000001)^2", .both, at100),
            ("0", "1/(x+10^(-14))", .right, 1e14), ("0", "1/(x+10^(-14))", .left, 1e14),
            ("1000", "1/(x-1000.00000000001)", .right, at1000),
            // Only the right side exists (as √x at 0, where main takes it), and it is −∞.
            ("0", "ln(x)", .both, -.infinity),
            // Constant on every sample (x ≤ 81 920), not beyond: ⌊x/10⁵⌋ ≥ n for x ≥ 10⁵·n, sign(x − 10⁶) = 1 for
            // x > 10⁶, e^(−c/x) → e⁰ = 1. And bodies that are constant: x⁰ = 1ˣ = 1.
            ("inf", "floor(x/100000)", .both, .infinity), ("inf", "sign(x-1000000)", .both, 1),
            ("inf", "2+e^(-10^7/x)", .both, 3), ("inf", "e^(-10^8/x)", .both, 1), ("inf", "x^0", .both, 1), ("inf", "1^x", .both, 1),
            // Below 10⁻¹⁴ but not 0: (x/(x + a))^x = (1 + a/x)^(−x) → e⁻ᵃ, (1 + 1/x)^(−bx) → e⁻ᵇ.
            ("inf", "(x/(x+40))^x", .both, eMinus40), ("inf", "(1+1/x)^(-50*x)", .both, eMinus50),
            ("inf", "(1+3/x)^(-12*x)", .both, eMinus36), ("inf", "10^(-15)", .both, 1e-15), ("inf", "arctan(x)/10^15", .both, piOver2e15),
        ]
        for c in cases {
            let result = try outcome(c.point, c.body, c.direction)
            switch result {
            case .error:
                continue
            case .infinite(let positive):
                #expect(c.limit == (positive ? Double.infinity : -Double.infinity), "lim x→\(c.point) (\(c.direction)) \(c.body) gave \(result)")
            case .number(let number):
                #expect(c.limit.isFinite && shown(number.value) == shown(c.limit), "lim x→\(c.point) (\(c.direction)) \(c.body) gave \(result)")
            default:
                Issue.record("lim x→\(c.point) (\(c.direction)) \(c.body) gave \(result)")
            }
        }
    }

    /// Where LimitEvaluator's own samples give a value, it is kept bit for bit, also inside an expression
    /// (0 + lim …); its inaccurate ones too (xˣ at 0⁺ = 0,99999140327113, ln x/x at ∞ = 8,6·10⁻⁶).
    @Test func valuesOfTheSamplesAreKept() throws {
        let cases: [(body: String, point: Double, direction: LimitDirection)] = [
            ("x^x", 0, .right), ("x*ln(x)", 0, .right), ("sin(x)/x", 0, .right), ("1/x^2", 0, .left),
            ("ln(x)/x", .infinity, .both), ("x^(1/x)", .infinity, .both), ("(1+1/x)^x", .infinity, .both),
            ("e^x*cos(0.1*ln(x)+1)", .infinity, .both), ("x^2", .infinity, .both),
        ]
        for c in cases {
            let f = FunctionAnalyzer.makeFunction(try parse(c.body), variable: "x", context: EvaluationContext())
            let sampled = c.point.isInfinite ? NumericCalculus.limit(of: f, at: c.point) : LimitEvaluator.oneSided(f, c.point, c.direction == .left ? -1 : 1)
            let expected = try #require(sampled)
            let limit = try LimitEvaluator.limit(try parse(c.body), variable: "x", at: c.point, direction: c.direction, context: EvaluationContext())
            #expect(limit == expected, "\(c.body) at \(c.point)")
        }
        // Typed alone, (1+1/x)^x at ∞ comes from the shallower grids; inside 0 + lim it is the sampled value.
        let nested = MathRow([.symbol(.digit(0)), .symbol(.plus), try limitNode("inf", "(1+1/x)^x", .both)])
        let result = CalculationEngine.calculate(nested, variables: [:], exactVariables: [:], settings: CalculationSettings()).outcome
        let f = FunctionAnalyzer.makeFunction(try parse("(1+1/x)^x"), variable: "x", context: EvaluationContext())
        let sampled = try #require(NumericCalculus.limit(of: f, at: .infinity))
        guard case .number(let number) = result else {
            Issue.record("0 + lim x→∞ (1+1/x)^x gave \(result)")
            return
        }
        #expect(number.value == sampled)
    }
}
