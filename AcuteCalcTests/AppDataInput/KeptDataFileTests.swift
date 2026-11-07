import AcuteCore
import Foundation
import Testing
@testable import AcuteCalc

/// critic:0: a data file this build cannot decode is moved aside as AcuteCalcData-unreadable-<seconds>.json, and
/// nothing ever read it again. Running an older build once (a PR artifact, an older IPA) moved the newer build's
/// file aside, and going back to the newest build did not bring the data back.
@MainActor
@Suite struct KeptDataFileTests {
    /// Saves a history with only `older`, copies that file to each of `keptNames` (where an older build moves a
    /// file it cannot decode), then saves a history with only `current`.
    private func prepare(_ directory: URL, older: String, current: String, keptNames: [String]) async throws {
        let url = directory.appendingPathComponent("AcuteCalcData.json")
        let writer = AppStore(fileURL: url)
        writer.addHistory(HistoryEntry(expression: MathRow.text("1"), resultText: older))
        let written = try await AppDataInputTestSupport.wait { AppDataInputTestSupport.text(of: url).contains(older) }
        try #require(written)
        for name in keptNames {
            try FileManager.default.copyItem(at: url, to: directory.appendingPathComponent(name))
        }
        writer.clearHistory()
        writer.addHistory(HistoryEntry(expression: MathRow.text("2"), resultText: current))
        let rewritten = try await AppDataInputTestSupport.wait {
            let text = AppDataInputTestSupport.text(of: url)
            return text.contains(current) && !text.contains(older)
        }
        try #require(rewritten)
    }

    @Test func keptFileThisBuildCanReadIsOfferedAndRestored() async throws {
        let directory = try AppDataInputTestSupport.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("AcuteCalcData.json")
        let older = "older-\(UUID().uuidString)", current = "current-\(UUID().uuidString)"
        try await prepare(directory, older: older, current: current, keptNames: ["AcuteCalcData-unreadable-1000.json"])

        let store = AppStore(fileURL: url)
        // Offered (before the fix nothing read the kept file again), not restored without asking.
        #expect(store.restorableFile?.lastPathComponent == "AcuteCalcData-unreadable-1000.json")
        // The offer names the day the file was kept aside: the seconds in its name.
        #expect(store.restorableDate == Date(timeIntervalSince1970: 1000))
        let beforeRestore = store.history.map(\.resultText)
        #expect(beforeRestore == [current])

        store.restoreFile()
        #expect(store.restorableFile == nil)
        let restored = store.history.map(\.resultText)
        #expect(restored == [older])
        #expect(AppDataInputTestSupport.text(of: url).contains(older))
        // The data it replaced is kept aside too.
        let names = try FileManager.default.contentsOfDirectory(atPath: directory.path(percentEncoded: false))
        let replaced = names.filter { $0.hasPrefix("AcuteCalcData-replaced-") }
        #expect(replaced.count == 1)
        let replacedText = replaced.first.map { AppDataInputTestSupport.text(of: directory.appendingPathComponent($0)) } ?? ""
        #expect(replacedText.contains(current))

        // Saving continues; the next launch keeps the restored data and does not offer the file again.
        let marker = "marker-\(UUID().uuidString)"
        store.addHistory(HistoryEntry(expression: MathRow.text("3"), resultText: marker))
        let saved = try await AppDataInputTestSupport.wait { AppDataInputTestSupport.text(of: url).contains(marker) }
        #expect(saved)
        let relaunched = AppStore(fileURL: url)
        #expect(relaunched.restorableFile == nil)
        let relaunchedHistory = relaunched.history.map(\.resultText)
        #expect(relaunchedHistory == [marker, older])
    }

    /// »Obdrži trenutne« keeps the current data, and neither that file nor an older kept one is offered again.
    @Test func keptFileIsOfferedOnlyOnce() async throws {
        let directory = try AppDataInputTestSupport.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("AcuteCalcData.json")
        let older = "older-\(UUID().uuidString)", current = "current-\(UUID().uuidString)"
        // Two runs of an older build, each moved a file aside.
        try await prepare(directory, older: older, current: current,
                          keptNames: ["AcuteCalcData-unreadable-1000.json", "AcuteCalcData-unreadable-2000.json"])

        let store = AppStore(fileURL: url)
        #expect(store.restorableFile?.lastPathComponent == "AcuteCalcData-unreadable-2000.json")
        store.keepCurrentData()
        #expect(store.restorableFile == nil)
        let kept = store.history.map(\.resultText)
        #expect(kept == [current])

        let relaunched = AppStore(fileURL: url)
        #expect(relaunched.restorableFile == nil)
        let relaunchedHistory = relaunched.history.map(\.resultText)
        #expect(relaunchedHistory == [current])
        // Both files stay; the offered one is only renamed.
        let names = try FileManager.default.contentsOfDirectory(atPath: directory.path(percentEncoded: false))
        #expect(names.contains("AcuteCalcData-unreadable-1000.json"))
        #expect(names.contains("AcuteCalcData-unreadable-2000-offered.json"))
    }

    /// Here this build is the older one: the newest kept file is from a newer build and cannot be decoded, so
    /// nothing is offered, also not an older kept file this build could read (stale data).
    @Test func olderKeptFileIsNotOfferedAfterANewerOne() async throws {
        let directory = try AppDataInputTestSupport.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("AcuteCalcData.json")
        let older = "older-\(UUID().uuidString)", current = "current-\(UUID().uuidString)"
        try await prepare(directory, older: older, current: current, keptNames: ["AcuteCalcData-unreadable-1000.json"])
        try Data(#"{"version":2}"#.utf8).write(to: directory.appendingPathComponent("AcuteCalcData-unreadable-2000.json"))

        let store = AppStore(fileURL: url)
        #expect(store.restorableFile == nil)
        let history = store.history.map(\.resultText)
        #expect(history == [current])
    }

    /// A file from a newer build with one MathFunction this build does not know: before, the whole file was moved
    /// aside and the app started empty. Now only that entry is left out, and the whole file is kept aside byte for
    /// byte before anything is saved (a newer build offers it again).
    @Test func entryThisBuildCannotDecodeIsLeftOutAndTheFileIsKeptAside() async throws {
        let directory = try AppDataInputTestSupport.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("AcuteCalcData.json")
        let readable = "readable-\(UUID().uuidString)", unknown = "unknown-\(UUID().uuidString)"
        let writer = AppStore(fileURL: url)
        writer.store(0.5, rational: Rational(1, 2), in: "A")
        writer.addHistory(HistoryEntry(expression: MathRow.text("2"), resultText: readable))
        writer.addHistory(HistoryEntry(expression: MathRow([.function(.cos, argument: MathRow.text("0"))]), resultText: unknown))
        let written = try await AppDataInputTestSupport.wait { AppDataInputTestSupport.text(of: url).contains(unknown) }
        try #require(written)
        // As a newer build writes it: in place of cos, a MathFunction this build does not know.
        let text = AppDataInputTestSupport.text(of: url)
        try #require(text.contains(#""cos""#))
        let original = Data(text.replacingOccurrences(of: #""cos""#, with: #""futureFunction""#).utf8)
        try original.write(to: url)

        let store = AppStore(fileURL: url)
        let readableKept = store.history.contains { $0.resultText == readable }
        #expect(readableKept)
        let unknownKept = store.history.contains { $0.resultText == unknown }
        #expect(!unknownKept)
        #expect(store.variables["A"]?.value == 0.5)
        #expect(store.graphFunctions.count == 1)
        // This build cannot decode the kept file, so it offers nothing.
        #expect(store.restorableFile == nil)
        let names = try FileManager.default.contentsOfDirectory(atPath: directory.path(percentEncoded: false))
        let keptAside = names.filter { $0.hasPrefix("AcuteCalcData-unreadable-") }
        #expect(keptAside.count == 1)
        let keptData = keptAside.first.flatMap { try? Data(contentsOf: directory.appendingPathComponent($0)) }
        #expect(keptData == original)

        // What was read is saved without another change, so the next launch reads it.
        let resaved = try await AppDataInputTestSupport.wait { AppDataInputTestSupport.text(of: url).contains(readable) }
        #expect(resaved)
        let relaunched = AppStore(fileURL: url)
        let relaunchedHistory = relaunched.history.map(\.resultText)
        #expect(relaunchedHistory == [readable])
        #expect(relaunched.variables["A"]?.value == 0.5)
    }
}
