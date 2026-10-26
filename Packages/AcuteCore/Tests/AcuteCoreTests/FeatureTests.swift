import Foundation
import Testing
@testable import AcuteCore

// MARK: Matrices and vectors

@Suite struct MatrixTests {
    func calc(_ s: String, unit: AngleUnit = .radians) throws -> CalculationOutcome {
        CalculationEngine.calculate(try parse(s), variables: [:], exactVariables: [:], settings: CalculationSettings(angleUnit: unit)).outcome
    }

    @Test func determinantAndInverseAreExact() throws {
        let m = Matrix(rows: 2, columns: 2, exact: [Rational(4), Rational(7), Rational(2), Rational(6)])
        let det = try m.determinant()
        #expect(det.exact == Rational(10))
        let inverse = try m.inverse()
        #expect(inverse.exact == [Rational(3, 5)!, Rational(-7, 10)!, Rational(-1, 5)!, Rational(2, 5)!])
        let product = try m.multiplied(by: inverse)
        #expect(product.exact == Matrix.identity(2).exact)
    }

    @Test func singularMatrixHasNoInverse() {
        let m = Matrix(rows: 2, columns: 2, exact: [Rational(1), Rational(2), Rational(2), Rational(4)])
        #expect(throws: MathError.self) { try m.inverse() }
        #expect(m.rank() == 1)
    }

    @Test func linearSystem() throws {
        // 2x + y = 5, x − y = 1 → x = 2, y = 1
        let a = Matrix(rows: 2, columns: 2, exact: [Rational(2), Rational(1), Rational(1), Rational(-1)])
        let b = Matrix(rows: 2, columns: 1, exact: [Rational(5), Rational(1)])
        let x = try a.solve(b)
        #expect(x.exact == [Rational(2), Rational(1)])
    }

    @Test func vectorsInTheCalculator() throws {
        guard case .number(let dot) = try calc("(1, 2, 3)(4, 5, 6)") else { Issue.record("dot"); return }
        #expect(dot.value == 32)
        guard case .matrix(let cross) = try calc("cross((1, 0, 0), (0, 1, 0))") else { Issue.record("cross"); return }
        #expect(cross.values == [0, 0, 1])
        guard case .number(let length) = try calc("abs((3, 4))") else { Issue.record("norm"); return }
        #expect(length.value == 5)
        guard case .number(let angle) = try calc("angle((1, 0), (1, 1))", unit: .degrees) else { Issue.record("angle"); return }
        #expect(approx(angle.value, 45))
    }

    @Test func matricesInTheCalculator() throws {
        guard case .number(let det) = try calc("det(((1, 2), (3, 4)))") else { Issue.record("det"); return }
        #expect(det.value == -2)
        guard case .matrix(let inverse) = try calc("((1, 2), (3, 4))^-1") else { Issue.record("inverse"); return }
        #expect(inverse.exact == [Rational(-2), Rational(1), Rational(3, 2)!, Rational(-1, 2)!])
        guard case .matrix(let t) = try calc("((1, 2), (3, 4))ᵀ") else { Issue.record("transpose"); return }
        #expect(t.values == [1, 3, 2, 4])
    }
}

// MARK: Statistics and distributions

@Suite struct StatisticsTests {
    @Test func oneVariable() throws {
        let s = try #require(OneVariableStatistics(values: [2, 4, 4, 4, 5, 5, 7, 9]))
        #expect(s.count == 8)
        #expect(s.mean == 5)
        #expect(approx(s.populationStandardDeviation, 2))
        #expect(s.median == 4.5)
        #expect(s.lowerQuartile == 4)
        #expect(s.upperQuartile == 6)
        #expect(s.modes == [4])
    }

    @Test func frequenciesAreWeights() throws {
        let expanded = try #require(OneVariableStatistics(values: [1, 2, 2, 3, 3, 3]))
        let weighted = try #require(OneVariableStatistics(values: [1, 2, 3], frequencies: [1, 2, 3]))
        #expect(approx(expanded.mean, weighted.mean))
        #expect(approx(expanded.populationVariance, weighted.populationVariance))
        #expect(expanded.median == weighted.median)
    }

    @Test func linearRegression() throws {
        let points = [(1.0, 2.1), (2, 3.9), (3, 6.2), (4, 7.8), (5, 10.1)].map { DataPoint(x: $0.0, y: $0.1) }
        let fit = try Regression.fit(.linear, points: points)
        #expect(approx(fit.b, 1.99, 1e-3))
        #expect(approx(fit.a, 0.05, 1e-2))
        #expect((fit.r ?? 0) > 0.99)
        #expect(approx(fit.estimateX(fit.predict(3))[0], 3))
    }

    @Test func exponentialAndQuadraticRegression() throws {
        let exp = (0...5).map { DataPoint(x: Double($0), y: 3 * Foundation.exp(0.5 * Double($0))) }
        let e = try Regression.fit(.exponential, points: exp)
        #expect(approx(e.a, 3, 1e-9))
        #expect(approx(e.b, 0.5, 1e-9))
        let quad = (-3...3).map { DataPoint(x: Double($0), y: 1 + 2 * Double($0) - Double($0 * $0)) }
        let q = try Regression.fit(.quadratic, points: quad)
        #expect(approx(q.a, 1, 1e-9))
        #expect(approx(q.b, 2, 1e-9))
        #expect(approx(q.c ?? 0, -1, 1e-9))
        #expect(q.estimateX(1).count == 2)
    }

    @Test func distributions() throws {
        #expect(approx(try Distributions.binomialPMF(n: 10, p: 0.5, k: 3), 120.0 / 1024))
        #expect(approx(try Distributions.binomialCDF(n: 10, p: 0.5, k: 10), 1))
        #expect(approx(Distributions.normalCDF(1.959963984540054), 0.975, 1e-12))
        #expect(approx(try Distributions.inverseNormal(0.975), 1.959963984540054, 1e-12))
        #expect(approx(try Distributions.poissonPMF(lambda: 2, k: 0), Foundation.exp(-2)))
        #expect(approx(try value("binompdf(5, 0.2, 1)"), 5 * 0.2 * pow(0.8, 4)))
    }
}

// MARK: Parser extensions

@Suite struct ParserExtensionTests {
    @Test func inverseTrigShorthand() throws {
        #expect(try parse("sin^-1(1/2)") == .function(.asin, [.quotient(.int(1), .int(2))]))
        #expect(approx(try value("sin^2(x) + cos^2(x)", vars: ["x": 0.7]), 1))
    }

    @Test func greekLettersAndVectors() throws {
        #expect(try parse("alpha") == .variable("α"))
        #expect(try parse("gamma(5)") == .function(.gamma, [.int(5)]))
        #expect(try parse("(1, 2, 3)") == .matrix(rows: 3, columns: 1, entries: [.int(1), .int(2), .int(3)]))
    }

    @Test func piecewiseFunctions() throws {
        let f = try parse("piecewise(x^2, x < 0, x, 0 <= x < 2, 4)")
        #expect(try RealEvaluator.evaluate(f, context: EvaluationContext(variables: ["x": -3])) == 9)
        #expect(try RealEvaluator.evaluate(f, context: EvaluationContext(variables: ["x": 1])) == 1)
        #expect(try RealEvaluator.evaluate(f, context: EvaluationContext(variables: ["x": 5])) == 4)
        // The GPU/VM bytecode agrees with the tree evaluator.
        let program = try BytecodeCompiler(slots: ["x": .x]).compile(f)
        let vm = RealVM(program: program)
        for x in [-3.0, -0.5, 0, 1, 1.99, 2, 5] {
            #expect(vm.evaluate(x: x) == (try RealEvaluator.evaluate(f, context: EvaluationContext(variables: ["x": x]))))
        }
    }

    @Test func products() throws {
        #expect(try value("prod(n, n, 1, 5)") == 120)
        let partialSum = try BytecodeCompiler(slots: ["x": .x]).compile(try parse("sum(x^n/n!, n, 0, 8)"))
        #expect(approx(RealVM(program: partialSum).evaluate(x: 1), M_E, 1e-4))
    }
}

// MARK: Editor features

@Suite struct EditorFeatureTests {
    @Test func autoClosingParentheses() {
        var editor = MathEditor()
        editor.insert(.leftParenthesis)
        #expect(editor.root.nodes == [.symbol(.leftParenthesis), .symbol(.rightParenthesis)])
        #expect(editor.cursor.index == 1)
        editor.insert(.digit(2))
        editor.insert(.rightParenthesis)
        #expect(editor.root.nodes.count == 3)
        #expect(editor.cursor.index == 3)
    }

    @Test func toggleSign() {
        var editor = MathEditor()
        editor.insert(.digit(5))
        editor.toggleSign()
        #expect(MathRowConverter.plainText(editor.root) == "−5")
        editor.toggleSign()
        #expect(MathRowConverter.plainText(editor.root) == "5")
    }

    @Test func typingFunctionNames() throws {
        var editor = MathEditor()
        for letter in ["s", "i", "n", "h"] { editor.insertLetter(letter) }
        #expect(editor.root.nodes == [.function(.sinh, argument: MathRow())])
        var greek = MathEditor()
        for letter in ["a", "l", "p", "h", "a"] { greek.insertLetter(letter) }
        #expect(greek.root.nodes == [.symbol(.variable("α"))])
    }

    @Test func selectionWrapsIntoStructures() throws {
        var editor = MathEditor()
        for d in [1, 2] { editor.insert(.digit(d)) }
        editor.selectAll()
        editor.insertWrapping(.squareRoot(MathRow()))
        #expect(editor.root.nodes == [.squareRoot(MathRow([.symbol(.digit(1)), .symbol(.digit(2))]))])
    }

    @Test func matrixResize() throws {
        var editor = MathEditor()
        editor.insertMatrix(rows: 2, columns: 2)
        editor.insert(.digit(7))
        editor.resizeGrid(at: [], index: 0, rows: 3, columns: 3)
        guard case .matrix(let r, let c, let cells) = editor.root.nodes[0] else { Issue.record("matrix"); return }
        #expect(r == 3 && c == 3)
        #expect(cells[0].nodes == [.symbol(.digit(7))])
        #expect(cells.count == 9)
    }

    @Test func latexRoundTrip() throws {
        let row = try LaTeXConverter.row(fromLaTeX: #"\frac{1}{2}+\sqrt{x}\cdot\sin\left(\pi\right)"#)
        let expr = try MathRowConverter.expr(from: row)
        let value = try RealEvaluator.evaluate(expr, context: EvaluationContext(variables: ["x": 4]))
        #expect(approx(value, 0.5))
        let text = LaTeXConverter.latex(row)
        #expect(text.contains(#"\frac{1}{2}"#))
        let matrix = try LaTeXConverter.row(fromLaTeX: #"\begin{bmatrix} 1 & 2 \\ 3 & 4 \end{bmatrix}"#)
        guard case .matrix(2, 2, _) = matrix.nodes.first else { Issue.record("matrix"); return }
    }
}

// MARK: Tools

@Suite struct ToolTests {
    @Test func nBase() throws {
        #expect(BaseConversion.format(-1, base: .binary, bits: 8) == "11111111")
        #expect(BaseConversion.format(255, base: .hexadecimal, bits: 16) == "FF")
        #expect(try BaseConversion.parse("FF", base: .hexadecimal, bits: 8) == -1)
        #expect(try BaseConversion.evaluate("1010 AND 1100", base: .binary, bits: 8) == 0b1000)
        #expect(try BaseConversion.evaluate("NOT 0", base: .decimal, bits: 16) == -1)
        #expect(try BaseConversion.evaluate("A + 5 * 2", base: .hexadecimal, bits: 16) == 20)
        #expect(BaseConversion.format(7, base: .pental, bits: 32) == "12")
    }

    @Test func triangles() throws {
        let right = try TriangleSolver.solve(TriangleInput(a: 3, b: 4, c: 5))
        #expect(right.count == 1)
        #expect(right[0].isRight)
        #expect(approx(right[0].area, 6))
        // SSA with two solutions: a = 6, b = 8, α = 30°
        let ambiguous = try TriangleSolver.solve(TriangleInput(a: 6, b: 8, alpha: .pi / 6))
        #expect(ambiguous.count == 2)
        // SAS
        let sas = try TriangleSolver.solve(TriangleInput(b: 5, c: 7, alpha: .pi / 3))
        #expect(approx(sas[0].a, (25 + 49 - 35.0).squareRoot()))
    }

    @Test func sequencesAndFinance() {
        #expect(ArithmeticSequence(first: 1, difference: 1).sum(100) == 5050)
        #expect(GeometricSequence(first: 1, ratio: 0.5).infiniteSum == 2)
        #expect(approx(Finance.compound(principal: 1000, ratePercent: 5, years: 2), 1102.5))
        #expect(approx(Finance.loanPayment(principal: 1000, ratePercent: 0, periods: 4), 250))
    }

    @Test func linearSystems() throws {
        let a = Matrix(rows: 2, columns: 3, exact: [Rational(1), Rational(1), Rational(1), Rational(0), Rational(1), Rational(-1)])
        let b = Matrix(rows: 2, columns: 1, exact: [Rational(6), Rational(1)])
        if case .infinite(_, _, let free) = try LinearSystemSolver.solve(coefficients: a, constants: b) {
            #expect(free == [2])
        } else {
            Issue.record("expected infinitely many solutions")
        }
        let c = Matrix(rows: 2, columns: 2, exact: [Rational(1), Rational(1), Rational(1), Rational(1)])
        let d = Matrix(rows: 2, columns: 1, exact: [Rational(1), Rational(2)])
        if case .none = try LinearSystemSolver.solve(coefficients: c, constants: d) {} else { Issue.record("expected no solution") }
    }

    @Test func drill() {
        var generator = DrillGenerator(seed: 42)
        for _ in 0..<50 {
            let q = generator.next(.division, level: .medium)
            #expect(q.right != 0)
            #expect(q.left == q.answer * q.right)
        }
    }
}

// MARK: Formula sheets

@Suite struct FormulaTests {
    @Test func everyFormulaParses() {
        for subject in FormulaSubject.allCases {
            for section in FormulaLibrary.sections(subject) {
                for formula in section.formulas {
                    do {
                        let row = try LaTeXConverter.row(fromLaTeX: formula.latex)
                        #expect(!row.isEmpty, "\(formula.title) is empty")
                    } catch {
                        Issue.record("\(subject.rawValue) – \(formula.title): \(error)")
                    }
                }
            }
        }
    }
}

// MARK: Framing implicit curves

@Suite struct ImplicitBoundsTests {
    func program(_ s: String) throws -> Program {
        guard case .relation(let lhs, _, let rhs) = try parse(s) else { throw MathError.syntax("ni relacija") }
        return try BytecodeCompiler(slots: ["x": .x, "y": .y]).compile(.sum([lhs, .negation(rhs)]))
    }

    @Test func circleIsFramed() throws {
        let box = try #require(ImplicitBounds.find(program: program("x^2+y^2=9"), x: -12...12, y: -9...9))
        #expect(box.isBounded)
        #expect(abs(box.x.lowerBound + 3) < 0.3 && abs(box.x.upperBound - 3) < 0.3)
        #expect(abs(box.y.lowerBound + 3) < 0.3 && abs(box.y.upperBound - 3) < 0.3)
    }

    @Test func shiftedEllipseIsFramed() throws {
        let box = try #require(ImplicitBounds.find(program: program("(x-2)^2/16+(y+1)^2/4=1"), x: -20...20, y: -15...15))
        #expect(box.isBounded)
        #expect(abs(box.x.lowerBound + 2) < 0.5 && abs(box.x.upperBound - 6) < 0.5)
        #expect(abs(box.y.lowerBound + 3) < 0.5 && abs(box.y.upperBound - 1) < 0.5)
    }

    @Test func lineReachesTheWindowEdge() throws {
        let box = try #require(ImplicitBounds.find(program: program("y=2x+1"), x: -10...10, y: -10...10))
        #expect(!box.isBounded)
    }

    @Test func emptyRelationHasNoCurve() throws {
        let empty = try program("x^2+y^2=-1")
        #expect(ImplicitBounds.find(program: empty, x: -5...5, y: -5...5) == nil)
    }
}

// MARK: Complex-plane sets and chains of inequalities

@Suite struct PlaneSetTests {
    func value(_ e: Expr, x: Double, y: Double) throws -> Double {
        try RealEvaluator.evaluate(e, context: EvaluationContext(variables: ["x": x, "y": y]))
    }

    func plane(_ s: String) throws -> (lhs: Expr, op: RelationOperator, rhs: Expr) {
        guard case .relation(let lhs, let op, let rhs) = try parse(s) else { throw MathError.syntax("ni relacija") }
        let real = try #require(PlaneSets.complexRelation(lhs, rhs))
        return (real.lhs, op, real.rhs)
    }

    @Test func discAroundOne() throws {
        let set = try plane("|z-1|<=2")
        #expect(set.op == .lessOrEqual)
        #expect(abs(try value(set.lhs, x: 1, y: 2) - 2) < 1e-12)
        #expect(abs(try value(set.lhs, x: 4, y: 0) - 3) < 1e-12)
    }

    @Test func realPartIsX() throws {
        let set = try plane("Re z >= -2")
        #expect(abs(try value(set.lhs, x: 5, y: 7) - 5) < 1e-12)
        #expect(abs(try value(set.rhs, x: 5, y: 7) + 2) < 1e-12)
    }

    @Test func quotientOfComplexNumbers() throws {
        // Re(1/z) at z = 1 + i is 1/2.
        let set = try plane("Re(1/z)=1/2")
        #expect(abs(try value(set.lhs, x: 1, y: 1) - 0.5) < 1e-12)
    }

    @Test func calculatorDrawsComplexSets() throws {
        let calculation = CalculationEngine.calculate(try parse("|z+i|<3"), variables: [:], exactVariables: [:], settings: CalculationSettings())
        guard case .implicit? = calculation.graph?.kinds.first else {
            Issue.record("no region for |z + i| < 3")
            return
        }
    }

    @Test func chainBecomesRegion() throws {
        let request = try #require(CalculationEngine.graphRequest(for: try parse("-1<=y<2")))
        guard case .implicit(let lhs, let relation, _)? = request.kinds.first else {
            Issue.record("no region")
            return
        }
        #expect(relation == .greaterOrEqual)
        #expect(try value(lhs, x: 0, y: 0) > 0)
        #expect(try value(lhs, x: 0, y: 3) < 0)
    }

    @Test func annulusInComplexPlane() throws {
        let request = try #require(CalculationEngine.graphRequest(for: try parse("1<=|z|<=2")))
        guard case .implicit(let lhs, _, _)? = request.kinds.first else {
            Issue.record("no annulus")
            return
        }
        #expect(try value(lhs, x: 1.5, y: 0) > 0)
        #expect(try value(lhs, x: 0.5, y: 0) < 0)
        #expect(try value(lhs, x: 0, y: 2.5) < 0)
    }
}

// MARK: f(x) = … definitions

@Suite struct FunctionDefinitionTests {
    @Test func definitionIsAGraph() throws {
        let expr = try parse("f(x)=x^2-4")
        let body = try parse("x^2-4")
        #expect(expr == .relation(.y, .equal, body))
    }

    @Test func otherVariablesBecomeX() throws {
        let expr = try parse("v(t)=2+3t")
        let body = try parse("2+3x")
        #expect(expr == .relation(.y, .equal, body))
    }

    @Test func subscriptedName() throws {
        let expr = try parse("f_1(x)=sin x")
        guard case .relation(.variable("y"), .equal, _) = expr else {
            Issue.record("f₁(x) = sin x is not a graph")
            return
        }
    }

    @Test func productIsNotADefinition() throws {
        // a(x − 1) = 3 stays an equation with a parameter.
        guard case .relation(.product, .equal, _) = try parse("a(x-1)=3") else {
            Issue.record("a(x − 1) = 3 changed meaning")
            return
        }
    }
}

// MARK: Systems and branches of implicit curves

@Suite struct SystemTests {
    func value(_ e: Expr, x: Double, y: Double = 0) throws -> Double {
        try RealEvaluator.evaluate(e, context: EvaluationContext(variables: ["x": x, "y": y]))
    }

    func sides(_ s: String) throws -> (Expr, Expr) {
        guard case .relation(let lhs, _, let rhs) = try parse(s) else { throw MathError.syntax("ni relacija") }
        return (lhs, rhs)
    }

    func system(_ s: String) throws -> [Expr]? {
        let tokens = try Lexer().tokenize(s)
        return Parser.parseSystem(tokens: tokens)
    }

    @Test func circleHasTwoBranches() throws {
        let (lhs, rhs) = try sides("x^2+y^2=25")
        let branches = try #require(ImplicitBranches.branches(lhs, rhs))
        #expect(branches.count == 2)
        let ys = try branches.map { try value($0, x: 3) }.sorted()
        #expect(abs(ys[0] + 4) < 1e-9 && abs(ys[1] - 4) < 1e-9)
    }

    @Test func lineInGeneralForm() throws {
        let (lhs, rhs) = try sides("2x+y=3")
        let branches = try #require(ImplicitBranches.branches(lhs, rhs))
        #expect(branches.count == 1)
        #expect(abs(try value(branches[0], x: 1) - 1) < 1e-12)
    }

    @Test func cubicInYHasNoBranches() throws {
        let (lhs, rhs) = try sides("y^3+x=1")
        #expect(ImplicitBranches.branches(lhs, rhs) == nil)
    }

    @Test func inequalitiesFormOneRegion() throws {
        let relations = try #require(try system("x>=0, y>=0, x+y<=4"))
        #expect(relations.count == 3)
        let request = try #require(CalculationEngine.systemGraph(relations))
        #expect(request.kinds.count == 1)
        guard case .implicit(let region, _, _)? = request.kinds.first else {
            Issue.record("no region")
            return
        }
        #expect(try value(region, x: 1, y: 1) > 0)
        #expect(try value(region, x: 3, y: 3) < 0)
        #expect(try value(region, x: -1, y: 1) < 0)
    }

    @Test func equationsAreCurvesWithIntersections() throws {
        let relations = try #require(try system("y=2x+1, y=4-x"))
        let request = try #require(CalculationEngine.systemGraph(relations))
        #expect(request.kinds.count == 2)
        #expect(request.highlightIntersections)
    }

    @Test func equationWithInequalityIsRestricted() throws {
        let relations = try #require(try system("x^2+y^2=4, y>=0"))
        let request = try #require(CalculationEngine.systemGraph(relations))
        #expect(request.kinds.count == 1)
        guard case .implicit(let curve, .equal, _)? = request.kinds.first else {
            Issue.record("no curve")
            return
        }
        #expect(abs(try value(curve, x: 0, y: 2)) < 1e-12)
        let below = try? value(curve, x: 0, y: -2)
        #expect(below == nil || below!.isNaN)
    }

    @Test func tuplesAreNotSystems() throws {
        #expect(try system("(1, 2)") == nil)
        #expect(try system("nCr(5, 2)") == nil)
    }
}

// MARK: Line through the origin (physics measurements)

@Suite struct ProportionalFitTests {
    @Test func slopeThroughOrigin() throws {
        let points = [(1.0, 2.1), (2, 3.9), (3, 6.2)].map { DataPoint(x: $0.0, y: $0.1) }
        let fit = try Regression.fit(.proportional, points: points)
        #expect(fit.a == 0)
        #expect(abs(fit.b - 28.5 / 14) < 1e-12)
        #expect(abs(fit.predict(10) - 10 * 28.5 / 14) < 1e-9)
        #expect(fit.estimateX(fit.b * 4).first.map { abs($0 - 4) < 1e-12 } == true)
    }
}

// MARK: Complex numbers and vectors in the plane

@Suite struct PlaneFigureTests {
    func graph(_ s: String) throws -> GraphRequest? {
        CalculationEngine.calculate(try parse(s), variables: [:], exactVariables: [:], settings: CalculationSettings()).graph
    }

    @Test func complexSumShowsParallelogram() throws {
        let request = try #require(try graph("(2+3i)+(1-i)"))
        #expect(request.kinds.count == 5)
        guard case .segment(_, _, let x1, let y1, true)? = request.kinds.first else {
            Issue.record("no arrow")
            return
        }
        #expect(x1 == .decimal(3) && y1 == .decimal(2))
        let allFigures = request.kinds.allSatisfy { $0.isFigure }
        #expect(allFigures)
    }

    @Test func complexProductIsOneArrow() throws {
        let request = try #require(try graph("(1+i)*(1+i)"))
        #expect(request.kinds.count == 1)
    }

    @Test func planeVectorIsAnArrow() throws {
        let request = try #require(try graph("(1,2)+(3,1)"))
        #expect(request.kinds.count == 5)
    }
}

// MARK: Sequences as points

@Suite struct SequenceGraphTests {
    func graph(_ s: String) throws -> GraphRequest? {
        CalculationEngine.calculate(try parse(s), variables: [:], exactVariables: [:], settings: CalculationSettings()).graph
    }

    @Test func subscriptDefinition() throws {
        let request = try #require(try graph("a_n=2n+1"))
        guard case .sequence? = request.kinds.first else {
            Issue.record("a_n = 2n + 1 is not a sequence")
            return
        }
        #expect(request.parameters.isEmpty)
    }

    @Test func functionNotationIsASequence() throws {
        guard case .relation(.variable("a_n"), .equal, _) = try parse("a(n)=n^2") else {
            Issue.record("a(n) = n² is not a_n")
            return
        }
    }

    @Test func expressionInNAlone() throws {
        let request = try #require(try graph("1/n"))
        guard case .sequence? = request.kinds.first else {
            Issue.record("1/n is not a sequence")
            return
        }
    }
}

// MARK: Amortization plan and period rates

@Suite struct AmortizationTests {
    @Test func planRepaysTheLoan() {
        let rows = Finance.amortizationPlan(principal: 10_000, ratePercent: 1, periods: 12)
        #expect(rows.count == 12)
        let payment = Finance.loanPayment(principal: 10_000, ratePercent: 1, periods: 12)
        #expect(abs(rows[0].interest - 100) < 1e-9)
        #expect(abs(rows[0].repayment - (payment - 100)) < 1e-9)
        #expect(rows.last?.remaining == 0)
        #expect(abs(rows.reduce(0) { $0 + $1.repayment } - 10_000) < 1e-6)
    }

    @Test func conformalRateKeepsYearlyGrowth() {
        let monthly = Finance.periodRate(annualPercent: 6, periodsPerYear: 12, conformal: true)
        #expect(abs(pow(1 + monthly / 100, 12) - 1.06) < 1e-12)
        #expect(Finance.periodRate(annualPercent: 6, periodsPerYear: 12, conformal: false) == 0.5)
    }
}

// MARK: Angle between intersecting curves

@Suite struct IntersectionAngleTests {
    @Test func anglesFromSlopes() throws {
        let right = try #require(SpecialPoint.intersectionAngle(slope: 1, slope: -1))
        #expect(abs(right - .pi / 2) < 1e-12)
        let half = try #require(SpecialPoint.intersectionAngle(slope: 0, slope: 1))
        #expect(abs(half - .pi / 4) < 1e-12)
        let vertical = try #require(SpecialPoint.intersectionAngle(slope: .infinity, slope: 0))
        #expect(abs(vertical - .pi / 2) < 1e-12)
        #expect(SpecialPoint.intersectionAngle(slope: .nan, slope: 0) == nil)
    }
}

// MARK: Using functions defined in other rows

@Suite struct DefinedFunctionTests {
    func value(_ e: Expr, x: Double) throws -> Double {
        try RealEvaluator.evaluate(e, context: EvaluationContext(variables: ["x": x]))
    }

    @Test func shiftedCopyOfAnotherFunction() throws {
        let options = ParserOptions(functions: ["f": try parse("x^2")])
        guard case .relation(.variable("y"), .equal, let body) = try Parser.parse("g(x)=f(x-2)+1", options: options) else {
            Issue.record("g(x) = f(x − 2) + 1 is not a graph")
            return
        }
        #expect(abs(try value(body, x: 5) - 10) < 1e-12)
    }

    @Test func definitionsFromRows() throws {
        let rows = try ["f(x)=x^{2}", "g(x)=f(x-2)+1", "y=3x"].map { try LaTeXConverter.row(fromLaTeX: $0) }
        let functions = CalculationEngine.definedFunctions(rows)
        #expect(functions.count == 2)
        let g = try #require(functions["g"])
        #expect(abs(try value(g, x: 5) - 10) < 1e-12)
    }

    @Test func calculatorEvaluatesDefinedFunction() throws {
        let row = try LaTeXConverter.row(fromLaTeX: "f(2)")
        let calculation = CalculationEngine.calculate(row, variables: [:], exactVariables: [:],
                                                      functions: ["f": try parse("x^2+1")], settings: CalculationSettings())
        guard case .number(let result) = calculation.outcome else {
            Issue.record("f(2) did not evaluate")
            return
        }
        #expect(result.value == 5)
    }
}

// MARK: Points and polygons

@Suite struct PointTests {
    func system(_ s: String) throws -> [Expr]? {
        Parser.parseSystem(tokens: try Lexer().tokenize(s))
    }

    @Test func namedPointIsDrawn() throws {
        let calculation = CalculationEngine.calculate(try parse("A(2,3)"), variables: [:], exactVariables: [:], settings: CalculationSettings())
        guard case .point(let x, let y)? = calculation.graph?.kinds.first else {
            Issue.record("A(2, 3) is not a point")
            return
        }
        #expect(x == .int(2) && y == .int(3))
    }

    @Test func triangleFromPoints() throws {
        let parts = try #require(try system("A(1,2), B(4,5), C(6,1)"))
        let request = try #require(CalculationEngine.systemGraph(parts))
        guard case .polyline(let coordinates, let closed)? = request.kinds.first else {
            Issue.record("no triangle")
            return
        }
        #expect(closed && coordinates.count == 6)
        #expect(request.kinds.count == 4)
    }

    @Test func storedVariableStillMultiplies() throws {
        let calculation = CalculationEngine.calculate(try parse("A(2,3)"), variables: ["A": 2], exactVariables: [:], settings: CalculationSettings())
        guard case .matrix? = Optional(calculation.outcome) else {
            Issue.record("A·(2, 3) with A = 2 should be a vector")
            return
        }
    }
}

@Suite struct DataPolygonTests {
    @Test func unnamedPointsAreAnOpenPolyline() throws {
        let parts = try #require(Parser.parseSystem(tokens: try Lexer().tokenize("(1,9), (2,15), (3,12), (4,6)")))
        let request = try #require(CalculationEngine.systemGraph(parts))
        guard case .polyline(let coordinates, let closed)? = request.kinds.first else {
            Issue.record("no polyline")
            return
        }
        #expect(!closed && coordinates.count == 8)
    }
}

// MARK: Ends of piecewise functions

@Suite struct PiecewiseEndpointTests {
    @Test func jumpHasOpenAndClosedEnds() {
        // x for x < 1, 2 for x ≥ 1
        let f = Expr.piecewise([.x, .relation(.x, .less, .one), .int(2), .relation(.x, .greaterOrEqual, .one)])
        let ends = PiecewiseEndpoints.points(f, context: EvaluationContext())
        #expect(ends.contains { $0.kind == .openEnd && $0.x == 1 && $0.y == 1 })
        #expect(ends.contains { $0.kind == .closedEnd && $0.x == 1 && $0.y == 2 })
    }

    @Test func continuousJoinIsOneFilledPoint() {
        // x for x ≤ 1, 2 − x for x > 1
        let f = Expr.piecewise([.x, .relation(.x, .lessOrEqual, .one), .int(2) - .x, .relation(.x, .greater, .one)])
        let ends = PiecewiseEndpoints.points(f, context: EvaluationContext())
        #expect(ends.count == 1)
        #expect(ends.first?.kind == .closedEnd)
    }

    @Test func intervalCondition() {
        // −1 ≤ x < 3 on a single piece: closed at −1, open at 3
        let f = Expr.piecewise([.x, .relation(.relation(.int(-1), .lessOrEqual, .x), .less, .int(3))])
        let ends = PiecewiseEndpoints.points(f, context: EvaluationContext())
        #expect(ends.contains { $0.kind == .closedEnd && $0.x == -1 })
        #expect(ends.contains { $0.kind == .openEnd && $0.x == 3 })
    }
}

@Suite struct PolygonMeasureTests {
    /// A row as typed on the keypad: letters, digits, parentheses and the comma key.
    func keypadRow(_ text: String) -> MathRow {
        MathRow(text.compactMap { c -> MathNode? in
            switch c {
            case "(": return .symbol(.leftParenthesis)
            case ")": return .symbol(.rightParenthesis)
            case ",": return .symbol(.comma)
            case "0"..."9": return .symbol(.digit(Int(String(c))!))
            case " ": return nil
            default: return .symbol(.variable(String(c)))
            }
        })
    }

    func calculate(_ text: String) -> CalculationOutcome {
        CalculationEngine.calculate(keypadRow(text), variables: [:], exactVariables: [:], settings: CalculationSettings()).outcome
    }

    @Test func triangleAreaAndPerimeter() {
        guard case .special(.polygon(let area, let perimeter), _) = calculate("A(0,0), B(4,0), C(0,3)") else {
            Issue.record("no polygon measures")
            return
        }
        #expect(abs(area - 6) < 1e-12)
        #expect(abs(perimeter - 12) < 1e-12)
    }

    @Test func segmentLength() {
        guard case .special(.segmentLength(let d), _) = calculate("A(1,2), B(4,6)") else {
            Issue.record("no segment length")
            return
        }
        #expect(abs(d - 5) < 1e-12)
    }
}

// MARK: Physics measurements: linearisation and the area under a broken line

@Suite struct MeasurementTests {
    @Test func squaredPeriodAgainstLengthIsALine() throws {
        // t0² = (4π²/g)·l: with t0 squared the points lie on a line through the origin.
        let l = [0.25, 0.5, 0.75, 1.0, 1.5]
        let data = l.map { DataPoint(x: $0, y: 2 * Double.pi * ($0 / 9.81).squareRoot()) }
        let points = AxisTransform.transform(data, x: .none, y: .square)
        let fit = try Regression.fit(.proportional, points: points)
        #expect(abs(fit.b - 4 * Double.pi * Double.pi / 9.81) < 1e-9)
        #expect(AxisTransform.reciprocal.label("V") == "1/V")
    }

    @Test func areaUnderVelocityGraph() {
        let v = [(0.0, 0.0), (4, 12), (10, 12), (12, 0)].map { DataPoint(x: $0.0, y: $0.1) }
        #expect(TwoVariableStatistics.areaUnderPolyline(v) == 108)
    }
}

// MARK: Derivative and integral function of piecewise graphs (a(t) and x(t) from v(t))

@Suite struct PiecewiseCalculusTests {
    // v(t) = 3t for t < 4, 12 for t ≥ 4
    let v = Expr.piecewise([.product([.int(3), .x]), .relation(.x, .less, .int(4)), .int(12), .relation(.x, .greaterOrEqual, .int(4))])

    @Test func accelerationIsPiecewiseConstant() throws {
        let a = try Differentiator.derivative(of: v, withRespectTo: "x")
        #expect(abs(try RealEvaluator.evaluate(a, context: EvaluationContext(variables: ["x": 2])) - 3) < 1e-12)
        #expect(abs(try RealEvaluator.evaluate(a, context: EvaluationContext(variables: ["x": 6]))) < 1e-12)
    }

    @Test func distanceIsTheIntegralFunction() throws {
        let x = Expr.integral(v.substituting("x", with: .variable("τ")), variable: "τ", lower: .zero, upper: .x)
        // 0.5·4·12 + 2·12 = 48 at t = 6
        #expect(abs(try RealEvaluator.evaluate(x, context: EvaluationContext(variables: ["x": 6])) - 48) < 1e-6)
    }
}

// MARK: Inequalities as intervals

@Suite struct InequalityTests {
    func solve(_ s: String) throws -> InequalitySolution {
        guard case .relation(let lhs, let op, let rhs) = try parse(s) else { throw MathError.syntax("ni neenačba") }
        return try #require(InequalitySolver.solve(lhs, op, rhs, context: EvaluationContext()))
    }

    @Test func quadraticOutside() throws {
        let s = try solve("x^2-4>0")
        try #require(s.intervals.count == 2)
        #expect(s.intervals[0].lower == -.infinity && s.intervals[0].upper == -2 && !s.intervals[0].upperIncluded)
        #expect(s.intervals[1].lower == 2 && s.intervals[1].upper == .infinity)
    }

    @Test func quadraticInsideClosed() throws {
        let s = try solve("x^2<=9")
        try #require(s.intervals.count == 1)
        #expect(s.intervals[0].lower == -3 && s.intervals[0].upper == 3 && s.intervals[0].lowerIncluded && s.intervals[0].upperIncluded)
    }

    @Test func rationalExcludesThePole() throws {
        // (x − 1)/(x + 2) ≥ 0 → (−∞, −2) ∪ [1, ∞)
        let s = try solve("(x-1)/(x+2)>=0")
        try #require(s.intervals.count == 2)
        #expect(s.intervals[0].upper == -2 && !s.intervals[0].upperIncluded)
        #expect(s.intervals[1].lower == 1 && s.intervals[1].lowerIncluded)
    }

    @Test func squareRootDomain() throws {
        // √x ≤ 2 → [0, 4]
        let s = try solve("sqrt(x)<=2")
        try #require(s.intervals.count == 1)
        #expect(abs(s.intervals[0].lower) < 1e-9 && s.intervals[0].lowerIncluded)
        #expect(abs(s.intervals[0].upper - 4) < 1e-9 && s.intervals[0].upperIncluded)
    }

    @Test func singlePointAndEverything() throws {
        let point = try solve("x^2<=0")
        #expect(point.intervals.count == 1 && point.intervals[0].isPoint)
        #expect(try solve("x^2+1>0").isAllReals)
        #expect(try solve("x^2+1<0").isEmpty)
    }
}

@Suite struct InequalitySystemTests {
    @Test func systemInOneUnknown() throws {
        let parts = try #require(Parser.parseSystem(tokens: try Lexer().tokenize("x^2-4<0, x>1")))
        guard case .inequality(let s)? = CalculationEngine.inequalitySystem(parts, variables: [:]) else {
            Issue.record("no solution of the system")
            return
        }
        try #require(s.intervals.count == 1)
        #expect(s.intervals[0].lower == 1 && s.intervals[0].upper == 2)
        #expect(!s.intervals[0].lowerIncluded && !s.intervals[0].upperIncluded)
    }

    @Test func chainInOneUnknown() throws {
        let calculation = CalculationEngine.calculate(try parse("-2<2x-1<=5"), variables: [:], exactVariables: [:], settings: CalculationSettings())
        guard case .inequality(let s) = calculation.outcome else {
            Issue.record("no solution of the chain")
            return
        }
        try #require(s.intervals.count == 1)
        #expect(s.intervals[0].lower == -0.5 && s.intervals[0].upper == 3)
        #expect(!s.intervals[0].lowerIncluded && s.intervals[0].upperIncluded)
    }
}

@Suite struct TimeGraphTests {
    @Test func expressionInTIsDrawnAgainstT() throws {
        let calculation = CalculationEngine.calculate(try parse("20cos(pi*t/3)"), variables: [:], exactVariables: [:], settings: CalculationSettings())
        guard case .explicit(let curve)? = calculation.graph?.kinds.first else {
            Issue.record("no graph against t")
            return
        }
        #expect(abs(try RealEvaluator.evaluate(curve, context: EvaluationContext(variables: ["x": 3])) + 20) < 1e-9)
        #expect(calculation.graph?.parameters.isEmpty == true)
    }
}

// MARK: Electrical engineering: phasors, parallel connections, j, linear systems

@Suite struct ElectricalTests {
    func outcome(_ s: String, unit: AngleUnit = .degrees, j: Bool = false) throws -> CalculationOutcome {
        let expr = try Parser.parse(s, options: ParserOptions(imaginaryUnitJ: j))
        return CalculationEngine.calculate(expr, variables: [:], exactVariables: [:],
                                           settings: CalculationSettings(angleUnit: unit, imaginaryUnitJ: j)).outcome
    }

    @Test func phasorInDegrees() throws {
        guard case .complex(let c) = try outcome("10∠90") else {
            Issue.record("10∠90° is not complex")
            return
        }
        #expect(abs(c.re) < 1e-9 && abs(c.im - 10) < 1e-9)
    }

    @Test func parallelResistors() throws {
        guard case .number(let r) = try outcome("6∥3") else {
            Issue.record("6∥3 is not a number")
            return
        }
        #expect(abs(r.value - 2) < 1e-12)
    }

    @Test func jIsTheImaginaryUnit() throws {
        guard case .complex(let c) = try outcome("2+3j", j: true) else {
            Issue.record("2 + 3j is not complex")
            return
        }
        #expect(c.re == 2 && c.im == 3)
    }

    @Test func exactLinearSystem() throws {
        let relations = try #require(Parser.parseSystem(tokens: try Lexer().tokenize("2x+y=5, x-y=1")))
        let solution = try #require(try LinearEquations.solve(relations, variables: [:], angleUnit: .radians))
        #expect(solution.unknowns == ["x", "y"])
        #expect(solution.exact == [Rational(2), Rational(1)])
    }

    @Test func complexNodeEquations() throws {
        // (1 + i)U₁ − U₂ = 1, −U₁ + 2U₂ = i → U₁ = 0,8 − 0,6i, U₂ = 0,4 + 0,2i
        let relations = try #require(Parser.parseSystem(tokens: try Lexer().tokenize("(1+i)U_1-U_2=1, -U_1+2U_2=i")))
        let solution = try #require(try LinearEquations.solve(relations, variables: [:], angleUnit: .radians))
        #expect(solution.unknowns == ["U_1", "U_2"])
        #expect((solution.values[0] - Complex(0.8, -0.6)).magnitude < 1e-12)
        #expect((solution.values[1] - Complex(0.4, 0.2)).magnitude < 1e-12)
    }

    @Test func singularSystemIsReported() throws {
        let relations = try #require(Parser.parseSystem(tokens: try Lexer().tokenize("x+y=1, 2x+2y=3")))
        #expect(throws: MathError.self) { _ = try LinearEquations.solve(relations, variables: [:], angleUnit: .radians) }
    }
}

// MARK: Expanding powers of sums (y = (x + 1)⁵ overflowed the stack in the graph analysis)

@Suite struct ExpansionTests {
    @Test func powerOfASumIsMultipliedOut() throws {
        let p = try #require(Polynomial.extract(from: try parse("(x+1)^5"), variable: "x"))
        #expect(p.exactCoefficients == [1, 5, 10, 10, 5, 1].map { Rational($0) })
    }

    @Test func productOfPowersIsMultipliedOut() throws {
        // x(x − 2)²(x + 3) = x⁴ − x³ − 8x² + 12x
        let p = try #require(Polynomial.extract(from: try parse("x(x-2)^2(x+3)"), variable: "x"))
        #expect(p.exactCoefficients == [0, 12, -8, -1, 1].map { Rational($0) })
    }

    @Test func graphOfAPowerOfASumIsAnalysed() throws {
        let analysis = FunctionAnalyzer.analyze(try parse("(x+1)^5-3"), range: -6...6, context: EvaluationContext())
        try #require(analysis.zeros.count == 1)
        #expect(abs(analysis.zeros[0].x - (pow(3, 0.2) - 1)) < 1e-9)
        #expect(analysis.inflections.map(\.x) == [-1])
    }

    @Test func equationWithAPowerOfASumIsSolved() throws {
        let calculation = CalculationEngine.calculate(try parse("(x+1)^2=4"), variables: [:], exactVariables: [:], settings: CalculationSettings())
        guard case .solutions(let s) = calculation.outcome else {
            Issue.record("(x + 1)² = 4 has no solutions")
            return
        }
        #expect(s.solutions.map(\.value).sorted() == [-3, 1])
    }
}

// MARK: Indefinite integrals (Matematika I)

@Suite struct AntiderivativeTests {
    /// First-year integrals: table, substitution, by parts, partial fractions, trigonometric
    /// powers, t = tan(x/2), eˣ substitution and radicals. A result is only returned after
    /// F′ = f was checked, so success here means a correct antiderivative.
    static let integrands = [
        "x^3-2x+5", "1/x", "1/x^2", "sqrt(x)", "1/sqrt(x)", "(2x+3)^10", "e^(3x)", "2^x",
        "sin(2x)", "cos(x/2)", "tan(x)", "1/cos(x)^2", "1/(1+x^2)", "1/sqrt(1-x^2)", "1/(x^2+4)",
        "x*e^x", "x^2*e^(-x)", "x*sin(x)", "x^2*cos(3x)", "ln(x)", "x*ln(x)", "ln(x)^2", "atan(x)", "x*atan(x)",
        "e^x*sin(x)", "e^(2x)*cos(3x)",
        "2x*cos(x^2)", "x*e^(x^2)", "ln(x)/x", "1/(x*ln(x))", "x/(x^2+1)", "x*sqrt(x^2+1)", "x/sqrt(1-x^2)",
        "sin(x)*cos(x)", "sin(x)^2", "cos(x)^2", "sin(x)^3", "sin(x)^2*cos(x)^2", "tan(x)^2", "sin(3x)*cos(2x)",
        "1/(x^2-1)", "(3x+1)/(x^2+2x+5)", "1/(x*(x+1)^2)", "1/(x^3+1)", "(x^3+1)/(x^2-1)", "1/(x^4-1)",
        "1/((x^2+1)*(x^2+4))", "1/(x^2+1)^2",
        "sqrt(1-x^2)", "sqrt(x^2+1)", "1/sqrt(x^2+2x+5)", "x*sqrt(x+1)",
        "e^x/(1+e^(2x))", "1/(1+e^x)", "1/(2+cos(x))", "1/(1+sin(x))", "sinh(x)", "x*cosh(x)",
    ]

    @Test(arguments: integrands)
    func integrates(_ text: String) throws {
        #expect(Antiderivative.integrate(try parse(text)) != nil, "∫ \(text) dx")
    }

    @Test(arguments: [("1/(x^2-1)", 2.0, 3.0), ("x*e^x", 0, 1), ("(3x+1)/(x^2+2x+5)", 0, 2), ("1/(x^2+1)^2", 0, 1),
                      ("sqrt(1-x^2)", 0, 0.5), ("1/(2+cos(x))", 0, 1), ("sin(x)^2*cos(x)^2", 0, 1), ("x*sqrt(x+1)", 0, 3),
                      ("e^x/(1+e^(2x))", 0, 1), ("1/(x^4-1)", 2, 3)])
    func matchesTheDefiniteIntegral(_ text: String, _ a: Double, _ b: Double) throws {
        let f = try parse(text)
        let F = try #require(Antiderivative.integrate(f))
        func value(_ x: Double) throws -> Double { try RealEvaluator.evaluate(F, context: EvaluationContext(variables: ["x": x])) }
        let exact = try value(b) - value(a)
        let numeric = try Integrator.integrate(f, variable: "x", from: a, to: b, context: EvaluationContext())
        #expect(abs(exact - numeric) < 1e-8 * max(1, abs(numeric)), "∫ \(text) dx from \(a) to \(b)")
    }

    @Test func nonElementaryIntegralsAreRejected() throws {
        #expect(Antiderivative.integrate(try parse("e^(x^2)")) == nil)
        #expect(Antiderivative.integrate(try parse("sin(x)/x")) == nil)
    }

    @Test func degreesUseTheCalculatorsUnit() throws {
        // ∫ sin x dx = −(180/π)·cos x when x is in degrees
        let F = try #require(Antiderivative.integrate(try parse("sin(x)"), angleUnit: .degrees))
        let derivative = try Differentiator.derivative(of: F, withRespectTo: "x", angleUnit: .degrees)
        let value = try RealEvaluator.evaluate(derivative, context: EvaluationContext(angleUnit: .degrees, variables: ["x": 40]))
        #expect(abs(value - sin(40 * Double.pi / 180)) < 1e-12)
    }

    @Test func calculatorShowsFPlusC() throws {
        let expr = Expr.integral(try parse("x*e^x"), variable: "x", lower: nil, upper: nil)
        let calculation = CalculationEngine.calculate(expr, variables: [:], exactVariables: [:], settings: CalculationSettings())
        guard case .symbolic(let result) = calculation.outcome else {
            Issue.record("∫ x·eˣ dx has no antiderivative")
            return
        }
        #expect(result.freeVariables.contains("C"))
        #expect(calculation.graph?.kinds.count == 2)
    }
}

// MARK: Linear algebra: eigenvalues, eigenvectors, null space

@Suite struct EigenTests {
    func matrix(_ rows: [[Int]]) -> Matrix {
        Matrix(rows: rows.count, columns: rows[0].count, exact: rows.flatMap { $0.map { Rational($0) } })
    }

    @Test func symmetricTwoByTwo() throws {
        // [[2, 1], [1, 2]]: λ = 1 with (1, −1), λ = 3 with (1, 1)
        let e = try EigenDecomposition(matrix([[2, 1], [1, 2]]))
        #expect(e.eigenvalues.map(\.exact) == [.number(Rational(1)), .number(Rational(3))])
        #expect(e.eigenvalues[0].exactVectors == [[Rational(1), Rational(-1)]])
        #expect(e.eigenvalues[1].exactVectors == [[Rational(1), Rational(1)]])
        #expect(e.isDiagonalizable)
    }

    @Test func characteristicPolynomialIsDetOfAMinusLambdaI() throws {
        let e = try EigenDecomposition(matrix([[2, 1], [1, 2]]))
        // λ² − 4λ + 3 at λ = 5
        #expect(try RealEvaluator.evaluate(e.characteristicPolynomial, context: EvaluationContext(variables: ["λ": 5])) == 8)
        // det(A − 0·I) = det A, also for odd sizes
        let e3 = try EigenDecomposition(matrix([[1, 0, 0], [0, 2, 0], [0, 0, 3]]))
        #expect(try RealEvaluator.evaluate(e3.characteristicPolynomial, context: EvaluationContext(variables: ["λ": 0])) == 6)
    }

    @Test func repeatedEigenvalueWithTooFewVectors() throws {
        // [[1, 1], [0, 1]]: λ = 1 twice with one eigenvector
        let e = try EigenDecomposition(matrix([[1, 1], [0, 1]]))
        try #require(e.eigenvalues.count == 1)
        #expect(e.eigenvalues[0].multiplicity == 2)
        #expect(e.eigenvalues[0].exactVectors == [[Rational(1), Rational(0)]])
        #expect(!e.isDiagonalizable)
    }

    @Test func rotationHasComplexEigenvalues() throws {
        // [[0, −1], [1, 0]]: λ = ±i, and A·v = λ·v
        let e = try EigenDecomposition(matrix([[0, -1], [1, 0]]))
        try #require(e.eigenvalues.count == 2)
        #expect(e.eigenvalues.allSatisfy { abs($0.value.re) < 1e-12 && abs(abs($0.value.im) - 1) < 1e-12 })
        let lambda = e.eigenvalues[0].value
        let v = try #require(e.eigenvalues[0].vectors.first)
        #expect((Complex(-1) * v[1] - lambda * v[0]).magnitude < 1e-9)
        #expect((v[0] - lambda * v[1]).magnitude < 1e-9)
    }

    @Test func irrationalEigenvaluesAreExact() throws {
        // [[1, 1], [1, 0]]: λ = (1 ± √5)/2
        let e = try EigenDecomposition(matrix([[1, 1], [1, 0]]))
        try #require(e.eigenvalues.count == 2)
        let values = e.eigenvalues.map(\.value.re).sorted()
        #expect(abs(values[0] - (1 - 5.0.squareRoot()) / 2) < 1e-12)
        #expect(abs(values[1] - (1 + 5.0.squareRoot()) / 2) < 1e-12)
        #expect(e.eigenvalues.allSatisfy { $0.exact != nil && $0.vectors.count == 1 })
    }

    @Test func threeByThree() throws {
        // [[2, 0, 0], [0, 3, 4], [0, 4, 9]]: λ = 1, 2, 11
        let e = try EigenDecomposition(matrix([[2, 0, 0], [0, 3, 4], [0, 4, 9]]))
        #expect(e.eigenvalues.compactMap(\.exact) == [1, 2, 11].map { Expr.number(Rational($0)) })
        #expect(e.eigenvalues.allSatisfy { $0.exactVectors?.count == 1 })
    }

    @Test func kernelSpansTheNullSpace() throws {
        let a = matrix([[1, 2, 3], [2, 4, 6]])
        let k = a.kernel()
        #expect(k.rows == 3 && k.columns == 2)
        #expect(try a.multiplied(by: k).values.allSatisfy { $0 == 0 })
    }

    @Test func calculatorShowsEigenvalues() throws {
        let calculation = CalculationEngine.calculate(try parse("eig(((2,1),(1,2)))"), variables: [:], exactVariables: [:], settings: CalculationSettings())
        guard case .eigen(let e) = calculation.outcome else {
            Issue.record("eig(A) gave no eigenvalues")
            return
        }
        #expect(e.eigenvalues.count == 2)
    }
}

// MARK: Parametric and polar curves (length, enclosed area)

@Suite struct ParametricCurveTests {
    func measures(_ text: String) throws -> (length: Double, area: Double?) {
        let calculation = CalculationEngine.calculate(try parse(text), variables: [:], exactVariables: [:], settings: CalculationSettings())
        guard case .parametric? = calculation.graph?.kinds.first else {
            Issue.record("\(text) is not drawn as a parametric curve")
            return (0, nil)
        }
        guard case .special(.curve(let length, let area), _) = calculation.outcome else {
            Issue.record("\(text) has no length")
            return (0, nil)
        }
        return (length, area)
    }

    @Test func ellipse() throws {
        // x = 2 cos t, y = sin t: perimeter 9.6884482205…, area 2π
        let m = try measures("(2cos(t), sin(t))")
        #expect(abs(m.length - 9.688448220547675) < 1e-8)
        #expect(abs((m.area ?? 0) - 2 * Double.pi) < 1e-9)
    }

    @Test func rose() throws {
        // r = sin 2θ: four petals of total area π/2
        let m = try measures("r = sin(2theta)")
        #expect(abs((m.area ?? 0) - Double.pi / 2) < 1e-9)
    }

    @Test func cardioid() throws {
        // r = 1 + cos θ: length 8, area 3π/2
        let m = try measures("r = 1 + cos(theta)")
        #expect(abs(m.length - 8) < 1e-8)
        #expect(abs((m.area ?? 0) - 3 * Double.pi / 2) < 1e-9)
    }

    @Test func rangeFromTheSystem() throws {
        let relations = try #require(Parser.parseSystem(tokens: try Lexer().tokenize("(t^2, t^3), -1<=t<=1")))
        let graph = try #require(CalculationEngine.systemGraph(relations))
        guard case .parametric(_, _, let from, let to)? = graph.kinds.first else {
            Issue.record("no parametric curve")
            return
        }
        #expect(from == -1 && to == 1)
    }

    @Test func coordinatesGivenAsEquations() throws {
        let relations = try #require(Parser.parseSystem(tokens: try Lexer().tokenize("x = 3cos(t), y = 2sin(t)")))
        let graph = try #require(CalculationEngine.systemGraph(relations))
        guard case .parametric? = graph.kinds.first else {
            Issue.record("x = 3 cos t, y = 2 sin t is not a parametric curve")
            return
        }
        #expect(graph.kinds.count == 1)
    }
}
