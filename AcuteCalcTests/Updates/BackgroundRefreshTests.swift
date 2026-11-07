import BackgroundTasks
import Foundation
import Testing
import UIKit
@testable import AcuteCalc

/// apis:3: the request for the next background check was submitted with `try?`, so iOS refusing it because
/// Background App Refresh is off went unnoticed: the switch for notifications stayed on and the footer promised
/// background checks that could never run. (Before the fix there was nothing to test.)
@MainActor
@Suite struct BackgroundRefreshTests {
    /// The refusal as the scheduler delivers it, an NSError of its domain, and as the Swift error.
    @Test func unavailableMeansBackgroundRefreshIsOff() {
        let refused = NSError(domain: BGTaskScheduler.Error.errorDomain, code: BGTaskScheduler.Error.Code.unavailable.rawValue)
        #expect(UpdateChecker.backgroundRefreshIsOff(refused))
        #expect(UpdateChecker.backgroundRefreshIsOff(BGTaskScheduler.Error(.unavailable)))
    }

    /// Other refusals are only logged: they say nothing about the switch in Settings.
    @Test func otherRefusalsAreNotBackgroundRefresh() {
        #expect(!UpdateChecker.backgroundRefreshIsOff(BGTaskScheduler.Error(.tooManyPendingTaskRequests)))
        #expect(!UpdateChecker.backgroundRefreshIsOff(BGTaskScheduler.Error(.notPermitted)))
        #expect(!UpdateChecker.backgroundRefreshIsOff(URLError(.timedOut)))
    }

    @Test func offInSettingsLinksToSettings() {
        let note = UpdateChecker.backgroundRefreshNote(status: .denied, lowPowerMode: false)
        #expect(note == .turnedOff)
    }

    /// Low Power Mode turns Background App Refresh off by itself: the note says so instead of sending the
    /// user to a switch that is probably on.
    @Test func lowPowerModeIsNamedInstead() {
        let whileDenied = UpdateChecker.backgroundRefreshNote(status: .denied, lowPowerMode: true)
        let whileAvailable = UpdateChecker.backgroundRefreshNote(status: .available, lowPowerMode: true)
        #expect(whileDenied == .lowPowerMode)
        #expect(whileAvailable == .lowPowerMode)
    }

    /// Apple: no warning when it is restricted (parental controls), since that user cannot turn it on.
    @Test func noNoteWhenRestrictedOrOn() {
        #expect(UpdateChecker.backgroundRefreshNote(status: .restricted, lowPowerMode: false) == nil)
        #expect(UpdateChecker.backgroundRefreshNote(status: .restricted, lowPowerMode: true) == nil)
        #expect(UpdateChecker.backgroundRefreshNote(status: .available, lowPowerMode: false) == nil)
    }
}
