import Foundation

/// aₙ = a₁ + (n − 1)d
public struct ArithmeticSequence: Hashable, Sendable {
    public var first: Double
    public var difference: Double

    public init(first: Double, difference: Double) {
        self.first = first
        self.difference = difference
    }

    public func term(_ n: Int) -> Double { first + Double(n - 1) * difference }
    /// sₙ = n/2 · (2a₁ + (n − 1)d)
    public func sum(_ n: Int) -> Double { Double(n) / 2 * (2 * first + Double(n - 1) * difference) }
}

/// aₙ = a₁ · qⁿ⁻¹
public struct GeometricSequence: Hashable, Sendable {
    public var first: Double
    public var ratio: Double

    public init(first: Double, ratio: Double) {
        self.first = first
        self.ratio = ratio
    }

    public func term(_ n: Int) -> Double { first * pow(ratio, Double(n - 1)) }

    /// sₙ = a₁(qⁿ − 1)/(q − 1), or n·a₁ for q = 1.
    public func sum(_ n: Int) -> Double {
        ratio == 1 ? Double(n) * first : first * (pow(ratio, Double(n)) - 1) / (ratio - 1)
    }

    /// s = a₁ / (1 − q) when |q| < 1 (the infinite geometric series converges).
    public var infiniteSum: Double? { Swift.abs(ratio) < 1 ? first / (1 - ratio) : nil }
}

/// Interest and savings calculations (obrestni račun) from the matura syllabus.
public enum Finance {
    /// Simple interest o = G₀ · p · t / 100.
    public static func simpleInterest(principal: Double, ratePercent: Double, years: Double) -> Double {
        principal * ratePercent * years / 100
    }

    /// Compound interest Gₙ = G₀ (1 + p/(100m))^(m·n); `periodsPerYear: nil` compounds continuously.
    public static func compound(principal: Double, ratePercent: Double, years: Double, periodsPerYear: Int? = 1) -> Double {
        guard let m = periodsPerYear, m > 0 else { return principal * exp(ratePercent / 100 * years) }
        return principal * pow(1 + ratePercent / (100 * Double(m)), Double(m) * years)
    }

    /// Years until G₀ grows to G with yearly compounding: n = ln(G/G₀) / ln(1 + p/100).
    public static func yearsToReach(target: Double, principal: Double, ratePercent: Double) -> Double? {
        guard target > 0, principal > 0, ratePercent > -100, ratePercent != 0 else { return nil }
        return log(target / principal) / log(1 + ratePercent / 100)
    }

    /// Savings after n equal deposits a with interest rate p per period.
    /// Deposits at the start of each period (prenumerando) earn one period more.
    public static func savings(deposit: Double, ratePercent: Double, periods: Int, atStart: Bool) -> Double {
        let r = 1 + ratePercent / 100
        guard r != 1 else { return deposit * Double(periods) }
        let base = deposit * (pow(r, Double(periods)) - 1) / (r - 1)
        return atStart ? base * r : base
    }

    /// Equal loan payment (anuiteta) a = G·rⁿ(r − 1)/(rⁿ − 1) at the end of each period.
    public static func loanPayment(principal: Double, ratePercent: Double, periods: Int) -> Double {
        let r = 1 + ratePercent / 100
        guard r != 1 else { return principal / Double(periods) }
        let rn = pow(r, Double(periods))
        return principal * rn * (r - 1) / (rn - 1)
    }

    /// Relative change in percent from `old` to `new`.
    public static func percentChange(from old: Double, to new: Double) -> Double? {
        old == 0 ? nil : (new - old) / old * 100
    }

    /// Rate per period for m periods a year: the conformal (konformna) rate gives the same yearly
    /// growth, (1 + p/100)^(1/m) − 1; the relative (relativna) rate is simply p/m.
    public static func periodRate(annualPercent p: Double, periodsPerYear m: Int, conformal: Bool) -> Double {
        guard m > 0 else { return p }
        return conformal ? (pow(1 + p / 100, 1 / Double(m)) - 1) * 100 : p / Double(m)
    }

    /// One row of an amortization plan (amortizacijski načrt).
    public struct AmortizationRow: Hashable, Sendable, Identifiable {
        public var period: Int
        /// Anuiteta a = obresti + razdolžnina.
        public var payment: Double
        /// Obresti on the remaining debt.
        public var interest: Double
        /// Razdolžnina: the part of the payment that repays the debt.
        public var repayment: Double
        /// Ostanek dolga after this payment.
        public var remaining: Double
        public var id: Int { period }
    }

    /// Equal payments at the end of each period; the last row closes the remaining cents.
    public static func amortizationPlan(principal: Double, ratePercent: Double, periods: Int) -> [AmortizationRow] {
        guard periods > 0, periods <= 1200, principal.isFinite, ratePercent.isFinite else { return [] }
        let payment = loanPayment(principal: principal, ratePercent: ratePercent, periods: periods)
        var remaining = principal
        var rows: [AmortizationRow] = []
        rows.reserveCapacity(periods)
        for k in 1...periods {
            let interest = remaining * ratePercent / 100
            let repayment = k == periods ? remaining : payment - interest
            remaining -= repayment
            rows.append(AmortizationRow(period: k, payment: interest + repayment, interest: interest,
                                        repayment: repayment, remaining: Swift.abs(remaining) < 1e-9 ? 0 : remaining))
        }
        return rows
    }
}

/// Linear systems with any number of equations and unknowns (Gauss–Jordan, exact when possible).
public enum LinearSystemSolver {
    public enum Solution: Sendable {
        /// One solution x = values.
        case unique(Matrix)
        /// Contradiction (e.g. 0 = 1).
        case none
        /// Infinitely many: the reduced matrix, its pivot columns and the free unknowns.
        case infinite(reduced: Matrix, pivots: [Int], free: [Int])
    }

    public static func solve(coefficients a: Matrix, constants b: Matrix) throws(MathError) -> Solution {
        guard a.rows == b.rows, b.columns == 1 else { throw .domain("dimenzije sistema se ne ujemajo") }
        let augmented = Matrix.augment(a, b)
        let (reduced, pivots) = augmented.reducedRowEchelonForm()
        if pivots.contains(a.columns) { return .none }
        if pivots.count == a.columns {
            var values: [Double] = []
            var exact: [Rational]? = reduced.exact == nil ? nil : []
            for (row, _) in pivots.enumerated() {
                values.append(reduced[row, a.columns])
                if let e = reduced.exactEntry(row, a.columns) { exact?.append(e) }
            }
            return .unique(Matrix(rows: a.columns, columns: 1, values: values, exact: exact))
        }
        let free = (0..<a.columns).filter { !pivots.contains($0) }
        return .infinite(reduced: reduced, pivots: pivots, free: free)
    }
}
