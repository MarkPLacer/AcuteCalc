import AcuteCore
import Foundation
import Testing
@testable import AcuteCalc

/// Audit metal:8: where f or g of a shaded area ∫ₐᵇ (f − g) was undefined, shadeBands put NaN points into the
/// strips. fill_vertex draws a non-finite point at the centre of the view, so the triangles next to it fanned
/// out to there. Now such a sample ends the run, and Graph2DEncoder draws each run as a strip of its own.
@MainActor
@Suite struct ShadedAreaRunTests {
    private let color = RGBA.rgba(0, 0.66, 1)

    /// f = 2 over g = √x on [−1, 1]: g is undefined left of 0, so only the 361 samples on [0, 1] are shaded.
    @Test func anUndefinedStartIsLeftOut() {
        let fills = GraphCanvasModel.shadeBands(f: { _ in 2 }, g: { $0.squareRoot() }, range: -1...1, visible: -2...2, color: color)
        #expect(fills.count == 2)
        for fill in fills {
            let finite = fill.strip.allSatisfy { $0.x.isFinite && $0.y.isFinite }
            #expect(finite)
            #expect(fill.runs == [0..<722])
        }
    }

    /// g = √(x² − 1) on [−2, 2] is undefined on (−1, 1): two runs, which end at −1 and start again at 1, so
    /// nothing is drawn across the gap.
    @Test func aGapInTheMiddleSplitsTheBand() {
        let fills = GraphCanvasModel.shadeBands(f: { _ in 3 }, g: { ($0 * $0 - 1).squareRoot() }, range: -2...2, visible: -3...3,
                                                color: color)
        #expect(fills.count == 2)
        for fill in fills {
            let finite = fill.strip.allSatisfy { $0.x.isFinite && $0.y.isFinite }
            #expect(finite)
            #expect(fill.runs == [0..<362, 362..<724])
            #expect(fill.strip[361].x == -1)
            #expect(fill.strip[362].x == 1)
        }
    }

    /// g = ln x on [0, 1] is −∞ at 0. That sample is left out instead of being drawn millions of pixels down.
    @Test func anInfiniteSampleIsLeftOut() {
        let fills = GraphCanvasModel.shadeBands(f: { _ in 2 }, g: { log($0) }, range: 0...1, visible: -1...2, color: color)
        #expect(fills.count == 2)
        for fill in fills {
            let finite = fill.strip.allSatisfy { $0.x.isFinite && $0.y.isFinite }
            #expect(finite)
            #expect(fill.runs == [0..<1440])
        }
    }

    /// On a logarithmic y axis a band down to 0 has its lower edge at −∞ on purpose (the renderer clamps it), so
    /// it stays one run: the test is on the values of f and g, not on their plot coordinates.
    @Test func aBandDownToZeroOnALogarithmicAxisStaysWhole() throws {
        let fills = GraphCanvasModel.shadeBands(f: { _ in 10 }, g: nil, range: 1...2, visible: 0...3, color: color,
                                                axes: AxisScales(x: .linear, y: .logarithmic))
        let positiveFill = fills.first { $0.id == "pos" }
        let positive = try #require(positiveFill)
        #expect(positive.runs == [0..<1442])
        let reachesMinusInfinity = positive.strip.contains { $0.y == -Double.infinity }
        #expect(reachesMinusInfinity)
    }
}
