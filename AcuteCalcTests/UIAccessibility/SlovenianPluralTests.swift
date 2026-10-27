import Testing
@testable import AcuteCalc

/// A11Y-14: Slovenian has four plural forms (CLDR sl: one for n mod 100 = 1, two for 2, few for
/// 3–4, other); the old text chose only between 1 and "proste neznanke". The forms come from
/// Localizable.xcstrings, so these tests also check that the catalog key matches the source.
@MainActor
@Suite struct SlovenianPluralTests {
    @Test func freeUnknownsUseTheFourSlovenianForms() {
        #expect(LinearSystemToolView.infiniteSolutionsTitle(freeUnknowns: 1) == "Neskončno rešitev (1 prosta neznanka):")
        #expect(LinearSystemToolView.infiniteSolutionsTitle(freeUnknowns: 2) == "Neskončno rešitev (2 prosti neznanki):")
        #expect(LinearSystemToolView.infiniteSolutionsTitle(freeUnknowns: 3) == "Neskončno rešitev (3 proste neznanke):")
        #expect(LinearSystemToolView.infiniteSolutionsTitle(freeUnknowns: 4) == "Neskončno rešitev (4 proste neznanke):")
        #expect(LinearSystemToolView.infiniteSolutionsTitle(freeUnknowns: 5) == "Neskončno rešitev (5 prostih neznank):")
        #expect(LinearSystemToolView.infiniteSolutionsTitle(freeUnknowns: 101) == "Neskončno rešitev (101 prosta neznanka):")
    }

    @Test func vectorKeysUseTheDualAndTheRightPreposition() {
        // Before: "Vektor z 2 komponentami" (needs the dual) and "Vektor z 3 komponentami" (s before t).
        #expect(KeypadKey.matrix(rows: 2, columns: 1).accessibilityName == "Vektor z dvema komponentama")
        #expect(KeypadKey.matrix(rows: 3, columns: 1).accessibilityName == "Vektor s tremi komponentami")
        #expect(KeypadKey.matrix(rows: 3, columns: 3).accessibilityName == "Matrika 3 × 3")
    }
}
