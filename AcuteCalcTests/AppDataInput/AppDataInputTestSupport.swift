import Foundation

/// Helpers of the AppDataInput tests: a temporary data file and waiting for the debounced save.
enum AppDataInputTestSupport {
    /// A new, empty directory for the data file of one test.
    static func makeDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AppDataInput-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    /// The text of a file, or "" while it does not exist.
    static func text(of url: URL) -> String {
        (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }

    /// Checks `condition` every 50 ms, at most `rounds` times (about 10 s while the process runs; AppStore
    /// saves 400 ms after the last change, in the background), and returns whether it became true.
    ///
    /// The budget is counted in rounds, not on the clock: a round waits 50 ms and then for a job on the
    /// cooperative pool, where the save writes the file, so only time in which the save could run counts.
    /// On CI the app's tests once made no progress for about 24 s while other suites ran (integration run
    /// 40423618095), and a 10 s deadline on the clock had passed before the save could run.
    static func wait(rounds: Int = 200, until condition: () -> Bool) async throws -> Bool {
        for _ in 0..<rounds {
            if condition() { return true }
            try await Task.sleep(for: .milliseconds(50))
            await Task.detached(priority: .utility) {}.value
        }
        return condition()
    }
}
