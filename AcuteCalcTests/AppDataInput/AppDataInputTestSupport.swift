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

    /// Checks `condition` every 50 ms for at most `timeout` (AppStore saves 400 ms after the last change,
    /// in the background) and returns whether it became true.
    static func wait(timeout: Duration = .seconds(10), until condition: () -> Bool) async throws -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while clock.now < deadline {
            if condition() { return true }
            try await Task.sleep(for: .milliseconds(50))
        }
        return condition()
    }
}
