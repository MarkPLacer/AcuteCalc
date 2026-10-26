import Foundation
import Testing
@testable import AcuteCore

// Regression tests for audit/core-numbers that need the API added by the fixes
// (`NumberFormatting.sexagesimal(_:secondsDigits:)`, `UnitFactors`), so they do not compile before them.
// The tests that can run against the old code are in AuditNumbersTests.swift.

@Suite struct AuditSexagesimalTests {
    /// MAT-01: no D°M′S″ form for results that are too large or not finite, so CHANGE skips it.
    @Test func sexagesimalIsUnavailableForHugeValues() throws {
        // Optional tuples are not Equatable: compare with nil outside #expect.
        let unavailable = [6.02214076e23, 1e15, Double.infinity, Double.nan].map { NumberFormatting.sexagesimal($0, secondsDigits: 6) == nil }
        #expect(unavailable == [true, true, true, true])
        let dms = try #require(NumberFormatting.sexagesimal(12.5, secondsDigits: 6))
        #expect(dms.degrees == 12 && dms.minutes == 30 && dms.seconds == 0)
    }

    /// MAT-22: the seconds were rounded to 10⁻⁶″ but shown with six digits: 10,99999999° → 10° 59′ 60″.
    @Test func sexagesimalNeverShowsSixtySeconds() throws {
        let dms = try #require(NumberFormatting.sexagesimal(10.99999999, secondsDigits: 6))
        #expect(dms.degrees == 11 && dms.minutes == 0 && dms.seconds == 0)
        let negative = try #require(NumberFormatting.sexagesimal(-45.99999999, secondsDigits: 6))
        #expect(negative.negative && negative.degrees == 46 && negative.minutes == 0 && negative.seconds == 0)
        // Triangle angles show four digits: 29,999999° has 59′ 59,9964″, shown as 60,00″ before.
        let four = try #require(NumberFormatting.sexagesimal(29.999999, secondsDigits: 4))
        #expect(four.degrees == 30 && four.minutes == 0 && four.seconds == 0)
        // Unchanged where nothing rounds up: 12,51° = 12° 30′ 36″.
        let plain = try #require(NumberFormatting.sexagesimal(12.51, secondsDigits: 6))
        #expect(plain.degrees == 12 && plain.minutes == 30 && abs(plain.seconds - 36) < 1e-9)
        // The geodesy form keeps its 10⁻⁶″ seconds.
        let geodetic = NumberFormatting.sexagesimal(10.99999999)
        #expect(geodetic.degrees == 10 && geodetic.minutes == 59 && abs(geodetic.seconds - 59.999964) < 1e-9)
    }
}
