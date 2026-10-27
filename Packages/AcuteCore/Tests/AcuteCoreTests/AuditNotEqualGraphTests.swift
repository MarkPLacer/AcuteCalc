import Foundation
import Testing
@testable import AcuteCore

/// ≠ in graphs (SHD-07, follow-up to the region |F − G| > 0). The kinds are read the way Graph2D.metal draws
/// them: lhs − rhs as GraphCanvasModel compiles it, filled by its relation where finite (<, ≤, >, ≥; = and ≠
/// fill nothing), and with an edge where it vanishes, dashed for < and >, solid for =, ≠, ≤ and ≥. Reference
/// sets are the exact ones (F ≠ G excludes exactly F = G); the pixel counts in the comments come from a float32
/// emulation of implicit_fragment (described in the commit messages).
@Suite struct AuditNotEqualGraphTests {
    private func system(_ text: String) throws -> [Expr] {
        try #require(Parser.parseSystem(tokens: try Lexer().tokenize(text)))
    }

    /// lhs − rhs of every implicit kind at (x, y) with its relation.
    private func values(_ request: GraphRequest, _ x: Double, _ y: Double) throws -> [(relation: RelationOperator, value: Double)] {
        var result: [(relation: RelationOperator, value: Double)] = []
        for kind in request.kinds {
            guard case .implicit(let lhs, let relation, let rhs) = kind else { continue }
            let program = try BytecodeCompiler(slots: ["x": .x, "y": .y]).compile(.sum([lhs, .negation(rhs)]))
            result.append((relation, RealVM(program: program).evaluate(x: x, y: y)))
        }
        return result
    }

    /// Whether (x, y) is shaded: a finite value on the filled side of 0 (exact, as the fragment shader compares).
    private func filled(_ request: GraphRequest, _ x: Double, _ y: Double) throws -> Bool {
        try values(request, x, y).contains { kind in
            guard kind.value.isFinite else { return false }
            switch kind.relation {
            case .less: return kind.value < 0
            case .lessOrEqual: return kind.value <= 0
            case .greater: return kind.value > 0
            case .greaterOrEqual: return kind.value >= 0
            case .equal, .notEqual: return false
            }
        }
    }

    /// The edges through (x, y), a point of a boundary: a kind that vanishes there (up to the ≠ tolerance, 10⁻⁶ for
    /// values up to 1, 10⁻⁵ allowed) draws one, dashed for < and >, solid for the others.
    private func edges(_ request: GraphRequest, _ x: Double, _ y: Double) throws -> (solid: Bool, dashed: Bool) {
        var solid = false, dashed = false
        for kind in try values(request, x, y) where kind.value.isFinite && abs(kind.value) <= 1e-5 {
            if kind.relation == .less || kind.relation == .greater { dashed = true } else { solid = true }
        }
        return (solid, dashed)
    }

    private func drawsNotEqual(_ request: GraphRequest) -> Bool {
        request.kinds.contains { kind in
            if case .implicit(_, .notEqual, _) = kind { return true }
            return false
        }
    }

    // MARK: Sets of complex numbers

    /// |z − 1| ≠ 2: the plane without the circle around 1 with radius 2, which is dashed. Main drew only that
    /// circle (`.implicit(√((x − 1)² + y²), ≠, 2)`, the curve mode), exactly the points that are not solutions.
    @Test func complexModulusNotEqualIsTheRegionAroundTheCircle() throws {
        let relation = try parse("|z-1|!=2")
        let calculation = CalculationEngine.calculate(relation, variables: [:], exactVariables: [:], settings: CalculationSettings())
        for request in [try #require(calculation.graph), try #require(CalculationEngine.graphRequest(for: relation))] {
            #expect(!drawsNotEqual(request))
            #expect(try filled(request, 1, 0))
            #expect(try filled(request, 4, 1))
            #expect(try filled(request, 1, 1.5))
            #expect(try !filled(request, 3, 0))
            #expect(try !filled(request, 1, -2))
            let circle = try edges(request, -1, 0)
            #expect(circle.dashed && !circle.solid)
        }
    }

    /// Re z ≠ 0: the plane without the imaginary axis (main: only the axis).
    @Test func realPartNotEqualIsThePlaneWithoutTheAxis() throws {
        let request = try #require(CalculationEngine.graphRequest(for: try parse("Re z != 0")))
        #expect(!drawsNotEqual(request))
        #expect(try filled(request, 1, 0.5))
        #expect(try filled(request, -1, 0.5))
        #expect(try !filled(request, 0, 0.5))
        let axis = try edges(request, 0, 0.5)
        #expect(axis.dashed && !axis.solid)
    }

    // MARK: Systems of strict inequalities

    /// y > x, x ≠ 0 (strict parts only, no equation): the open half-plane without the half-line x = 0, y > 0,
    /// every edge dashed. Main drew only that half-line (emulation: 0 % filled, 1194 px solid).
    @Test func strictSystemWithNotEqualIsOneRegion() throws {
        let request = try #require(CalculationEngine.systemGraph(try system("y>x, x!=0")))
        #expect(try filled(request, -1, 1))
        #expect(try filled(request, 1, 2))
        #expect(try !filled(request, 0, 1))
        #expect(try !filled(request, 1, 0))
        let excluded = try edges(request, 0, 1)
        #expect(excluded.dashed && !excluded.solid)
    }

    /// Several ≠ at once: x ≠ 0, y ≠ 0 is the plane without both axes, which are dashed (main: only the axes).
    @Test func severalNotEqualsAtOnce() throws {
        let request = try #require(CalculationEngine.systemGraph(try system("x!=0, y!=0")))
        #expect(try filled(request, 1, 1))
        #expect(try filled(request, -1, -2))
        #expect(try !filled(request, 0, 1))
        #expect(try !filled(request, 1, 0))
        for (x, y) in [(0.0, 1.0), (1.0, 0.0)] {
            let axis = try edges(request, x, y)
            #expect(axis.dashed && !axis.solid)
        }
    }

    // MARK: Identities and the tolerance

    /// The points of a 41 × 41 grid over [−5; 5]² (steps of 0.2437, which binary floating point cannot hold).
    private func filledPoints(_ request: GraphRequest) throws -> Int {
        var count = 0
        for i in 0...40 {
            for j in 0...40 {
                if try filled(request, -5 + 0.2437 * Double(i), -5 + 0.2437 * Double(j)) { count += 1 }
            }
        }
        return count
    }

    /// An identity typed with ≠ holds nowhere, so nothing is drawn (as on main, which drew only the curve F = G,
    /// and an identity has none: a guard). Compared exactly, F − G rounded to nonzero values: on the CPU 369
    /// (sin²x + cos²x ≠ 1) and 945 ((x + y)² ≠ x² + 2xy + y²) of these 1681 points, on the GPU in float 19.5 %
    /// and 61.5 % of the pixels. With the tolerance of ≠ (10⁻⁶ relative, bc_compare) none on the CPU and 0 % of
    /// the pixels for sin²x + cos²x; the polynomial identity, which the simplifier proves, is −1 everywhere.
    @Test func identityTypedWithNotEqualIsEmpty() throws {
        for text in ["sin(x)^2+cos(x)^2!=1", "(x+y)^2!=x^2+2x*y+y^2"] {
            let request = try #require(CalculationEngine.graphRequest(for: try parse(text)))
            #expect(try filledPoints(request) == 0, "\(text)")
        }
        // Also next to ≥ in a system (exact: 820 of the points).
        let mixed = try #require(CalculationEngine.systemGraph(try system("x>=0, sin(x)^2+cos(x)^2!=1")))
        #expect(try filledPoints(mixed) == 0)
    }

    /// The tolerance takes out only F = G itself: x ≠ 2 still holds a thousandth away from x = 2.
    @Test func notEqualToleranceIsOnlyRounding() throws {
        let request = try #require(CalculationEngine.graphRequest(for: try parse("x != 2")))
        #expect(try filled(request, 2.001, 0))
        #expect(try filled(request, 1.999, 0))
        #expect(try !filled(request, 2, 0))
    }

    // MARK: ≠ next to ≤ or ≥

    /// 0 ≤ x ≤ 3, x ≠ 1: the band with its solid edges x = 0 and x = 3, without the line x = 1, which is dashed.
    /// Main drew only the line x = 1 (solid, no band); with one strictness flag for the system |x − 1| ≥ 0 held
    /// everywhere, so x = 1 was filled over and solid like the included edges (emulation: 2400 of 7200 edge px).
    @Test func notEqualNextToANonStrictChain() throws {
        let request = try #require(CalculationEngine.systemGraph(try system("0<=x<=3, x!=1")))
        #expect(try filled(request, 2, 0))
        #expect(try filled(request, 0, 0))
        #expect(try filled(request, 3, 0.5))
        #expect(try !filled(request, 1, 0))
        #expect(try !filled(request, -1, 0))
        #expect(try !filled(request, 4, 0))
        let excluded = try edges(request, 1, 0.5)
        #expect(excluded.dashed && !excluded.solid)
        #expect(try edges(request, 0, 0.5).solid)
        #expect(try edges(request, 3, 0.5).solid)
        // The solid edges are a second kind of the same region: one colour in the graph list.
        #expect(!request.highlightIntersections)
    }

    /// 0 ≤ x ≤ 3, x ≠ 0: the excluded line is the band's own edge, so x = 0 is dashed and only x = 3 solid.
    @Test func notEqualAlongTheEdgeOfAClosedRegion() throws {
        let request = try #require(CalculationEngine.systemGraph(try system("0<=x<=3, x!=0")))
        #expect(try filled(request, 1, 0))
        #expect(try filled(request, 3, 0))
        #expect(try !filled(request, 0, 1))
        let excluded = try edges(request, 0, 1)
        #expect(excluded.dashed && !excluded.solid)
        #expect(try edges(request, 3, 1).solid)
    }

    /// y ≤ x, x ≠ 0: the closed half-plane without the half-line x = 0, y < 0 (dashed); y = x stays solid.
    @Test func notEqualNextToANonStrictInequality() throws {
        let request = try #require(CalculationEngine.systemGraph(try system("y<=x, x!=0")))
        #expect(try filled(request, 1, 0))
        #expect(try filled(request, 1, 1))
        #expect(try filled(request, -1, -2))
        #expect(try !filled(request, 0, -1))
        #expect(try !filled(request, -1, 0))
        let excluded = try edges(request, 0, -1)
        #expect(excluded.dashed && !excluded.solid)
        #expect(try edges(request, 2, 2).solid)
    }

    /// x² + y² ≤ 4, x ≠ 0: the closed disc without its chord x = 0 (dashed); the circle stays solid.
    @Test func notEqualInsideAClosedDisc() throws {
        let request = try #require(CalculationEngine.systemGraph(try system("x^2+y^2<=4, x!=0")))
        #expect(try filled(request, 1, 0))
        #expect(try filled(request, 2, 0))
        #expect(try !filled(request, 0, 1))
        #expect(try !filled(request, 0, 2))
        #expect(try !filled(request, 3, 0))
        let chord = try edges(request, 0, 1)
        #expect(chord.dashed && !chord.solid)
        #expect(try edges(request, 2, 0).solid)
    }

    /// x ≥ 0, y ≥ 0, x ≠ y: the closed quadrant without its diagonal (dashed); the axes stay solid.
    @Test func notEqualDiagonalOfAClosedQuadrant() throws {
        let request = try #require(CalculationEngine.systemGraph(try system("x>=0, y>=0, x!=y")))
        #expect(try filled(request, 2, 1))
        #expect(try filled(request, 1, 0))
        #expect(try !filled(request, 1, 1))
        #expect(try !filled(request, 2.5, 2.5))
        let diagonal = try edges(request, 1, 1)
        #expect(diagonal.dashed && !diagonal.solid)
        #expect(try edges(request, 1, 0).solid)
        #expect(try edges(request, 0, 1).solid)
    }

    /// Several ≠ next to ≤: x ≠ 1 and y ≠ 1 take both chords out of the closed disc x² + y² ≤ 4, whose circle
    /// stays solid.
    @Test func severalNotEqualsInAClosedDisc() throws {
        let request = try #require(CalculationEngine.systemGraph(try system("x^2+y^2<=4, x!=1, y!=1")))
        #expect(try filled(request, 0, 0))
        #expect(try filled(request, 2, 0))
        #expect(try filled(request, 0, -2))
        #expect(try !filled(request, 1, 0))
        #expect(try !filled(request, 0, 1))
        #expect(try !filled(request, 1, 1))
        for (x, y) in [(1.0, 0.0), (0.0, 1.0)] {
            let chord = try edges(request, x, y)
            #expect(chord.dashed && !chord.solid)
        }
        #expect(try edges(request, 2, 0).solid)
        #expect(try edges(request, 0, -2).solid)
    }

    // MARK: Undefined values

    /// min and max of an undefined value are undefined in RealVM, in either order. Swift.min(a, .nan) is a, so
    /// min(2 − y; y − ln x) was 1 at (−1, 1), where ln x is undefined, but min(y − ln x; 2 − y) NaN. Where both
    /// are defined the values are unchanged (at (1, 0.5): min 0.5, max 1.5, exact).
    @Test func minAndMaxOfAnUndefinedOperandAreUndefined() throws {
        let gap = Expr.sum([.y, .negation(.function(.ln, [.x]))])
        let other = Expr.sum([.int(2), .negation(.y)])
        for function in [MathFunction.min, .max] {
            for arguments in [[other, gap], [gap, other]] {
                let vm = RealVM(program: try BytecodeCompiler(slots: ["x": .x, "y": .y]).compile(.function(function, arguments)))
                #expect(vm.evaluate(x: -1, y: 1).isNaN, "\(function)(\(arguments)) at (−1, 1)")
                #expect(vm.evaluate(x: 1, y: 0.5) == (function == .min ? 0.5 : 1.5), "\(function)(\(arguments)) at (1, 0.5)")
            }
        }
        // y ≥ 0, ln x ≠ 0 is the region min(y; gap of ln x ≠ 0) > 0: not filled at (−1, 1), where ln x is undefined.
        let region = try #require(CalculationEngine.systemGraph(try system("y>=0, ln(x)!=0")))
        #expect(try !filled(region, -1, 1))
        #expect(try filled(region, 2, 1))
    }

    /// The value of the one curve (an `.equal` kind) of a request at (x, y).
    private func curve(_ request: GraphRequest, _ x: Double, _ y: Double) throws -> Double {
        let curves = request.kinds.filter { kind in
            if case .implicit(_, .equal, _) = kind { return true }
            return false
        }
        try #require(curves.count == 1)
        guard case .implicit(let lhs, _, let rhs) = curves[0] else { return .nan }
        let program = try BytecodeCompiler(slots: ["x": .x, "y": .y]).compile(.sum([lhs, .negation(rhs)]))
        return RealVM(program: program).evaluate(x: x, y: y)
    }

    /// x² + y² = 4, y ≥ 0, x ≠ 0 is the upper semicircle without (0, 2); y = x², x ≥ 0, x ≠ 1 the right half of
    /// the parabola without (1, 1). Main kept these points and drew the line x = 0 (x = 1) as a second curve.
    @Test func notEqualRestrictsACurveNextToANonStrictInequality() throws {
        let semicircle = try #require(CalculationEngine.systemGraph(try system("x^2+y^2=4, y>=0, x!=0")))
        #expect(!drawsNotEqual(semicircle))
        #expect(try !curve(semicircle, 0, 2).isFinite)
        #expect(try curve(semicircle, 2, 0) == 0)
        #expect(try !curve(semicircle, 0, -2).isFinite)
        let parabola = try #require(CalculationEngine.systemGraph(try system("y=x^2, x>=0, x!=1")))
        #expect(!drawsNotEqual(parabola))
        #expect(try !curve(parabola, 1, 1).isFinite)
        #expect(try curve(parabola, 2, 4) == 0)
        #expect(try !curve(parabola, -1, 1).isFinite)
    }
}
