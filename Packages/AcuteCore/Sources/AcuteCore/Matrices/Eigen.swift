import Foundation

/// Eigenvalues and eigenvectors of a square matrix (lastne vrednosti in lastni vektorji):
/// the characteristic polynomial det(A − λI) (exact for rational matrices), its roots (exact
/// when rational or from a quadratic factor, otherwise numeric; complex pairs included) and a
/// basis of every eigenspace.
public struct EigenDecomposition: Sendable, Hashable {
    public struct Eigenvalue: Sendable, Hashable {
        public var value: Complex
        /// The exact value (5, 1 − √3, 2 + 3i …) when it is known.
        public var exact: Expr?
        /// Algebraic multiplicity (as a root of the characteristic polynomial).
        public var multiplicity: Int
        /// Basis of the eigenspace; its size is the geometric multiplicity.
        public var vectors: [[Complex]]
        /// The same basis with exact integer or rational entries (rational eigenvalues).
        public var exactVectors: [[Rational]]?
    }

    public var size: Int
    /// det(A − λI) as an expression in λ.
    public var characteristicPolynomial: Expr
    public var eigenvalues: [Eigenvalue]

    /// Diagonalisable when every eigenspace is as large as the multiplicity of its eigenvalue.
    public var isDiagonalizable: Bool { eigenvalues.allSatisfy { $0.vectors.count == $0.multiplicity } }

    public init(_ m: Matrix) throws(MathError) {
        guard m.isSquare else { throw .domain("lastne vrednosti ima le kvadratna matrika") }
        let n = m.rows
        guard n <= 8 else { throw .domain("matrika je prevelika (največ 8 × 8)") }
        size = n
        let sign = n % 2 == 0 ? Rational.one : Rational.minusOne
        if let exact = m.exact, let monic = EigenDecomposition.characteristic(exact, n: n) {
            // det(A − λI) = (−1)ⁿ det(λI − A)
            characteristicPolynomial = Simplifier.simplify(Poly.expr(Poly.scaled(monic, by: sign) ?? monic, "λ"))
            eigenvalues = EigenDecomposition.exactEigenvalues(of: m, exact: exact, monic: monic)
        } else {
            let monic = EigenDecomposition.characteristic(m.values, n: n)
            characteristicPolynomial = Simplifier.simplify(EigenDecomposition.polynomialExpr(monic.map { $0 * sign.doubleValue }))
            let roots = EigenDecomposition.isSymmetric(m) ? EigenDecomposition.jacobi(m.values, n: n).map { Complex($0) }
                                                          : Polynomial(coefficients: monic).complexRoots()
            eigenvalues = EigenDecomposition.cluster(roots).map { value, multiplicity in
                Eigenvalue(value: value, exact: EigenDecomposition.recognized(value), multiplicity: multiplicity,
                           vectors: EigenDecomposition.nullSpace(m, value), exactVectors: nil)
            }
        }
    }

    // MARK: Characteristic polynomial (Faddeev–LeVerrier)

    /// Coefficients of det(λI − A), lowest power first, exactly; nil on overflow.
    static func characteristic(_ a: [Rational], n: Int) -> [Rational]? {
        var c = [Rational](repeating: .zero, count: n + 1)
        c[n] = .one
        var previous = [Rational](repeating: .zero, count: n * n)   // M₀ = 0
        for k in 1...n {
            // Mₖ = A·Mₖ₋₁ + cₙ₋ₖ₊₁·I, cₙ₋ₖ = −tr(A·Mₖ)/k
            guard var mk = multiply(a, previous, n) else { return nil }
            for i in 0..<n {
                guard let d = mk[i * n + i].adding(c[n - k + 1]) else { return nil }
                mk[i * n + i] = d
            }
            guard let amk = multiply(a, mk, n) else { return nil }
            var trace = Rational.zero
            for i in 0..<n {
                guard let t = trace.adding(amk[i * n + i]) else { return nil }
                trace = t
            }
            guard let ck = trace.divided(by: Rational(-k)) else { return nil }
            c[n - k] = ck
            previous = mk
        }
        return c
    }

    static func characteristic(_ a: [Double], n: Int) -> [Double] {
        var c = [Double](repeating: 0, count: n + 1)
        c[n] = 1
        var previous = [Double](repeating: 0, count: n * n)
        for k in 1...n {
            var mk = multiply(a, previous, n)
            for i in 0..<n { mk[i * n + i] += c[n - k + 1] }
            let amk = multiply(a, mk, n)
            c[n - k] = -(0..<n).reduce(0) { $0 + amk[$1 * n + $1] } / Double(k)
            previous = mk
        }
        return c.map { NumericCalculus.clean($0) }
    }

    static func multiply(_ a: [Rational], _ b: [Rational], _ n: Int) -> [Rational]? {
        var out = [Rational](repeating: .zero, count: n * n)
        for i in 0..<n {
            for k in 0..<n where !a[i * n + k].isZero {
                for j in 0..<n where !b[k * n + j].isZero {
                    guard let p = a[i * n + k].multiplied(by: b[k * n + j]), let s = out[i * n + j].adding(p) else { return nil }
                    out[i * n + j] = s
                }
            }
        }
        return out
    }

    static func multiply(_ a: [Double], _ b: [Double], _ n: Int) -> [Double] {
        var out = [Double](repeating: 0, count: n * n)
        for i in 0..<n { for k in 0..<n { for j in 0..<n { out[i * n + j] += a[i * n + k] * b[k * n + j] } } }
        return out
    }

    static func polynomialExpr(_ c: [Double]) -> Expr {
        var terms: [Expr] = []
        for (power, coefficient) in c.enumerated().reversed() where coefficient != 0 {
            let number: Expr = Rational.approximating(coefficient, maxDenominator: 1000, tolerance: 1e-12).map(Expr.number) ?? .decimal(coefficient)
            let monomial: Expr = power == 0 ? .one : power == 1 ? .variable("λ") : .power(.variable("λ"), .int(power))
            terms.append(power == 0 ? number : .product([number, monomial]))
        }
        return terms.isEmpty ? .zero : .sum(terms)
    }

    // MARK: Eigenvalues

    /// Rational roots exactly, a remaining quadratic factor with surds or i, the rest numerically.
    static func exactEigenvalues(of m: Matrix, exact a: [Rational], monic: [Rational]) -> [Eigenvalue] {
        let n = m.rows
        guard let split = Poly.rationalRoots(monic) else {
            return cluster(Polynomial(coefficients: monic.map(\.doubleValue)).complexRoots()).map { value, multiplicity in
                Eigenvalue(value: value, exact: recognized(value), multiplicity: multiplicity, vectors: nullSpace(m, value), exactVectors: nil)
            }
        }
        var result: [Eigenvalue] = []
        for root in split.roots.sorted(by: { $0.value < $1.value }) {
            var shifted = a
            for i in 0..<n {
                guard let d = shifted[i * n + i].subtracting(root.value) else { continue }
                shifted[i * n + i] = d
            }
            let basis = exactNullSpace(shifted, n: n)
            result.append(Eigenvalue(value: Complex(root.value.doubleValue), exact: .number(root.value), multiplicity: root.multiplicity,
                                     vectors: basis.map { $0.map { Complex($0.doubleValue) } }, exactVectors: basis))
        }
        let rest = split.rest
        if Poly.degree(rest) == 2 {
            // λ² + pλ + q: λ = −p/2 ± √(p²/4 − q)
            let p = rest[1], q = rest[0]
            if let halfP = p.multiplied(by: .half), let center = halfP.negated(), let p2 = halfP.multiplied(by: halfP), let d = p2.subtracting(q) {
                let root = Swift.abs(d.doubleValue).squareRoot()
                let radical = Expr.power(.number(d.isNegative ? (d.negated() ?? d) : d), .number(.half))
                for sign in [-1.0, 1.0] {
                    let value = d.isNegative ? Complex(center.doubleValue, sign * root) : Complex(center.doubleValue + sign * root)
                    var offset = Expr.product([.number(Rational(Int(sign))), radical])
                    if d.isNegative { offset = .product([offset, .constant(.i)]) }
                    let exact = Simplifier.simplify(.sum([.number(center), offset]))
                    result.append(Eigenvalue(value: value, exact: exact, multiplicity: 1, vectors: nullSpace(m, value), exactVectors: nil))
                }
            }
        } else if Poly.degree(rest) > 2 {
            for (value, multiplicity) in cluster(Polynomial(coefficients: rest.map(\.doubleValue)).complexRoots()) {
                result.append(Eigenvalue(value: value, exact: recognized(value), multiplicity: multiplicity, vectors: nullSpace(m, value), exactVectors: nil))
            }
        }
        return result
    }

    /// Equal roots (within numerical noise) merged, with their count; real ones first, ascending.
    static func cluster(_ roots: [Complex]) -> [(Complex, Int)] {
        var groups: [(sum: Complex, count: Int)] = []
        for r in roots {
            let snapped = Swift.abs(r.im) < 1e-9 * Swift.max(1, r.magnitude) ? Complex(r.re) : r
            if let i = groups.firstIndex(where: { (($0.sum / Double($0.count)) - snapped).magnitude < 1e-6 * Swift.max(1, snapped.magnitude) }) {
                groups[i].sum += snapped
                groups[i].count += 1
            } else {
                groups.append((snapped, 1))
            }
        }
        return groups.map { group in
            let mean = group.sum / Double(group.count)
            return (Complex(NumericCalculus.clean(mean.re), NumericCalculus.clean(mean.im)), group.count)
        }.sorted { a, b in
            if (a.0.im == 0) != (b.0.im == 0) { return a.0.im == 0 }
            return a.0.re != b.0.re ? a.0.re < b.0.re : a.0.im < b.0.im
        }
    }

    /// Nice closed forms of numeric eigenvalues (√2, 1 + i …).
    static func recognized(_ z: Complex) -> Expr? {
        guard let re = z.re == 0 ? .zero : ExactRecognizer.recognize(z.re) else { return nil }
        if z.im == 0 { return re.expr }
        guard let im = ExactRecognizer.recognize(z.im) else { return nil }
        return Simplifier.simplify(.sum([re.expr, .product([im.expr, .constant(.i)])]))
    }

    static func isSymmetric(_ m: Matrix) -> Bool {
        let n = m.rows
        let scale = Swift.max(1, m.values.map(Swift.abs).max() ?? 1)
        for i in 0..<n { for j in (i + 1)..<Swift.max(i + 1, n) where Swift.abs(m[i, j] - m[j, i]) > 1e-12 * scale { return false } }
        return true
    }

    /// Eigenvalues of a symmetric matrix by cyclic Jacobi rotations.
    static func jacobi(_ values: [Double], n: Int) -> [Double] {
        var a = values
        let scale = values.reduce(0) { $0 + $1 * $1 }
        for _ in 0..<100 {
            var off = 0.0
            for p in 0..<n { for q in 0..<n where p != q { off += a[p * n + q] * a[p * n + q] } }
            if off <= 1e-26 * Swift.max(scale, 1e-300) { break }
            for p in 0..<(n - 1) {
                for q in (p + 1)..<n where a[p * n + q] != 0 {
                    let theta = (a[q * n + q] - a[p * n + p]) / (2 * a[p * n + q])
                    let t = (theta >= 0 ? 1.0 : -1.0) / (Swift.abs(theta) + (theta * theta + 1).squareRoot())
                    let c = 1 / (t * t + 1).squareRoot(), s = t * c
                    for k in 0..<n {
                        let akp = a[k * n + p], akq = a[k * n + q]
                        a[k * n + p] = c * akp - s * akq
                        a[k * n + q] = s * akp + c * akq
                    }
                    for k in 0..<n {
                        let apk = a[p * n + k], aqk = a[q * n + k]
                        a[p * n + k] = c * apk - s * aqk
                        a[q * n + k] = s * apk + c * aqk
                    }
                }
            }
        }
        return (0..<n).map { a[$0 * n + $0] }
    }

    // MARK: Eigenvectors

    /// Basis of ker(A − λI) with exact entries: one vector per free variable, scaled to integers.
    static func exactNullSpace(_ b: [Rational], n: Int) -> [[Rational]] {
        guard let reduced = Matrix.exactRREF(b, rows: n, columns: n) else { return [] }
        let free = (0..<n).filter { !reduced.pivots.contains($0) }
        return free.compactMap { f -> [Rational]? in
            var v = [Rational](repeating: .zero, count: n)
            v[f] = .one
            for (row, pivot) in reduced.pivots.enumerated() {
                guard let x = reduced.entries[row * n + f].negated() else { return nil }
                v[pivot] = x
            }
            return integerScaled(v)
        }
    }

    /// (1/2, 1) → (1, 2): the smallest integer multiple, first non-zero entry positive.
    static func integerScaled(_ v: [Rational]) -> [Rational] {
        var lcm = 1
        for x in v {
            guard let l = Rational.lcm(lcm, x.denominator) else { return v }
            lcm = l
        }
        var integers: [Int] = []
        for x in v {
            let (product, overflow) = x.numerator.multipliedReportingOverflow(by: lcm / x.denominator)
            guard !overflow else { return v }
            integers.append(product)
        }
        // Int.min (−2⁶²·2 for ker [[1, 0, 2⁶²], [0, 1, ½]]) passes the overflow check, but flipping
        // its sign traps: keep v unscaled, as on overflow.
        guard !integers.contains(.min) else { return v }
        let divisor = integers.reduce(0) { Rational.gcd($0, $1) }
        let sign = (integers.first { $0 != 0 } ?? 1) < 0 ? -1 : 1
        guard divisor > 0 else { return v }
        return integers.map { Rational($0 / divisor * sign) }
    }

    /// Basis of ker(A − λI) numerically (complex λ allowed), free variables set to 1.
    static func nullSpace(_ m: Matrix, _ lambda: Complex) -> [[Complex]] {
        let n = m.rows
        var b = m.values.map { Complex($0) }
        for i in 0..<n { b[i * n + i] -= lambda }
        let norm = Swift.max(1, m.values.map(Swift.abs).max() ?? 1)
        var tolerance = 1e-7 * norm
        for _ in 0..<3 {
            let (basis, smallestPivot) = complexNullSpace(b, n: n, tolerance: tolerance)
            if !basis.isEmpty { return basis.map { $0.map(clean) } }
            // λ is only approximate: treat the smallest pivot as zero.
            tolerance = smallestPivot * 1.0001
        }
        return []
    }

    static func complexNullSpace(_ b: [Complex], n: Int, tolerance: Double) -> ([[Complex]], Double) {
        var a = b
        var pivots: [Int] = []
        var smallest = Double.infinity
        var row = 0
        for col in 0..<n where row < n {
            var best = row
            for r in row..<n where a[r * n + col].magnitude > a[best * n + col].magnitude { best = r }
            let size = a[best * n + col].magnitude
            if size <= tolerance { continue }
            smallest = Swift.min(smallest, size)
            if best != row { for c in 0..<n { a.swapAt(best * n + c, row * n + c) } }
            let p = a[row * n + col]
            for c in 0..<n { a[row * n + c] = a[row * n + c] / p }
            for r in 0..<n where r != row {
                let factor = a[r * n + col]
                if factor == .zero { continue }
                for c in 0..<n { a[r * n + c] -= factor * a[row * n + c] }
            }
            pivots.append(col)
            row += 1
        }
        let free = (0..<n).filter { !pivots.contains($0) }
        let basis = free.map { f -> [Complex] in
            var v = [Complex](repeating: .zero, count: n)
            v[f] = .one
            for (i, p) in pivots.enumerated() { v[p] = -a[i * n + f] }
            return v
        }
        return (basis, smallest)
    }

    static func clean(_ z: Complex) -> Complex {
        let scale = Swift.max(1, z.magnitude)
        let re = Swift.abs(z.re) < 1e-10 * scale ? 0 : NumericCalculus.clean(z.re)
        let im = Swift.abs(z.im) < 1e-10 * scale ? 0 : NumericCalculus.clean(z.im)
        return Complex(re, im)
    }
}

extension Matrix {
    /// Basis of the null space ker A as the columns of a matrix (exact when possible); the zero
    /// vector when A is invertible.
    public func kernel() -> Matrix {
        let (reduced, pivots) = reducedRowEchelonForm()
        let free = (0..<columns).filter { !pivots.contains($0) }
        guard !free.isEmpty else { return Matrix(rows: columns, columns: 1, exact: [Rational](repeating: .zero, count: columns)) }
        if let exact = reduced.exact {
            var entries = [Rational](repeating: .zero, count: columns * free.count)
            for (k, f) in free.enumerated() {
                var v = [Rational](repeating: .zero, count: columns)
                v[f] = .one
                for (row, pivot) in pivots.enumerated() { v[pivot] = exact[row * columns + f].negated() ?? .zero }
                for (i, x) in EigenDecomposition.integerScaled(v).enumerated() { entries[i * free.count + k] = x }
            }
            return Matrix(rows: columns, columns: free.count, exact: entries)
        }
        var values = [Double](repeating: 0, count: columns * free.count)
        for (k, f) in free.enumerated() {
            values[f * free.count + k] = 1
            for (row, pivot) in pivots.enumerated() { values[pivot * free.count + k] = -reduced[row, f] }
        }
        return Matrix(rows: columns, columns: free.count, values: values)
    }
}
