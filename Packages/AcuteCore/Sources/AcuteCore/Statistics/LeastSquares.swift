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
        var normal = [[Double]](repeating: [Double](repeating: 0, count: u), count: u)
        var rhs = [Double](repeating: 0, count: u)
        for k in 0..<n {
            for i in 0..<u {
                rhs[i] += a[k][i] * w[k] * l[k]
                for j in 0..<u { normal[i][j] += a[k][i] * w[k] * a[k][j] }
            }
        }
        guard let x = Multivariable.solveLinear(normal, rhs) else {
            throw .domain("normalne enačbe so singularne: neznanke niso določene")
        }
        var cofactors = [[Double]](repeating: [Double](repeating: 0, count: u), count: u)
        for j in 0..<u {
            var unit = [Double](repeating: 0, count: u)
            unit[j] = 1
            guard let column = Multivariable.solveLinear(normal, unit) else { throw .domain("normalne enačbe so singularne") }
            for i in 0..<u { cofactors[i][j] = column[i] }
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
