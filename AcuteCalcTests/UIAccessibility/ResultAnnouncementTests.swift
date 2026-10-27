import AcuteCore
import Foundation
import Testing
@testable import AcuteCalc

/// A11Y-07: the calculator result is one VoiceOver element and is announced after "=". The text
/// follows the display (decimal comma, the chosen format); the period of a recurring decimal is
/// said in words because the overline (U+0305) is not read.
@MainActor
@Suite struct ResultAnnouncementTests {
    let settings: AppSettings

    init() throws {
        let suite = "AcuteCalcTests.ResultAnnouncement"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        settings = AppSettings(defaults: defaults)
    }

    @Test func scientificResultIsOnePhrase() {
        let r = NumericResult(value: 1.5e-12)
        #expect(ResultAccessibility.number(r, format: .decimal, settings: settings) == "je enako 1,5 krat 10 na −12")
        #expect(ResultAccessibility.number(r, format: .automatic, settings: settings) == "je enako 1,5 krat 10 na −12")
    }

    @Test func exactResultWithItsApproximation() throws {
        let half = try #require(Rational(1, 2))
        let r = NumericResult(value: 0.5, exact: ExactReal(half))
        #expect(ResultAccessibility.number(r, format: .automatic, settings: settings) == "je enako (1)/(2), približno 0,5")
    }

    @Test func recurringPeriodIsSpoken() throws {
        let sixth = try #require(Rational(1, 6))
        let r = NumericResult(value: 1.0 / 6, exact: ExactReal(sixth))
        #expect(ResultAccessibility.number(r, format: .recurring, settings: settings) == "je enako 0,16, perioda 6")
    }

    @Test func announcementFollowsTheOutcome() {
        let number = Calculation(expr: nil, outcome: .number(NumericResult(value: 2.5)), graph: nil)
        #expect(ResultAccessibility.text(for: number, format: .automatic, settings: settings) == "je enako 2,5")
        let infinite = Calculation(expr: nil, outcome: .infinite(positive: true), graph: nil)
        #expect(ResultAccessibility.text(for: infinite, format: .automatic, settings: settings) == "je enako neskončno")
        let graph = Calculation(expr: nil, outcome: .incomplete, graph: GraphRequest(kinds: [.explicit(.variable("x"))]))
        #expect(ResultAccessibility.text(for: graph, format: .automatic, settings: settings) == "Graf")
        let empty = Calculation(expr: nil, outcome: .empty, graph: nil)
        #expect(ResultAccessibility.text(for: empty, format: .automatic, settings: settings) == nil)
        #expect(ResultAccessibility.text(for: nil, format: .automatic, settings: settings) == nil)
    }
}
