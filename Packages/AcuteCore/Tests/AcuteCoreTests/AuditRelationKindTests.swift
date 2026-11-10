import Foundation
import Testing
@testable import AcuteCore

/// Which graph the calculator (CalculationEngine.calculate) and Grafi (graphRequest) give an equation, an inequality
/// or a point. The two keep their own copies of the rules, so each case is checked in both.
@Suite struct AuditRelationKindTests {
    private func calculate(_ text: String, variables: [String: Double] = [:]) throws -> Calculation {
        CalculationEngine.calculate(try parse(text), variables: variables, exactVariables: [:], settings: CalculationSettings())
    }

    /// The calculator with a row typed as text, the path of the keypad (systems included).
    private func calculate(row text: String) throws -> Calculation {
        CalculationEngine.calculate(try MathRowConverter.row(fromText: text), variables: [:], exactVariables: [:],
                                    settings: CalculationSettings())
    }

    // MARK: An equation in z beside x or y is a surface

    /// |x| + |y| + |z| = 1 is the octahedron, a surface in x, y and z, as the 3D tab draws it. Read as a set of
    /// complex numbers z = x + iy, |z| became √(x² + y²) beside the real x and y, and the calculator and Grafi drew
    /// the closed curve |x| + |y| + √(x² + y²) = 1 (x² + y² = |z|: the unit circle and its centre).
    @Test(arguments: ["|x|+|y|+|z|=1", "abs(x)+abs(y)+abs(z)=1", "x^2+y^2=|z|", "max(|x|,|y|,|z|)=1"])
    func equationInZBesideXOrYIsASurface(_ text: String) throws {
        let expr = try parse(text)
        let calculation = CalculationEngine.calculate(expr, variables: [:], exactVariables: [:], settings: CalculationSettings())
        guard case .surface(let body)? = calculation.graph?.kinds.first else {
            Issue.record("\(text): \(String(describing: calculation.graph?.kinds))")
            return
        }
        #expect(body.dependsOn("z"), "\(text)")
        let request = try #require(CalculationEngine.graphRequest(for: expr), "\(text)")
        #expect(request.kinds == [GraphKind.surface(body)], "\(text)")
    }

    /// The octahedron as the implicit surface F − G = 0: 0 at its corners, −1 at its centre, ½ outside it.
    @Test func octahedronIsTheImplicitSurface() throws {
        let calculation = try calculate("|x|+|y|+|z|=1")
        guard case .surface(let body)? = calculation.graph?.kinds.first else {
            Issue.record("no surface: \(String(describing: calculation.graph?.kinds))")
            return
        }
        let vm = RealVM(program: try BytecodeCompiler(slots: ["x": .x, "y": .y, "z": .t]).compile(body))
        #expect(vm.evaluate(x: 1, y: 0, t: 0) == 0)
        #expect(vm.evaluate(x: 0, y: -1, t: 0) == 0)
        #expect(vm.evaluate(x: 0, y: 0, t: 1) == 0)
        #expect(vm.evaluate(x: 0, y: 0, t: 0) == -1)
        #expect(vm.evaluate(x: 0.5, y: 0.5, t: 0.5) == 0.5)
    }

    /// z = |x| + |y| was the height field already (z = x + iy has the imaginary part y there), and stays it.
    @Test func heightFieldWithAbsoluteValuesStays() throws {
        let height = try parse("|x|+|y|")
        let expected = [GraphKind.surface(height)]
        let expr = try parse("z=|x|+|y|")
        let calculation = CalculationEngine.calculate(expr, variables: [:], exactVariables: [:], settings: CalculationSettings())
        let request = CalculationEngine.graphRequest(for: expr)
        #expect(calculation.graph?.kinds == expected)
        #expect(request?.kinds == expected)
    }

    /// Sets of complex numbers stay regions and curves of the plane z = x + iy: inequalities, chains and ≠ in z (also
    /// beside x or y), and equations with i (|z − i| = y is a parabola).
    @Test(arguments: ["|z-1|<=2", "Re z >= -2", "1<=|z|<=2", "|z+i|<3", "Re z != 0", "|z-i|=y", "|z|<=y+1"])
    func complexSetsStayInThePlane(_ text: String) throws {
        let expr = try parse(text)
        let calculation = CalculationEngine.calculate(expr, variables: [:], exactVariables: [:], settings: CalculationSettings())
        guard case .implicit(let lhs, _, let rhs)? = calculation.graph?.kinds.first else {
            Issue.record("\(text): \(String(describing: calculation.graph?.kinds))")
            return
        }
        #expect(!lhs.dependsOn("z") && !rhs.dependsOn("z"), "\(text)")
        let request = CalculationEngine.graphRequest(for: expr)
        guard case .implicit? = request?.kinds.first else {
            Issue.record("\(text) in Grafi: \(String(describing: request?.kinds))")
            return
        }
    }

    // MARK: An inequality in x, y and z is a solid

    /// An inequality in x, y and z describes a solid in space (x² + y² + z² ≤ 4 is the ball): the plane has no axis
    /// for z and the 3D view draws surfaces only. Its region compiled without a slot for z and drew nothing, with no
    /// message. The calculator now says so, and Grafi gets no request ("Tega ni mogoče narisati"). The inverted
    /// pyramid |x| + |y| ≤ z ≤ 1 is such a chain too: with |…| and z it reads as a chain about complex numbers, which
    /// has no region in the plane, and the calculator gave the message of chains without x, y or z.
    @Test(arguments: ["x^2+y^2+z^2<=4", "z>x^2+y^2", "x+y+z!=1", "z>x^2", "0<=z<=x^2+y^2", "|x|+|y|<=z<=1"])
    func inequalityInXYAndZIsRefused(_ text: String) throws {
        let expr = try parse(text)
        let calculation = CalculationEngine.calculate(expr, variables: [:], exactVariables: [:], settings: CalculationSettings())
        #expect(calculation.graph == nil, "\(text)")
        guard case .error(let error) = calculation.outcome else {
            Issue.record("\(text): \(calculation.outcome)")
            return
        }
        #expect(error == MathError.unsupported("neenačbe v x, y in z ni mogoče narisati"), "\(text)")
        #expect(CalculationEngine.graphRequest(for: expr) == nil, "\(text)")
    }

    /// The same in a system: half of the ball (x² + y² + z² ≤ 4, z ≥ 0), and a curve cut by an inequality in z.
    @Test func systemInXYAndZIsRefused() throws {
        for text in ["x^2+y^2+z^2<=4, z>=0", "y=x^2, z>=0"] {
            let row = try MathRowConverter.row(fromText: text)
            let calculation = CalculationEngine.calculate(row, variables: [:], exactVariables: [:], settings: CalculationSettings())
            #expect(calculation.graph == nil, "\(text)")
            guard case .error = calculation.outcome else {
                Issue.record("\(text): \(calculation.outcome)")
                continue
            }
            let request = try CalculationEngine.graphRequest(for: row)
            #expect(request == nil, "\(text)")
        }
    }

    /// What stays: z² < 4 is solved for z, and with a stored z the inequality of the ball is the disc it cuts.
    @Test func inequalityInZAloneOrWithAStoredZStays() throws {
        let solved = try calculate("z^2<4")
        guard case .inequality = solved.outcome else {
            Issue.record("z² < 4: \(solved.outcome)")
            return
        }
        let disc = try calculate("x^2+y^2+z^2<=4", variables: ["z": 1])
        let graph = try #require(disc.graph)
        guard case .implicit? = graph.kinds.first else {
            Issue.record("no disc: \(graph.kinds)")
            return
        }
        #expect(graph.parameters.isEmpty)
    }

    // MARK: A named point with a parameter

    /// A(a, 2) and A(t, t²) get a slider in the calculator, as in Grafi and as two points already did (systemGraph).
    /// Without it the coordinates had no value, and nothing was drawn, with no message.
    @Test func namedPointWithAParameterHasASlider() throws {
        for (text, slider) in [("A(a,2)", "a"), ("A(t,t^2)", "t")] {
            let expr = try parse(text)
            let calculation = CalculationEngine.calculate(expr, variables: [:], exactVariables: [:], settings: CalculationSettings())
            let graph = try #require(calculation.graph, "\(text)")
            guard case .point? = graph.kinds.first else {
                Issue.record("\(text): \(graph.kinds)")
                continue
            }
            #expect(graph.parameters == [slider], "\(text)")
            let request = try #require(CalculationEngine.graphRequest(for: expr), "\(text)")
            #expect(request.parameters == [slider], "\(text)")
        }
        // Two points (systemGraph), and a stored value, which has no slider.
        let two = try #require(try calculate(row: "A(a,2), B(3,4)").graph)
        #expect(two.parameters == ["a"])
        let stored = try #require(try calculate("A(a,2)", variables: ["a": 3]).graph)
        #expect(stored.parameters.isEmpty)
    }

    // MARK: The calculator and Grafi agree

    /// The two copies of the rules give the same graph: the calculator checks the rules for z first, Grafi those for
    /// y = f(x) and x = g(y), with guards against z. 3 = x and a = x are the vertical line in the calculator; Grafi
    /// drew y = 3 (y = a) and y = x with their intersection instead.
    @Test(arguments: ["y=x^2", "x=3", "3=x", "a=x", "x=y^2", "y=z", "z=y", "5=z", "x=y*z", "x*z=y", "xyz=1", "|z-1|<=2"])
    func calculatorAndGrafiAgree(_ text: String) throws {
        let expr = try parse(text)
        let calculation = CalculationEngine.calculate(expr, variables: [:], exactVariables: [:], settings: CalculationSettings())
        let graph = try #require(calculation.graph, "\(text)")
        let request = try #require(CalculationEngine.graphRequest(for: expr), "\(text)")
        #expect(graph.kinds == request.kinds, "\(text)")
        #expect(graph.parameters == request.parameters, "\(text)")
    }

    /// 3 = x and a = x in a row of Grafi: the vertical lines x = 3 and x = a, the second with a slider for a.
    @Test func constantEqualsXIsAVerticalLineInGrafi() throws {
        let three = try #require(try CalculationEngine.graphRequest(for: try MathRowConverter.row(fromText: "3=x")))
        #expect(three.kinds == [GraphKind.explicitInY(.int(3))])
        #expect(three.parameters.isEmpty)
        let a = try #require(try CalculationEngine.graphRequest(for: try MathRowConverter.row(fromText: "a=x")))
        #expect(a.kinds == [GraphKind.explicitInY(.variable("a"))])
        #expect(a.parameters == ["a"])
    }

    /// An equation in z alone is solved in the calculator, with no graph: z² = 4 and 2z + 1 = z.
    @Test func equationInZAloneIsSolved() throws {
        for (text, roots) in [("z^2=4", [-2.0, 2.0]), ("2z+1=z", [-1.0])] {
            let calculation = try calculate(text)
            guard case .solutions(let result) = calculation.outcome else {
                Issue.record("\(text): \(calculation.outcome)")
                continue
            }
            let values = result.solutions.map { $0.value }.sorted()
            #expect(result.variable == "z", "\(text)")
            #expect(values == roots, "\(text): \(values)")
            #expect(calculation.graph == nil, "\(text)")
        }
    }
}
