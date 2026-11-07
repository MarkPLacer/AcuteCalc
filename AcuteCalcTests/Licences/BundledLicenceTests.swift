import Testing
@testable import AcuteCalc

/// Audit hygiene:2: Apache-2.0 section 4(a) asks that everyone who gets the app also gets the licence of the
/// Turbo colour map (Surface3D.metal). Nastavitve › Licence shows the copy bundled with the app.
@MainActor
@Suite struct BundledLicenceTests {
    @Test func theApacheLicenceIsBundledUnchanged() throws {
        let text = try #require(LicensesView.apacheLicense)
        // https://www.apache.org/licenses/LICENSE-2.0.txt has 11,358 bytes: a blank line, the title, the terms
        // and the appendix.
        #expect(text.utf8.count == 11358)
        #expect(text.hasPrefix("\n                                 Apache License\n"))
        #expect(text.contains("TERMS AND CONDITIONS FOR USE, REPRODUCTION, AND DISTRIBUTION"))
        #expect(text.hasSuffix("   limitations under the License.\n"))
    }
}
