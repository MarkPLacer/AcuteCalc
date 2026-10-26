import Foundation

/// A value that is either a number or a matrix (vectors are n×1 matrices).
public enum MathValue: Hashable, Sendable {
    case scalar(Double, exact: ExactReal?)
    case matrix(Matrix)
}

/// Evaluates expressions that involve matrices and vectors: A·B, A⁻¹, Aᵀ, det A,
/// a⃗·b⃗, a⃗×b⃗, |a⃗|, angles between vectors and linear systems A⁻¹·b.
public struct MatrixEvaluator {
    public var context: EvaluationContext

    public init(context: EvaluationContext) {
        self.context = context
    }

    public static func involvesMatrices(_ expr: Expr, matrixVariables: Set<String>) -> Bool {
        expr.containsMatrix || !expr.freeVariables.isDisjoint(with: matrixVariables)
    }

    private func involvesMatrices(_ e: Expr) -> Bool {
        MatrixEvaluator.involvesMatrices(e, matrixVariables: Set(context.matrixVariables.keys))
    }

    public func evaluate(_ e: Expr) throws(MathError) -> MathValue {
        guard involvesMatrices(e) else { return try scalarValue(e) }
        switch e {
        case .matrix(let rows, let columns, let entries):
            guard rows > 0, columns > 0, entries.count == rows * columns else { throw .syntax("neveljavna matrika") }
            var values: [Double] = []
            var exact: [Rational] = []
            var allExact = true
            for entry in entries {
                guard case .scalar(let v, let ex) = try evaluate(entry) else { throw .domain("matrika ne sme vsebovati matrik") }
                values.append(v)
                if allExact, let q = ex?.rational { exact.append(q) } else { allExact = false }
            }
            return .matrix(Matrix(rows: rows, columns: columns, values: values, exact: allExact ? exact : nil))
        case .variable(let name):
            if let m = context.matrixVariables[name] { return .matrix(m) }
            return try scalarValue(e)
        case .sum(let terms):
            guard let first = terms.first else { return .scalar(0, exact: .zero) }
            var acc = try evaluate(first)
            for t in terms.dropFirst() { acc = try add(acc, try evaluate(t)) }
            return acc
        case .product(let factors):
            guard let first = factors.first else { return .scalar(1, exact: .one) }
            var acc = try evaluate(first)
            for f in factors.dropFirst() { acc = try multiply(acc, try evaluate(f)) }
            return acc
        case .negation(let inner):
            return try multiply(.scalar(-1, exact: ExactReal(Rational.minusOne)), try evaluate(inner))
        case .quotient(let a, let b):
            let numerator = try evaluate(a)
            let denominator = try evaluate(b)
            switch denominator {
            case .scalar(let d, let exact):
                guard d != 0 else { throw .divisionByZero }
                let reciprocal = exact.flatMap { ExactReal.one.divided(by: $0) }
                return try multiply(numerator, .scalar(1 / d, exact: reciprocal))
            case .matrix(let m):
                // A/B = A·B⁻¹
                return try multiply(numerator, .matrix(try m.inverse()))
            }
        case .power(let base, let exponent):
            let b = try evaluate(base)
            guard case .matrix(let m) = b else { return try scalarValue(e) }
            if case .variable("T") = exponent { return .matrix(m.transposed) }
            guard case .scalar(let x, _) = try evaluate(exponent), let n = RealEvaluator.exactInt(x) else {
                throw .domain("matriko lahko potenciramo le s celim številom")
            }
            if m.isVector && !m.isSquare {
                // |v|² written as v²
                guard n == 2 else { throw .domain("vektorja ne moremo potencirati") }
                let d = try m.dot(m)
                return .scalar(d.value, exact: d.exact.map { ExactReal($0) })
            }
            return .matrix(try m.power(n))
        case .function(let f, let args):
            return try function(f, args)
        case .relation:
            throw .unsupported("enačbe z matrikami – uporabi A⁻¹·b")
        default:
            throw .unsupported("ta zapis z matrikami")
        }
    }

    // MARK: Functions

    private func function(_ f: MathFunction, _ args: [Expr]) throws(MathError) -> MathValue {
        var values: [MathValue] = []
        for a in args { values.append(try evaluate(a)) }
        func matrixArg(_ i: Int) throws(MathError) -> Matrix {
            guard i < values.count, case .matrix(let m) = values[i] else { throw .domain("\(f.internationalName) potrebuje matriko ali vektor") }
            return m
        }
        switch f {
        case .det:
            let d = try matrixArg(0).determinant()
            return .scalar(d.value, exact: d.exact.map { ExactReal($0) })
        case .transpose:
            return .matrix(try matrixArg(0).transposed)
        case .inv:
            return .matrix(try matrixArg(0).inverse())
        case .trace:
            let t = try matrixArg(0).trace()
            return .scalar(t.value, exact: t.exact.map { ExactReal($0) })
        case .rank:
            let r = try matrixArg(0).rank()
            return .scalar(Double(r), exact: ExactReal(r))
        case .dot:
            let d = try matrixArg(0).dot(try matrixArg(1))
            return .scalar(d.value, exact: d.exact.map { ExactReal($0) })
        case .cross:
            return .matrix(try matrixArg(0).cross(try matrixArg(1)))
        case .norm, .abs:
            let m = try matrixArg(0)
            if f == .abs && m.isSquare && !m.isVector {
                // |A| = det A for square matrices
                let d = try m.determinant()
                return .scalar(d.value, exact: d.exact.map { ExactReal($0) })
            }
            return .scalar(m.norm, exact: m.exactSquaredNorm.flatMap { ExactReal.squareRoot(of: $0) })
        case .rref:
            return .matrix(try matrixArg(0).reducedRowEchelonForm().matrix)
        case .kernel:
            return .matrix(try matrixArg(0).kernel())
        case .eig, .charpoly:
            throw .unsupported("\(f.internationalName) izračunaj samostojno, ne kot del izraza")
        case .unit:
            let m = try matrixArg(0)
            let length = m.norm
            guard length > 0 else { throw .domain("ničelni vektor nima smeri") }
            return .matrix(m.scaled(by: 1 / length))
        case .angle:
            let a = try matrixArg(0), b = try matrixArg(1)
            let d = try a.dot(b)
            let lengths = a.norm * b.norm
            guard lengths > 0 else { throw .domain("kot z ničelnim vektorjem ni definiran") }
            let cosine = Swift.max(-1, Swift.min(1, d.value / lengths))
            let angle = acos(cosine) / context.angleUnit.radiansPerUnit
            return .scalar(NumericCalculus.clean(angle), exact: ExactRecognizer.recognize(angle, tolerance: 1e-10))
        default:
            // Scalar function applied to a matrix: elementwise is rarely meant, so refuse clearly.
            throw .domain("\(f.internationalName) ni definirana za matrike")
        }
    }

    // MARK: Arithmetic

    private func add(_ a: MathValue, _ b: MathValue) throws(MathError) -> MathValue {
        switch (a, b) {
        case (.matrix(let x), .matrix(let y)):
            return .matrix(try x.adding(y))
        case (.scalar(let x, let ex), .scalar(let y, let ey)):
            return .scalar(x + y, exact: ex.flatMap { e in ey.flatMap { e.adding($0) } })
        default:
            throw .domain("števila in matrike ne moremo seštevati")
        }
    }

    private func multiply(_ a: MathValue, _ b: MathValue) throws(MathError) -> MathValue {
        switch (a, b) {
        case (.scalar(let x, let ex), .scalar(let y, let ey)):
            return .scalar(x * y, exact: ex.flatMap { e in ey.flatMap { e.multiplied(by: $0) } })
        case (.scalar(let k, let ek), .matrix(let m)), (.matrix(let m), .scalar(let k, let ek)):
            return .matrix(m.scaled(by: k, exact: ek?.rational))
        case (.matrix(let x), .matrix(let y)):
            // Two vectors of the same length: the dot product (a⃗·b⃗).
            if x.isVector, y.isVector, x.count == y.count, x.columns == 1, y.columns == 1 {
                let d = try x.dot(y)
                return .scalar(d.value, exact: d.exact.map { ExactReal($0) })
            }
            return .matrix(try x.multiplied(by: y))
        }
    }

    private func scalarValue(_ e: Expr) throws(MathError) -> MathValue {
        let value = try RealEvaluator.evaluate(e, context: context)
        let exact = ExactEvaluator.value(e, angleUnit: context.angleUnit, variables: context.exactVariables)
        return .scalar(value, exact: exact)
    }
}
