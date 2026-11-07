import AcuteCore
import Foundation
import Testing
@testable import AcuteCalc

/// apis:4: one UpdateChecker serves every iPad window, so each window shows the update popup, and closing it
/// runs onDismiss once per window. The first call reset the bookkeeping, and the second took the closing for
/// "Kasneje": the hour after »Posodobi v …« (or a skipped version) became a day without the popup.
@MainActor
@Suite struct UpdatePopupSnoozeTests {
    private static let update = AvailableUpdate(versions: [AppVersionInfo(version: "9.9.2", build: 9992)])

    @Test func secondWindowKeepsTheHourAfterAnUpdate() throws {
        let suite = "Updates-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let updates = UpdateChecker(defaults: defaults)

        updates.presented = Self.update
        updates.didStartUpdate()
        updates.popupClosed()   // the window where »Posodobi v …« was tapped
        updates.popupClosed()   // another window that showed the same popup
        let snoozedUntil = try #require(updates.prompt.snoozedUntil)
        #expect(snoozedUntil < Date.now.addingTimeInterval(2 * 3600))   // before the fix: a day from now
    }

    @Test func secondWindowDoesNotSnoozeASkippedVersion() throws {
        let suite = "Updates-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let updates = UpdateChecker(defaults: defaults)

        updates.presented = Self.update
        updates.skip(Self.update)
        updates.popupClosed()
        updates.popupClosed()
        #expect(updates.prompt.skipped == Self.update.latest.bundleVersion)
        #expect(updates.prompt.snoozedUntil == nil)   // before the fix: a day, also for a newer build
    }

    /// Not a regression test: closing the popup without a decision (swiped away) still means "Kasneje".
    @Test func closingWithoutADecisionSnoozesForADay() throws {
        let suite = "Updates-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let updates = UpdateChecker(defaults: defaults)

        updates.presented = Self.update
        updates.presented = nil   // the sheet's binding, when the popup is swiped away
        updates.popupClosed()
        updates.popupClosed()
        let snoozedUntil = try #require(updates.prompt.snoozedUntil)
        #expect(snoozedUntil > Date.now.addingTimeInterval(23 * 3600))
    }

    /// Not a regression test: the next popup counts on its own, so closing it without a decision snoozes again.
    @Test func nextPopupCountsAgain() throws {
        let suite = "Updates-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let updates = UpdateChecker(defaults: defaults)

        updates.presented = Self.update
        updates.didStartUpdate()
        updates.popupClosed()
        updates.popupClosed()
        updates.presented = Self.update
        updates.presented = nil
        updates.popupClosed()
        let snoozedUntil = try #require(updates.prompt.snoozedUntil)
        #expect(snoozedUntil > Date.now.addingTimeInterval(23 * 3600))
    }
}
