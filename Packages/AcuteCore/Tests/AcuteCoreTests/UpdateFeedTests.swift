import Foundation
import Testing
@testable import AcuteCore

// MARK: The update check reads the app source that scripts/altsource.py publishes

@Suite struct UpdateFeedTests {
    /// The shape scripts/altsource.py writes: a versions array plus the flat fields for eSign.
    static let source = #"""
    {
      "name": "Acute Calc",
      "identifier": "com.markplacer.acutecalc.source",
      "sourceURL": "https://github.com/MarkPLacer/AcuteCalc/releases/download/latest/apps.json",
      "tintColor": "1EA8FE",
      "featuredApps": ["com.markplacer.acutecalc"],
      "apps": [
        {
          "name": "Acute Calc",
          "bundleIdentifier": "com.markplacer.acutecalc",
          "developerName": "MarkPLacer",
          "localizedDescription": "Kalkulator",
          "iconURL": "https://github.com/MarkPLacer/AcuteCalc/releases/download/latest/AcuteCalc-icon.png",
          "category": "utilities",
          "versions": [
            {
              "version": "2.0.42",
              "buildVersion": "42",
              "date": "2026-10-27T08:15:00Z",
              "localizedDescription": "• Update popup and notifications\n• App source for AltStore, SideStore, Feather and eSign",
              "downloadURL": "https://github.com/MarkPLacer/AcuteCalc/releases/download/latest/AcuteCalc-2.0.42.ipa",
              "size": 24126922,
              "sha256": "73177d64a54b9d9ecf1c1d10478fdc7e9f3806a954407821ec7fd1bfb820fce2",
              "minOSVersion": "27.0"
            },
            {
              "version": "2.0.41",
              "buildVersion": "41",
              "date": "2026-10-26",
              "localizedDescription": "• Circuit analysis by nodal analysis",
              "downloadURL": "https://github.com/MarkPLacer/AcuteCalc/releases/download/latest/AcuteCalc-2.0.41.ipa",
              "size": 24100000
            },
            { "buildVersion": "40", "localizedDescription": "an entry without a version is skipped" },
            {
              "version": "2.0.39",
              "buildVersion": "39",
              "date": "not a date",
              "localizedDescription": "- Plane trusses",
              "downloadURL": "https://github.com/MarkPLacer/AcuteCalc/releases/download/latest/AcuteCalc-2.0.39.ipa",
              "size": "24 MB"
            }
          ],
          "appPermissions": { "entitlements": [], "privacy": {} },
          "version": "2.0.42",
          "versionDate": "2026-10-27T08:15:00Z",
          "versionDescription": "• Update popup and notifications",
          "downloadURL": "https://github.com/MarkPLacer/AcuteCalc/releases/download/latest/AcuteCalc-2.0.42.ipa",
          "size": 24126922,
          "type": 1
        },
        {
          "name": "Another app",
          "bundleIdentifier": "com.example.other",
          "versions": [{ "version": "9.0", "buildVersion": "900" }]
        }
      ],
      "news": []
    }
    """#

    static let bundleID = "com.markplacer.acutecalc"

    @Test func decodesTheGeneratedSource() throws {
        let feed = try AppSourceFeed(json: Data(Self.source.utf8))
        let versions = try #require(feed.apps.first?.versions)
        #expect(versions.map(\.version) == ["2.0.42", "2.0.41", "2.0.39"])
        #expect(versions.map(\.build) == [42, 41, 39])
        #expect(versions[0].size == 24_126_922)
        #expect(versions[0].downloadURL?.lastPathComponent == "AcuteCalc-2.0.42.ipa")
        #expect(versions[0].changes == ["Update popup and notifications", "App source for AltStore, SideStore, Feather and eSign"])
        #expect(versions[2].changes == ["Plane trusses"])
        // Odd values become nil instead of failing the entry.
        #expect(versions[2].date == nil && versions[2].size == nil)
        let expected = try #require(Calendar(identifier: .gregorian).date(from: DateComponents(
            timeZone: TimeZone(identifier: "UTC"), year: 2026, month: 10, day: 27, hour: 8, minute: 15)))
        #expect(versions[0].date == expected)
        #expect(versions[1].date != nil)
    }

    @Test func findsTheNewerVersionsByBuild() throws {
        let feed = try AppSourceFeed(json: Data(Self.source.utf8))
        let update = try #require(feed.update(for: Self.bundleID, installed: BundleVersion(version: "2.0.39", build: 39)))
        #expect(update.versions.map(\.version) == ["2.0.42", "2.0.41"])
        #expect(update.latest.build == 42)
        #expect(feed.update(for: Self.bundleID, installed: BundleVersion(version: "2.0.42", build: 42)) == nil)
        // A build from Xcode (build 1) sees every published version as newer.
        #expect(feed.update(for: Self.bundleID, installed: BundleVersion(version: "2.0.0", build: 1))?.versions.count == 3)
        // The other app's versions never count.
        #expect(feed.update(for: "com.example.missing", installed: BundleVersion(version: "1.0", build: 1)) == nil)
    }

    @Test func comparesVersionsWithoutBuilds() {
        #expect(AppVersionInfo.compare("2.0.10", "2.0.9") == .orderedDescending)
        #expect(AppVersionInfo.compare("2.1", "2.0.99") == .orderedDescending)
        #expect(AppVersionInfo.compare("2.0", "2.0.0") == .orderedSame)
        #expect(AppVersionInfo.compare("1.9", "2.0") == .orderedAscending)
        let entry = AppVersionInfo(version: "2.0.10", build: nil)
        #expect(entry.isNewer(than: BundleVersion(version: "2.0.9", build: 9)))
        #expect(!entry.isNewer(than: BundleVersion(version: "2.0.10", build: nil)))
    }

    @Test func installedVersionFromInfoDictionary() {
        let installed = BundleVersion(infoDictionary: ["CFBundleShortVersionString": "2.0.31", "CFBundleVersion": "31"])
        #expect(installed == BundleVersion(version: "2.0.31", build: 31))
        #expect(BundleVersion(infoDictionary: nil).build == nil)
    }

    @Test func promptRespectsLaterAndSkip() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let update = AvailableUpdate(versions: [AppVersionInfo(version: "2.0.42", build: 42)])
        #expect(UpdatePromptState().shouldPrompt(for: update, now: now))
        // "Kasneje" waits until the date passes.
        let snoozed = UpdatePromptState(snoozedUntil: now.addingTimeInterval(3600))
        #expect(!snoozed.shouldPrompt(for: update, now: now))
        #expect(snoozed.shouldPrompt(for: update, now: now.addingTimeInterval(7200)))
        // "Preskoči" silences this build, not a newer one.
        let skipped = UpdatePromptState(skipped: BundleVersion(version: "2.0.42", build: 42))
        #expect(!skipped.shouldPrompt(for: update, now: now))
        #expect(skipped.shouldPrompt(for: AvailableUpdate(versions: [AppVersionInfo(version: "2.0.43", build: 43)]), now: now))
        // Without builds the versions decide.
        let versionOnly = AvailableUpdate(versions: [AppVersionInfo(version: "2.1", build: nil)])
        #expect(!UpdatePromptState(skipped: BundleVersion(version: "2.1", build: nil)).shouldPrompt(for: versionOnly, now: now))
        #expect(UpdatePromptState(skipped: BundleVersion(version: "2.0.9", build: nil)).shouldPrompt(for: versionOnly, now: now))
    }

    @Test func notifiesOncePerVersion() throws {
        let update = AvailableUpdate(versions: [AppVersionInfo(version: "2.0.42", build: 42)])
        #expect(UpdatePromptState().shouldNotify(for: update))
        #expect(!UpdatePromptState(notified: BundleVersion(version: "2.0.42", build: 42)).shouldNotify(for: update))
        #expect(UpdatePromptState(notified: BundleVersion(version: "2.0.41", build: 41)).shouldNotify(for: update))
        #expect(!UpdatePromptState(skipped: BundleVersion(version: "2.0.42", build: 42)).shouldNotify(for: update))
        let versionOnly = AvailableUpdate(versions: [AppVersionInfo(version: "2.1", build: nil)])
        #expect(!UpdatePromptState(notified: BundleVersion(version: "2.1", build: nil)).shouldNotify(for: versionOnly))
        // The state survives a relaunch (UserDefaults keeps it as JSON).
        let state = UpdatePromptState(skipped: BundleVersion(version: "2.0.42", build: 42), snoozedUntil: Date(timeIntervalSince1970: 0))
        let decoded = try JSONDecoder().decode(UpdatePromptState.self, from: JSONEncoder().encode(state))
        #expect(decoded == state)
    }
}
