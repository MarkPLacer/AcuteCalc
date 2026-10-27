import Foundation
import Testing
@testable import AcuteCalc

/// CON-07: BackgroundWork.run replaces `await Task.detached { … }.value` in the calculator, the 2D
/// graph's sampling and analysis, the function analysis and the differential equations tool.
@Suite struct BackgroundWorkTests {
    @Test func cancellingTheAwaitingTaskCancelsTheWork() async {
        let caller = Task {
            await BackgroundWork.run(priority: .userInitiated) {
                // At most 3 s, so the test also ends when the cancellation never arrives.
                let deadline = ContinuousClock.now + .seconds(3)
                while !Task.isCancelled, ContinuousClock.now < deadline {}
                return Task.isCancelled
            }
        }
        caller.cancel()
        let sawCancellation = await caller.value
        #expect(sawCancellation)
    }

    @Test func returnsTheResultOfWorkDoneOffTheMainThread() async {
        let onMainThread = await BackgroundWork.run(priority: .utility) { Thread.isMainThread }
        #expect(!onMainThread)
    }
}
