import Foundation

/// Sharp DRILL mode: mental arithmetic and the multiplication table.
public enum DrillKind: String, CaseIterable, Identifiable, Sendable, Codable {
    case addition, subtraction, multiplication, division, mixed, multiplicationTable

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .addition: "Seštevanje"
        case .subtraction: "Odštevanje"
        case .multiplication: "Množenje"
        case .division: "Deljenje"
        case .mixed: "Mešano (+ − × ÷)"
        case .multiplicationTable: "Poštevanka"
        }
    }

    public var symbol: String {
        switch self {
        case .addition: "+"
        case .subtraction: "−"
        case .multiplication, .multiplicationTable: "×"
        case .division: "÷"
        case .mixed: "±"
        }
    }
}

public enum DrillLevel: Int, CaseIterable, Identifiable, Sendable, Codable {
    case easy = 1, medium = 2, hard = 3
    public var id: Int { rawValue }
    public var title: String {
        switch self {
        case .easy: "Lahko"
        case .medium: "Srednje"
        case .hard: "Težko"
        }
    }
}

public struct DrillQuestion: Hashable, Sendable, Identifiable {
    public var id = UUID()
    public var left: Int
    public var right: Int
    public var operation: DrillKind
    public var answer: Int

    public var text: String { "\(left) \(operation.symbol) \(right)" }
}

/// Generates questions with whole-number answers (division questions are exact).
public struct DrillGenerator: Sendable {
    private var rng: SplitMix64

    public init(seed: UInt64 = UInt64.random(in: 1...UInt64.max)) {
        rng = SplitMix64(seed: seed)
    }

    /// `table` picks the row of the multiplication table (nil = random 1…10).
    public mutating func next(_ kind: DrillKind, level: DrillLevel = .easy, table: Int? = nil) -> DrillQuestion {
        let limit = [9, 99, 999][level.rawValue - 1]
        switch kind {
        case .addition:
            let a = Int.random(in: 0...limit, using: &rng), b = Int.random(in: 0...limit, using: &rng)
            return DrillQuestion(left: a, right: b, operation: .addition, answer: a + b)
        case .subtraction:
            var a = Int.random(in: 0...limit, using: &rng), b = Int.random(in: 0...limit, using: &rng)
            if a < b { swap(&a, &b) }
            return DrillQuestion(left: a, right: b, operation: .subtraction, answer: a - b)
        case .multiplication:
            let factorLimit = [9, 20, 99][level.rawValue - 1]
            let a = Int.random(in: 0...factorLimit, using: &rng), b = Int.random(in: 0...max(9, factorLimit / 2), using: &rng)
            return DrillQuestion(left: a, right: b, operation: .multiplication, answer: a * b)
        case .division:
            let factorLimit = [9, 20, 99][level.rawValue - 1]
            let b = Int.random(in: 1...max(9, factorLimit / 2), using: &rng), q = Int.random(in: 0...factorLimit, using: &rng)
            return DrillQuestion(left: b * q, right: b, operation: .division, answer: q)
        case .mixed:
            let kinds: [DrillKind] = [.addition, .subtraction, .multiplication, .division]
            return next(kinds[Int.random(in: 0..<kinds.count, using: &rng)], level: level)
        case .multiplicationTable:
            let row = table ?? Int.random(in: 1...10, using: &rng)
            let b = Int.random(in: 1...10, using: &rng)
            return DrillQuestion(left: row, right: b, operation: .multiplicationTable, answer: row * b)
        }
    }
}
