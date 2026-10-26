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
