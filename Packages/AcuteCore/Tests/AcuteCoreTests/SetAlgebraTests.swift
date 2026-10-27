import Foundation
import Testing
@testable import AcuteCore

// MARK: Sets on the number line and Venn diagrams

@Suite struct SetAlgebraTests {
    private func set(_ text: String) throws -> SetAlgebra.RealSet { try #require(SetAlgebra.RealSet.parse(text)) }

    @Test func intervalsAndPoints() throws {
        let a = try set("[-2, 3)"), b = try set("(1; ∞)")
        #expect(a.contains(-2) && !a.contains(3) && a.contains(2.5))
        // [−2, 3) ∪ (1, ∞) = [−2, ∞), the intersection (1, 3), the difference [−2, 1].
        let union = a.union(b)
        #expect(union.intervals.count == 1 && union.intervals[0].lower == -2 && union.intervals[0].lowerIncluded && union.intervals[0].upper == .infinity)
        let both = a.intersection(b)
        #expect(both.intervals.count == 1 && both.intervals[0].lower == 1 && !both.intervals[0].lowerIncluded)
        #expect(both.intervals[0].upper == 3 && !both.intervals[0].upperIncluded)
        let difference = a.subtracting(b)
        #expect(difference.intervals.count == 1 && difference.intervals[0].upper == 1 && difference.intervals[0].upperIncluded)
        // The complement (−∞, −2) ∪ [3, ∞).
        let complement = a.complement
        #expect(complement.intervals.count == 2)
        #expect(complement.intervals[0].lower == -.infinity && complement.intervals[0].upper == -2 && !complement.intervals[0].upperIncluded)
        #expect(complement.intervals[1].lower == 3 && complement.intervals[1].lowerIncluded && complement.intervals[1].upper == .infinity)
        // Touching pieces and points merge: (0, 1) ∪ {1} ∪ (1, 2] = (0, 2].
        let merged = try set("(0, 1) ∪ {1} ∪ (1, 2]")
        #expect(merged.intervals.count == 1 && merged.intervals[0].upper == 2 && merged.intervals[0].upperIncluded)
        // Removing a number splits an interval.
        #expect(try set("[0, 2]").subtracting(try set("{1}")).intervals.count == 2)
        #expect(SetAlgebra.RealSet.reals.complement.isEmpty && SetAlgebra.RealSet.empty.complement.isAllReals)
        #expect(SetAlgebra.RealSet.parse("[3, 1]") == nil)
        #expect(SetAlgebra.RealSet.parse("[1, 2") == nil)
        #expect(SetAlgebra.RealSet.parse("[1, 2] ∪") == nil)
        #expect(SetAlgebra.RealSet.parse("[1, 2] ∪ ∪ [3, 4]") == nil)
        // Ends given as expressions keep their exact value.
        let roots = try set("[-sqrt(2), sqrt(2)]")
        #expect(approx(roots.intervals[0].upper, 2.0.squareRoot()) && roots.intervals[0].exactUpper != nil)
        // Decimal commas with semicolons.
        #expect(try set("[0,5; 1,5]").contains(1.25))
    }

    @Test func inequalities() throws {
        let square = try set("x^2 < 4")
        #expect(square.intervals.count == 1 && approx(square.intervals[0].lower, -2) && !square.intervals[0].lowerIncluded)
        let chain = try set("-1 <= x < 2")
        #expect(chain.contains(-1) && !chain.contains(2))
        let distance = try set("|x - 1| >= 2")
        #expect(distance.intervals.count == 2 && distance.contains(-1) && distance.contains(3) && !distance.contains(0))
    }

    @Test func expressionsOnTheLine() throws {
        let a = try set("[-2, 3)"), b = try set("(1, ∞)"), c = try set("{0, 2, 5}")
        let expression = try #require(SetAlgebra.Expression.parse("(A ∪ B) ∩ C′"))
        let value = try #require(expression.evaluate([a, b, c]))
        // [−2, ∞) without 0, 2 and 5.
        #expect(value.contains(-2) && !value.contains(0) && value.contains(1) && !value.contains(2) && !value.contains(5) && value.contains(6))
        #expect(SetAlgebra.Expression.parse("A \\ B") == .difference(.set(0), .set(1)))
        #expect(SetAlgebra.Expression.parse("A ∪ B ∩ C") == .union(.set(0), .intersection(.set(1), .set(2))))
        #expect(SetAlgebra.Expression.parse("(A ∩ B)ᶜ") == .complement(.intersection(.set(0), .set(1))))
        #expect(SetAlgebra.Expression.parse("A^c ∪ B'") == .union(.complement(.set(0)), .complement(.set(1))))
        #expect(SetAlgebra.Expression.parse("A ∪") == nil)
        #expect(SetAlgebra.Expression.parse("D") == nil)
        // A missing set leaves the value unknown.
        #expect(expression.evaluate([a, b, nil]) == nil)
    }

    @Test func vennDiagrams() throws {
        #expect(try #require(SetAlgebra.Expression.parse("A ∩ B′")).regions(of: 2) == [0b01])
        #expect(try #require(SetAlgebra.Expression.parse("(A ∪ B)′")).regions(of: 3) == [0b000, 0b100])
        // 30 pupils: 18 play football, 12 basketball, 5 both.
        let counts = try SetAlgebra.regionCounts(universe: 30, a: 18, b: 12, ab: 5)
        #expect(counts[0b01] == 13 && counts[0b10] == 7 && counts[0] == 5)
        #expect(try SetAlgebra.count(SetAlgebra.Expression.union(.set(0), .set(1)).regions(of: 2), in: counts) == 25)
        #expect(throws: MathError.self) { try SetAlgebra.regionCounts(universe: 10, a: 8, b: 7, ab: 2) }
        // Numbers of elements are whole: 2,5 pupils cannot play both.
        #expect(throws: MathError.self) { try SetAlgebra.regionCounts(universe: 30, a: 18, b: 12, ab: 2.5) }
        // A set outside the diagram has no regions, and its value on the line is unknown.
        #expect(SetAlgebra.Expression.set(5).regions(of: 2).isEmpty && SetAlgebra.Expression.set(-1).regions(of: 3).isEmpty)
        #expect(SetAlgebra.Expression.set(-1).evaluate([.reals]) == nil && SetAlgebra.Expression.set(0).regions(of: 40).isEmpty)
        // Three sets by inclusion and exclusion: |A ∪ B ∪ C| = 43.
        let three = try SetAlgebra.regionCounts(universe: 50, a: 20, b: 25, c: 15, ab: 8, ac: 6, bc: 5, abc: 2)
        #expect(three[0b111] == 2 && three[0b001] == 8 && three[0] == 7)
        // Without the universal set the outside is unknown.
        let open = try SetAlgebra.regionCounts(universe: nil, a: 3, b: 4, ab: 1)
        #expect(try SetAlgebra.count([0, 1], in: open) == nil)
        // Counts that add up beyond the largest double are an overflow, not a missing n(U).
        let huge = try SetAlgebra.regionCounts(universe: nil, a: 1.5e308, b: 1.5e308, ab: 0)
        #expect(throws: MathError.self) { try SetAlgebra.count([0b01, 0b10], in: huge) }
    }
}
