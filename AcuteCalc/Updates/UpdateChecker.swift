import AcuteCore
import BackgroundTasks
import Foundation
import Observation
import OSLog
import UIKit
import UserNotifications

/// Looks for a newer build in the app source on GitHub — the apps.json that AltStore, SideStore,
/// Feather and eSign read too. This is the app's only network request; it can be turned off.
///
/// In the foreground a newer build opens the update popup (at most once a day after "Kasneje",
/// never again for a skipped build); in the background, Background App Refresh checks every few
/// hours and posts a local notification once per build. Neither needs a push entitlement, so it
/// works with any certificate, also a free Apple ID in AltStore or SideStore.
@Observable
final class UpdateChecker {
    /// The original identifier, as in the source: AltStore and SideStore append their team ID
    /// to the installed app's identifier.
    static let bundleIdentifier = "com.markplacer.acutecalc"
    static let sourceURL = URL(string: "https://github.com/MarkPLacer/AcuteCalc/releases/download/latest/apps.json")!
    static let releaseURL = URL(string: "https://github.com/MarkPLacer/AcuteCalc/releases/tag/latest")!
    /// "<bundle identifier>.update-check" as Info.plist permits it. AltStore and SideStore rename
    /// it along with the bundle identifier, and registering a name the list lacks would crash.
    static let refreshTaskIdentifier: String = {
        let permitted = Bundle.main.object(forInfoDictionaryKey: "BGTaskSchedulerPermittedIdentifiers") as? [String] ?? []
        return permitted.first { $0.hasSuffix(".update-check") } ?? "\(UpdateChecker.bundleIdentifier).update-check"
    }()

    enum Status: Equatable {
        case idle, checking, upToDate, available, failed
    }

    let installed = BundleVersion(infoDictionary: Bundle.main.infoDictionary)
    private(set) var status: Status = .idle
    /// The newer versions found by the last check.
    private(set) var update: AvailableUpdate?
    private(set) var lastChecked: Date?
    /// The update shown in the popup.
    var presented: AvailableUpdate?
    private(set) var notificationStatus: UNAuthorizationStatus = .notDetermined
    /// Background App Refresh as Settings has it (read on activation): while it is off, iOS runs no
    /// background check, so no notification can come.
    private(set) var backgroundRefreshStatus: UIBackgroundRefreshStatus = .available
    /// Low Power Mode turns Background App Refresh off while it is on.
    private(set) var lowPowerMode = false

    var automaticChecks: Bool {
        didSet {
            defaults.set(automaticChecks, forKey: Keys.automaticChecks)
            scheduleBackgroundCheck()
        }
    }
    var notifications: Bool {
        didSet {
            defaults.set(notifications, forKey: Keys.notifications)
            scheduleBackgroundCheck()
        }
    }
    /// The app that installs updates on this device: chosen in the popup the first time
    /// (or in Settings), forgotten when it no longer opens.
    var manager: SideloadManager? {
        didSet { defaults.set(manager?.rawValue, forKey: Keys.manager) }
    }

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var prompt: UpdatePromptState {
        didSet { defaults.set(try? JSONEncoder().encode(prompt), forKey: Keys.prompt) }
    }
    /// A button in the popup decided what happens next (otherwise closing it means "Kasneje").
    @ObservationIgnored private var promptHandled = false
    @ObservationIgnored private var notificationDelegate: UpdateNotificationDelegate?
    /// The request under way: a second check waits for it instead of starting another.
    @ObservationIgnored private var running: Task<AvailableUpdate?, Never>?
    @ObservationIgnored private let log = Logger(subsystem: "com.markplacer.acutecalc", category: "Updates")

    private enum Keys {
        static let automaticChecks = "updates.automaticChecks"
        static let notifications = "updates.notifications"
        static let lastChecked = "updates.lastChecked"
        static let source = "updates.source"
        static let prompt = "updates.prompt"
        static let manager = "updates.manager"
    }

    /// Debug builds (simulator smoke test, screenshots) never check by themselves.
    #if DEBUG
    static let checksAutomatically = false
    #else
    static let checksAutomatically = true
    #endif

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        automaticChecks = defaults.object(forKey: Keys.automaticChecks) as? Bool ?? true
        notifications = defaults.object(forKey: Keys.notifications) as? Bool ?? false
        manager = defaults.string(forKey: Keys.manager).flatMap(SideloadManager.init(rawValue:))
        lastChecked = defaults.object(forKey: Keys.lastChecked) as? Date
        prompt = defaults.data(forKey: Keys.prompt).flatMap { try? JSONDecoder().decode(UpdatePromptState.self, from: $0) } ?? UpdatePromptState()
        // The source of the last check, read against the version running now: within the hour
        // after a relaunch the popup and the badge need no new request.
        if let data = defaults.data(forKey: Keys.source), let feed = try? AppSourceFeed(json: data) {
            update = feed.update(for: Self.bundleIdentifier, installed: installed)
            status = update == nil ? .upToDate : .available
        }
        // Set before launch finishes, so tapping a notification that launched the app is seen.
        let delegate = UpdateNotificationDelegate(updates: self)
        UNUserNotificationCenter.current().delegate = delegate
        notificationDelegate = delegate
    }

    // MARK: Checking

    /// The app came to the foreground: notification permission and Background App Refresh may have
    /// changed in Settings (or in Control Center, Low Power Mode), then the automatic check.
    func becameActive() async {
        refreshBackgroundRefreshStatus()
        await refreshNotificationStatus()
        await checkAutomatically()
    }

    /// On launch and back in the foreground: fetches at most once an hour (also across
    /// relaunches) and opens the popup unless the user chose "Kasneje" or skipped this version.
    func checkAutomatically() async {
        guard Self.checksAutomatically, automaticChecks else { return }
        let found: AvailableUpdate?
        if let lastChecked, Date.now.timeIntervalSince(lastChecked) < 3600 {
            found = update
        } else {
            found = await check()
        }
        guard let found, presented == nil, prompt.shouldPrompt(for: found, now: .now) else { return }
        // Let the launch settle before the sheet slides in.
        try? await Task.sleep(for: .seconds(1))
        if presented == nil { presented = found }
    }

    /// "Preveri zdaj" in Settings, the acutecalc://update link and a tapped notification: always
    /// shows the popup when there is something newer (joining a check already under way).
    func checkNow() async {
        if let found = await check() { presented = found }
    }

    /// Fetches the source: the newer versions, or nil when up to date or the check failed
    /// (`status` tells which; `update` keeps the last good result for the badge and Settings).
    /// Checks that overlap share one request.
    @discardableResult
    func check() async -> AvailableUpdate? {
        if let running { return await running.value }
        let task = Task { await fetch() }
        running = task
        let found = await task.value
        running = nil
        return found
    }

    private func fetch() async -> AvailableUpdate? {
        status = .checking
        do {
            var request = URLRequest(url: Self.sourceURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
            let feed = try AppSourceFeed(json: data)
            update = feed.update(for: Self.bundleIdentifier, installed: installed)
            lastChecked = .now
            defaults.set(lastChecked, forKey: Keys.lastChecked)
            defaults.set(data, forKey: Keys.source)
            status = update == nil ? .upToDate : .available
            return update
        } catch {
            // No popup from a failed check.
            status = .failed
            return nil
        }
    }

    // MARK: Popup choices

    /// "Kasneje": ask again tomorrow.
    func remindLater() {
        prompt.snoozedUntil = .now.addingTimeInterval(24 * 3600)
        closePopup()
    }

    /// "Preskoči to različico": no popup or notification for this version; a newer one asks again.
    func skip(_ update: AvailableUpdate) {
        prompt.skipped = update.latest.bundleVersion
        closePopup()
    }

    /// The user went off to update: no popup for the next hour while the manager installs it.
    func didStartUpdate() {
        prompt.snoozedUntil = .now.addingTimeInterval(3600)
        closePopup()
    }

    /// The popup is gone (also swiped away): without a decision that means "Kasneje".
    func popupClosed() {
        if !promptHandled { prompt.snoozedUntil = .now.addingTimeInterval(24 * 3600) }
        promptHandled = false
    }

    private func closePopup() {
        promptHandled = true
        presented = nil
    }

    // MARK: Notifications

    func refreshNotificationStatus() async {
        notificationStatus = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        if notifications, notificationStatus == .denied { notifications = false }
    }

    /// Turns notifications on, asking for permission in context (the popup or Settings).
    func enableNotifications() async {
        let center = UNUserNotificationCenter.current()
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        await refreshNotificationStatus()
        notifications = granted
    }

    /// Background App Refresh: a quiet check that posts one notification per new version.
    func checkInBackground() async {
        // The task is complete, and the app suspended again, as soon as this returns: the next request
        // goes in first, as in Apple's handleAppRefresh (a Task started at the end might never run).
        await requestBackgroundCheck()
        guard automaticChecks, notifications else { return }
        guard let update = await check(), prompt.shouldNotify(for: update) else { return }
        await refreshNotificationStatus()
        guard notificationStatus == .authorized || notificationStatus == .provisional else { return }
        // Only a delivered notification counts; a failed one is tried again next time.
        if await post(update) { prompt.notified = update.latest.bundleVersion }
    }

    private func post(_ update: AvailableUpdate) async -> Bool {
        let latest = update.latest
        let content = UNMutableNotificationContent()
        content.title = "Acute Calc \(latest.version) je na voljo"
        let changes = update.versions.flatMap(\.changes)
        content.body = changes.isEmpty
            ? "Odpri za seznam sprememb in posodobitev."
            : changes.prefix(3).map { "• \($0)" }.joined(separator: "\n") + (changes.count > 3 ? "\n… in še \(changes.count - 3)" : "")
        // A banner without a sound: worth seeing, never urgent (HIG, Managing notifications).
        content.threadIdentifier = "updates"
        content.interruptionLevel = .active
        content.relevanceScore = 0.3
        content.targetContentIdentifier = "update"
        // One identifier for all of them: a newer update replaces the older notification.
        let request = UNNotificationRequest(identifier: Self.notificationIdentifier, content: content, trigger: nil)
        do {
            try await UNUserNotificationCenter.current().add(request)
            return true
        } catch {
            return false
        }
    }

    nonisolated static let notificationIdentifier = "com.markplacer.acutecalc.update"

    // MARK: Background App Refresh

    /// Asks iOS for the next background check (it decides when, from how the app is used; one
    /// request is pending at a time and a new one replaces it), or cancels it while automatic checks
    /// or notifications are off.
    func requestBackgroundCheck() async {
        guard Self.checksAutomatically, automaticChecks, notifications else {
            BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.refreshTaskIdentifier)
            return
        }
        let request = BGAppRefreshTaskRequest(identifier: Self.refreshTaskIdentifier)
        request.earliestBeginDate = .now.addingTimeInterval(6 * 3600)
        do {
            // Callable on any thread, the main one too (Apple DTS, developer forums thread 840876).
            try await BGTaskScheduler.shared.submitTaskRequest(request)
        } catch {
            if Self.backgroundRefreshIsOff(error) {
                // Settings › Posodobitve says so; the popup still works.
                refreshBackgroundRefreshStatus()
            } else {
                log.error("Could not ask for a background check: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// The same for the switches and RootView, which cannot wait for it.
    func scheduleBackgroundCheck() {
        Task { await requestBackgroundCheck() }
    }

    /// iOS refused the request because Background App Refresh is off: in Settings, by Low Power Mode,
    /// or on the simulator (BGTaskScheduler.Error.Code.unavailable).
    static func backgroundRefreshIsOff(_ error: any Error) -> Bool {
        (error as? BGTaskScheduler.Error)?.code == .unavailable
    }

    /// Reads Background App Refresh and Low Power Mode again. Never during App.init: UIApplication
    /// does not exist before UIApplicationMain.
    func refreshBackgroundRefreshStatus() {
        backgroundRefreshStatus = UIApplication.shared.backgroundRefreshStatus
        lowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
    }

    /// What Settings › Posodobitve says about Background App Refresh while notifications are on.
    enum BackgroundRefreshNote: Equatable {
        /// Off for this app, or for all apps, in Settings: a link to Settings.
        case turnedOff
        /// Low Power Mode turned it off; the switch in Settings is probably on.
        case lowPowerMode
    }

    var backgroundRefreshNote: BackgroundRefreshNote? {
        Self.backgroundRefreshNote(status: backgroundRefreshStatus, lowPowerMode: lowPowerMode)
    }

    /// Apple: warn when Background App Refresh is off, but not when it is restricted (parental
    /// controls, a managed device), since that person cannot turn it on. Low Power Mode turns it off
    /// by itself, so then the note names Low Power Mode instead of the switch in Settings.
    static func backgroundRefreshNote(status: UIBackgroundRefreshStatus, lowPowerMode: Bool) -> BackgroundRefreshNote? {
        if status == .restricted { return nil }
        if lowPowerMode { return .lowPowerMode }
        return status == .denied ? .turnedOff : nil
    }
}

/// Opens the update popup when a notification about an update is tapped. Not main-actor
/// isolated: the notification center calls it from its own queue.
nonisolated final class UpdateNotificationDelegate: NSObject, UNUserNotificationCenterDelegate, Sendable {
    private let updates: UpdateChecker

    init(updates: UpdateChecker) {
        self.updates = updates
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard response.notification.request.identifier == UpdateChecker.notificationIdentifier else { return }
        await updates.checkNow()
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list]
    }
}
