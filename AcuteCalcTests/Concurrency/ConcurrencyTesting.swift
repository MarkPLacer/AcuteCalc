import Foundation
import Synchronization
import Testing

/// Helpers for the tests in this folder (one name, so tests of other folders don't clash with them).
enum ConcurrencyTesting {
    /// Yields the main actor, where the models' tasks run, until `condition` holds; false after `timeout`.
    static func eventually(timeout: Duration = .seconds(5), _ condition: () -> Bool) async throws -> Bool {
        let deadline = ContinuousClock.now + timeout
        while !condition() {
            guard ContinuousClock.now < deadline else { return false }
            try await Task.sleep(for: .milliseconds(5))
        }
        return true
    }

    /// Counts calls from any thread.
    nonisolated final class Counter: Sendable {
        private let count = Mutex(0)

        func increment() { count.withLock { $0 += 1 } }

        var value: Int { count.withLock { $0 } }
    }

    /// The first call runs until its task is cancelled (at most `limit`, so a test also ends when the
    /// cancellation never arrives) and records whether it saw the cancellation; later calls return at once.
    nonisolated final class CancellationProbe: Sendable {
        private let state = Mutex<(calls: Int, finished: Bool, sawCancellation: Bool)>((0, false, false))

        func runFirstCallUntilCancelled(limit: Duration) {
            let first = state.withLock { current in
                current.calls += 1
                return current.calls == 1
            }
            guard first else { return }
            let deadline = ContinuousClock.now + limit
            while !Task.isCancelled, ContinuousClock.now < deadline {}
            let cancelled = Task.isCancelled
            state.withLock { current in
                current.finished = true
                current.sawCancellation = cancelled
            }
        }

        var started: Bool { state.withLock { $0.calls > 0 } }
        var finished: Bool { state.withLock { $0.finished } }
        var sawCancellation: Bool { state.withLock { $0.sawCancellation } }
    }
}
