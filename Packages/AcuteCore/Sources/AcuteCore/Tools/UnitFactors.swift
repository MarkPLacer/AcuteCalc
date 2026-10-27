import Foundation

/// Exact conversion factors for the units whose built-in Foundation coefficients are rounded.
///
/// Foundation stores many customary and astronomical units with about six significant digits
/// (km/h = 0,277778 m/s, mmHg = 133,322 Pa, mi = 1609,34 m, g = 9,81 m/s²), while the unit converter
/// shows ten, so 36 km/h came out as 10,000008 m/s. `convert` uses the exact definitions below and
/// Foundation's own converter for every other unit, temperatures with their offsets included.
public enum UnitFactors {
    /// Size of `unit` in the base unit of its dimension (m, m², kg, m/s, m/s², W, Pa, degree) when
    /// Foundation's coefficient for it is rounded, otherwise `nil`.
    public static func exactFactor(of unit: Dimension) -> Double? {
        let kind = ObjectIdentifier(type(of: unit))
        let coefficient = unit.converter.baseUnitValue(fromValue: 1)
        return exactFactors.first {
            $0.kind == kind && $0.symbol == unit.symbol && $0.foundationCoefficient == coefficient
        }?.factor
    }

    /// `value` in `from` expressed in `to`, two units of the same dimension.
    public static func convert(_ value: Double, from: Dimension, to: Dimension) -> Double {
        if from == to { return value }
        let base = exactFactor(of: from).map { value * $0 } ?? from.converter.baseUnitValue(fromValue: value)
        return exactFactor(of: to).map { base / $0 } ?? to.converter.value(fromBaseUnitValue: base)
    }

    /// `convert` as the converter shows it: what the offsets of temperature scales leave of an exact 0
    /// (32 °F → 2·10⁻¹² °C with Foundation's coefficients) becomes 0, and every other value keeps 13
    /// significant digits, so small results such as 1 eV = 1,602176634·10⁻¹⁹ J (`clean` made it 0) or
    /// 32,0000000001 °F = 5,6·10⁻¹¹ °C stay.
    public static func displayValue(_ value: Double, from: Dimension, to: Dimension) -> Double {
        if from == to { return NumericCalculus.roundNoise(value) }
        let x = convert(value, from: from, to: to)
        // The rounding is relative to the terms of base = value·a + c and of x = (base − d)/b.
        let (a, c) = linearMap(from), (b, d) = linearMap(to)
        let scale = (Swift.abs(value * a) + Swift.abs(c) + Swift.abs(d)) / Swift.abs(b)
        return Swift.abs(x) < 1e-14 * scale ? 0 : NumericCalculus.roundNoise(x)
    }

    /// Coefficient and offset of `unit` to its base unit: base = value·coefficient + offset.
    private static func linearMap(_ unit: Dimension) -> (coefficient: Double, offset: Double) {
        if let factor = exactFactor(of: unit) { return (factor, 0) }
        let offset = unit.converter.baseUnitValue(fromValue: 0)
        return (unit.converter.baseUnitValue(fromValue: 1) - offset, offset)
    }

    /// A unit of the table by its class and symbol ("g" is both the gram and standard gravity) and
    /// Foundation's coefficient for it, so a custom unit with the same symbol (a "mi" of 1852 m) keeps its own.
    private struct ExactFactor: Sendable {
        let kind: ObjectIdentifier
        let symbol: String
        let foundationCoefficient: Double
        let factor: Double
    }

    /// Built once; it keeps class and symbol instead of the (non-Sendable) Foundation units.
    private static let exactFactors: [ExactFactor] = {
        let table: [(unit: Dimension, factor: Double)] = [
            // Length (m): international mile 1609,344 m; astronomical unit 149 597 870 700 m (IAU 2012 B2);
            // light year = Julian year · c = 31 557 600 s · 299 792 458 m/s; parsec = 648 000/π au (IAU 2015 B2).
            (UnitLength.miles, 1609.344),
            (UnitLength.astronomicalUnits, 149_597_870_700),
            (UnitLength.lightyears, 9_460_730_472_580_800),
            (UnitLength.parsecs, 648_000 / Double.pi * 149_597_870_700),
            // Area (m²): international acre = 43 560 ft²; foot = 0,3048 m.
            (UnitArea.acres, 4046.8564224),
            (UnitArea.squareFeet, 0.09290304),
            // Mass (kg): avoirdupois pound 0,45359237 kg, ounce = 1/16 lb.
            (UnitMass.pounds, 0.45359237),
            (UnitMass.ounces, 0.028349523125),
            // Speed (m/s): km/h = 1000/3600, knot = 1852/3600 (international nautical mile 1852 m).
            (UnitSpeed.kilometersPerHour, 1000.0 / 3600),
            (UnitSpeed.knots, 1852.0 / 3600),
            // Acceleration (m/s²): standard gravity 9,80665 m/s² (3rd CGPM, 1901).
            (UnitAcceleration.gravity, 9.80665),
            // Power (W): mechanical horsepower = 550 ft·lbf/s = 550 · 0,3048 · 0,45359237 · 9,80665 W.
            (UnitPower.horsepower, 745.69987158227022),
            // Pressure (Pa): the conventional millimetre of mercury, 13 595,1 kg/m³ · 9,80665 m/s² · 1 mm =
            // 133,322387415 Pa (NIST SP 811 lists it apart from the torr, 101 325/760 Pa), so 1 atm is
            // 759,99989 mmHg; psi = 0,45359237 · 9,80665 N / (0,0254 m)².
            (UnitPressure.millimetersOfMercury, 133.322387415),
            (UnitPressure.poundsForcePerSquareInch, 6894.7572931683613),
            // Angle (degree): ′ = 1/60°, ″ = 1/3600°, rad = 180/π°.
            (UnitAngle.arcMinutes, 1.0 / 60),
            (UnitAngle.arcSeconds, 1.0 / 3600),
            (UnitAngle.radians, 180 / Double.pi),
        ]
        return table.map {
            ExactFactor(kind: ObjectIdentifier(type(of: $0.unit)), symbol: $0.unit.symbol,
                        foundationCoefficient: $0.unit.converter.baseUnitValue(fromValue: 1), factor: $0.factor)
        }
    }()
}
