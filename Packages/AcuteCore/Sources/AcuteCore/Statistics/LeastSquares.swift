import Foundation

/// Least squares adjustment of indirect observations (Izravnalni račun I at FGG): l + v = A·x̂
/// with weights P = diag(p) gives x̂ = (AᵀPA)⁻¹AᵀPl, the residuals v = A·x̂ − l, σ₀² = vᵀPv/(n − u)
/// and the cofactor matrix Q_x = (AᵀPA)⁻¹ with σ(x̂ᵢ) = σ₀·√qᵢᵢ.
public enum LeastSquares {
    public struct Adjustment: Sendable, Hashable {
        public var parameters: [Double]
        public var residuals: [Double]
        /// vᵀPv
        public var weightedSquares: Double
        /// n − u
        public var redundancy: Int
        /// σ₀; nil without redundancy.
        public var sigma: Double?
        /// Q_x = (AᵀPA)⁻¹
        public var cofactors: [[Double]]

        /// σ₀·√qᵢᵢ for each unknown.
        public var standardDeviations: [Double]? {
            sigma.map { s in cofactors.indices.map { s * Swift.max(0, cofactors[$0][$0]).squareRoot() } }
        }
    }

    /// Rows of A, the observations l and their weights (all 1 when nil).
    public static func adjust(design a: [[Double]], observations l: [Double], weights p: [Double]? = nil) throws(MathError) -> Adjustment {
        let n = l.count
        guard n > 0, a.count == n, let u = a.first?.count, u > 0, a.allSatisfy({ $0.count == u }) else {
            throw .domain("vsaka meritev potrebuje vrstico matrike A z enakim številom koeficientov")
        }
        let w = p ?? [Double](repeating: 1, count: n)
        guard w.count == n, w.allSatisfy({ $0 > 0 && $0.isFinite }) else { throw .domain("uteži morajo biti pozitivne") }
        guard n >= u else { throw .domain("meritev je manj kot neznank") }
        guard a.allSatisfy({ $0.allSatisfy(\.isFinite) }), l.allSatisfy(\.isFinite) else {
            throw .domain("koeficienti in meritve morajo biti končna števila")
        }
        // √P·A x = √P·l by Householder QR: forming AᵀPA would square the condition number, which
        // large coordinates (a line at x ≈ 10⁷) do not survive. Columns are scaled to unit length first.
        var m = (0..<n).map { k in a[k].map { $0 * w[k].squareRoot() } }
        var y = (0..<n).map { k in l[k] * w[k].squareRoot() }
        var scales = [Double](repeating: 1, count: u)
        for j in 0..<u {
            let norm = (0..<n).reduce(0.0) { $0 + m[$1][j] * m[$1][j] }.squareRoot()
            guard norm > 0 else { throw .domain("stolpec matrike A je ničeln: neznanka ni določena") }
            scales[j] = norm
            for i in 0..<n { m[i][j] /= norm }
        }
        for j in 0..<u {
            let norm = (j..<n).reduce(0.0) { $0 + m[$1][j] * m[$1][j] }.squareRoot()
            let alpha = m[j][j] > 0 ? -norm : norm
            var v = [Double](repeating: 0, count: n)
            for i in j..<n { v[i] = m[i][j] }
            v[j] -= alpha
            let vv = (j..<n).reduce(0.0) { $0 + v[$1] * v[$1] }
            guard vv > 0 else { continue }
            for c in j..<u {
                let f = 2 * (j..<n).reduce(0.0) { $0 + v[$1] * m[$1][c] } / vv
                for i in j..<n { m[i][c] -= f * v[i] }
            }
            let f = 2 * (j..<n).reduce(0.0) { $0 + v[$1] * y[$1] } / vv
            for i in j..<n { y[i] -= f * v[i] }
        }
        guard (0..<u).allSatisfy({ Swift.abs(m[$0][$0]) > 1e-12 }) else {
            throw .domain("stolpci matrike A so linearno odvisni: neznanke niso določene")
        }
        var scaled = [Double](repeating: 0, count: u)
        for r in stride(from: u - 1, through: 0, by: -1) {
            var s = y[r]
            for c in (r + 1)..<u { s -= m[r][c] * scaled[c] }
            scaled[r] = s / m[r][r]
        }
        let x = (0..<u).map { scaled[$0] / scales[$0] }
        // Q_x = (AᵀPA)⁻¹ = R⁻¹R⁻ᵀ, undoing the column scaling.
        var inverse = [[Double]](repeating: [Double](repeating: 0, count: u), count: u)
        for j in 0..<u {
            inverse[j][j] = 1 / m[j][j]
            for r in stride(from: j - 1, through: 0, by: -1) {
                var s = 0.0
                for c in (r + 1)...j { s += m[r][c] * inverse[c][j] }
                inverse[r][j] = -s / m[r][r]
            }
        }
        var cofactors = [[Double]](repeating: [Double](repeating: 0, count: u), count: u)
        for i in 0..<u {
            for k in 0..<u {
                cofactors[i][k] = (0..<u).reduce(0.0) { $0 + inverse[i][$1] * inverse[k][$1] } / (scales[i] * scales[k])
            }
        }
        let residuals = (0..<n).map { k in zip(a[k], x).reduce(0) { $0 + $1.0 * $1.1 } - l[k] }
        let squares = (0..<n).reduce(0.0) { $0 + w[$1] * residuals[$1] * residuals[$1] }
        let redundancy = n - u
        let clean = NumericCalculus.clean
        return Adjustment(parameters: x.map(clean), residuals: residuals.map(clean), weightedSquares: squares, redundancy: redundancy,
                          sigma: redundancy > 0 ? (squares / Double(redundancy)).squareRoot() : nil,
                          cofactors: cofactors.map { $0.map(clean) })
    }
}
