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

    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var loading = false
    @ObservationIgnored private let log = Logger(subsystem: "com.markplacer.acutecalc", category: "Store")

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
    }

    nonisolated private static var fileURL: URL {
        let base = (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("AcuteCalcData.json")
    }

    init() {
        load()
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
        defer { loading = false }
        guard let data = try? Data(contentsOf: AppStore.fileURL) else { return }
        do {
            let snapshot = try JSONDecoder().decode(Snapshot.self, from: data)
            history = snapshot.history
            variables = snapshot.variables
            memory = snapshot.memory
            graphFunctions = snapshot.graphFunctions
            graphParameters = snapshot.graphParameters
            surfaces = snapshot.surfaces
            complexFunction = snapshot.complexFunction
            statisticsData = snapshot.statisticsData ?? []
        } catch {
            log.error("Could not read saved data: \(error.localizedDescription)")
        }
    }

    private func scheduleSave() {
        guard !loading else { return }
        saveTask?.cancel()
        let snapshot = Snapshot(history: history, variables: variables, memory: memory, graphFunctions: graphFunctions,
                                graphParameters: graphParameters, surfaces: surfaces, complexFunction: complexFunction,
                                statisticsData: statisticsData)
        saveTask = Task {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            await Task.detached(priority: .utility) {
                do {
                    let data = try JSONEncoder().encode(snapshot)
                    try data.write(to: AppStore.fileURL, options: [.atomic, .completeFileProtection])
                } catch {
                    // Saving is best effort; the next change retries.
                }
            }.value
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
        for (name, v) in variables where v.matrix == nil { if let r = v.rational { result[name] = ExactReal(r) } }
        return result
    }

    var matrixVariables: [String: Matrix] {
        var result: [String: Matrix] = [:]
        for (name, v) in variables { if let m = v.matrix { result[name] = m } }
        return result
    }
}
