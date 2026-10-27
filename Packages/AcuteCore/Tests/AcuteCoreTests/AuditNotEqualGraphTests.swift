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
    /// and 61.5 % of the pixels. With the tolerance of ≠ (10⁻⁶ relative, bc_compare) none on the CPU, 0 % and
    /// 2.2 % of the pixels on the GPU (float rounding beyond 10⁻⁶ where 2xy cancels x² + y², |x| > 3).
    @Test func identityTypedWithNotEqualIsEmpty() throws {
        for text in ["sin(x)^2+cos(x)^2!=1", "(x+y)^2!=x^2+2x*y+y^2"] {
            let request = try #require(CalculationEngine.graphRequest(for: try parse(text)))
            #expect(!drawsNotEqual(request))
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
}
