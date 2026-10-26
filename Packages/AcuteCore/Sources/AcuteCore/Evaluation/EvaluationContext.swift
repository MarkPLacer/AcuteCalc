import Foundation

/// Angle unit used by trigonometric functions (DRG on scientific calculators).
public enum AngleUnit: String, Hashable, Sendable, Codable, CaseIterable {
    case radians
    case degrees
    case gradians

    /// Multiply a value in this unit by this factor to get radians.
    public var radiansPerUnit: Double {
        switch self {
        case .radians: 1
        case .degrees: .pi / 180
        case .gradians: .pi / 200
        }
    }

    /// Size of a full turn in this unit (2π, 360, 400).
    public var fullTurn: Double {
        switch self {
        case .radians: 2 * .pi
        case .degrees: 360
        case .gradians: 400
        }
    }

    public var shortLabel: String {
        switch self {
        case .radians: "RAD"
        case .degrees: "DEG"
        case .gradians: "GRAD"
        }
    }

    /// Converts a value given in `self` to `target`.
    public func convert(_ value: Double, to target: AngleUnit) -> Double {
        value * radiansPerUnit / target.radiansPerUnit
    }
}

/// Small, fast, seedable PRNG (SplitMix64) so random functions are reproducible
/// while the user edits an expression and change only when they press Enter.
public struct SplitMix64: RandomNumberGenerator, Sendable, Hashable {
    private var state: UInt64

    public init(seed: UInt64) { state = seed }

    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// Everything evaluation needs besides the expression itself.
public struct EvaluationContext: Sendable {
    public var angleUnit: AngleUnit
    /// Numeric values of variables (`x` while graphing, user memories A–F, X, Y, M, ANS…).
    public var variables: [String: Double]
    /// Exact values of variables, when known (lets `A + 1/3` stay exact).
    public var exactVariables: [String: ExactReal]
    /// Complex values of variables (complex mode, domain colouring).
    public var complexVariables: [String: Complex]
    /// Matrices and vectors stored in variables (A, B, …).
    public var matrixVariables: [String: Matrix]
    public var randomSeed: UInt64

    public init(
        angleUnit: AngleUnit = .radians,
        variables: [String: Double] = [:],
        exactVariables: [String: ExactReal] = [:],
        complexVariables: [String: Complex] = [:],
        matrixVariables: [String: Matrix] = [:],
        randomSeed: UInt64 = 0x5EED
    ) {
        self.angleUnit = angleUnit
        self.variables = variables
        self.exactVariables = exactVariables
        self.complexVariables = complexVariables
        self.matrixVariables = matrixVariables
        self.randomSeed = randomSeed
    }

    public func with(_ name: String, _ value: Double) -> EvaluationContext {
        var copy = self
        copy.variables[name] = value
        copy.exactVariables[name] = nil
        return copy
    }
}
