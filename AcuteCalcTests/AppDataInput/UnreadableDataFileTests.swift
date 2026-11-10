import AcuteCore
import Foundation
import Testing
@testable import AcuteCalc

/// CON-09 = PLT-03 = CI-02: when the data file could not be read or decoded, the store started with the
/// defaults and saved them over the file 400 ms after launch, so all history, memories and graphs were lost.
@MainActor
@Suite struct UnreadableDataFileTests {
    /// E.g. a file written by a newer build (a MathFunction this build does not know) or a damaged one.
    @Test func undecodableFileIsKeptAsideAndSavingContinues() async throws {
        let directory = try AppDataInputTestSupport.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("AcuteCalcData.json")
        let original = Data(#"{"version":1,"history":[{"expression":{"nodes":[{"function":{"_0":"futureFunction"}}]}}]}"#.utf8)
        try original.write(to: url)
        let marker = "marker-\(UUID().uuidString)"

        let store = AppStore(fileURL: url)
        #expect(store.history.isEmpty)
        store.addHistory(HistoryEntry(expression: MathRow.text("5"), resultText: marker))
        let saved = try await AppDataInputTestSupport.wait { AppDataInputTestSupport.text(of: url).contains(marker) }
        #expect(saved)

        // Before the fix the save above replaced the only copy of the original bytes.
        let names = try FileManager.default.contentsOfDirectory(atPath: directory.path(percentEncoded: false))
        let kept = names.filter { $0.hasPrefix("AcuteCalcData-unreadable-") && $0.hasSuffix(".json") }
        #expect(kept.count == 1)
        let keptData = kept.first.flatMap { try? Data(contentsOf: directory.appendingPathComponent($0)) }
        #expect(keptData == original)

        let reloaded = AppStore(fileURL: url)
        let keptHistory = reloaded.history.contains { $0.resultText == marker }
        #expect(keptHistory)
    }

    /// A file that is there but cannot be read now (here: no read permission; on a device e.g. data
    /// protection or an I/O error) must stay untouched.
    @Test func unreadableFileIsNotSavedOver() async throws {
        let directory = try AppDataInputTestSupport.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("AcuteCalcData.json")
        let path = url.path(percentEncoded: false)
        let original = Data(#"{"version":1,"note":"the user's data"}"#.utf8)
        try original.write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: path) }
        let readable = (try? Data(contentsOf: url)) != nil
        try #require(!readable, "the test process can read a file without read permission (root?)")

        let store = AppStore(fileURL: url)
        store.addHistory(HistoryEntry(expression: MathRow.text("6"), resultText: "6"))
        // Saves are written 400 ms after the last change; before the fix the defaults replaced the file here.
        try await Task.sleep(for: .seconds(2))

        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: path)
        let after = try Data(contentsOf: url)
        #expect(after == original)
    }

    /// apis:0 = concurrency:0: a launch for Background App Refresh while the device is locked cannot read the
    /// file (complete protection), and that process lives on into the next session. The store kept the defaults
    /// and saved nothing until the process ended, so the app looked wiped and that session's work was lost.
    @Test func fileThatBecomesReadableIsReadAgainAndSavingResumes() async throws {
        let directory = try AppDataInputTestSupport.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("AcuteCalcData.json")
        let path = url.path(percentEncoded: false)
        let earlier = "earlier-\(UUID().uuidString)"
        let writer = AppStore(fileURL: url)
        writer.store(0.25, rational: Rational(1, 4), in: "B")
        writer.addHistory(HistoryEntry(expression: MathRow.text("4"), resultText: earlier))
        let written = try await AppDataInputTestSupport.wait { AppDataInputTestSupport.text(of: url).contains(earlier) }
        try #require(written)
        let original = try Data(contentsOf: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: path) }
        let readable = (try? Data(contentsOf: url)) != nil
        try #require(!readable, "the test process can read a file without read permission (root?)")

        // The locked launch: nothing is read, and nothing is saved over the file.
        let store = AppStore(fileURL: url)
        let readWhileLocked = store.history.contains { $0.resultText == earlier }
        #expect(!readWhileLocked)
        store.addHistory(HistoryEntry(expression: MathRow.text("5"), resultText: "5"))
        try await Task.sleep(for: .seconds(2))
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: path)
        let untouched = try Data(contentsOf: url)
        #expect(untouched == original)

        // Unlocked, the app becomes active: the same store reads the file (before the fix it never did again).
        store.reloadIfReadFailed()
        let restored = store.history.contains { $0.resultText == earlier }
        #expect(restored)
        #expect(store.variables["B"]?.value == 0.25)
        // Saving works again (before the fix every change was dropped), and the file's data stays.
        let marker = "marker-\(UUID().uuidString)"
        store.addHistory(HistoryEntry(expression: MathRow.text("6"), resultText: marker))
        let saved = try await AppDataInputTestSupport.wait { AppDataInputTestSupport.text(of: url).contains(marker) }
        #expect(saved)
        let keptEarlier = AppDataInputTestSupport.text(of: url).contains(earlier)
        #expect(keptEarlier)
    }

    /// Not a regression test: the first launch (no file yet) must still save, as before.
    @Test func missingFileStartsWithDefaultsAndSaves() async throws {
        let directory = try AppDataInputTestSupport.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("AcuteCalcData.json")
        let marker = "marker-\(UUID().uuidString)"

        let store = AppStore(fileURL: url)
        #expect(store.graphFunctions.count == 1)
        store.addHistory(HistoryEntry(expression: MathRow.text("7"), resultText: marker))
        let saved = try await AppDataInputTestSupport.wait { AppDataInputTestSupport.text(of: url).contains(marker) }
        #expect(saved)
        let names = try FileManager.default.contentsOfDirectory(atPath: directory.path(percentEncoded: false))
        let movedAside = names.contains { $0.contains("unreadable") }
        #expect(!movedAside)
    }
}
