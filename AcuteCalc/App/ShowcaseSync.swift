import Foundation
import Metal
import Synchronization

#if DEBUG
/// The handshake between the showcase (Showcase.swift) and the screenshot UI test, and the wait
/// until a scene has settled (Debug builds only).
///
/// The test passes a directory on the Mac in `ACUTE_SHOWCASE_SYNC` (the simulator does not sandbox
/// apps). The app writes `plan.json` with the shots it will show, `ready-n.json` once shot n has
/// settled, and goes on to the next shot when the test has written `ack-n`.
enum ShowcaseSync {
    /// A scene in one appearance, saved as `<scene>-<appearance>.png`.
    nonisolated struct Shot: Codable, Equatable {
        var scene: String
        var appearance: String
    }

    nonisolated struct Plan: Codable {
        var shots: [Shot]
        var error: String?
    }

    nonisolated struct Ready: Codable {
        /// Seconds from the start of the shot until the app had settled.
        var seconds: Double
        /// False if the app was still busy when the wait ran out.
        var settled: Bool
        /// What could not be built as asked (a missing example, a hook that never came).
        var problems: [String] = []
    }

    private static let directory = ProcessInfo.processInfo.environment["ACUTE_SHOWCASE_SYNC"]
        .map { URL(filePath: $0, directoryHint: .isDirectory) }

    /// Writes a file for the test; atomically, so it never reads half of one.
    static func write(_ name: String, _ value: some Encodable) {
        guard let directory, let data = try? JSONEncoder().encode(value) else { return }
        try? data.write(to: directory.appending(path: name), options: .atomic)
    }

    /// Waits for the test's file `name` (at once without a test; false after the timeout).
    static func wait(for name: String, timeout: Duration = .seconds(120)) async -> Bool {
        guard let directory else { return true }
        let path = directory.appending(path: name).path
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if FileManager.default.fileExists(atPath: path) { return true }
            try? await Task.sleep(for: .milliseconds(40))
        }
        return false
    }

    /// Waits until the app has been idle for `quiet` in a row: the main thread wakes up on time
    /// (no layout or pipeline compile holds it), the process uses at most an eighth of a core (a
    /// blinking caret is fine, sampling a graph is not) and no GPU frame is in flight. False if it
    /// was still busy at the timeout.
    @discardableResult
    static func settle(quiet: Duration = .milliseconds(750), timeout: Duration = .seconds(60)) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        var last = ContinuousClock.now
        var quietSince = last
        var cpuAtQuietStart = cpuSeconds()
        while ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(100))
            let now = ContinuousClock.now
            let cpu = cpuSeconds()
            let late = now - last > .milliseconds(250)
            last = now
            let window = max((now - quietSince) / .seconds(1), 0.1)
            if late || ShowcaseProbe.framesInFlight.load(ordering: .relaxed) > 0 || cpu - cpuAtQuietStart > window / 8 {
                quietSince = now
                cpuAtQuietStart = cpu
            } else if now - quietSince >= quiet {
                return true
            }
        }
        return false
    }

    /// CPU time of the whole process (all threads), in seconds.
    private static func cpuSeconds() -> Double {
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        return Double(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec)
            + Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1_000_000
    }
}

/// GPU frames committed and not finished yet; the showcase waits until there are none.
nonisolated enum ShowcaseProbe {
    static let framesInFlight = Atomic<Int>(0)

    static func track(_ commandBuffer: MTLCommandBuffer) {
        framesInFlight.add(1, ordering: .relaxed)
        commandBuffer.addCompletedHandler { _ in ShowcaseProbe.framesInFlight.subtract(1, ordering: .relaxed) }
    }
}
#endif
