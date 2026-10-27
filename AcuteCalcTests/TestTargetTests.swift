import Foundation
import Testing
@testable import AcuteCalc
import AcuteCore

/// The unit-test bundle runs inside the app (TEST_HOST), so app types and AcuteCore are reachable.
@Suite struct TestTargetTests {
    @Test func runsInsideTheApp() {
        #expect(Bundle.main.bundleIdentifier == "com.markplacer.acutecalc")
    }

    @Test func seesTheAppAndItsMathEngine() throws {
        #expect(AppStore.memoryNames.contains("A"))
        let value = try RealEvaluator.evaluate(try Parser.parse("2^10"))
        #expect(value == 1024)
    }
}
