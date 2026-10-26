import Foundation

/// The source (apps.json) that AltStore, SideStore, Feather and eSign read — published with
/// every build of main by `scripts/altsource.py`. The app reads it too, to offer updates.
///
/// Only what the update check needs is decoded, and leniently: a version entry that cannot be
/// read is skipped instead of failing the whole source.
public struct AppSourceFeed: Decodable, Sendable {
    public var apps: [App]

    public init(apps: [App]) {
        self.apps = apps
    }

    public init(json: Data) throws {
        self = try JSONDecoder().decode(AppSourceFeed.self, from: json)
    }

    public struct App: Decodable, Sendable {
        public var bundleIdentifier: String
        /// Newest first, as in the source.
        public var versions: [AppVersionInfo]

        public init(bundleIdentifier: String, versions: [AppVersionInfo]) {
            self.bundleIdentifier = bundleIdentifier
            self.versions = versions
        }

        private enum CodingKeys: String, CodingKey {
            case bundleIdentifier, versions
        }

        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            bundleIdentifier = try container.decode(String.self, forKey: .bundleIdentifier)
            let entries = try container.decodeIfPresent([Lenient<AppVersionInfo>].self, forKey: .versions) ?? []
            versions = entries.compactMap(\.value)
        }
    }

    /// The versions of `bundleIdentifier` newer than the installed one, newest first, or nil
    /// when the installed version is the newest. The bundle identifier is the original one:
    /// AltStore and SideStore change the installed app's identifier, not its version or build.
    public func update(for bundleIdentifier: String, installed: BundleVersion) -> AvailableUpdate? {
        guard let app = apps.first(where: { $0.bundleIdentifier == bundleIdentifier }) else { return nil }
        let newer = app.versions.filter { $0.isNewer(than: installed) }
        return newer.isEmpty ? nil : AvailableUpdate(versions: newer)
    }
}

/// A version (CFBundleShortVersionString) with its build (CFBundleVersion): the running app's,
/// or the one the user skipped or was notified about.
public struct BundleVersion: Codable, Sendable, Equatable {
    public var version: String
    public var build: Int?

    public init(version: String, build: Int?) {
        self.version = version
        self.build = build
    }

    public init(infoDictionary: [String: Any]?) {
        version = infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
        build = (infoDictionary?["CFBundleVersion"] as? String).flatMap { Int($0) }
    }
}

/// One version entry of the source: its version and build, release date, changelog and IPA.
public struct AppVersionInfo: Decodable, Sendable, Hashable, Identifiable {
    public var version: String
    public var build: Int?
    public var date: Date?
    /// The changelog, one "• change" per line.
    public var notes: String
    public var downloadURL: URL?
    /// IPA size in bytes.
    public var size: Int64?

    public var id: String { "\(version) (\(build.map { "\($0)" } ?? "–"))" }

    public init(version: String, build: Int?, date: Date? = nil, notes: String = "", downloadURL: URL? = nil, size: Int64? = nil) {
        self.version = version
        self.build = build
        self.date = date
        self.notes = notes
        self.downloadURL = downloadURL
        self.size = size
    }

    private enum CodingKeys: String, CodingKey {
        case version, buildVersion, date, localizedDescription, downloadURL, size
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(String.self, forKey: .version)
        // `try?` flattens: each of these is a plain optional, nil for a missing or odd value.
        build = (try? container.decodeIfPresent(String.self, forKey: .buildVersion)).flatMap { Int($0) }
        date = (try? container.decodeIfPresent(String.self, forKey: .date)).flatMap(Self.date(from:))
        notes = (try? container.decodeIfPresent(String.self, forKey: .localizedDescription)) ?? ""
        downloadURL = try? container.decodeIfPresent(URL.self, forKey: .downloadURL)
        size = try? container.decodeIfPresent(Int64.self, forKey: .size)
    }

    /// The changelog as separate lines, without the bullets.
    public var changes: [String] {
        notes.split(whereSeparator: \.isNewline).map { line in
            var text = line.trimmingCharacters(in: .whitespaces)
            for bullet in ["• ", "- ", "* "] where text.hasPrefix(bullet) {
                text.removeFirst(bullet.count)
            }
            return text
        }
        .filter { !$0.isEmpty }
    }

    public var bundleVersion: BundleVersion { BundleVersion(version: version, build: build) }

    /// Builds are CI run numbers and only grow; versions without builds compare component-wise.
    public func isNewer(than other: BundleVersion) -> Bool {
        if let build, let otherBuild = other.build {
            return build > otherBuild
        }
        return Self.compare(version, other.version) == .orderedDescending
    }

    /// "2.0.10" > "2.0.9"; a missing component counts as 0.
    public static func compare(_ a: String, _ b: String) -> ComparisonResult {
        let left = a.split(separator: "."), right = b.split(separator: ".")
        for index in 0..<max(left.count, right.count) {
            let l = index < left.count ? String(left[index]) : "0"
            let r = index < right.count ? String(right[index]) : "0"
            let order: ComparisonResult = if let x = Int(l), let y = Int(r) {
                x == y ? .orderedSame : (x < y ? .orderedAscending : .orderedDescending)
            } else {
                l.compare(r, options: .numeric)
            }
            if order != .orderedSame { return order }
        }
        return .orderedSame
    }

    /// ISO 8601 with time ("2026-10-26T17:12:45Z") or just the day ("2026-10-26").
    static func date(from text: String) -> Date? {
        if let date = try? Date(text, strategy: .iso8601) { return date }
        return try? Date(text, strategy: Date.ISO8601FormatStyle().year().month().day())
    }
}

/// Newer versions than the installed one, newest first (never empty).
public struct AvailableUpdate: Sendable, Hashable, Identifiable {
    public var versions: [AppVersionInfo]

    public init(versions: [AppVersionInfo]) {
        precondition(!versions.isEmpty, "An update has at least one version")
        self.versions = versions
    }

    public var latest: AppVersionInfo { versions[0] }
    public var id: String { latest.id }
}

/// What the user chose in the update prompt, persisted between launches. Versions are kept
/// with their builds and compared like the source's entries (by build, else by version).
public struct UpdatePromptState: Codable, Sendable, Equatable {
    /// "Preskoči to različico": no prompt for this version or older ones.
    public var skipped: BundleVersion?
    /// "Kasneje": no prompt before this date.
    public var snoozedUntil: Date?
    /// The newest version a notification was already posted for.
    public var notified: BundleVersion?

    public init(skipped: BundleVersion? = nil, snoozedUntil: Date? = nil, notified: BundleVersion? = nil) {
        self.skipped = skipped
        self.snoozedUntil = snoozedUntil
        self.notified = notified
    }

    /// Whether the automatic check should show the prompt (a manual check always shows it).
    public func shouldPrompt(for update: AvailableUpdate, now: Date) -> Bool {
        if let snoozedUntil, now < snoozedUntil { return false }
        if let skipped, !update.latest.isNewer(than: skipped) { return false }
        return true
    }

    /// Whether a notification about this update is new (one per version, never for a skipped one).
    public func shouldNotify(for update: AvailableUpdate) -> Bool {
        if let skipped, !update.latest.isNewer(than: skipped) { return false }
        if let notified, !update.latest.isNewer(than: notified) { return false }
        return true
    }
}

/// Decodes an element or yields nil, so one bad entry does not fail the whole array.
private struct Lenient<Value: Decodable>: Decodable {
    let value: Value?

    init(from decoder: any Decoder) throws {
        value = try? Value(from: decoder)
    }
}
