import AcuteCore
import Foundation
import Observation
import SwiftUI

enum AppearanceMode: String, CaseIterable, Identifiable, Codable {
    case system, dark, light
    var id: String { rawValue }
    var title: String {
        switch self {
        case .system: "Sistemsko"
        case .dark: "Temno"
        case .light: "Svetlo"
        }
    }
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .dark: .dark
        case .light: .light
        }
    }
}

enum AccentTheme: String, CaseIterable, Identifiable, Codable {
    case acuteBlue, mint, purple, pink, orange, red, green, graphite
    var id: String { rawValue }
    var title: String {
        switch self {
        case .acuteBlue: "Acute modra"
        case .mint: "Meta"
        case .purple: "Vijolična"
        case .pink: "Roza"
        case .orange: "Oranžna"
        case .red: "Rdeča"
        case .green: "Zelena"
        case .graphite: "Grafit"
        }
    }
    var color: Color {
        switch self {
        case .acuteBlue: Color(red: 0.0, green: 0.66, blue: 1.0)
        case .mint: Color(red: 0.0, green: 0.78, blue: 0.67)
        case .purple: Color(red: 0.58, green: 0.38, blue: 1.0)
        case .pink: Color(red: 1.0, green: 0.36, blue: 0.62)
        case .orange: Color(red: 1.0, green: 0.58, blue: 0.0)
        case .red: Color(red: 1.0, green: 0.27, blue: 0.27)
        case .green: Color(red: 0.2, green: 0.8, blue: 0.35)
        case .graphite: Color(red: 0.55, green: 0.58, blue: 0.62)
        }
    }
    var rgba: RGBA {
        switch self {
        case .acuteBlue: .rgba(0.0, 0.66, 1.0)
        case .mint: .rgba(0.0, 0.78, 0.67)
        case .purple: .rgba(0.58, 0.38, 1.0)
        case .pink: .rgba(1.0, 0.36, 0.62)
        case .orange: .rgba(1.0, 0.58, 0.0)
        case .red: .rgba(1.0, 0.27, 0.27)
        case .green: .rgba(0.2, 0.8, 0.35)
        case .graphite: .rgba(0.55, 0.58, 0.62)
        }
    }
}

enum MultiplicationSign: String, CaseIterable, Identifiable, Codable {
    case dot, cross
    var id: String { rawValue }
    var symbol: String { self == .dot ? "·" : "×" }
    var title: String { self == .dot ? "Pika (·)" : "Križec (×)" }
}

enum FunctionNotation: String, CaseIterable, Identifiable, Codable {
    case international, slovenian
    var id: String { rawValue }
    var title: String { self == .international ? "tan, cot, arcsin" : "tg, ctg, arc sin" }
}

/// User preferences, persisted in UserDefaults.
@Observable
final class AppSettings {
    @ObservationIgnored private let defaults: UserDefaults

    var appearance: AppearanceMode { didSet { save(appearance.rawValue, "appearance") } }
    var accent: AccentTheme { didSet { save(accent.rawValue, "accent") } }
    var angleUnit: AngleUnit { didSet { save(angleUnit.rawValue, "angleUnit") } }
    var displayMode: DisplayMode { didSet { save(displayMode.rawValue, "displayMode") } }
    var fixedPlaces: Int { didSet { save(fixedPlaces, "fixedPlaces") } }
    var significantDigits: Int { didSet { save(significantDigits, "significantDigits") } }
    var decimalComma: Bool { didSet { save(decimalComma, "decimalComma") } }
    var digitGrouping: Bool { didSet { save(digitGrouping, "digitGrouping") } }
    var multiplication: MultiplicationSign { didSet { save(multiplication.rawValue, "multiplication") } }
    var notation: FunctionNotation { didSet { save(notation.rawValue, "notation") } }
    var recurringDecimals: Bool { didSet { save(recurringDecimals, "recurringDecimals") } }
    var complexResults: Bool { didSet { save(complexResults, "complexResults") } }
    /// Electrical engineering notation: j instead of i.
    var imaginaryJ: Bool { didSet { save(imaginaryJ, "imaginaryJ") } }
    var haptics: Bool { didSet { save(haptics, "haptics") } }
    var keyRepeatDelay: Double { didSet { save(keyRepeatDelay, "keyRepeatDelay") } }
    var keyRepeatRate: Double { didSet { save(keyRepeatRate, "keyRepeatRate") } }
    var addOnEnter: Bool { didSet { save(addOnEnter, "addOnEnter") } }
    var addOnClear: Bool { didSet { save(addOnClear, "addOnClear") } }
    var addGraphsToHistory: Bool { didSet { save(addGraphsToHistory, "addGraphsToHistory") } }
    var addIncomplete: Bool { didSet { save(addIncomplete, "addIncomplete") } }
    var rendererBackend: RendererBackendKind { didSet { save(rendererBackend.rawValue, "rendererBackend") } }
    var showSpecialPoints: Bool { didSet { save(showSpecialPoints, "showSpecialPoints") } }
    var graphLineWidth: Double { didSet { save(graphLineWidth, "graphLineWidth") } }
    /// One scale on both graph axes (a circle stays round); pinch zooms both axes together.
    var equalAxes: Bool { didSet { save(equalAxes, "equalAxes") } }
    /// Label the x axis in multiples of π when a trigonometric function is drawn.
    var trigPiAxis: Bool { didSet { save(trigPiAxis, "trigPiAxis") } }
    var surfaceResolution: Int { didSet { save(surfaceResolution, "surfaceResolution") } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        func string(_ key: String) -> String? { defaults.string(forKey: key) }
        func bool(_ key: String, _ fallback: Bool) -> Bool { defaults.object(forKey: key) == nil ? fallback : defaults.bool(forKey: key) }
        func double(_ key: String, _ fallback: Double) -> Double { defaults.object(forKey: key) == nil ? fallback : defaults.double(forKey: key) }
        func int(_ key: String, _ fallback: Int) -> Int { defaults.object(forKey: key) == nil ? fallback : defaults.integer(forKey: key) }
        appearance = string("appearance").flatMap(AppearanceMode.init(rawValue:)) ?? .dark
        accent = string("accent").flatMap(AccentTheme.init(rawValue:)) ?? .acuteBlue
        angleUnit = string("angleUnit").flatMap(AngleUnit.init(rawValue:)) ?? .radians
        displayMode = string("displayMode").flatMap(DisplayMode.init(rawValue:)) ?? .norm1
        fixedPlaces = int("fixedPlaces", 4)
        significantDigits = int("significantDigits", 10)
        decimalComma = bool("decimalComma", true)
        digitGrouping = bool("digitGrouping", false)
        multiplication = string("multiplication").flatMap(MultiplicationSign.init(rawValue:)) ?? .dot
        notation = string("notation").flatMap(FunctionNotation.init(rawValue:)) ?? .international
        recurringDecimals = bool("recurringDecimals", true)
        complexResults = bool("complexResults", true)
        imaginaryJ = bool("imaginaryJ", false)
        haptics = bool("haptics", true)
        keyRepeatDelay = double("keyRepeatDelay", 0.4)
        keyRepeatRate = double("keyRepeatRate", 0.1)
        addOnEnter = bool("addOnEnter", true)
        addOnClear = bool("addOnClear", true)
        addGraphsToHistory = bool("addGraphsToHistory", true)
        addIncomplete = bool("addIncomplete", false)
        rendererBackend = string("rendererBackend").flatMap(RendererBackendKind.init(rawValue:)) ?? .metal4
        showSpecialPoints = bool("showSpecialPoints", true)
        graphLineWidth = double("graphLineWidth", 3)
        equalAxes = bool("equalAxes", true)
        trigPiAxis = bool("trigPiAxis", true)
        surfaceResolution = int("surfaceResolution", 160)
    }

    private func save(_ value: Any, _ key: String) { defaults.set(value, forKey: key) }

    var decimalSeparator: String { decimalComma ? "," : "." }

    var imaginaryUnit: String { imaginaryJ ? "j" : "i" }

    var numberFormat: NumberFormatOptions {
        NumberFormatOptions(mode: displayMode, places: fixedPlaces, significantDigits: significantDigits,
                            decimalSeparator: decimalSeparator, groupingSeparator: digitGrouping ? "\u{2009}" : nil)
    }

    func functionName(_ f: MathFunction) -> String {
        notation == .slovenian ? f.slovenianName : f.internationalName
    }
}
