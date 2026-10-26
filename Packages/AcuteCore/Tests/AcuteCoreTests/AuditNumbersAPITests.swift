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

@Suite struct AuditUnitFactorTests {
    func close(_ a: Double, _ b: Double) -> Bool { abs(a - b) <= 1e-14 * abs(b) }

    /// MAT-04: the unit converter used Foundation's rounded coefficients (Apple's tables and
    /// swift-corelibs-foundation: km/h 0,277778, mmHg 133,322, g 9,81, mi 1609,34, au 1,496·10¹¹ …), so
    /// 36 km/h showed 10,000008 m/s and 1 atm 760,0021 mmHg. Exact values from the SI/NIST/IAU definitions.
    @Test func unitConverterUsesExactFactors() {
        #expect(close(UnitFactors.convert(36, from: UnitSpeed.kilometersPerHour, to: UnitSpeed.metersPerSecond), 10))
        #expect(close(UnitFactors.convert(1, from: UnitSpeed.metersPerSecond, to: UnitSpeed.kilometersPerHour), 3.6))
        #expect(close(UnitFactors.convert(1, from: UnitSpeed.knots, to: UnitSpeed.kilometersPerHour), 1.852))
        let atmospheres = UnitPressure(symbol: "atm", converter: UnitConverterLinear(coefficient: 101_325))
        #expect(close(UnitFactors.convert(1, from: atmospheres, to: UnitPressure.millimetersOfMercury), 760))
        #expect(close(UnitFactors.convert(1, from: UnitPressure.poundsForcePerSquareInch, to: UnitPressure.newtonsPerMetersSquared), 6894.757293168361))
        #expect(UnitFactors.convert(1, from: UnitAcceleration.gravity, to: UnitAcceleration.metersPerSecondSquared) == 9.80665)
        #expect(UnitFactors.convert(1, from: UnitLength.miles, to: UnitLength.meters) == 1609.344)
        #expect(UnitFactors.convert(1, from: UnitLength.astronomicalUnits, to: UnitLength.meters) == 149_597_870_700)
        #expect(UnitFactors.convert(1, from: UnitLength.lightyears, to: UnitLength.meters) == 9_460_730_472_580_800)
        #expect(close(UnitFactors.convert(1, from: UnitLength.parsecs, to: UnitLength.astronomicalUnits), 648_000 / Double.pi))
        #expect(close(UnitFactors.convert(1, from: UnitMass.kilograms, to: UnitMass.pounds), 1 / 0.45359237))
        #expect(close(UnitFactors.convert(1, from: UnitMass.pounds, to: UnitMass.ounces), 16))
        #expect(close(UnitFactors.convert(1, from: UnitArea.acres, to: UnitArea.squareFeet), 43_560))
        #expect(close(UnitFactors.convert(1, from: UnitPower.horsepower, to: UnitPower.watts), 745.69987158227022))
        #expect(close(UnitFactors.convert(1, from: UnitAngle.radians, to: UnitAngle.degrees), 180 / Double.pi))
        #expect(close(UnitFactors.convert(1, from: UnitAngle.degrees, to: UnitAngle.arcSeconds), 3600))
        #expect(close(UnitFactors.convert(1, from: UnitAngle.arcMinutes, to: UnitAngle.arcSeconds), 60))
    }

    /// Units whose Foundation coefficients are exact, and temperatures with their offsets, keep
    /// Foundation's conversion; the gram ("g") is not standard gravity ("g").
    @Test func otherUnitsKeepFoundationConversion() {
        #expect(UnitFactors.convert(1, from: UnitLength.kilometers, to: UnitLength.meters) == 1000)
        #expect(close(UnitFactors.convert(3, from: UnitLength.feet, to: UnitLength.inches),
                      Measurement(value: 3, unit: UnitLength.feet).converted(to: .inches).value))
        #expect(close(UnitFactors.convert(100, from: UnitTemperature.celsius, to: UnitTemperature.kelvin), 373.15))
        #expect(close(UnitFactors.convert(373.15, from: UnitTemperature.kelvin, to: UnitTemperature.celsius), 100))
        #expect(UnitFactors.convert(36, from: UnitSpeed.kilometersPerHour, to: UnitSpeed.kilometersPerHour) == 36)
        #expect(UnitFactors.exactFactor(of: UnitMass.grams) == nil)
        #expect(UnitFactors.exactFactor(of: UnitAcceleration.gravity) == 9.80665)
        #expect(UnitFactors.exactFactor(of: UnitLength.meters) == nil)
    }
}
