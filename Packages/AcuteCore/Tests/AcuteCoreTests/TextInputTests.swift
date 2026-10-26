import Testing
@testable import AcuteCore

// MARK: Typed text (linear input, graph examples)

@Suite struct TextInputTests {
    @Test func systemKeepsItsParts() throws {
        let row = try MathRowConverter.row(fromText: "x >= 0, y >= 0, x + y <= 4")
        let system = try #require(MathRowConverter.system(from: row))
        #expect(system.count == 3)
    }

    @Test func curvesStayPairs() throws {
        let row = try MathRowConverter.row(fromText: "(2t, 6t), (2 + 2t, 6 - 6t), 0 <= t <= 1")
        let hasMatrix = row.nodes.contains { node in
            if case .matrix = node { return true }
            return false
        }
        #expect(!hasMatrix)
        let graph = try #require(try CalculationEngine.graphRequest(for: row))
        #expect(graph.kinds.count == 2)
        for kind in graph.kinds {
            guard case .parametric(_, _, let from, let to) = kind else {
                Issue.record("\(kind) is not a parametric curve")
                continue
            }
            #expect(from == 0 && to == 1)
        }
    }

    @Test func namedPointsStayPairs() throws {
        let row = try MathRowConverter.row(fromText: "A(1, 2), B(4, 5), C(6, 1)")
        let hasMatrix = row.nodes.contains { node in
            if case .matrix = node { return true }
            return false
        }
        #expect(!hasMatrix)
        let graph = try #require(try CalculationEngine.graphRequest(for: row))
        guard case .polyline(_, let closed)? = graph.kinds.first else {
            Issue.record("A, B, C are not drawn as a polygon")
            return
        }
        #expect(closed)
    }

    @Test func singleInputIsUnchanged() throws {
        for text in ["sin(x)/x", "x^2 + y^2 = 9", "y < x^2 - 2"] {
            let row = try MathRowConverter.row(fromText: text)
            let expected = MathRowConverter.rowPreservingStructure(for: try Parser.parse(text))
            #expect(row == expected)
        }
    }
}
