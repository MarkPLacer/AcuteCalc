import Foundation

/// A dense matrix (row-major). Entries are kept exactly as fractions whenever every
/// entry is rational, so det, inverse and solutions of linear systems stay exact.
public struct Matrix: Hashable, Sendable, Codable {
    public let rows: Int
    public let columns: Int
    public private(set) var values: [Double]
    /// Exact entries, when all of them are known rationals.
    public private(set) var exact: [Rational]?

    public init(rows: Int, columns: Int, values: [Double], exact: [Rational]? = nil) {
        precondition(rows > 0 && columns > 0 && values.count == rows * columns, "matrix shape")
        self.rows = rows
        self.columns = columns
        self.values = values
        self.exact = exact?.count == values.count ? exact : nil
    }

    public init(rows: Int, columns: Int, exact: [Rational]) {
        self.init(rows: rows, columns: columns, values: exact.map(\.doubleValue), exact: exact)
    }

    public static func identity(_ n: Int) -> Matrix {
        var e = [Rational](repeating: .zero, count: n * n)
        for i in 0..<n { e[i * n + i] = .one }
        return Matrix(rows: n, columns: n, exact: e)
    }

    public subscript(row: Int, column: Int) -> Double { values[row * columns + column] }

    public func exactEntry(_ row: Int, _ column: Int) -> Rational? { exact?[row * columns + column] }

    public var isSquare: Bool { rows == columns }
    public var isVector: Bool { columns == 1 || rows == 1 }
    public var count: Int { values.count }

    // MARK: Elementwise operations

    public var transposed: Matrix {
        var v = [Double](repeating: 0, count: count)
        var e: [Rational]? = exact.map { _ in [Rational](repeating: .zero, count: count) }
        for r in 0..<rows {
            for c in 0..<columns {
                v[c * rows + r] = values[r * columns + c]
                if let ex = exact { e?[c * rows + r] = ex[r * columns + c] }
            }
        }
        return Matrix(rows: columns, columns: rows, values: v, exact: e)
    }

    public func adding(_ other: Matrix) throws(MathError) -> Matrix {
        guard rows == other.rows, columns == other.columns else { throw .domain("matriki morata biti enakih dimenzij") }
        let v = zip(values, other.values).map { $0 + $1 }
        return Matrix(rows: rows, columns: columns, values: v, exact: Matrix.combine(exact, other.exact) { $0.adding($1) })
    }

    public func subtracting(_ other: Matrix) throws(MathError) -> Matrix {
        try adding(other.negated())
    }

    public func negated() -> Matrix {
        Matrix(rows: rows, columns: columns, values: values.map { -$0 }, exact: exact.flatMap { e in Matrix.mapAll(e) { $0.negated() } })
    }

    public func scaled(by k: Double, exact q: Rational? = nil) -> Matrix {
        let e: [Rational]? = (q != nil && exact != nil) ? Matrix.mapAll(exact!) { $0.multiplied(by: q!) } : nil
        return Matrix(rows: rows, columns: columns, values: values.map { $0 * k }, exact: e)
    }

    public func multiplied(by other: Matrix) throws(MathError) -> Matrix {
        guard columns == other.rows else {
            throw .domain("množenje matrik \(rows)×\(columns) in \(other.rows)×\(other.columns) ni definirano")
        }
        var v = [Double](repeating: 0, count: rows * other.columns)
        for i in 0..<rows {
            for j in 0..<other.columns {
                var s = 0.0
                for k in 0..<columns { s += self[i, k] * other[k, j] }
                v[i * other.columns + j] = s
            }
        }
        var e: [Rational]?
        if let a = exact, let b = other.exact {
            e = []
            outer: for i in 0..<rows {
                for j in 0..<other.columns {
                    var s = Rational.zero
                    for k in 0..<columns {
                        guard let p = a[i * columns + k].multiplied(by: b[k * other.columns + j]), let t = s.adding(p) else {
                            e = nil
                            break outer
                        }
                        s = t
                    }
                    e?.append(s)
                }
            }
        }
        return Matrix(rows: rows, columns: other.columns, values: v, exact: e)
    }

    /// Aⁿ for integer n (A⁻ⁿ = (A⁻¹)ⁿ, A⁰ = I).
    public func power(_ n: Int) throws(MathError) -> Matrix {
        guard isSquare else { throw .domain("potenca je definirana le za kvadratne matrike") }
        guard Swift.abs(n) <= 1000 else { throw .tooComplex }
        if n < 0 { return try inverse().power(-n) }
        var result = Matrix.identity(rows)
        var base = self
        var e = n
        while e > 0 {
            if e & 1 == 1 { result = try result.multiplied(by: base) }
            e >>= 1
            if e > 0 { base = try base.multiplied(by: base) }
        }
        return result
    }

    // MARK: Determinant, inverse, rank, solving

    public func determinant() throws(MathError) -> (value: Double, exact: Rational?) {
        guard isSquare else { throw .domain("determinanta je definirana le za kvadratne matrike") }
        if let e = exact, let d = Matrix.exactDeterminant(e, n: rows) {
            return (d.doubleValue, d)
        }
        var a = values
        let n = rows
        var det = 1.0
        for col in 0..<n {
            var pivot = col
            for r in (col + 1)..<max(col + 1, n) where Swift.abs(a[r * n + col]) > Swift.abs(a[pivot * n + col]) { pivot = r }
            if a[pivot * n + col] == 0 { return (0, nil) }
            if pivot != col {
                for c in 0..<n { a.swapAt(pivot * n + c, col * n + c) }
                det = -det
            }
            let p = a[col * n + col]
            det *= p
            for r in (col + 1)..<max(col + 1, n) {
                let factor = a[r * n + col] / p
                if factor == 0 { continue }
                for c in col..<n { a[r * n + c] -= factor * a[col * n + c] }
            }
        }
        return (det, nil)
    }

    public func trace() throws(MathError) -> (value: Double, exact: Rational?) {
        guard isSquare else { throw .domain("sled je definiran le za kvadratne matrike") }
        var sum = 0.0
        var exactSum: Rational? = .zero
        for i in 0..<rows {
            sum += self[i, i]
            if let s = exactSum, let entry = exactEntry(i, i) { exactSum = s.adding(entry) } else { exactSum = nil }
        }
        return (sum, exactSum)
    }

    public func inverse() throws(MathError) -> Matrix {
        guard isSquare else { throw .domain("inverz obstaja le za kvadratne matrike") }
        let n = rows
        let augmented = Matrix.augment(self, Matrix.identity(n))
        let reduced = augmented.reducedRowEchelonForm()
        for i in 0..<n where Swift.abs(reduced.matrix[i, i] - 1) > 1e-9 {
            throw .domain("matrika je singularna (det = 0), inverz ne obstaja")
        }
        return reduced.matrix.columnSlice(n..<(2 * n))
    }

    public func rank() -> Int { reducedRowEchelonForm().pivots.count }

    /// Unique solution of A·x = b.
    public func solve(_ b: Matrix) throws(MathError) -> Matrix {
        guard isSquare, b.rows == rows else { throw .domain("dimenzije sistema se ne ujemajo") }
        let reduced = Matrix.augment(self, b).reducedRowEchelonForm()
        guard reduced.pivots.count == rows, reduced.pivots.allSatisfy({ $0 < columns }) else {
            throw .domain("sistem nima enolične rešitve")
        }
        return reduced.matrix.columnSlice(columns..<(columns + b.columns))
    }

    /// Reduced row echelon form (Gauss–Jordan) with the pivot columns.
    public func reducedRowEchelonForm() -> (matrix: Matrix, pivots: [Int]) {
        if let e = exact, let result = Matrix.exactRREF(e, rows: rows, columns: columns) {
            return (Matrix(rows: rows, columns: columns, exact: result.entries), result.pivots)
        }
        var a = values
        var pivots: [Int] = []
        var row = 0
        let scale = values.map(Swift.abs).max() ?? 1
        let tolerance = 1e-10 * Swift.max(1, scale)
        for col in 0..<columns where row < rows {
            var best = row
            for r in row..<rows where Swift.abs(a[r * columns + col]) > Swift.abs(a[best * columns + col]) { best = r }
            if Swift.abs(a[best * columns + col]) <= tolerance { continue }
            if best != row { for c in 0..<columns { a.swapAt(best * columns + c, row * columns + c) } }
            let p = a[row * columns + col]
            for c in 0..<columns { a[row * columns + c] /= p }
            for r in 0..<rows where r != row {
                let factor = a[r * columns + col]
                if factor == 0 { continue }
                for c in 0..<columns { a[r * columns + c] -= factor * a[row * columns + c] }
            }
            pivots.append(col)
            row += 1
        }
        for i in a.indices where Swift.abs(a[i]) <= tolerance { a[i] = 0 }
        return (Matrix(rows: rows, columns: columns, values: a), pivots)
    }

    // MARK: Vectors

    /// Entries of a row or column vector.
    public var vectorEntries: [Double]? { isVector ? values : nil }

    public func dot(_ other: Matrix) throws(MathError) -> (value: Double, exact: Rational?) {
        guard isVector, other.isVector, count == other.count else { throw .domain("skalarni produkt potrebuje vektorja enakih dimenzij") }
        let value = zip(values, other.values).reduce(0) { $0 + $1.0 * $1.1 }
        var e: Rational? = .zero
        if let a = exact, let b = other.exact {
            for (x, y) in zip(a, b) {
                guard let s = e, let p = x.multiplied(by: y) else { e = nil; break }
                e = s.adding(p)
            }
        } else {
            e = nil
        }
        return (value, e)
    }

    public func cross(_ other: Matrix) throws(MathError) -> Matrix {
        guard isVector, other.isVector, count == 3, other.count == 3 else { throw .domain("vektorski produkt je definiran za 3D vektorja") }
        let a = values, b = other.values
        let v = [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]]
        var e: [Rational]?
        if let x = exact, let y = other.exact {
            func term(_ i: Int, _ j: Int, _ k: Int, _ l: Int) -> Rational? {
                guard let p = x[i].multiplied(by: y[j]), let q = x[k].multiplied(by: y[l]) else { return nil }
                return p.subtracting(q)
            }
            if let c0 = term(1, 2, 2, 1), let c1 = term(2, 0, 0, 2), let c2 = term(0, 1, 1, 0) { e = [c0, c1, c2] }
        }
        return Matrix(rows: rows, columns: columns, values: v, exact: e)
    }

    /// |v| (length of a vector, Frobenius norm of a matrix).
    public var norm: Double { values.reduce(0) { $0 + $1 * $1 }.squareRoot() }

    /// |v|² exactly, when the entries are exact.
    public var exactSquaredNorm: Rational? {
        guard let e = exact else { return nil }
        var s = Rational.zero
        for x in e {
            guard let p = x.multiplied(by: x), let t = s.adding(p) else { return nil }
            s = t
        }
        return s
    }

    // MARK: Helpers

    func columnSlice(_ range: Range<Int>) -> Matrix {
        var v: [Double] = []
        var e: [Rational]? = exact == nil ? nil : []
        for r in 0..<rows {
            for c in range {
                v.append(self[r, c])
                if let x = exactEntry(r, c) { e?.append(x) }
            }
        }
        return Matrix(rows: rows, columns: range.count, values: v, exact: e)
    }

    static func augment(_ a: Matrix, _ b: Matrix) -> Matrix {
        var v: [Double] = []
        var e: [Rational]? = (a.exact != nil && b.exact != nil) ? [] : nil
        for r in 0..<a.rows {
            for c in 0..<a.columns {
                v.append(a[r, c])
                if let x = a.exactEntry(r, c) { e?.append(x) }
            }
            for c in 0..<b.columns {
                v.append(b[r, c])
                if let x = b.exactEntry(r, c) { e?.append(x) }
            }
        }
        return Matrix(rows: a.rows, columns: a.columns + b.columns, values: v, exact: e)
    }

    static func mapAll(_ entries: [Rational], _ transform: (Rational) -> Rational?) -> [Rational]? {
        var out: [Rational] = []
        out.reserveCapacity(entries.count)
        for x in entries {
            guard let y = transform(x) else { return nil }
            out.append(y)
        }
        return out
    }

    static func combine(_ a: [Rational]?, _ b: [Rational]?, _ op: (Rational, Rational) -> Rational?) -> [Rational]? {
        guard let a, let b, a.count == b.count else { return nil }
        var out: [Rational] = []
        for (x, y) in zip(a, b) {
            guard let z = op(x, y) else { return nil }
            out.append(z)
        }
        return out
    }

    static func exactDeterminant(_ entries: [Rational], n: Int) -> Rational? {
        var a = entries
        var det = Rational.one
        for col in 0..<n {
            guard let pivot = (col..<n).first(where: { !a[$0 * n + col].isZero }) else { return .zero }
            if pivot != col {
                for c in 0..<n { a.swapAt(pivot * n + c, col * n + c) }
                guard let d = det.negated() else { return nil }
                det = d
            }
            let p = a[col * n + col]
            guard let d = det.multiplied(by: p) else { return nil }
            det = d
            for r in (col + 1)..<max(col + 1, n) where !a[r * n + col].isZero {
                guard let factor = a[r * n + col].divided(by: p) else { return nil }
                for c in col..<n {
                    guard let product = factor.multiplied(by: a[col * n + c]), let value = a[r * n + c].subtracting(product) else { return nil }
                    a[r * n + c] = value
                }
            }
        }
        return det
    }

    static func exactRREF(_ entries: [Rational], rows: Int, columns: Int) -> (entries: [Rational], pivots: [Int])? {
        var a = entries
        var pivots: [Int] = []
        var row = 0
        for col in 0..<columns where row < rows {
            guard let pivot = (row..<rows).first(where: { !a[$0 * columns + col].isZero }) else { continue }
            if pivot != row { for c in 0..<columns { a.swapAt(pivot * columns + c, row * columns + c) } }
            let p = a[row * columns + col]
            for c in 0..<columns {
                guard let v = a[row * columns + c].divided(by: p) else { return nil }
                a[row * columns + c] = v
            }
            for r in 0..<rows where r != row && !a[r * columns + col].isZero {
                let factor = a[r * columns + col]
                for c in 0..<columns {
                    guard let product = factor.multiplied(by: a[row * columns + c]), let v = a[r * columns + c].subtracting(product) else { return nil }
                    a[r * columns + c] = v
                }
            }
            pivots.append(col)
            row += 1
        }
        return (a, pivots)
    }
}
