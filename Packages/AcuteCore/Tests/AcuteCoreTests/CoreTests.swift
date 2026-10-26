import Foundation
import Testing
@testable import AcuteCore

// MARK: Helpers

func parse(_ s: String) throws -> Expr { try Parser.parse(s) }

func value(_ s: String, unit: AngleUnit = .radians, vars: [String: Double] = [:]) throws -> Double {
    try RealEvaluator.evaluate(try parse(s), context: EvaluationContext(angleUnit: unit, variables: vars))
}

func approx(_ a: Double, _ b: Double, _ tol: Double = 1e-9) -> Bool {
    abs(a - b) <= tol * max(1, abs(b))
}

// MARK: Numbers

@Suite struct NumberTests {
    @Test func rationalArithmetic() throws {
        let a = try #require(Rational(1, 3))
        let b = try #require(Rational(1, 6))
        #expect(a.adding(b) == Rational(1, 2))
        #expect(Rational(2, 3)?.power(5) == Rational(32, 243))
        #expect(Rational(decimalString: "0.125") == Rational(1, 8))
        #expect(Rational(decimalString: "1.5E3") == Rational(1500))
        #expect(Rational(Int.max).adding(Rational(1)) == nil)
    }

    @Test func surds() throws {
        let root12 = try #require(ExactReal.squareRoot(of: Rational(12)))
        #expect(root12.terms == [ExactReal.Basis(radicand: 3, piPower: 0): Rational(2)])
        let root8 = try #require(ExactReal.squareRoot(of: Rational(8)))
        let root2 = try #require(ExactReal.squareRoot(of: Rational(2)))
        let sum = try #require(root8.adding(root2))
        #expect(sum.terms == [ExactReal.Basis(radicand: 2, piPower: 0): Rational(3)])
        // 1/(1 + √2) = √2 − 1
        let inverse = try #require(ExactReal.one.adding(root2)?.reciprocal())
        #expect(approx(inverse.doubleValue, 2.0.squareRoot() - 1))
    }

    @Test func formatting() {
        let options = NumberFormatOptions(mode: .norm1, significantDigits: 10, decimalSeparator: ",")
        #expect(NumberFormatting.format(0.1 + 0.2, options: options).mantissa == "0,3")
        #expect(NumberFormatting.format(1234.5, options: options).mantissa == "1234,5")
        let big = NumberFormatting.format(6.02214076e23, options: options)
        #expect(big.exponent == 23)
        #expect(NumberFormatting.recurringDecimal(Rational(1, 7)!)?.period == "142857")
        #expect(NumberFormatting.mixedFraction(Rational(7, 3)!)?.whole == 2)
        #expect(NumberFormatting.primeFactorization(1001)?.map(\.prime) == [7, 11, 13])
    }
}

// MARK: Parsing & evaluation

@Suite struct ParserTests {
    @Test func precedenceAndImplicitMultiplication() throws {
        #expect(try value("2+3*4") == 14)
        #expect(try value("-2^2") == -4)
        #expect(try value("2^3^2") == 512)
        #expect(try value("2x", vars: ["x": 5]) == 10)
        #expect(try value("2(3+4)") == 14)
        #expect(try value("1/2x", vars: ["x": 4]) == 2)
        #expect(try value("3!") == 6)
        #expect(try value("200+10%") == 220)
        #expect(approx(try value("sin 2x", vars: ["x": 0.3]), sin(0.6)))
        #expect(try value("|3-5|") == 2)
        #expect(try value("log2(8)") == 3)
        #expect(try value("gcd(12, 18)") == 6)
    }

    @Test func trigonometryAndAngles() throws {
        #expect(try value("sin(pi)") == 0)
        #expect(try value("cos(90)", unit: .degrees) == 0)
        #expect(approx(try value("sin(30)", unit: .degrees), 0.5))
        #expect(throws: MathError.self) { try value("tan(90)", unit: .degrees) }
        #expect(approx(try value("asin(1)", unit: .degrees), 90))
        #expect(approx(try value("sin(30°)", unit: .radians), 0.5))
        #expect(approx(try value("12°30'", unit: .degrees), 12.5))
    }

    @Test func realRootsOfNegativeNumbers() throws {
        #expect(approx(try value("(-8)^(1/3)"), -2))
        #expect(throws: MathError.self) { try value("sqrt(-4)") }
        #expect(approx(try value("root(3, -27)"), -3))
    }

    @Test func exactResults() throws {
        func exact(_ s: String, unit: AngleUnit = .radians) throws -> ExactReal {
            try ExactEvaluator.evaluate(try parse(s), angleUnit: unit)
        }
        #expect(try exact("1/3 + 1/6") == ExactReal(Rational(1, 2)!))
        #expect(try exact("sin(pi/6)") == ExactReal(Rational(1, 2)!))
        #expect(try exact("sin(60)", unit: .degrees).terms == [ExactReal.Basis(radicand: 3, piPower: 0): Rational(1, 2)!])
        #expect(try exact("sqrt(12)").terms == [ExactReal.Basis(radicand: 3, piPower: 0): Rational(2)])
        #expect(try exact("log2(32)") == ExactReal(5))
        #expect(try exact("asin(1/2)").terms == [ExactReal.Basis(radicand: 1, piPower: 1): Rational(1, 6)!])
    }
}

// MARK: CAS

@Suite struct CASTests {
    @Test func derivatives() throws {
        let d = try Differentiator.derivative(of: try parse("x^3 - 2x"), withRespectTo: "x")
        for x in [-2.0, 0.5, 3.0] {
            #expect(approx(try RealEvaluator.evaluate(d, context: EvaluationContext(variables: ["x": x])), 3 * x * x - 2))
        }
        let d2 = try Differentiator.derivative(of: try parse("sin(x)*e^x"), withRespectTo: "x")
        let x = 0.7
        #expect(approx(try RealEvaluator.evaluate(d2, context: EvaluationContext(variables: ["x": x])), (cos(x) + sin(x)) * exp(x)))
    }

    @Test func simplification() throws {
        let s = Simplifier.simplify(try parse("x + x + 2x"))
        #expect(s == .product([.number(Rational(4)), .variable("x")]))
        #expect(Simplifier.simplify(try parse("x*x^2")) == .power(.variable("x"), .number(Rational(3))))
    }

    @Test func polynomialRoots() throws {
        let p = try #require(Polynomial.extract(from: try parse("x^3 - 2x"), variable: "x"))
        let roots = try #require(p.exactRealRoots())
        #expect(roots.count == 3)
        #expect(approx(roots[0].doubleValue, -2.0.squareRoot()))
        #expect(roots[1] == .zero)
    }

    @Test func taylor() throws {
        let t = try #require(TaylorSeries.polynomial(of: try parse("e^x"), around: 0, order: 3, context: EvaluationContext()))
        #expect(approx(try RealEvaluator.evaluate(t, context: EvaluationContext(variables: ["x": 0.1])), 1 + 0.1 + 0.005 + 0.1 * 0.1 * 0.1 / 6))
    }
}

// MARK: Analysis

@Suite struct AnalysisTests {
    @Test func exponentialEquationBySubstitution() throws {
        let result = try EquationSolver.solve(lhs: try parse("7^x + 7^(2x) + 7^(3x)"), rhs: .int(14), context: EvaluationContext())
        #expect(result.solutions.count == 1)
        #expect(approx(result.solutions[0].value, log(2) / log(7)))
        #expect(result.solutions[0].closedForm != nil)
    }

    @Test func quadraticEquationExact() throws {
        let result = try EquationSolver.solve(lhs: try parse("x^2 - 2"), rhs: .zero, context: EvaluationContext())
        #expect(result.solutions.count == 2)
        #expect(result.solutions.allSatisfy { $0.exact != nil })
    }

    @Test func trigonometricEquationIsPeriodic() throws {
        let result = try EquationSolver.solve(lhs: try parse("sin(x)"), rhs: .frac(1, 2), context: EvaluationContext())
        #expect(result.period != nil)
        #expect(result.solutions.count == 2)
        #expect(approx(result.solutions[0].value, .pi / 6))
    }

    @Test func improperOscillatoryIntegral() throws {
        let v = try Integrator.integrate({ $0 == 0 ? 1 : sin($0) / $0 }, from: -.infinity, to: .infinity)
        #expect(approx(v, .pi, 1e-7))
        let gauss = try Integrator.integrate({ exp(-$0 * $0) }, from: -.infinity, to: .infinity)
        #expect(approx(gauss, Double.pi.squareRoot(), 1e-9))
        #expect(approx(try value("integral(x^2, x, 0, 1)"), 1.0 / 3))
    }

    @Test func limits() throws {
        #expect(approx(try LimitEvaluator.limit({ sin($0) / $0 }, at: 0, direction: .both), 1, 1e-9))
        #expect(approx(try LimitEvaluator.limit({ pow(1 + 1 / $0, $0) }, at: .infinity, direction: .both), M_E, 1e-6))
        #expect(try LimitEvaluator.limit({ 1 / ($0 * $0) }, at: 0, direction: .both) == .infinity)
    }

    @Test func infiniteSeries() throws {
        #expect(approx(try value("sum(1/n^2, n, 1, inf)"), .pi * .pi / 6, 1e-6))
        #expect(approx(try value("sum((1/2)^n, n, 0, inf)"), 2, 1e-12))
    }

    @Test func functionAnalysis() throws {
        let a = FunctionAnalyzer.analyze(try parse("x^3 - 3x"), range: -3...3, context: EvaluationContext())
        #expect(a.zeros.count == 3)
        #expect(a.extrema.count == 2)
        #expect(a.extrema.contains { $0.kind == .maximum && approx($0.x, -1) })
        #expect(a.inflections.count == 1)
        #expect(a.isOdd)
    }

    @Test func intersections() throws {
        let points = FunctionAnalyzer.intersections(try parse("x^2"), try parse("x + 2"), range: -5...5, context: EvaluationContext())
        #expect(points.map(\.x).sorted() == [-1, 2])
    }

    @Test func holes() throws {
        let h = HoleFinder.holes(try parse("sin(x)/x"), range: -5...5, context: EvaluationContext())
        #expect(h.count == 1)
        #expect(approx(h[0].y, 1))
    }

    @Test func samplerBreaksAtPoles() {
        let sampler = CurveSampler(unitsPerPixel: SIMD2(0.01, 0.01), visibleY: -5...5)
        let curve = sampler.sampleExplicit({ tan($0) }, over: -3...3)
        let breaks = curve.points.filter { $0.x.isNaN }.count
        #expect(breaks >= 2)
    }
}

// MARK: Bytecode

@Suite struct BytecodeTests {
    @Test func vmMatchesTreeEvaluator() throws {
        let sources = ["x^x", "sin(x)/x", "sqrt(x^2+1)", "x^(1/3)", "log(2, x)", "abs(x) - floor(x)", "e^(-x^2)"]
        for source in sources {
            let e = try parse(source)
            let program = try BytecodeCompiler(slots: ["x": .x]).compile(e)
            let vm = RealVM(program: program)
            for x in [0.3, 1.7, 2.5] {
                let expected = try RealEvaluator.evaluate(e, context: EvaluationContext(variables: ["x": x]))
                #expect(approx(vm.evaluate(x: x), expected), "\(source) at \(x)")
            }
        }
        // Real cube root of negative numbers
        let cube = RealVM(program: try BytecodeCompiler(slots: ["x": .x]).compile(try parse("x^(1/3)")))
        #expect(approx(cube.evaluate(x: -8), -2))
    }

    @Test func complexZeta() {
        let z2 = Complex.zeta(Complex(2, 0))
        #expect(approx(z2.re, .pi * .pi / 6, 1e-10))
        // First non-trivial zero ≈ ½ + 14.134725i
        let zero = Complex.zeta(Complex(0.5, 14.134725141734693))
        #expect(zero.magnitude < 1e-6)
        let g = Complex.gamma(Complex(5, 0))
        #expect(approx(g.re, 24, 1e-12))
    }
}

// MARK: Editor

@Suite struct EditorTests {
    @Test func typingAFraction() throws {
        var editor = MathEditor()
        editor.insert(.digit(1))
        editor.insertFraction()
        editor.insert(.digit(2))
        editor.moveRight()
        editor.insert(.plus)
        editor.insert(.digit(1))
        editor.insertFraction()
        editor.insert(.digit(3))
        let e = try MathRowConverter.expr(from: editor.root)
        #expect(approx(try RealEvaluator.evaluate(e), 5.0 / 6))
    }

    @Test func powerAndDelete() throws {
        var editor = MathEditor()
        editor.insert(.variable("x"))
        editor.insertPower()
        editor.insert(.digit(2))
        editor.moveRight()
        #expect(editor.cursor.path.isEmpty)
        let e = try MathRowConverter.expr(from: editor.root)
        #expect(e == .power(.variable("x"), .number(Rational(2))))
        editor.deleteBackward() // steps into the exponent
        #expect(editor.cursor.path.count == 1)
    }

    @Test func calculatorClassification() throws {
        func calc(_ s: String) throws -> Calculation {
            CalculationEngine.calculate(try parse(s), variables: [:], exactVariables: [:], settings: CalculationSettings())
        }
        if case .solutions(let r) = try calc("7^x + 7^(2x) + 7^(3x) = 14").outcome {
            #expect(r.solutions.count == 1)
        } else {
            Issue.record("expected solutions")
        }
        #expect(try calc("x^2 + y^2 = 4").graph?.kinds.count == 1)
        #expect(try calc("y = ±sqrt(4 - x^2)").graph?.kinds.count == 2)
        #expect(try calc("z = sin(x^2 + y^2)").graph != nil)
        if case .number(let r) = try calc("integral(sin(x)/x, x, -inf, inf)").outcome {
            #expect(approx(r.value, .pi, 1e-7))
            #expect(r.exact == ExactReal.pi)
        } else {
            Issue.record("expected number")
        }
        if case .complex(let c) = try calc("(2+3i)(1-i)").outcome {
            #expect(c == Complex(5, 1))
        } else {
            Issue.record("expected complex")
        }
    }
}
