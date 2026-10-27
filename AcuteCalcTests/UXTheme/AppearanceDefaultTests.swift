import Foundation
import Testing
@testable import AcuteCalc

/// PLT-12: the appearance defaulted to dark (`?? .dark` in AppSettings) and RootView forces it, so a new
/// install ignored the system appearance (HIG Dark Mode: "Avoid offering an app-specific appearance
/// setting"). Earlier builds stored nothing until the user chose, so an install that already has data
/// and no stored choice keeps dark, which is what it showed; a new install follows the system.
@MainActor
@Suite struct AppearanceDefaultTests {
    @Test func newInstallFollowsTheSystem() {
        // Before the fix every install without a stored choice started dark.
        #expect(AppearanceMode.initial(stored: nil, hasEarlierData: false) == .system)
    }

    @Test func earlierInstallWithoutAChoiceStaysDark() {
        #expect(AppearanceMode.initial(stored: nil, hasEarlierData: true) == .dark)
    }

    @Test func storedChoiceIsKept() {
        for mode in AppearanceMode.allCases {
            #expect(AppearanceMode.initial(stored: mode.rawValue, hasEarlierData: false) == mode)
            #expect(AppearanceMode.initial(stored: mode.rawValue, hasEarlierData: true) == mode)
        }
    }

    /// Not a regression test: a value this build does not know (a newer build's) gives dark, as before.
    @Test func unknownStoredValueGivesDark() {
        #expect(AppearanceMode.initial(stored: "sepia", hasEarlierData: false) == .dark)
    }

    // Through AppSettings, as at launch: the decision is stored once.

    @Test func newInstallStoresSystemAndKeepsItAfterTheFirstSave() throws {
        let directory = try Self.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let dataFile = directory.appendingPathComponent("AcuteCalcData.json")
        let suite = "UXTheme-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let settings = AppSettings(defaults: defaults, dataFileURL: dataFile)
        #expect(settings.appearance == .system)
        #expect(defaults.string(forKey: "appearance") == "system")

        // AppStore writes its data file during the first launch; the next launch is still the same install.
        try Data("{}".utf8).write(to: dataFile)
        let relaunched = AppSettings(defaults: defaults, dataFileURL: dataFile)
        #expect(relaunched.appearance == .system)
    }

    @Test func earlierInstallWithoutAChoiceStoresDark() throws {
        let directory = try Self.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let dataFile = directory.appendingPathComponent("AcuteCalcData.json")
        try Data("{}".utf8).write(to: dataFile)
        let suite = "UXTheme-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let settings = AppSettings(defaults: defaults, dataFileURL: dataFile)
        #expect(settings.appearance == .dark)
        #expect(defaults.string(forKey: "appearance") == "dark")
    }

    @Test func storedChoiceIsNotRewritten() throws {
        let directory = try Self.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let dataFile = directory.appendingPathComponent("AcuteCalcData.json")
        let suite = "UXTheme-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("light", forKey: "appearance")

        let settings = AppSettings(defaults: defaults, dataFileURL: dataFile)
        #expect(settings.appearance == .light)
        #expect(defaults.string(forKey: "appearance") == "light")
    }

    /// A new, empty directory for the data file of one test.
    private static func makeDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("UXTheme-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
