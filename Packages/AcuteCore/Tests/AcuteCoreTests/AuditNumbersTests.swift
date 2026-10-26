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
