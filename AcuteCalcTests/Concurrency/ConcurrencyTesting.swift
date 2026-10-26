import Foundation
import Synchronization
import Testing

/// Helpers for the tests in this folder (one name, so tests of other folders don't clash with them).
enum ConcurrencyTesting {
    /// Yields the main actor, where the models' tasks run, until `condition` holds; false when it still
    /// does not after `rounds` rounds (about 5 s when the process runs normally).
    ///
    /// The budget is counted in rounds, not on the clock: a round waits 5 ms and then for a job on the
    /// cooperative pool, where the models' detached work runs, so only time in which that work could
    /// progress counts. On CI the whole test process once stood still for about 86 s; a 5 s deadline on
    /// the clock had passed when it went on, before the evaluation the test waited for had run.
    static func eventually(rounds: Int = 1000, _ condition: () -> Bool) async throws -> Bool {
        for _ in 0..<rounds {
            if condition() { return true }
            try await Task.sleep(for: .milliseconds(5))
            await Task.detached(priority: .userInitiated) {}.value
        }
        return condition()
    }

    /// Counts calls from any thread.
    nonisolated final class Counter: Sendable {
        private let count = Mutex(0)

        func increment() { count.withLock { $0 += 1 } }

        var value: Int { count.withLock { $0 } }
    }

    /// The first call runs until its task is cancelled or the test releases it (so a test also ends when
    /// the cancellation never arrives) and records whether it saw the cancellation; later calls return at
    /// once. No clock ends it: a stall of the test process must not end it before the test typed on.
    nonisolated final class CancellationProbe: Sendable {
        private let state = Mutex<(calls: Int, released: Bool, finished: Bool, sawCancellation: Bool)>((0, false, false, false))

        func runFirstCallUntilCancelled() {
            let first = state.withLock { current in
                current.calls += 1
                return current.calls == 1
            }
            guard first else { return }
            while !Task.isCancelled, !state.withLock({ $0.released }) {}
            let cancelled = Task.isCancelled
            state.withLock { current in
                current.finished = true
                current.sawCancellation = cancelled
            }
        }

        /// Ends the first call; it records whether it had been cancelled by then.
        func release() { state.withLock { $0.released = true } }

        var started: Bool { state.withLock { $0.calls > 0 } }
        var finished: Bool { state.withLock { $0.finished } }
        var sawCancellation: Bool { state.withLock { $0.sawCancellation } }
    }
}
