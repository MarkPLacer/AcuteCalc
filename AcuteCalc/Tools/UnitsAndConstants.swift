import AcuteCore
import Foundation
import SwiftUI
import UIKit

/// Unit categories backed by Foundation's `Measurement` and `Dimension` types.
enum UnitCategory: String, CaseIterable, Identifiable {
    case length, area, volume, mass, time, speed, acceleration, energy, power, pressure, temperature, angle
    case frequency, charge, voltage, current, resistance

    var id: String { rawValue }

    var title: String {
        switch self {
        case .length: "Dolžina"
        case .area: "Ploščina"
        case .volume: "Prostornina"
        case .mass: "Masa"
        case .time: "Čas"
        case .speed: "Hitrost"
        case .acceleration: "Pospešek"
        case .energy: "Energija"
        case .power: "Moč"
        case .pressure: "Tlak"
        case .temperature: "Temperatura"
        case .angle: "Kot"
        case .frequency: "Frekvenca"
        case .charge: "Električni naboj"
        case .voltage: "Napetost"
        case .current: "Električni tok"
        case .resistance: "Upornost"
        }
    }

    var units: [Dimension] {
        // The generic helper lets each literal infer its concrete unit type (UnitLength, UnitMass, …).
        func dims<T: Dimension>(_ units: [T]) -> [Dimension] { units }
        switch self {
        case .length:
            return dims([UnitLength.kilometers, .meters, .decimeters, .centimeters, .millimeters, .micrometers, .nanometers, .picometers,
                         .inches, .feet, .yards, .miles, .nauticalMiles, .astronomicalUnits, .lightyears, .parsecs])
        case .area:
            return dims([UnitArea.squareKilometers, .hectares, .ares, .squareMeters, .squareCentimeters, .squareMillimeters, .acres, .squareFeet])
        case .volume:
            return dims([UnitVolume.cubicMeters, .kiloliters, .liters, .deciliters, .centiliters, .milliliters, .cubicDecimeters, .cubicCentimeters, .cubicMillimeters])
        case .mass:
            return dims([UnitMass.metricTons, .kilograms, .grams, .milligrams, .micrograms, .pounds, .ounces, .carats, CustomUnits.atomicMass])
        case .time:
            return dims([CustomUnits.years, CustomUnits.days, UnitDuration.hours, .minutes, .seconds, .milliseconds, .microseconds, .nanoseconds])
        case .speed:
            return dims([UnitSpeed.metersPerSecond, .kilometersPerHour, .milesPerHour, .knots, CustomUnits.speedOfLight])
        case .acceleration:
            return dims([UnitAcceleration.metersPerSecondSquared, .gravity])
        case .energy:
            return dims([UnitEnergy.joules, .kilojoules, CustomUnits.megajoules, .calories, .kilocalories, .kilowattHours, CustomUnits.wattHours, CustomUnits.electronVolts])
        case .power:
            return dims([UnitPower.watts, .milliwatts, .kilowatts, .megawatts, .gigawatts, .horsepower])
        case .pressure:
            return dims([UnitPressure.newtonsPerMetersSquared, .hectopascals, .kilopascals, .megapascals, .bars, .millibars, CustomUnits.atmospheres, .millimetersOfMercury, .poundsForcePerSquareInch])
        case .temperature:
            return dims([UnitTemperature.celsius, .kelvin, .fahrenheit])
        case .angle:
            return dims([UnitAngle.degrees, .radians, .gradians, .revolutions, .arcMinutes, .arcSeconds])
        case .frequency:
            return dims([UnitFrequency.hertz, .kilohertz, .megahertz, .gigahertz, CustomUnits.revolutionsPerMinute])
        case .charge:
            return dims([UnitElectricCharge.coulombs, .ampereHours, .milliampereHours, CustomUnits.elementaryCharges])
        case .voltage:
            return dims([UnitElectricPotentialDifference.volts, .kilovolts, .millivolts, .megavolts])
        case .current:
            return dims([UnitElectricCurrent.amperes, .milliamperes, .microamperes, .kiloamperes])
        case .resistance:
            return dims([UnitElectricResistance.ohms, .kiloohms, .megaohms, .milliohms])
        }
    }
}

/// Units that Foundation does not define, with CODATA conversion factors.
enum CustomUnits {
    static let electronVolts = UnitEnergy(symbol: "eV", converter: UnitConverterLinear(coefficient: 1.602_176_634e-19))
    static let megajoules = UnitEnergy(symbol: "MJ", converter: UnitConverterLinear(coefficient: 1e6))
    static let wattHours = UnitEnergy(symbol: "Wh", converter: UnitConverterLinear(coefficient: 3600))
    static let atmospheres = UnitPressure(symbol: "atm", converter: UnitConverterLinear(coefficient: 101_325))
    static let atomicMass = UnitMass(symbol: "u", converter: UnitConverterLinear(coefficient: 1.660_539_068_92e-27))
    static let days = UnitDuration(symbol: "dan", converter: UnitConverterLinear(coefficient: 86_400))
    static let years = UnitDuration(symbol: "leto", converter: UnitConverterLinear(coefficient: 365.25 * 86_400))
    static let speedOfLight = UnitSpeed(symbol: "c", converter: UnitConverterLinear(coefficient: 299_792_458))
    static let revolutionsPerMinute = UnitFrequency(symbol: "obr/min", converter: UnitConverterLinear(coefficient: 1.0 / 60))
    static let elementaryCharges = UnitElectricCharge(symbol: "e₀", converter: UnitConverterLinear(coefficient: 1.602_176_634e-19))
}

/// Converts a value into every unit of a category.
struct UnitConverterView: View {
    @AppStorage("unitCategory") private var category: UnitCategory = .length
    @State private var value: Double? = 1
    @State private var fromIndex = 0
    @Environment(AppSettings.self) private var settings

    private static let nameFormatter: MeasurementFormatter = {
        let formatter = MeasurementFormatter()
        formatter.unitStyle = .long
        formatter.unitOptions = .providedUnit
        return formatter
    }()

    var body: some View {
        let units = category.units
        List {
            Section {
                Picker("Količina", selection: $category) {
                    ForEach(UnitCategory.allCases) { Text($0.title).tag($0) }
                }
                NumberInputField(title: "Vrednost", value: $value)
                Picker("Enota", selection: $fromIndex) {
                    ForEach(units.indices, id: \.self) { i in
                        Text(label(for: units[i])).tag(i)
                    }
                }
            }
            if let value, fromIndex < units.count {
                Section("Pretvorbe") {
                    ForEach(units.indices, id: \.self) { i in
                        // Exact factors where Foundation's coefficients are rounded (36 km/h = 10 m/s).
                        let converted = UnitFactors.convert(value, from: units[fromIndex], to: units[i])
                        LabeledContent {
                            Text(format(converted))
                                .font(.body.monospacedDigit())
                                .textSelection(.enabled)
                        } label: {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(units[i].symbol).font(.body.weight(i == fromIndex ? .bold : .regular))
                                Text(Self.nameFormatter.string(from: units[i])).font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollDismissesKeyboard(.interactively)
        .onChange(of: category) { _, _ in fromIndex = 0 }
    }

    private func label(for unit: Dimension) -> String {
        "\(unit.symbol) – \(Self.nameFormatter.string(from: unit))"
    }

    private func format(_ x: Double) -> String {
        NumberFormatting.format(NumericCalculus.clean(x), options: NumberFormatOptions(mode: .norm1, significantDigits: 10, decimalSeparator: settings.decimalSeparator)).plainTextLocalized
    }
}

/// Physical constants (CODATA 2022) with copy and insert into the calculator.
struct ConstantsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.insertIntoCalculator) private var insertIntoCalculator
    @State private var search = ""

    private struct GroupSection: Identifiable {
        let group: PhysicalConstant.Group
        let items: [PhysicalConstant]
        var id: String { group.rawValue }
    }

    private var groups: [GroupSection] {
        let filtered = search.isEmpty ? PhysicalConstants.all : PhysicalConstants.all.filter {
            $0.name.localizedCaseInsensitiveContains(search) || $0.symbol.localizedCaseInsensitiveContains(search)
        }
        return PhysicalConstant.Group.allCases.compactMap { group in
            let items = filtered.filter { $0.group == group }
            return items.isEmpty ? nil : GroupSection(group: group, items: items)
        }
    }

    var body: some View {
        List {
            ForEach(groups) { section in
                Section(section.group.rawValue) {
                    ForEach(section.items) { constant in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(constant.name)
                                Spacer()
                                Text(constant.symbol).font(.body.italic().weight(.semibold))
                            }
                            HStack(spacing: 6) {
                                Text(valueText(constant)).font(.callout.monospacedDigit())
                                Text(constant.unit).font(.callout).foregroundStyle(.secondary)
                                if constant.isExact {
                                    Text("točno")
                                        .font(.caption2.weight(.semibold))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 1)
                                        .background(Color.green.opacity(0.2), in: .capsule)
                                }
                            }
                        }
                        .contextMenu {
                            Button("Vstavi v računalo", systemImage: "plus.forwardslash.minus") {
                                insertIntoCalculator(MathRowConverter.rowPreservingStructure(for: .decimal(constant.value)))
                            }
                            Button("Kopiraj vrednost", systemImage: "doc.on.doc") {
                                UIPasteboard.general.string = NumberFormatting.plain(constant.value)
                            }
                        }
                    }
                }
            }
            Section {
                Text("Vrednosti: CODATA 2022 (NIST) in IAU. Pri nalogah na maturi uporabljaj vrednosti s priloženega lista, npr. g = 9,81 m/s².")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .searchable(text: $search, prompt: "Išči konstanto")
    }

    private func valueText(_ constant: PhysicalConstant) -> String {
        let magnitude = Swift.abs(constant.value)
        let mode: DisplayMode = magnitude >= 1e6 || magnitude < 1e-3 ? .sci : .norm1
        return NumberFormatting.format(constant.value, options: NumberFormatOptions(mode: mode, places: 9, significantDigits: 12, decimalSeparator: settings.decimalSeparator)).plainTextLocalized
    }
}
