import AcuteCore
import Foundation
import Observation
import OSLog

nonisolated struct HistoryEntry: Codable, Identifiable, Hashable, Sendable {
    var id = UUID()
    var date = Date()
    var expression: MathRow
    /// Formatted decimal result (or a short description for graphs and equations).
    var resultText: String
    /// Exact form of the result, if any.
    var exactResult: MathRow?
    var numericValue: Double?
    var isGraph = false
}

nonisolated struct StoredVariable: Codable, Identifiable, Hashable, Sendable {
    var name: String
    var value: Double
    /// Exact rational value when known (keeps A = 1/3 exact).
    var numerator: Int?
    var denominator: Int?
    /// A stored matrix or vector (then `value` is unused).
    var matrix: Matrix?
    var id: String { name }

    var rational: Rational? {
        guard let numerator, let denominator else { return nil }
        return Rational(numerator, denominator)
    }
}

// A matrix keeps `value` = NaN in memory, but JSON has no NaN: it is written as the finite placeholder 0
// (builds without AppStore.makeDecoder cannot read the string "NaN") and read back as NaN.
nonisolated extension StoredVariable {
    private nonisolated enum CodingKeys: String, CodingKey {
        case name, value, numerator, denominator, matrix
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        let stored = try c.decode(Double.self, forKey: .value)
        numerator = try c.decodeIfPresent(Int.self, forKey: .numerator)
        denominator = try c.decodeIfPresent(Int.self, forKey: .denominator)
        matrix = try c.decodeIfPresent(Matrix.self, forKey: .matrix)
        value = matrix == nil ? stored : .nan
    }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(name, forKey: .name)
        try c.encode(matrix == nil ? value : 0, forKey: .value)
        try c.encodeIfPresent(numerator, forKey: .numerator)
        try c.encodeIfPresent(denominator, forKey: .denominator)
        try c.encodeIfPresent(matrix, forKey: .matrix)
    }
}

/// A function in the graph workspace.
nonisolated struct GraphFunctionDefinition: Codable, Identifiable, Hashable, Sendable {
    var id = UUID()
    var row: MathRow
    var colorIndex: Int
    var visible = true
    var shadeEnabled = false
    var shadeFrom = 0.0
    var shadeTo = 1.0
    /// Shade between this function and another one (instead of the x axis).
    var shadeAgainst: UUID?
    var showDerivative = false
    var taylorEnabled = false
    var taylorOrder = 3
    var taylorCenter = 0.0
    /// Draw the inverse function (the graph mirrored over y = x). Optional so older saves decode.
    var showInverse: Bool?
    /// Draw the integral function F(x) = ∫₀ˣ f(τ) dτ (x(t) from v(t)).
    var showIntegralFunction: Bool?
}

nonisolated struct SurfaceDefinition: Codable, Identifiable, Hashable, Sendable {
    var id = UUID()
    var row: MathRow
    var colorIndex = 0
    var visible = true
    var kind: SurfaceKind = .heightField
    var colorMode: SurfaceColorMode = .height
    /// Half-width of the square domain [−extent, extent]².
    var extent = 4.0
    var zScale = 0.75

    init(row: MathRow, kind: SurfaceKind = .heightField, extent: Double = 4) {
        self.row = row
        self.kind = kind
        self.extent = extent
    }

    // Tolerant decoding: fields added in later versions fall back to their defaults.
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        row = try c.decode(MathRow.self, forKey: .row)
        colorIndex = try c.decodeIfPresent(Int.self, forKey: .colorIndex) ?? 0
        visible = try c.decodeIfPresent(Bool.self, forKey: .visible) ?? true
        kind = try c.decodeIfPresent(SurfaceKind.self, forKey: .kind) ?? .heightField
        colorMode = try c.decodeIfPresent(SurfaceColorMode.self, forKey: .colorMode) ?? .height
        extent = try c.decodeIfPresent(Double.self, forKey: .extent) ?? 4
        zScale = try c.decodeIfPresent(Double.self, forKey: .zScale) ?? 0.75
    }
}

/// Persistent app data (history, variables, graph workspaces) as JSON in Application Support.
@Observable
final class AppStore {
    var history: [HistoryEntry] = [] { didSet { scheduleSave() } }
    var variables: [String: StoredVariable] = [:] { didSet { scheduleSave() } }
    var memory: Double = 0 { didSet { scheduleSave() } }
    var graphFunctions: [GraphFunctionDefinition] = [] { didSet { scheduleSave() } }
    var graphParameters: [String: Double] = [:] { didSet { scheduleSave() } }
    var surfaces: [SurfaceDefinition] = [] { didSet { scheduleSave() } }
    var complexFunction: MathRow = MathRow() { didSet { scheduleSave() } }
    /// Data of the statistics tool (x, y, frequency).
    var statisticsData: [DataPoint] = [] { didSet { scheduleSave() } }
    /// The second sample B, compared with the first one.
    var statisticsSecondData: [DataPoint] = [] { didSet { scheduleSave() } }
    /// A data file that an earlier launch kept aside because it could not decode it (e.g. written by a newer
    /// build, then an older one ran) and that this build can read. RootView offers it once: restoreFile() or
    /// keepCurrentData().
    private(set) var restorableFile: URL?
    /// When the offered file was kept aside: the seconds since 1970 in its name (…-unreadable-<seconds>.json).
    var restorableDate: Date? {
        guard let name = restorableFile?.deletingPathExtension().lastPathComponent,
              let seconds = name.split(separator: "-").last.flatMap({ Int($0) }) else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(seconds))
    }

    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var loading = false
    /// The data file could not be read or kept aside: saving would replace the user's data.
    @ObservationIgnored private var saveBlocked = false
    /// The data file is there but could not be read (data protection while the device is locked, I/O):
    /// `reloadIfReadFailed()` reads it again.
    @ObservationIgnored private var readFailed = false
    @ObservationIgnored private let log = Logger(subsystem: "com.markplacer.acutecalc", category: "Store")
    @ObservationIgnored private let fileURL: URL

    /// Sharp-style memories plus x and y stored values.
    static let memoryNames = ["A", "B", "C", "D", "E", "F", "X", "Y", "M"]

    private nonisolated struct Snapshot: Codable, Sendable {
        var version = 1
        var history: [HistoryEntry]
        var variables: [String: StoredVariable]
        var memory: Double
        var graphFunctions: [GraphFunctionDefinition]
        var graphParameters: [String: Double]
        var surfaces: [SurfaceDefinition]
        var complexFunction: MathRow
        // Added later: optional so older files still load.
        var statisticsData: [DataPoint]?
        var statisticsSecondData: [DataPoint]?
    }

    /// The data file read entry by entry: a history entry, variable, graph, surface or data point this build
    /// cannot decode (e.g. a MathFunction added later) is left out; the complex function falls back to the default.
    private nonisolated struct LenientSnapshot: Decodable {
        var history: [Lenient<HistoryEntry>]
        var variables: [String: Lenient<StoredVariable>]
        var memory: Double
        var graphFunctions: [Lenient<GraphFunctionDefinition>]
        var graphParameters: [String: Double]
        var surfaces: [Lenient<SurfaceDefinition>]
        var complexFunction: Lenient<MathRow>
        var statisticsData: [Lenient<DataPoint>]?
        var statisticsSecondData: [Lenient<DataPoint>]?
    }

    nonisolated static var defaultFileURL: URL {
        let base = (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("AcuteCalcData.json")
    }

    /// JSON has no NaN or ±∞, and the default strategy throws, so one such value (∞ from an overflowing
    /// result, pasted "inf" data) made every save fail. They are written as strings; finite numbers as before.
    nonisolated static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.nonConformingFloatEncodingStrategy = .convertToString(positiveInfinity: "Infinity", negativeInfinity: "-Infinity", nan: "NaN")
        return encoder
    }

    nonisolated static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.nonConformingFloatDecodingStrategy = .convertFromString(positiveInfinity: "Infinity", negativeInfinity: "-Infinity", nan: "NaN")
        return decoder
    }

    /// `fileURL` is the data file; tests pass a file of their own.
    init(fileURL: URL = AppStore.defaultFileURL) {
        self.fileURL = fileURL
        load()
        applyDefaults()
        findRestorableFile()
    }

    /// Reads the data file again if it was there but could not be read; until then nothing is saved. A launch
    /// for Background App Refresh while the device is locked cannot read it (complete protection), and the
    /// process lives on into the next session. RootView calls this when the app becomes active and when
    /// protected data becomes available. Changes made in the meantime were never saved; the file's data
    /// replaces them.
    func reloadIfReadFailed() {
        guard readFailed else { return }
        load()
        guard !readFailed else { return }
        applyDefaults()
        findRestorableFile()
    }

    /// The first graph, surface and complex function; also after the user removed them all.
    private func applyDefaults() {
        if graphFunctions.isEmpty {
            graphFunctions = [GraphFunctionDefinition(row: MathRow([.function(.sin, argument: MathRow([.symbol(.variable("x"))]))]), colorIndex: 0)]
        }
        if surfaces.isEmpty {
            surfaces = [SurfaceDefinition(row: MathRow([
                .function(.sin, argument: MathRow([
                    .symbol(.variable("x")), .power(exponent: .text("2")), .symbol(.plus),
                    .symbol(.variable("y")), .power(exponent: .text("2")),
                ])),
            ]))]
        }
        if complexFunction.isEmpty {
            complexFunction = MathRow([.function(.zeta, argument: MathRow([.symbol(.variable("z"))]))])
        }
    }

    private func load() {
        loading = true
        var saveAfterLoading = false
        defer {
            loading = false
            if saveAfterLoading { scheduleSave() }
        }
        // No file yet: the first launch, start with the defaults.
        guard FileManager.default.fileExists(atPath: fileURL.path(percentEncoded: false)) else {
            readFailed = false
            saveBlocked = false
            return
        }
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            // The file is there but cannot be read now (data protection while the device is locked, I/O): the
            // defaults must not be saved over it, so nothing is saved until reloadIfReadFailed() has read it.
            readFailed = true
            saveBlocked = true
            log.error("Could not read saved data, not saving: \(error.localizedDescription, privacy: .public)")
            return
        }
        // Read (also by a reload): from here on as at a launch. Saving stays blocked only when the file can
        // be neither decoded nor kept aside.
        readFailed = false
        saveBlocked = false
        do {
            let snapshot = try AppStore.makeDecoder().decode(Snapshot.self, from: data)
            apply(snapshot)
        } catch {
            // E.g. written by a newer build. Move it aside before the defaults are saved over it.
            log.error("Could not decode saved data: \(error.localizedDescription, privacy: .public)")
            let kept = keptAsideURL("unreadable")
            do {
                try FileManager.default.moveItem(at: fileURL, to: kept)
                log.notice("Kept the unreadable data as \(kept.lastPathComponent, privacy: .public)")
            } catch {
                saveBlocked = true
                log.error("Could not keep the unreadable data, not saving: \(error.localizedDescription, privacy: .public)")
            }
            // Entry by entry, one this build cannot decode no longer costs all the others. The whole file is
            // kept aside above (a newer build offers it again), and what was read is saved right away: the
            // data file was moved, so without a save the next launch would start from the defaults.
            if let lenient = try? AppStore.makeDecoder().decode(LenientSnapshot.self, from: data) {
                apply(Snapshot(history: lenient.history.compactMap(\.value), variables: lenient.variables.compactMapValues(\.value),
                               memory: lenient.memory, graphFunctions: lenient.graphFunctions.compactMap(\.value),
                               graphParameters: lenient.graphParameters, surfaces: lenient.surfaces.compactMap(\.value),
                               complexFunction: lenient.complexFunction.value ?? MathRow(),
                               statisticsData: lenient.statisticsData?.compactMap(\.value),
                               statisticsSecondData: lenient.statisticsSecondData?.compactMap(\.value)))
                saveAfterLoading = true
            }
        }
    }

    private func apply(_ snapshot: Snapshot) {
        history = snapshot.history
        variables = snapshot.variables
        memory = snapshot.memory
        graphFunctions = snapshot.graphFunctions
        graphParameters = snapshot.graphParameters
        surfaces = snapshot.surfaces
        complexFunction = snapshot.complexFunction
        statisticsData = snapshot.statisticsData ?? []
        statisticsSecondData = snapshot.statisticsSecondData ?? []
    }

    private func scheduleSave() {
        guard !loading, !saveBlocked else { return }
        saveTask?.cancel()
        let url = fileURL, log = self.log, previous = saveTask
        let snapshot = Snapshot(history: history, variables: variables, memory: memory, graphFunctions: graphFunctions,
                                graphParameters: graphParameters, surfaces: surfaces, complexFunction: complexFunction,
                                statisticsData: statisticsData, statisticsSecondData: statisticsSecondData)
        saveTask = Task {
            try? await Task.sleep(for: .milliseconds(400))
            // cancel() does not reach a write already under way (it runs detached), so that write ends first and
            // an older snapshot never lands after this one. Also when cancelled, so the next save waits for it too.
            if let previous { await previous.value }
            guard !Task.isCancelled else { return }
            await Task.detached(priority: .utility) {
                do {
                    let data = try AppStore.makeEncoder().encode(snapshot)
                    try data.write(to: url, options: [.atomic, .completeFileProtection])
                } catch {
                    // Saving is best effort; the next change retries.
                    log.error("Could not save data: \(error.localizedDescription, privacy: .public)")
                }
            }.value
        }
    }

    // MARK: Kept data

    /// A file next to the data file, e.g. AcuteCalcData-unreadable-1761500000.json (seconds since 1970).
    private func keptAsideURL(_ label: String) -> URL {
        let name = "\(fileURL.deletingPathExtension().lastPathComponent)-\(label)-\(Int(Date.now.timeIntervalSince1970)).\(fileURL.pathExtension)"
        return fileURL.deletingLastPathComponent().appendingPathComponent(name)
    }

    /// Offers the newest file that load() kept aside (…-unreadable-<seconds>.json) when this build can decode
    /// it, e.g. after an older build could not. An answered offer renames it …-offered; it still counts as the
    /// newest, so an older kept file is never offered after it.
    private func findRestorableFile() {
        let directory = fileURL.deletingLastPathComponent()
        guard !saveBlocked, let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path(percentEncoded: false)) else { return }
        let stem = "\(fileURL.deletingPathExtension().lastPathComponent)-unreadable-"
        let kept = names.compactMap { name -> (seconds: Int, name: String)? in
            guard name.hasPrefix(stem), let seconds = Int(name.dropFirst(stem.count).prefix(while: { $0.isNumber })) else { return nil }
            return (seconds: seconds, name: name)
        }
        guard let newest = kept.max(by: { $0.seconds < $1.seconds }),
              newest.name == "\(stem)\(newest.seconds).\(fileURL.pathExtension)" else { return }
        let url = directory.appendingPathComponent(newest.name)
        guard let data = try? Data(contentsOf: url), (try? AppStore.makeDecoder().decode(Snapshot.self, from: data)) != nil else { return }
        restorableFile = url
    }

    /// "Obnovi": the offered file becomes the data file. The data it replaces is kept aside too
    /// (…-replaced-<seconds>.json), and the offered file is not offered again.
    func restoreFile() {
        guard let url = restorableFile else { return }
        restorableFile = nil
        do {
            let data = try Data(contentsOf: url)
            let snapshot = try AppStore.makeDecoder().decode(Snapshot.self, from: data)
            // The data as the app holds it, not the file: also a change whose save still waits or is being written.
            let current = Snapshot(history: history, variables: variables, memory: memory, graphFunctions: graphFunctions,
                                   graphParameters: graphParameters, surfaces: surfaces, complexFunction: complexFunction,
                                   statisticsData: statisticsData, statisticsSecondData: statisticsSecondData)
            try AppStore.makeEncoder().encode(current).write(to: keptAsideURL("replaced"), options: [.withoutOverwriting, .completeFileProtection])
            // Written now, not 400 ms later, so the restored data is in the file before the offer is marked.
            try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
            loading = true
            apply(snapshot)
            loading = false
            // Saved once more: scheduleSave cancels a save of the replaced data that still waits, and it writes after
            // one already under way, which may land after the write above. The waiting save resumes on the main
            // actor, so not before this returns: when a step above fails, it still saves the current data.
            scheduleSave()
        } catch {
            log.error("Could not restore the kept data: \(error.localizedDescription, privacy: .public)")
            return
        }
        applyDefaults()
        markOffered(url)
    }

    /// "Obdrži trenutne": the offered file stays as it is and is not offered again.
    func keepCurrentData() {
        guard let url = restorableFile else { return }
        restorableFile = nil
        markOffered(url)
    }

    private func markOffered(_ url: URL) {
        let name = "\(url.deletingPathExtension().lastPathComponent)-offered.\(url.pathExtension)"
        do {
            try FileManager.default.moveItem(at: url, to: url.deletingLastPathComponent().appendingPathComponent(name))
        } catch {
            log.error("Could not mark the kept data as offered: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: History

    func addHistory(_ entry: HistoryEntry) {
        if let last = history.first, last.expression == entry.expression, last.resultText == entry.resultText { return }
        history.insert(entry, at: 0)
        if history.count > 1000 { history.removeLast(history.count - 1000) }
    }

    func clearHistory(keepingRecent count: Int = 0) {
        history = Array(history.prefix(count))
    }

    // MARK: Variables

    func store(_ value: Double, rational: Rational?, in name: String) {
        variables[name] = StoredVariable(name: name, value: value, numerator: rational?.numerator, denominator: rational?.denominator)
    }

    func store(matrix: Matrix, in name: String) {
        variables[name] = StoredVariable(name: name, value: .nan, matrix: matrix)
    }

    var numericVariables: [String: Double] {
        var result: [String: Double] = [:]
        for (name, v) in variables where v.matrix == nil { result[name] = v.value }
        result["M"] = memory
        return result
    }

    var exactVariables: [String: ExactReal] {
        var result: [String: ExactReal] = [:]
        // M is the memory (see numericVariables): a value left there by STO M must not give it a second value.
        for (name, v) in variables where v.matrix == nil && name != "M" { if let r = v.rational { result[name] = ExactReal(r) } }
        return result
    }

    var matrixVariables: [String: Matrix] {
        var result: [String: Matrix] = [:]
        for (name, v) in variables { if let m = v.matrix { result[name] = m } }
        return result
    }
}

/// Decodes an element or yields nil, so one entry this build cannot decode does not fail the whole file
/// (as Lenient in AcuteCore's AppSourceFeed, which is private there).
private nonisolated struct Lenient<Value: Decodable>: Decodable {
    let value: Value?

    init(from decoder: any Decoder) throws {
        value = try? Value(from: decoder)
    }
}
