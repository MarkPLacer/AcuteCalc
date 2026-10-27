import AcuteCore
import Foundation
import Testing
@testable import AcuteCalc

/// CON-01 = PLT-01 = CI-01: one NaN or ±∞ anywhere in the saved data made JSONEncoder (default strategy
/// .throw) fail on every save, silently, so after STO of a matrix (value = NaN) nothing was saved any more.
/// Before the fix none of the markers below reaches the file and every test fails at `saved`.
@MainActor
@Suite struct NonFinitePersistenceTests {
    @Test func storedMatrixAndLaterChangesSurviveARelaunch() async throws {
        let directory = try AppDataInputTestSupport.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("AcuteCalcData.json")
        let matrix = Matrix(rows: 2, columns: 2, exact: [Rational(1), Rational(2), Rational(3), Rational(4)])
        let marker = "marker-\(UUID().uuidString)"

        let store = AppStore(fileURL: url)
        store.store(matrix: matrix, in: "A")   // STO of a matrix result
        store.addHistory(HistoryEntry(expression: MathRow.text("1+1"), resultText: marker))
        let saved = try await AppDataInputTestSupport.wait { AppDataInputTestSupport.text(of: url).contains(marker) }
        #expect(saved)

        let reloaded = AppStore(fileURL: url)
        let keptHistory = reloaded.history.contains { $0.resultText == marker }
        #expect(keptHistory)
        #expect(reloaded.variables["A"]?.matrix == matrix)
        // In memory a matrix keeps value = NaN, as before (the variable tile shows it).
        #expect(reloaded.variables["A"]?.value.isNaN == true)
        #expect(reloaded.matrixVariables["A"] == matrix)
        #expect(reloaded.numericVariables["A"] == nil)
    }

    /// The current release reads its file with a plain JSONDecoder, which rejects the string "NaN";
    /// a matrix memory is therefore written with a finite placeholder, so it can still read the file.
    @Test func fileWithAMatrixMemoryStaysReadableForAPlainDecoder() async throws {
        let directory = try AppDataInputTestSupport.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("AcuteCalcData.json")
        let matrix = Matrix(rows: 2, columns: 1, exact: [Rational(5), Rational(-2)])
        let marker = "marker-\(UUID().uuidString)"

        let store = AppStore(fileURL: url)
        store.store(matrix: matrix, in: "B")
        store.store(0.25, rational: Rational(1, 4), in: "C")
        store.addHistory(HistoryEntry(expression: MathRow.text("2"), resultText: marker))
        let saved = try await AppDataInputTestSupport.wait { AppDataInputTestSupport.text(of: url).contains(marker) }
        #expect(saved)

        let release = try JSONDecoder().decode(ReleaseSnapshot.self, from: Data(contentsOf: url))
        #expect(release.variables["B"]?.matrix == matrix)
        #expect(release.variables["C"]?.value == 0.25)
        #expect(release.variables["C"]?.numerator == 1)
        #expect(release.variables["C"]?.denominator == 4)
        let releaseHistory = release.history.contains { $0.resultText == marker }
        #expect(releaseHistory)
    }

    @Test func nonFiniteValuesElsewhereDoNotStopSaving() async throws {
        let directory = try AppDataInputTestSupport.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("AcuteCalcData.json")
        let marker = "marker-\(UUID().uuidString)"

        let store = AppStore(fileURL: url)
        // Pasted statistics rows "nan" and "2;0;inf" (Double(String) accepts both).
        store.statisticsData = [DataPoint(x: .nan), DataPoint(x: 2, frequency: .infinity)]
        store.memory = -.infinity   // M− past −Double.greatestFiniteMagnitude
        // A result that overflowed to ∞ (e.g. det of a matrix with huge entries).
        store.addHistory(HistoryEntry(expression: MathRow.text("3"), resultText: marker, numericValue: .infinity))
        let saved = try await AppDataInputTestSupport.wait { AppDataInputTestSupport.text(of: url).contains(marker) }
        #expect(saved)

        let reloaded = AppStore(fileURL: url)
        #expect(reloaded.statisticsData.count == 2)
        #expect(reloaded.statisticsData.first?.x.isNaN == true)
        #expect(reloaded.statisticsData.last?.x == 2)
        #expect(reloaded.statisticsData.last?.frequency == .infinity)
        #expect(reloaded.memory == -.infinity)
        #expect(reloaded.history.first?.resultText == marker)
        #expect(reloaded.history.first?.numericValue == .infinity)
    }
}

/// The data file as the current release decodes it: synthesized Codable, plain JSONDecoder.
private nonisolated struct ReleaseSnapshot: Decodable {
    nonisolated struct Variable: Decodable {
        var name: String
        var value: Double
        var numerator: Int?
        var denominator: Int?
        var matrix: Matrix?
    }

    var version: Int
    var history: [HistoryEntry]
    var variables: [String: Variable]
    var memory: Double
    var graphFunctions: [GraphFunctionDefinition]
    var graphParameters: [String: Double]
    var surfaces: [SurfaceDefinition]
    var complexFunction: MathRow
    var statisticsData: [DataPoint]?
}
