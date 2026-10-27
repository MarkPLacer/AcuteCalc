import Foundation
import Testing
@testable import AcuteCore

// MARK: Unions D₁ ∪ D₂ ∪ … of regions given with an index condition

@Suite struct RegionUnionParsingTests {
    func request(_ text: String) throws -> GraphRequest? {
        try CalculationEngine.graphRequest(for: try MathRowConverter.row(fromText: text))
    }

    func family(_ text: String) throws -> RegionFamily? {
        guard case .union(let family)? = try request(text)?.kinds.first else { return nil }
        return family
    }

    /// (x − n)² + y² ≤ 2^(−n−1), then `condition`, as the keypad types it.
    func keypadRow(_ condition: [MathNode]) -> MathRow {
        let two = MathRow([.symbol(.digit(2))])
        return MathRow([
            .symbol(.leftParenthesis), .symbol(.variable("x")), .symbol(.minus), .symbol(.variable("n")), .symbol(.rightParenthesis),
            .power(exponent: two), .symbol(.plus), .symbol(.variable("y")), .power(exponent: two),
            .symbol(.lessOrEqual), .symbol(.digit(2)),
            .power(exponent: MathRow([.symbol(.minus), .symbol(.variable("n")), .symbol(.minus), .symbol(.digit(1))])),
            .symbol(.comma),
        ] + condition)
    }

    @Test func typedConditions() throws {
        let disc = "(x-n)^2+y^2<=2^(-n-1)"
        let forms: [(String, Int)] = [
            ("\(disc), n ∈ ℕ", 1), ("\(disc), n in N", 1), ("\(disc), n ∈ N", 1),
            ("\(disc), n = 1, 2, ...", 1), ("\(disc), n = 1, 2, 3, …", 1), ("\(disc), n = 1, …", 1),
            ("\(disc), n ∈ {1, 2, 3, ...}", 1), ("n ∈ ℕ, \(disc)", 1),
            ("\(disc), n ∈ ℕ₀", 0), ("\(disc), n in N_0", 0), ("\(disc), n = 0, 1, 2, ...", 0),
            ("\(disc), n = 3, 4, ...", 3),
        ]
        for (text, start) in forms {
            let union = try #require(try family(text), "\(text) is not a union")
            #expect(union.start == start, "\(text)")
            #expect(union.index == "n", "\(text)")
            #expect(!union.strict, "\(text)")
        }
        let other = try #require(try family("(x-k)^2+y^2<2^(-k-1), k ∈ ℕ"))
        #expect(other.index == "k")
        #expect(other.strict)
    }

    @Test func keypadConditions() throws {
        let n = MathNode.symbol(.variable("n"))
        let element = MathNode.symbol(.variable("∈"))
        let naturals = MathNode.symbol(.variable("ℕ"))
        let rows: [(MathRow, Int)] = [
            (keypadRow([n, element, naturals]), 1),
            (keypadRow([n, element, naturals, .subscriptRow(MathRow([.symbol(.digit(0))]))]), 0),
            (keypadRow([n, .symbol(.equals), .symbol(.digit(1)), .symbol(.comma), .symbol(.digit(2)), .symbol(.comma), .symbol(.variable("…"))]), 1),
        ]
        for (row, start) in rows {
            guard case .union(let union)? = try CalculationEngine.graphRequest(for: row)?.kinds.first else {
                Issue.record("\(MathRowConverter.plainText(row)) is not a union")
                continue
            }
            #expect(union.start == start)
        }
        // While the set is still to be typed.
        #expect(throws: MathError.self) { try CalculationEngine.graphRequest(for: keypadRow([n, element])) }
        guard case .incomplete = CalculationEngine.calculate(keypadRow([n, element]), variables: [:], exactVariables: [:],
                                                             settings: CalculationSettings()).outcome else {
            Issue.record("n ∈ without the set is not incomplete")
            return
        }
    }

    @Test func textBecomesKeypadRow() throws {
        let row = try MathRowConverter.row(fromText: "(x-n)^2+y^2<=2^(-n-1), n in N")
        #expect(Array(row.nodes.suffix(4)) == [.symbol(.comma), .symbol(.variable("n")), .symbol(.variable("∈")), .symbol(.variable("ℕ"))])
        guard case .union? = try CalculationEngine.graphRequest(for: row)?.kinds.first else {
            Issue.record("the row is not a union")
            return
        }
        let fromZero = try MathRowConverter.row(fromText: "(x-n)^2+y^2<=2^(-n-1), n = 0, 1, ...")
        #expect(fromZero.nodes.last == .subscriptRow(MathRow([.symbol(.digit(0))])))
        let fromTwo = try MathRowConverter.row(fromText: "(x-n)^2+y^2<=2^(-n-1), n = 2, 3, ...")
        #expect(fromTwo.nodes.last == .symbol(.variable("…")))
        #expect(try family(MathRowConverter.plainText(fromTwo).replacingOccurrences(of: ";", with: ","))?.start == 2)
    }

    @Test func latexPasteAndExport() throws {
        let row = try LaTeXConverter.row(fromLaTeX: #"(x-n)^{2}+y^{2}\le 2^{-n-1};\ n\in\mathbb{N}"#)
        guard case .union(let union)? = try CalculationEngine.graphRequest(for: row)?.kinds.first else {
            Issue.record("the LaTeX row is not a union")
            return
        }
        #expect(union.start == 1)
        let latex = LaTeXConverter.latex(try MathRowConverter.row(fromText: "(x-n)^2+y^2<=2^(-n-1), n in N"))
        #expect(latex.contains(#"\in"#))
        #expect(latex.contains(#"\mathbb{N}"#))
    }

    @Test func lexerReadsElementSignAndEllipsis() throws {
        #expect(try Lexer().tokenize("n ∈ ℕ") == [.identifier("n"), .op("∈"), .identifier("ℕ")])
        #expect(try Lexer().tokenize("1, 2, ...") == [.number("1"), .op(","), .number("2"), .op(","), .op("…")])
        #expect(try Lexer().tokenize("2…") == [.number("2"), .op("…")])
    }

    @Test func sequencesStaySequences() throws {
        for text in ["a_n=2n+1", "1/n", "a_n = 1/n, n ∈ ℕ", "1/n^2, n in N", "a_k = 2^k, k = 1, 2, ..."] {
            guard case .sequence(let term)? = try request(text)?.kinds.first else {
                Issue.record("\(text) is not a sequence")
                continue
            }
            #expect(term.dependsOn("n"), "\(text)")
        }
        // Sequences are drawn from n = 1.
        #expect(throws: MathError.self) { try request("a_n = 1/n, n ∈ ℕ₀") }
    }

    @Test func otherSystemsAreUnchanged() throws {
        guard case .implicit? = try request("x>=0, y>=0, x+y<=4")?.kinds.first else {
            Issue.record("a region system changed")
            return
        }
        // Without an index condition n is a parameter with a slider, as before.
        let parametric = try #require(try request("(x-n)^2+y^2<=2^(-n-1), n >= 1"))
        #expect(parametric.parameters == ["n"])
        guard case .implicit? = parametric.kinds.first else {
            Issue.record("a parametric region changed")
            return
        }
    }

    @Test func invalidConditions() throws {
        #expect(throws: MathError.self) { try request("(x-n)^2+y^2<=1, n ∈ ℕ, n ∈ ℕ") }
        #expect(throws: MathError.self) { try request("x^2+y^2<=1, n ∈ ℕ") }
        #expect(throws: MathError.self) { try request("(x-n)^2+y^2=1, n ∈ ℕ") }
        #expect(throws: MathError.self) { try request("(x-n)^2+y^2<=1, n = 1, 3, ...") }
        #expect(throws: MathError.self) { try request("(x-n)^2+y^2<=1, n ∈") }
    }
}

@Suite struct RegionUnionAreaTests {
    let halfPi = ExactReal.pi.multiplied(by: ExactReal(Rational.half))

    func family(_ text: String) throws -> RegionFamily {
        guard case .union(let family)? = try CalculationEngine.graphRequest(for: try MathRowConverter.row(fromText: text))?.kinds.first else {
            throw MathError.syntax("not a union: \(text)")
        }
        return family
    }

    @Test func discsOfTheExercise() throws {
        let discs = try family("(x-n)^2+y^2<=2^(-n-1), n ∈ ℕ")
        guard case .ellipse(let first) = discs.member(1) else {
            Issue.record("D₁ is not a disc")
            return
        }
        #expect(first.center == SIMD2(1, 0))
        #expect(approx(first.halfSize.x, 0.5, 1e-15) && approx(first.halfSize.y, 0.5, 1e-15))
        #expect(approx(first.area, .pi / 4, 1e-15))
        for n in [10, 40] {
            guard case .ellipse(let member) = discs.member(Double(n)) else {
                Issue.record("D_\(n) is not a disc")
                continue
            }
            let area = Double.pi * pow(2, Double(-n - 1))
            #expect(abs(member.area - area) <= 1e-9 * area)
            #expect(abs(member.center.x - Double(n)) < 1e-12)
        }
    }

    @Test func areaOfTheExerciseIsExactlyHalfPi() throws {
        let union = try family("(x-n)^2+y^2<=2^(-n-1), n ∈ ℕ").area()
        #expect(union.overlap == .disjoint)
        #expect(union.exact == halfPi)
        #expect(abs(union.sum - .pi / 2) < 1e-15)
        #expect(union.area == union.sum)
        #expect(union.errorBound == 0)
        #expect(approx(union.ratio ?? 0, 0.5, 1e-12))
        #expect(union.remainder < 1e-15)
        // In the calculator: P = π/2 as the result.
        let row = try MathRowConverter.row(fromText: "(x-n)^2+y^2<=2^(-n-1), n ∈ ℕ")
        let calculation = CalculationEngine.calculate(row, variables: [:], exactVariables: [:], settings: CalculationSettings())
        guard case .special(.unionArea(let result), let number) = calculation.outcome else {
            Issue.record("no area in the calculator")
            return
        }
        #expect(result == union)
        #expect(number.exact == halfPi)
        guard case .union? = calculation.graph?.kinds.first else {
            Issue.record("no union drawn")
            return
        }
    }

    @Test func radiusAndComplexForms() throws {
        for text in ["sqrt((x-n)^2+y^2) <= 2^(-(n+1)/2), n ∈ ℕ", "|z-n| <= 2^(-(n+1)/2), n ∈ ℕ", "2^(-n-1) >= (x-n)^2+y^2, n = 1, 2, ..."] {
            let union = try family(text).area()
            #expect(union.overlap == .disjoint, "\(text)")
            #expect(abs(union.sum - .pi / 2) < 1e-14, "\(text)")
            #expect(union.exact == halfPi, "\(text)")
        }
    }

    @Test func ellipses() throws {
        // Semi-axes 2·2⁻ⁿ and 2⁻ⁿ: areas 2π·4⁻ⁿ, the sum 2π/3.
        let union = try family("x^2/4+(y-3n)^2<=4^(-n), n ∈ ℕ").area()
        #expect(union.overlap == .disjoint)
        #expect(abs(union.sum - 2 * .pi / 3) < 1e-14)
        #expect(union.exact == ExactReal.pi.multiplied(by: ExactReal(Rational(2, 3)!)))
    }

    @Test func overlappingMembersGiveAnUpperBound() throws {
        // Radii 2⁻ⁿ at x = n/2: D₁ and D₂ overlap; Σ π·4⁻ⁿ = π/3.
        let union = try family("(x-n/2)^2+y^2<=4^(-n), n ∈ ℕ").area()
        #expect(union.overlap == .members(1, 2))
        #expect(union.area == nil)
        #expect(abs(union.sum - .pi / 3) < 1e-14)
    }

    @Test func touchingIsNotOverlapping() throws {
        // Equal discs whose centres are as far apart as the sum of their radii: the area is infinite.
        let union = try family("(x-n)^2+(y-n)^2<=1/2, n ∈ ℕ").area()
        #expect(union.overlap == .disjoint)
        #expect(union.sum == .infinity)
    }

    @Test func slowSeriesHasAnErrorBound() throws {
        // Radii 1/(2n): Σ π/(4n²) = π³/24, not geometric.
        let union = try family("(x-n)^2+y^2<=1/(4n^2), n ∈ ℕ").area()
        #expect(union.overlap == .disjoint)
        #expect(union.exact == nil)
        #expect(union.ratio == nil)
        let bound = try #require(union.errorBound)
        #expect(bound < 1e-9)
        #expect(abs(union.sum - pow(Double.pi, 3) / 24) <= bound)
    }

    @Test func divergentSeries() throws {
        // Radii 1/(2√n) never meet, but Σ π/(4n) diverges.
        let union = try family("(x-n)^2+y^2<=1/(4n), n ∈ ℕ").area()
        #expect(union.overlap == .disjoint)
        #expect(union.sum == .infinity)
    }

    @Test func otherShapesAreDrawnWithoutArea() throws {
        let squares = try family("abs(x-n)+abs(y)<=2^(-n), n ∈ ℕ")
        #expect(throws: MathError.self) { try squares.area() }
        #expect(squares.drawnMembers(x: -1...20, y: -5...5, minimumSize: 0.01, limit: 5) == [1, 2, 3, 4, 5])
    }

    @Test func membersDrawnDownToAPixel() throws {
        let discs = try family("(x-n)^2+y^2<=2^(-n-1), n ∈ ℕ")
        // Diameters 2·2^(−(n+1)/2) ≥ 0,01 up to n = 14.
        #expect(discs.drawnMembers(x: -1...20, y: -5...5, minimumSize: 0.01, limit: 48) == Array(1...14))
        #expect(discs.drawnMembers(x: 5.5...8.5, y: -5...5, minimumSize: 0.01, limit: 48) == [6, 7, 8])
        #expect(discs.drawnMembers(x: -1...20, y: -5...5, minimumSize: 0.01, limit: 3) == [1, 2, 3])
        #expect(discs.drawnMembers(x: 100...110, y: -5...5, minimumSize: 0.01, limit: 48).isEmpty)
        let frame = try #require(discs.frame())
        #expect(abs(frame.x.lowerBound - 0.5) < 1e-12)
        #expect(frame.x.upperBound > 12 && frame.x.upperBound < 12.1)
        #expect(abs(frame.y.lowerBound + 0.5) < 1e-12 && abs(frame.y.upperBound - 0.5) < 1e-12)
    }

    @Test func parametersComeFromTheSliders() throws {
        let request = try #require(try CalculationEngine.graphRequest(for: try MathRowConverter.row(fromText: "(x-n)^2+y^2<=a*2^(-n-1), n ∈ ℕ")))
        #expect(request.parameters == ["a"])
        guard case .union(let family)? = request.kinds.first else {
            Issue.record("not a union")
            return
        }
        #expect(throws: MathError.self) { try family.area() }
        let doubled = try family.area(parameters: ["a": 2])
        #expect(abs(doubled.sum - .pi) < 1e-14)
    }

    @Test func ellipseOverlap() {
        // Semi-axes 2 and ½ along the axes: one above the other touches at distance 1.
        let flat = RegionFamily.Ellipse(center: .zero, sxx: 4, sxy: 0, syy: 0.25)
        func moved(_ x: Double, _ y: Double) -> RegionFamily.Ellipse {
            var e = flat
            e.center = SIMD2(x, y)
            return e
        }
        #expect(!flat.overlaps(moved(0, 1)))
        #expect(flat.overlaps(moved(0, 0.9)))
        #expect(flat.overlaps(moved(3.9, 0)))
        #expect(!flat.overlaps(moved(4.1, 0)))
        // Thin ellipses along the diagonal (semi-axes 2 and 0,1): their boxes overlap, they need not.
        let thin = RegionFamily.Ellipse(center: .zero, sxx: 2.005, sxy: 1.995, syy: 2.005)
        var apart = thin
        apart.center = SIMD2(0.5, -0.5)
        var close = thin
        close.center = SIMD2(0.05, -0.05)
        #expect(!thin.overlaps(apart))
        #expect(thin.overlaps(close))
        #expect(RegionFamily.Ellipse(center: .zero, radius: 1).overlaps(RegionFamily.Ellipse(center: SIMD2(1.5, 0), radius: 1)))
    }
}
