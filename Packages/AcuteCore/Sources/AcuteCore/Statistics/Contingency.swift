import Foundation

// Tests of association (Statistične metode at FGG): χ² independence in a contingency table and the
// t-test for a correlation coefficient.
extension Inference {
    /// χ² test of independence for observed counts in r rows and c columns: the expected counts are
    /// E = (row sum)·(column sum)/n, χ² = Σ (O − E)²/E with (r − 1)(c − 1) degrees of freedom, and
    /// Cramér's V = √(χ²/(n·(min(r, c) − 1))) measures the strength of the association.
    public static func chiSquareIndependence(_ table: [[Double]]) throws(MathError) -> (test: Test, expected: [[Double]], cramer: Double) {
        let rows = table.count
        guard rows >= 2, let columns = table.first?.count, columns >= 2, table.allSatisfy({ $0.count == columns }) else {
            throw .domain("tabela potrebuje vsaj dve vrstici in dva stolpca enake dolžine")
        }
        guard table.allSatisfy({ $0.allSatisfy { $0 >= 0 && $0.isFinite } }) else { throw .domain("frekvence morajo biti nenegativne") }
        let rowSums = table.map { $0.reduce(0, +) }
        let columnSums = (0..<columns).map { j in table.reduce(0) { $0 + $1[j] } }
        guard rowSums.allSatisfy({ $0 > 0 }), columnSums.allSatisfy({ $0 > 0 }) else {
            throw .domain("nobena vrstica ali stolpec ne sme biti brez opazovanj")
        }
        let n = rowSums.reduce(0, +)
        guard n.isFinite else { throw .domain("frekvence so prevelike") }
        // R·(C/n) and (O − E)·((O − E)/E) stay finite whenever n is; R·C and (O − E)² could overflow.
        let expected = rowSums.map { r in columnSums.map { c in r * (c / n) } }
        var chi = 0.0
        for i in 0..<rows {
            for j in 0..<columns {
                let d = table[i][j] - expected[i][j]
                chi += d * (d / expected[i][j])
            }
        }
        guard chi.isFinite else { throw .domain("frekvence so zunaj obsega računala") }
        let degrees = Double((rows - 1) * (columns - 1))
        let p = try Distributions.chiSquareUpperTail(chi, degrees: degrees)
        let cramer = (chi / n / Double(Swift.min(rows, columns) - 1)).squareRoot()
        return (Test(statistic: chi, degrees: [degrees], pValue: p), expected, cramer)
    }

    /// The two-sided t-test of H₀: ρ = 0 for the correlation coefficient r of n pairs:
    /// t = r·√(n − 2)/√(1 − r²) with n − 2 degrees of freedom.
    public static func correlationTest(r: Double, count n: Double) throws(MathError) -> Test {
        guard Swift.abs(r) < 1, n >= 3, n == n.rounded() else { throw .domain("potrebna sta |r| < 1 in celo število n ≥ 3") }
        let t = r * (n - 2).squareRoot() / (1 - r * r).squareRoot()
        let tail = try Distributions.studentUpperTail(Swift.abs(t), degrees: n - 2)
        return Test(statistic: t, degrees: [n - 2], pValue: Swift.min(1, 2 * tail))
    }
}
