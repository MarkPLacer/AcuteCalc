import AcuteCore
import Foundation
import Testing
@testable import AcuteCalc

/// CON-03: with more than 16 different x the frequency chart groups the values into classes with
/// Int((log2(n) + 1).rounded(.up)) and Int((v − lo)/width). Pasted data reaches it through Double(String),
/// which accepts "inf" and turns "1e400" into ∞, so n = ∞ or (v − lo)/width = ∞/∞ = NaN trapped.
/// Before the fix the first three tests crash the test process (Int(∞), Int(NaN)) instead of failing.
/// Expected classes: a Python port of FrequencyChart.bars (same IEEE divisions and truncation).
@MainActor
@Suite struct FrequencyChartTests {
    /// 17 rows x = 1 … 17 and a pasted row "18;0;inf".
    @Test func infiniteFrequencyIsLeftOut() {
        let data = (1...17).map { DataPoint(x: Double($0)) } + [DataPoint(x: 18, frequency: .infinity)]
        let bars = FrequencyChart(data: data).bars
        // n = 17 finite observations: ⌈log₂ 17 + 1⌉ = 6 classes of width 16/6.
        let frequencies = bars.map(\.frequency)
        #expect(frequencies == [3, 3, 2, 3, 3, 3])
    }

    @Test func frequenciesAddingUpToInfinityGiveNoClasses() {
        let data = (1...17).map { DataPoint(x: Double($0), frequency: 1e308) }
        #expect(FrequencyChart(data: data).bars.isEmpty)
    }

    /// −1e308 … 1e308: hi − lo overflows to ∞, so the class width is ∞.
    @Test func spanWiderThanTheLargestDoubleGivesNoClasses() {
        let data = [DataPoint(x: -1e308), DataPoint(x: 1e308)] + (1...15).map { DataPoint(x: Double($0)) }
        #expect(FrequencyChart(data: data).bars.isEmpty)
    }

    /// Not a regression test: ordinary data keeps its chart (values and classes as before).
    @Test func ordinaryDataIsUnchanged() {
        let few = FrequencyChart(data: StatisticsSamples.heights).bars
        let centers = few.map(\.center), counts = few.map(\.frequency)
        #expect(centers == [158, 162, 165, 168, 170, 172, 175, 178, 182, 188])
        #expect(counts == [1, 3, 5, 7, 9, 8, 6, 4, 2, 1])

        let many = FrequencyChart(data: (1...20).map { DataPoint(x: Double($0)) }).bars
        let classCounts = many.map(\.frequency)
        #expect(classCounts == [4, 3, 3, 3, 3, 4])
    }
}
