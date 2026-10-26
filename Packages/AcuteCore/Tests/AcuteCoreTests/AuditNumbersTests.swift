import Foundation
import Testing
@testable import AcuteCore

// Regression tests for the audit findings fixed on audit/core-numbers. Everything here compiles against
// the code before the fixes as well, so the tests can be shown failing there; inputs that used to trap
// run as exit tests, so a trap fails its own test instead of ending the whole run.

/// Ends an exit test's child process with a failure status unless `condition` holds, so a wrong value
/// fails the exit test just like a trap does.
private func exitUnless(_ condition: Bool) {
    if !condition { exit(EXIT_FAILURE) }
}

// MARK: Formatting (CHANGE key)

@Suite struct AuditFormattingTests {
    /// MAT-01: the whole degrees went through `Int(_:)`, which traps from 2⁶³ on (6,02214076·10²³ → D°M′S″).
    @Test func sexagesimalOfHugeValuesDoesNotTrap() async {
        await #expect(processExitsWith: .success) {
            let dms = NumberFormatting.sexagesimal(6.02214076e23)
            exitUnless(dms.degrees == 0 && dms.minutes == 0 && dms.seconds == 6.02214076e23 * 3600)
            _ = NumberFormatting.sexagesimal(.infinity)
            _ = NumberFormatting.sexagesimal(.nan)
        }
    }

    /// MAT-02: `remainder *= 10` overflowed for a denominator above Int.max/10: (5/6)²⁴ = 5²⁴/6²⁴.
    @Test func recurringDecimalWithHugeDenominatorDoesNotTrap() async throws {
        await #expect(processExitsWith: .success) {
            guard let r = Rational(5, 6)?.power(24) else { exit(EXIT_FAILURE) }
            exitUnless(r.denominator == 4_738_381_338_321_616_896)   // 6²⁴ (Python)
            exitUnless(NumberFormatting.recurringDecimal(r) == nil)
        }
        let sixth = try #require(Rational(1, 6))
        #expect(NumberFormatting.recurringDecimal(sixth)?.prefix == "1")
        #expect(NumberFormatting.recurringDecimal(sixth)?.period == "6")
    }

    /// MAT-23: ENG took the exponent before rounding the mantissa: 999,99999 → 1000,0000·10⁰.
    @Test func engineeringFormatCarriesIntoTheNextExponent() {
        let options = NumberFormatOptions(mode: .eng, places: 4, decimalSeparator: ".")
        let a = NumberFormatting.format(999.99999, options: options)
        #expect(a.mantissa == "1.0000")
        #expect(a.exponent == 3)
        let b = NumberFormatting.format(0.00099999999, options: options)
        #expect(b.mantissa == "1.0000")
        #expect(b.exponent == -3)
        let c = NumberFormatting.format(-999_999.9999, options: options)
        #expect(c.mantissa == "\u{2212}1.0000")
        #expect(c.exponent == 6)
        // No carry needed: unchanged.
        let d = NumberFormatting.format(12_345.678, options: options)
        #expect(d.mantissa == "12.3457")
        #expect(d.exponent == 3)
    }
}

// MARK: Exact evaluation

@Suite struct AuditExactTests {
    /// MAT-17: floor/ceil and the reduction of degrees converted huge exact values with `Int(_:)` or
    /// multiplied past Int.max, both of which trap.
    @Test func hugeExactValuesDoNotTrap() async {
        // floor(2⁶²·π) = floor(1,4488·10¹⁹) has no exact form.
        await #expect(processExitsWith: .success) {
            let e = Expr.function(.floor, [.product([.power(.int(2), .int(62)), .constant(.pi)])])
            exitUnless(ExactEvaluator.value(e, angleUnit: .radians) == nil)
        }
        // ceil(9·10¹⁸·√2) = ceil(1,27·10¹⁹)
        await #expect(processExitsWith: .success) {
            let e = Expr.function(.ceil, [.product([.int(9_000_000_000_000_000_000), .function(.sqrt, [.int(2)])])])
            exitUnless(ExactEvaluator.value(e, angleUnit: .radians) == nil)
        }
        // floor, ceil and round of Int.max itself: Double(Int.max) rounds up to 2⁶³.
        await #expect(processExitsWith: .success) {
            for f in [MathFunction.floor, .ceil, .round] {
                exitUnless(ExactEvaluator.value(.function(f, [.int(Int.max)]), angleUnit: .radians) == ExactReal(Int.max))
            }
        }
        // DEG: Int.max mod 360 = 7 (no exact sine); Int.max − 337 ≡ 30, so its sine is exactly 1/2.
        await #expect(processExitsWith: .success) {
            exitUnless(ExactEvaluator.value(.function(.sin, [.int(Int.max)]), angleUnit: .degrees) == nil)
            exitUnless(ExactEvaluator.value(.function(.sin, [.int(Int.max - 337)]), angleUnit: .degrees) == ExactReal(Rational.half))
        }
    }

    /// MAT-19: "exact" nCr and nPr came from the Double loop, nCr(57, 24) gave …476 instead of
    /// 7 522 327 487 513 475 (Python math.comb), and floor/ceil/round of fractions used a rounded quotient.
    @Test func exactIntegerResultsAreExact() throws {
        #expect(ExactEvaluator.value(.function(.nCr, [.int(57), .int(24)]), angleUnit: .radians) == ExactReal(7_522_327_487_513_475))
        #expect(ExactEvaluator.value(.function(.nCr, [.int(49), .int(6)]), angleUnit: .radians) == ExactReal(13_983_816))
        #expect(ExactEvaluator.value(.function(.nPr, [.int(20), .int(10)]), angleUnit: .radians) == ExactReal(670_442_572_800))
        #expect(ExactEvaluator.value(.function(.nCr, [.int(5), .int(7)]), angleUnit: .radians) == ExactReal(0))
        // From 9·10¹⁵ on the result stays decimal, as before: C(60, 30) = 118 264 581 564 861 424.
        #expect(ExactEvaluator.value(.function(.nCr, [.int(60), .int(30)]), angleUnit: .radians) == nil)
        // 2,99999999999999999 and 2,49999999999999999 are 3,0 and 2,5 as Doubles.
        let almostThree = Expr.number(try #require(Rational(299_999_999_999_999_999, 100_000_000_000_000_000)))
        let almostHalf = Expr.number(try #require(Rational(249_999_999_999_999_999, 100_000_000_000_000_000)))
        #expect(ExactEvaluator.value(.function(.floor, [almostThree]), angleUnit: .radians) == ExactReal(2))
        #expect(ExactEvaluator.value(.function(.ceil, [.negation(almostThree)]), angleUnit: .radians) == ExactReal(-2))
        #expect(ExactEvaluator.value(.function(.round, [almostHalf]), angleUnit: .radians) == ExactReal(2))
        // Halves still round away from zero.
        #expect(ExactEvaluator.value(.function(.round, [.frac(5, 2)]), angleUnit: .radians) == ExactReal(3))
        #expect(ExactEvaluator.value(.function(.round, [.frac(-5, 2)]), angleUnit: .radians) == ExactReal(-3))
        #expect(ExactEvaluator.value(.function(.floor, [.frac(-7, 2)]), angleUnit: .radians) == ExactReal(-4))
    }
}

// MARK: Numeric evaluation

@Suite struct AuditNumericTests {
    /// MAT-18: `Int(_:)` of a huge or infinite argument trapped in root, binomcdf, poissoncdf and ζ.
    @Test func hugeOrInfiniteArgumentsDoNotTrap() async {
        // root(10²⁰; −8): every Double above 2⁵³ is even, so the root is not real.
        await #expect(processExitsWith: .success) {
            do throws(MathError) {
                _ = try RealEvaluator.evaluate(.function(.root, [.decimal(1e20), .int(-8)]))
                exit(EXIT_FAILURE)
            } catch {
                exitUnless(error == .notReal)
            }
        }
        // The graph of y = root(10²⁰; x) at x < 0 (RealVM).
        await #expect(processExitsWith: .success) {
            let program = try BytecodeCompiler(slots: ["x": .x]).compile(.function(.root, [.decimal(1e20), .x]))
            exitUnless(RealVM(program: program).evaluate(x: -8).isNaN)
        }
        // binomcdf(10; 0,5; k) for k = 10²⁰ and ∞ is 1 (k ≥ n), for k = −∞ it is 0.
        await #expect(processExitsWith: .success) {
            let huge = try RealEvaluator.evaluate(.function(.binomcdf, [.int(10), .frac(1, 2), .decimal(1e20)]))
            let infinite = try RealEvaluator.evaluate(.function(.binomcdf, [.int(10), .frac(1, 2), .constant(.infinity)]))
            let negative = try RealEvaluator.evaluate(.function(.binomcdf, [.int(10), .frac(1, 2), .negation(.constant(.infinity))]))
            exitUnless(huge == 1 && infinite == 1 && negative == 0)
        }
        // poissoncdf(3; k) for k = 10²⁰ and ∞ is 1.
        await #expect(processExitsWith: .success) {
            let huge = try RealEvaluator.evaluate(.function(.poissoncdf, [.int(3), .decimal(1e20)]))
            let infinite = try RealEvaluator.evaluate(.function(.poissoncdf, [.int(3), .constant(.infinity)]))
            exitUnless(huge == 1 && infinite == 1)
        }
        // ζ with an infinite, NaN or huge imaginary part (∞·i is NaN + ∞i in the complex VM).
        await #expect(processExitsWith: .success) {
            exitUnless(Complex.zeta(Complex(.nan, .infinity)).re.isNaN)
            exitUnless(Complex.zeta(Complex(-1, .infinity)).re.isNaN)
            exitUnless(Complex.zeta(Complex(0.5, .nan)).re.isNaN)
            _ = Complex.zeta(Complex(0.5, 1e19))
        }
    }

    /// Follow-up to MAT-18: poissoncdf was 1 for every k > 10⁵, but P(X ≤ k) = Q(k + 1, λ) is about ½
    /// for λ = k = 10⁹. References: the sums Σ e^(−λ)λⁱ/i! in 50-digit Decimal arithmetic (Python,
    /// ln k! from the Stirling series), summed outwards from k until the terms are below 10⁻⁴⁵.
    @Test func poissonCDFForLargeCounts() throws {
        let cases: [(lambda: Double, k: Double, expected: Double)] = [
            (1e9, 1e9, 0.50000841044173899253),
            (1e9, 999_900_000, 7.8261612533531638196e-4),
            (1e9, 1_000_100_000, 0.99921721386733276670),
            (200_000, 200_000, 0.50059470765876540192),
            (200_000, 199_000, 0.012661404229422274367),
            (100_000, 100_001, 0.50210259569351948264),
            (105_000, 100_001, 7.9465410770651991275e-55),
        ]
        for c in cases {
            let p = try Distributions.poissonCDF(lambda: c.lambda, k: c.k)
            #expect(abs(p / c.expected - 1) < 1e-12, "poissoncdf(\(c.lambda); \(c.k)) = \(p)")
        }
        // Far from the mean the result is 1 or 0 in double precision.
        #expect(try Distributions.poissonCDF(lambda: 3, k: 1_000_000) == 1)
        #expect(try Distributions.poissonCDF(lambda: 1e12, k: 200_000) == 0)
        // Up to 10⁵ the terms are still added: poissoncdf(4; 2) = 13e⁻⁴.
        let small = try Distributions.poissonCDF(lambda: 4, k: 2)
        #expect(abs(small - 13 * exp(-4)) < 1e-15)
    }

    /// Follow-up to MAT-18: binomcdf added all k + 1 terms, 10⁷ of them for n = 10⁷ (seconds on the
    /// main thread when = is pressed). References: 50-digit Decimal sums (Python), as for Poisson.
    @Test func binomialCDFForLargeCountsIsBounded() throws {
        let start = ContinuousClock.now
        let a = try Distributions.binomialCDF(n: 10_000_000, p: 0.5, k: 9_999_999)
        let b = try Distributions.binomialCDF(n: 10_000_000, p: 0.3, k: 9_999_999)
        let elapsed = ContinuousClock.now - start
        #expect(a == 1)
        #expect(b == 1)
        #expect(elapsed < .milliseconds(500), "\(elapsed)")
        // The terms come from lgamma differences near 1,3·10⁷ (ulp 1,9·10⁻⁹), so a few 10⁻⁹ is all they hold.
        let upper = try Distributions.binomialCDF(n: 1_000_000, p: 0.3, k: 300_500)
        #expect(abs(upper / 0.86261697203063726226 - 1) < 2e-8)
        let lower = try Distributions.binomialCDF(n: 1_000_000, p: 0.3, k: 299_000)
        #expect(abs(lower / 0.014568219219937684780 - 1) < 2e-8)
        // Up to 10⁴ terms the sum is unchanged: binomcdf(10; 0,5; 3) = 176/1024.
        #expect(try Distributions.binomialCDF(n: 10, p: 0.5, k: 3) == 176.0 / 1024)
    }

    /// MAT-20: gcd used `Rational.gcd`, which returns 1 for (0, 0); gcd(0; 0) is 0.
    @Test func gcdOfZerosIsZero() throws {
        #expect(try RealEvaluator.evaluate(.function(.gcd, [.int(0), .int(0)])) == 0)
        #expect(ExactEvaluator.value(.function(.gcd, [.int(0), .int(0)]), angleUnit: .radians) == ExactReal(0))
        let program = try BytecodeCompiler(slots: ["x": .x]).compile(.function(.gcd, [.x, .int(0)]))
        #expect(RealVM(program: program).evaluate(x: 0) == 0)
        // Unchanged otherwise.
        #expect(RealVM(program: program).evaluate(x: -12) == 12)
        #expect(try RealEvaluator.evaluate(.function(.gcd, [.int(0), .int(12)])) == 12)
        #expect(try RealEvaluator.evaluate(.function(.gcd, [.int(12), .int(18)])) == 6)
        #expect(ExactEvaluator.value(.function(.gcd, [.int(-12), .int(18)]), angleUnit: .radians) == ExactReal(6))
    }
}

// MARK: Loops that ran up to 10¹² times

@Suite struct AuditLoopTests {
    /// MAT-21, CON-04, SHD-08 (CPU): nCr and nPr kept multiplying after the product was ∞; here 2·10⁹
    /// steps each, although nCr is ∞ after 38 and nPr after 171 (Python).
    @Test func hugeCombinatoricsStopOnceInfinite() throws {
        let start = ContinuousClock.now
        let c = try RealEvaluator.combinatorics(.nCr, 4_000_000_000, 2_000_000_000)
        let p = try RealEvaluator.combinatorics(.nPr, 2_000_000_000, 2_000_000_000)
        let elapsed = ContinuousClock.now - start
        #expect(c == .infinity)
        #expect(p == .infinity)
        #expect(elapsed < .seconds(1), "\(elapsed)")
        // Finite results are unchanged.
        #expect(try RealEvaluator.combinatorics(.nCr, 10, 3) == 120)
        #expect(try RealEvaluator.combinatorics(.nPr, 10, 3) == 720)
        #expect(try RealEvaluator.combinatorics(.nCr, 52, 5) == 2_598_960)
        #expect(try RealEvaluator.combinatorics(.nCr, 1000, 500).isFinite)
        #expect(try RealEvaluator.combinatorics(.nCr, 1030, 515) == .infinity)
    }

    /// MAT-21, CON-05: `exactIntegerRoot` tried the candidates 0 and 1 with q multiplications each, so
    /// 2^(1/10⁹) (or any exponent with nine decimals) ran 2·10⁹ steps after every evaluation.
    @Test func rootsWithHugeIndexReturnQuickly() throws {
        let start = ContinuousClock.now
        let root = Rational(2).root(1_000_000_000)
        let exact = ExactEvaluator.value(.power(.int(2), .frac(1, 1_000_000_000)), angleUnit: .radians)
        let elapsed = ContinuousClock.now - start
        #expect(root == nil)
        #expect(exact == nil)
        #expect(elapsed < .seconds(1), "\(elapsed)")
        // Exact roots are unchanged.
        #expect(Rational(8).root(3) == Rational(2))
        #expect(Rational(1024).root(10) == Rational(2))
        #expect(Rational(-27).root(3) == Rational(-3))
        #expect(Rational(1).root(1_000_000_000) == Rational(1))
        #expect(Rational(2).root(2) == nil)
        let nineQuarters = try #require(Rational(9, 4))
        #expect(nineQuarters.root(2) == Rational(3, 2))
        #expect(ExactEvaluator.value(.power(.int(8), .frac(1, 3)), angleUnit: .radians) == ExactReal(Rational(2)))
    }
}

// MARK: Special functions

@Suite struct AuditSpecialFunctionTests {
    /// SHD-02 (CPU): ζ(0) went through the functional equation as 0·ζ(1) = 0·∞ = NaN, so the calculator
    /// reported "rezultat ni definiran"; ζ(0) = −1/2 (DLMF 25.6.1).
    @Test func zetaAtZeroIsMinusOneHalf() throws {
        let z = Complex.zeta(.zero)
        #expect(z.re == -0.5)
        #expect(z.im == 0)
        #expect(try RealEvaluator.evaluate(.function(.zeta, [.zero])) == -0.5)
        let program = try BytecodeCompiler(slots: ["x": .x]).compile(.function(.zeta, [.x]))
        #expect(RealVM(program: program).evaluate(x: 0) == -0.5)
        // Neighbouring values are unchanged: ζ(−1) = −1/12, ζ(2) = π²/6.
        #expect(abs(Complex.zeta(Complex(-1, 0)).re + 1.0 / 12) < 1e-12)
        #expect(abs(Complex.zeta(Complex(2, 0)).re - Double.pi * Double.pi / 6) < 1e-12)
    }

    /// MAT-16: Φ in the calculator and in graphs was 0,5·(1 + erf(x/√2)), which cancels in the left tail:
    /// Φ(−7) = 1,2798095916366492·10⁻¹² instead of 1,279812543885835·10⁻¹², Φ(−9) = 0 instead of
    /// 1,1285884059538422·10⁻¹⁹ (Python with the same erf and erfc). Now it is `Distributions.normalCDF` (erfc).
    @Test func calculatorNormalCDFKeepsTailPrecision() throws {
        let program = try BytecodeCompiler(slots: ["x": .x]).compile(.function(.normcdf, [.x]))
        for z in [-7.0, -9.0, -20.0, 1.5] {
            let calculator = try RealEvaluator.evaluate(.function(.normcdf, [.decimal(z)]))
            #expect(calculator == Distributions.normalCDF(z), "Φ(\(z)) = \(calculator)")
            #expect(RealVM(program: program).evaluate(x: z) == Distributions.normalCDF(z))
        }
        #expect(abs(Distributions.normalCDF(-7) / 1.279812543885835e-12 - 1) < 1e-12)
    }

    /// MAT-16: invNorm near 1 refined x with normalCDF(x) − p, which loses digits as p → 1: for
    /// p = 1 − 10⁻¹² (the Double) it gave 7,0344869026843035 instead of 7,0344869100478356, the quantile of
    /// its tail 9,999778782798785·10⁻¹³ (Python bisection on 0,5·erfc). Now Φ⁻¹(p) = −Φ⁻¹(1 − p) for p > ½.
    @Test func inverseNormalIsAccurateNearOne() throws {
        let p = 1 - 1e-12
        let upper = try Distributions.inverseNormal(p)
        let lower = try Distributions.inverseNormal(1 - p)
        #expect(abs(upper + lower) < 1e-12)
        #expect(abs(upper - 7.0344869100478356) < 1e-11)
        // Textbook quantiles: z(0,975) = 1,959963984540054, z(0,95) = 1,6448536269514722.
        #expect(abs(try Distributions.inverseNormal(0.975) - 1.959963984540054) < 1e-12)
        #expect(abs(try Distributions.inverseNormal(0.95) - 1.6448536269514722) < 1e-12)
        #expect(try Distributions.inverseNormal(0.5) == 0)
    }
}

// MARK: Angles

@Suite struct AuditAngleTests {
    /// MAT-10: d/dx at a point differentiated as if in RAD and then evaluated in DEG:
    /// d/dx sin x at x = 30 gave cos 30° = 0,8660 instead of (π/180)·cos 30° = 0,015114994701951816 (Python).
    @Test func derivativeAtAPointRespectsTheAngleUnit() throws {
        let e = Expr.derivative(.function(.sin, [.x]), variable: "x", at: .int(30))
        let degrees = try RealEvaluator.evaluate(e, context: EvaluationContext(angleUnit: .degrees))
        #expect(abs(degrees - 0.015114994701951816) < 1e-15)
        // GRAD: (π/200)·cos(30 gon) = 0,013995897753453765 (Python)
        let gradians = try RealEvaluator.evaluate(e, context: EvaluationContext(angleUnit: .gradians))
        #expect(abs(gradians - Double.pi / 200 * cos(Double.pi * 30 / 200)) < 1e-15)
        // RAD is unchanged: cos 30.
        let radians = try RealEvaluator.evaluate(e, context: EvaluationContext(angleUnit: .radians))
        #expect(abs(radians - cos(30)) < 1e-15)
    }

    func evaluate(_ f: MathFunction, _ x: Expr, _ unit: AngleUnit) throws -> Double {
        try RealEvaluator.evaluate(.function(f, [x]), context: EvaluationContext(angleUnit: unit))
    }

    /// MAT-15: arguments within 10⁻¹²·|q| of a quarter turn q were snapped to it, which from |x| ≈ 10¹¹ on
    /// is every argument, and DEG/GRAD were turned into radians before reducing. References (Python, libm
    /// and 80-digit Decimal with Machin's π): sin(10¹²) = −0,61123870237688950, sin(10¹¹ + 0,3) =
    /// 0,99680820091002493, sin(10¹⁵) = 0,85827279317023584; 10¹⁴ mod 360 = 280, 9 000 000 000 005 mod 360 = 5
    /// and (10¹⁴ + 50) mod 400 = 50.
    @Test func largeAnglesAreNotSnappedToQuarterTurns() throws {
        let cases: [(x: Double, unit: AngleUnit, sine: Double)] = [
            (1e12, .radians, -0.6112387023768895),
            (1e11 + 0.3, .radians, 0.996808200910025),
            (1e15, .radians, 0.8582727931702358),
            (1e14, .degrees, -0.984807753012208),
            (9_000_000_000_005, .degrees, 0.08715574274765817),
            (1e14 + 50, .gradians, 0.5.squareRoot()),
        ]
        for c in cases {
            let sine = try evaluate(.sin, .decimal(c.x), c.unit)
            #expect(abs(sine - c.sine) < 1e-12, "sin(\(c.x)) in \(c.unit) = \(sine)")
        }
        // Multiples of a quarter turn are still exact.
        #expect(try evaluate(.sin, .constant(.pi), .radians) == 0)
        #expect(try evaluate(.cos, .quotient(.constant(.pi), .int(2)), .radians) == 0)
        #expect(try evaluate(.sin, .product([.decimal(1e12), .constant(.pi)]), .radians) == 0)
        #expect(try evaluate(.cos, .int(90), .degrees) == 0)
        #expect(try evaluate(.sin, .int(-90), .degrees) == -1)
        #expect(try evaluate(.cos, .decimal(3.6e14 + 90), .degrees) == 0)
        #expect(try evaluate(.cos, .int(100), .gradians) == 0)
        #expect(throws: MathError.self) { try self.evaluate(.tan, .int(90), .degrees) }
        let thirty = try evaluate(.sin, .int(30), .degrees)
        #expect(abs(thirty - 0.5) < 1e-15)
    }
}

// MARK: Small results (added after the first red run)

@Suite struct AuditSmallResultTests {
    func outcome(_ e: Expr, unit: AngleUnit = .radians) -> CalculationOutcome {
        CalculationEngine.calculate(e, variables: [:], exactVariables: [:], settings: CalculationSettings(angleUnit: unit)).outcome
    }

    /// The calculator's decimal result (as shown and stored in Ans), NaN when it is not a number.
    func number(_ e: Expr, unit: AngleUnit = .radians) -> Double {
        guard case .number(let r) = outcome(e, unit: unit) else { return .nan }
        return r.value
    }

    /// MAT-03: NumericCalculus.clean set every |x| < 10⁻¹⁴ of the result to 0.
    @Test func smallResultsAreNotRoundedToZero() {
        // h·f for f = 5·10¹⁴ Hz: 6,62607015·10⁻³⁴ J s · 5·10¹⁴ Hz = 3,313035075·10⁻¹⁹ J (CODATA 2022, h exact).
        let photon = number(.product([.decimal(6.62607015e-34), .decimal(5e14)]))
        #expect(abs(photon / 3.313035075e-19 - 1) < 1e-15, "\(photon)")
        // e·(3 V + 2 V) = 8,01088317·10⁻¹⁹ J: a sum inside a product is no cancellation.
        let work = number(.product([.decimal(1.602176634e-19), .sum([.int(3), .int(2)])]))
        #expect(abs(work / 8.01088317e-19 - 1) < 1e-15, "\(work)")
        // 10⁻¹⁵, exact (it showed as 1/10¹⁵ ≈ 0) and as a decimal.
        let exactPower = number(.power(.int(10), .int(-15)))
        #expect(abs(exactPower / 1e-15 - 1) < 1e-15, "\(exactPower)")
        let decimal = number(.decimal(1e-15))
        #expect(abs(decimal / 1e-15 - 1) < 1e-15, "\(decimal)")
        // Φ(−8) = 6,22096057427178·10⁻¹⁶ (0,5·erfc(8/√2))
        let tail = number(.function(.normcdf, [.int(-8)]))
        #expect(abs(tail / 6.22096057427178e-16 - 1) < 1e-12, "\(tail)")
    }

    /// MAT-03: (1 + i)·6,62607015·10⁻³⁴ lost both parts and showed as 0.
    @Test func smallComplexResultsKeepTheirParts() {
        guard case .complex(let c) = outcome(.product([.sum([.int(1), .constant(.i)]), .decimal(6.62607015e-34)])) else {
            Issue.record("(1 + i)·6,62607015·10⁻³⁴ is not complex")
            return
        }
        #expect(abs(c.re / 6.62607015e-34 - 1) < 1e-15)
        #expect(abs(c.im / 6.62607015e-34 - 1) < 1e-15)
    }

    /// Cancellation noise still becomes 0 (these pass before the fix as well).
    @Test func cancellationNoiseStillBecomesZero() {
        // 0,1 + 0,2 − 0,3 as decimals (5,6·10⁻¹⁷ in floating point) and as exact fractions.
        #expect(number(.sum([.decimal(0.1), .decimal(0.2), .negation(.decimal(0.3))])) == 0)
        #expect(number(.sum([.frac(1, 10), .frac(2, 10), .negation(.frac(3, 10))])) == 0)
        // ln(e³) − 3, e^(ln 5) − 5, tan 0,7·cos 0,7 − sin 0,7
        #expect(number(.sum([.function(.ln, [.power(.constant(.e), .int(3))]), .int(-3)])) == 0)
        #expect(number(.sum([.power(.constant(.e), .function(.ln, [.int(5)])), .int(-5)])) == 0)
        #expect(number(.sum([.product([.function(.tan, [.decimal(0.7)]), .function(.cos, [.decimal(0.7)])]),
                             .negation(.function(.sin, [.decimal(0.7)]))])) == 0)
        // sin π = 0, ζ(−2) = 0
        #expect(number(.function(.sin, [.constant(.pi)])) == 0)
        #expect(number(.function(.zeta, [.int(-2)])) == 0)
        // e^(iπ) + 1 = 0 and 10∠90° = 10i
        #expect(number(.sum([.power(.constant(.e), .product([.constant(.i), .constant(.pi)])), .int(1)])) == 0)
        let phasor = Expr.product([.int(10), .sum([.function(.cos, [.int(90)]), .product([.constant(.i), .function(.sin, [.int(90)])])])])
        guard case .complex(let c) = outcome(phasor, unit: .degrees) else {
            Issue.record("10∠90° is not complex")
            return
        }
        #expect(c.re == 0)
        #expect(c.im == 10)
    }
}

// MARK: Taylor polynomials (follow-up #3)

@Suite struct AuditTaylorTests {
    /// The function of a graph row typed with the keypad (eˣ: insert e, then a power; sin: a function).
    func graphedFunction(_ keys: (inout MathEditor) -> Void) throws -> Expr? {
        var editor = MathEditor()
        keys(&editor)
        let request = try #require(try CalculationEngine.graphRequest(for: editor.root))
        guard case .explicit(let f)? = request.kinds.first else { return nil }
        return f
    }

    /// GAP-taylor-1: every coefficient |f⁽ᵏ⁾(a)/k!| ≤ 10⁻¹³ was dropped (clean() and the absolute tolerance of
    /// Rational.approximating), so T₁₆ … T₂₀ of eˣ were T₁₅: T₂₀(10) gave 20952,8869686067 instead of
    /// Σ_{k≤20} 10ᵏ/k! = 21991,48202566506314… (Python fractions; Node BigInt agrees).
    @Test func taylorPolynomialKeepsTinyCoefficients() throws {
        let f = try #require(try graphedFunction { editor in
            editor.insert(.constant(.e))
            editor.insertPower()
            editor.insert(.variable("x"))
        })
        let t = try #require(TaylorSeries.polynomial(of: f, around: 0, order: 20, context: EvaluationContext(variables: [:])))
        let p = try #require(Polynomial.extract(from: t, variable: "x"))
        try #require(p.degree == 20)
        #expect(abs(p.coefficients[16] * 20_922_789_888_000 - 1) < 1e-12)              // 1/16!
        #expect(abs(p.coefficients[20] * 2_432_902_008_176_640_000 - 1) < 1e-12)        // 1/20!
        let at10 = try RealEvaluator.evaluate(t, context: EvaluationContext(variables: ["x": 10]))
        #expect(abs(at10 / 21991.482025665063 - 1) < 1e-12, "\(at10)")
        // Σ_{k≤20} (−8)ᵏ/k! = 0,13229825662639869… (T₁₅(−8) = −9,0927706806…); the coefficients carry
        // 13 digits and the terms reach 416, so a few 10⁻¹² is their limit.
        let atMinus8 = try RealEvaluator.evaluate(t, context: EvaluationContext(variables: ["x": -8]))
        #expect(abs(atMinus8 - 0.13229825662639869) < 1e-9, "\(atMinus8)")
    }

    /// GAP-taylor-1: T₁₇ … T₂₀ of sin x were T₁₅; the even coefficients must stay exactly 0.
    /// T₁₉(10) = Σ (−1)ʲ 10²ʲ⁺¹/(2j + 1)! = −16,81185013741168 (Python fractions).
    @Test func taylorPolynomialOfSineKeepsItsZeros() throws {
        let f = try #require(try graphedFunction { editor in
            editor.insertNode(.function(.sin, argument: MathRow([.symbol(.variable("x"))])))
        })
        let t = try #require(TaylorSeries.polynomial(of: f, around: 0, order: 19, context: EvaluationContext(variables: [:])))
        let p = try #require(Polynomial.extract(from: t, variable: "x"))
        try #require(p.degree == 19)
        let even = stride(from: 0, through: 18, by: 2).map { p.coefficients[$0] }
        #expect(even == [Double](repeating: 0, count: 10))
        #expect(abs(p.coefficients[19] * 121_645_100_408_832_000 + 1) < 1e-12)   // −1/19!
        let at10 = try RealEvaluator.evaluate(t, context: EvaluationContext(variables: ["x": 10]))
        #expect(abs(at10 + 16.81185013741168) < 1e-9, "\(at10)")
    }
}

// MARK: Real-only functions of non-real numbers (follow-up #3)

@Suite struct AuditComplexArgumentTests {
    func outcome(_ e: Expr) -> CalculationOutcome {
        CalculationEngine.calculate(e, variables: [:], exactVariables: [:], settings: CalculationSettings()).outcome
    }

    func isError(_ outcome: CalculationOutcome) -> Bool {
        if case .error = outcome { return true }
        return false
    }

    /// GAP-complex-mode-1: ComplexVM applied these to Re z: erf(i) gave erf(0) = 0 (i·erfi(1) =
    /// 1,6504257587975429i), Φ(i) 0,5, sgn(−2i) 0, mod(5 + i; 3) 2, gcd(2i; 4) 4, lcm(2i; 4) 0, nCr(i; 2) 0,
    /// nPr(3 + i; 2) 6, min(1 + i; 2) 1, max(1 + 5i; 2) 2 and {1 if i ≥ 0} 1. They are not defined there.
    @Test func realOnlyFunctionsOfNonRealNumbersAreUndefined() {
        let i = Expr.constant(.i)
        let cases: [Expr] = [
            .function(.erf, [i]),
            .function(.normcdf, [i]),
            .function(.sign, [.product([.int(-2), i])]),
            .function(.mod, [.sum([.int(5), i]), .int(3)]),
            .function(.gcd, [.product([.int(2), i]), .int(4)]),
            .function(.lcm, [.product([.int(2), i]), .int(4)]),
            .function(.nCr, [i, .int(2)]),
            .function(.nPr, [.sum([.int(3), i]), .int(2)]),
            .function(.min, [.sum([.int(1), i]), .int(2)]),
            .function(.max, [.sum([.int(1), .product([.int(5), i])]), .int(2)]),
            .piecewise([.int(1), .relation(i, .greaterOrEqual, .int(0))]),
        ]
        for e in cases {
            let result = outcome(e)
            #expect(isError(result), "\(e) = \(result)")
        }
    }

    /// GAP-complex-mode-1: = and ≠ compared only real parts, so {1 if i = 0; 2} gave 1 and {1 if i ≠ 0; 2} gave 2.
    @Test func conditionsCompareComplexNumbers() {
        let i = Expr.constant(.i)
        func piecewise(_ op: RelationOperator) -> Expr { .piecewise([.int(1), .relation(i, op, .int(0)), .int(2)]) }
        guard case .number(let equal) = outcome(piecewise(.equal)), case .number(let notEqual) = outcome(piecewise(.notEqual)) else {
            Issue.record("{1 if i = 0; 2} = \(outcome(piecewise(.equal))), {1 if i ≠ 0; 2} = \(outcome(piecewise(.notEqual)))")
            return
        }
        #expect(equal.value == 2)
        #expect(notEqual.value == 1)
    }

    /// Real values computed with i stay real (these pass before the fix as well): e^(iπ) = −1 + 1,2·10⁻¹⁶i in
    /// floating point, so sgn(e^(iπ)) = −1, and erf(i·i) = erf(−1) = −0,8427007929497149 (Python math.erf).
    @Test func realValuesComputedWithIStayReal() {
        let ePowerIPi = Expr.power(.constant(.e), .product([.constant(.i), .constant(.pi)]))
        guard case .number(let sign) = outcome(.function(.sign, [ePowerIPi])) else {
            Issue.record("sgn(e^(iπ)) = \(outcome(.function(.sign, [ePowerIPi])))")
            return
        }
        #expect(sign.value == -1)
        guard case .number(let erf) = outcome(.function(.erf, [.product([.constant(.i), .constant(.i)])])) else {
            Issue.record("erf(i·i) is not a number")
            return
        }
        #expect(abs(erf.value + 0.8427007929497149) < 1e-13)   // the result keeps 13 significant digits
    }
}

// MARK: Review of PR #19 (these pass on main and failed on the branch before the review fixes)

@Suite struct AuditReviewTests {
    func outcome(_ e: Expr) -> CalculationOutcome {
        CalculationEngine.calculate(e, variables: [:], exactVariables: [:], settings: CalculationSettings()).outcome
    }

    func number(_ e: Expr) -> Double {
        guard case .number(let r) = outcome(e) else { return .nan }
        return r.value
    }

    /// The noise scale of a result must not come from what the result does not depend on: frac and mod are
    /// exact remainders (frac(10¹⁵ + 0,25) = 0,25), Re keeps only the real part's scale, the parts of a complex
    /// number have their own scales, and min/max only the chosen operand's.
    @Test func noiseScalesFollowTheResult() {
        #expect(number(.function(.frac, [.sum([.decimal(1e15), .decimal(0.25)])])) == 0.25)
        let realPart = number(.function(.re, [.sum([.decimal(1e-5), .product([.decimal(1e10), .constant(.i)])])]))
        #expect(abs(realPart / 1e-5 - 1) < 1e-15, "\(realPart)")
        guard case .complex(let z) = outcome(.sum([.decimal(1e10), .product([.decimal(1e-5), .constant(.i)])])) else {
            Issue.record("10¹⁰ + 10⁻⁵i lost its imaginary part")
            return
        }
        #expect(z.re == 1e10)
        #expect(abs(z.im / 1e-5 - 1) < 1e-15)
        let minimum = number(.function(.min, [.int(-1), .sum([.int(1), .sum([.decimal(1e20), .negation(.decimal(1e20))])])]))
        #expect(minimum == -1)
        // Noise is still removed: 1,1 + 2,2 − 0,3 = 3,0000000000000004 in floating point, so its frac is 0, and so
        // is frac(e^(ln 3)) (as before the branch).
        #expect(number(.function(.frac, [.sum([.decimal(1.1), .decimal(2.2), .negation(.decimal(0.3))])])) == 0)
        #expect(number(.function(.frac, [.power(.constant(.e), .function(.ln, [.int(3)]))])) == 0)
    }

    /// The recurring decimal of 1/(10¹⁸ + 1) has a 36-digit period; 10·remainder exceeds Int.max there
    /// (it trapped on main, and was hidden as nil on the branch).
    @Test func recurringDecimalWithHugeDenominatorAndShortPeriod() async {
        await #expect(processExitsWith: .success) {
            guard let r = Rational(1, 1_000_000_000_000_000_001), let decimal = NumberFormatting.recurringDecimal(r) else {
                exit(EXIT_FAILURE)
            }
            exitUnless(decimal.prefix.isEmpty && decimal.period == "000000000000000000999999999999999999")
        }
    }

    /// An infinite real part made the tolerance of isNearlyReal ∞, so an infinite imaginary part passed as real:
    /// (1 + i)·e¹⁰⁰⁰ is ∞ + ∞i in floating point, and its sgn and erf gave 1 from the real part, although
    /// sgn((1 + i)·e¹⁰⁰⁰) = (1 + i)/√2 is not real. e¹⁰⁰⁰ + i (∞ + i) is real up to 5·10⁻⁴³⁵ of itself, so its
    /// sign stays 1, like that of 10¹⁵ + 10⁻³i.
    @Test func infiniteImaginaryPartsAreNotReal() {
        let i = Expr.constant(.i)
        let huge = Expr.power(.constant(.e), .int(1000))
        for f in [MathFunction.sign, .erf] {
            let result = outcome(.function(f, [.product([.sum([.int(1), i]), huge])]))
            if case .error = result { continue }
            Issue.record("\(f)((1 + i)·e¹⁰⁰⁰) = \(result)")
        }
        #expect(number(.function(.sign, [.sum([huge, i])])) == 1)
    }

    /// = compared |a − b| with 10⁻¹² of max(1, |a|, |b|), and a magnitude overflows for parts near 10³⁰⁸:
    /// |1,3·10³⁰⁸·(1 + i)| = 1,84·10³⁰⁸ is ∞, so the bound was ∞ and 1,3·10³⁰⁸·(1 + i) equalled
    /// 1,3·10³⁰⁸ + 1,2·10³⁰⁸i, whose imaginary part is 10³⁰⁷ smaller.
    @Test func hugeComplexNumbersCompareWithoutOverflow() {
        let i = Expr.constant(.i)
        let a = Expr.product([.decimal(1.3e308), .sum([.int(1), i])])
        let b = Expr.sum([.decimal(1.3e308), .product([.decimal(1.2e308), i])])
        func condition(_ lhs: Expr, _ op: RelationOperator, _ rhs: Expr) -> Expr {
            .piecewise([.int(1), .relation(lhs, op, rhs), .int(2)])
        }
        #expect(number(condition(a, .equal, b)) == 2)
        #expect(number(condition(a, .notEqual, b)) == 1)
        #expect(number(condition(a, .equal, a)) == 1)
    }
}
