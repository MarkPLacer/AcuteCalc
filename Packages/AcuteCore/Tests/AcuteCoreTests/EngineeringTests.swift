import Foundation
import Testing
@testable import AcuteCore

// MARK: Lines and planes, cross-sections, Fourier series and surveying

private func evaluate(_ e: Expr, _ variables: [String: Double]) throws -> Double {
    try RealEvaluator.evaluate(e, context: EvaluationContext(variables: variables))
}

@Suite struct SpatialGeometryTests {
    typealias G = SpatialGeometry

    @Test func pointsAndPlanes() throws {
        #expect(approx(G.distance([1, 2, 3], G.Plane(normal: [2, -1, 2], d: -3)), 1))
        let floor = G.Plane(normal: [0, 0, 1], d: 0)
        #expect(G.projection([1, 2, 3], onto: floor) == [1, 2, 0])
        #expect(G.mirror([1, 2, 3], in: floor) == [1, 2, -3])
        let slanted = try #require(G.Plane(through: [1, 0, 0], [0, 1, 0], [0, 0, 1]))
        #expect(approx(G.distance([0, 0, 0], slanted), 1 / 3.0.squareRoot()))
        #expect(G.Plane(through: [0, 0, 0], [1, 1, 1], [2, 2, 2]) == nil)
    }

    @Test func positionsOfTwoLines() throws {
        let xAxis = G.Line(point: [0, 0, 0], direction: [1, 0, 0])
        let skew = G.Line(point: [0, 1, 1], direction: [0, 1, 0])
        #expect(G.position(xAxis, skew) == .skew)
        #expect(approx(G.distance(xAxis, skew), 1))
        let feet = try #require(G.closestPoints(xAxis, skew))
        #expect(feet.0 == [0, 0, 0] && feet.1 == [0, 0, 1])
        let a = G.Line(point: [0, 0, 0], direction: [1, 1, 0]), b = G.Line(point: [2, 0, 0], direction: [-1, 1, 0])
        #expect(G.position(a, b) == .intersecting([1, 1, 0]))
        #expect(approx(G.angle(a, b), .pi / 2))
        #expect(G.position(xAxis, G.Line(point: [5, 0, 0], direction: [-2, 0, 0])) == .identical)
        let parallel = G.Line(point: [0, 3, 4], direction: [2, 0, 0])
        #expect(G.position(xAxis, parallel) == .parallel && approx(G.distance(xAxis, parallel), 5))
        #expect(G.mirror([1, 1, 0], in: xAxis) == [1, -1, 0])
    }

    @Test func linesAndPlanesMeet() throws {
        let diagonal = G.Line(point: [0, 0, 0], direction: [1, 1, 1])
        let plane = G.Plane(normal: [1, 1, 1], d: -3)
        #expect(G.intersection(diagonal, plane) == [1, 1, 1])
        #expect(approx(G.angle(diagonal, plane), .pi / 2))
        let floor = G.Plane(normal: [0, 0, 1], d: 0), wall = G.Plane(normal: [1, 0, 0], d: -2)
        let edge = try #require(G.intersection(floor, wall))
        #expect(edge.direction == [0, 1, 0] && edge.point == [2, 0, 0])
        #expect(approx(G.angle(floor, wall), .pi / 2))
        #expect(approx(G.distance(floor, G.Plane(normal: [0, 0, -2], d: 8)), 4))
        #expect(G.intersection(G.Line(point: [0, 0, 1], direction: [1, 1, 0]), floor) == nil)
    }
}

@Suite struct CrossSectionTests {
    @Test func rectangle() throws {
        let p = try CrossSection.properties([(.rectangle(x: 0, y: 0, width: 4, height: 6), false)])
        #expect(p.area == 24 && p.centroid == SIMD2(2, 3))
        #expect(approx(p.ix, 72) && approx(p.iy, 32) && approx(p.ixy, 0))
        #expect(approx(p.i1, 72) && approx(p.i2, 32) && approx(p.principalAngle, 0))
        #expect(approx(p.sectionModulusX, 24) && approx(p.sectionModulusY, 16))
        let outline: [SIMD2<Double>] = [SIMD2(0, 0), SIMD2(4, 0), SIMD2(4, 6), SIMD2(0, 6)]
        let polygon = try CrossSection.properties([(.polygon(outline.reversed()), false)])
        #expect(approx(polygon.ix, 72) && approx(polygon.iy, 32) && approx(polygon.area, 24))
    }

    @Test func lSection() throws {
        // 1 × 6 upright and 4 × 1 foot: A = 10, T(1,5; 2), I_x = 100/3, I_y = 62,5/3, I_xy = −15
        let parts: [(part: CrossSection.Part, hole: Bool)] = [
            (.rectangle(x: 0, y: 0, width: 1, height: 6), false), (.rectangle(x: 1, y: 0, width: 4, height: 1), false),
        ]
        let l = try CrossSection.properties(parts)
        #expect(approx(l.area, 10) && approx(l.centroid.x, 1.5) && approx(l.centroid.y, 2))
        #expect(approx(l.ix, 100.0 / 3) && approx(l.iy, 62.5 / 3) && approx(l.ixy, -15))
        #expect(approx(l.i1, 130.0 / 3) && approx(l.i2, 32.5 / 3))
        #expect(approx(l.principalAngle, 0.5 * atan2(30, 12.5)))
        let outline: [SIMD2<Double>] = [SIMD2(0, 0), SIMD2(5, 0), SIMD2(5, 1), SIMD2(1, 1), SIMD2(1, 6), SIMD2(0, 6)]
        let polygon = try CrossSection.properties([(.polygon(outline), false)])
        #expect(approx(polygon.ix, l.ix) && approx(polygon.iy, l.iy) && approx(polygon.ixy, l.ixy))
    }

    @Test func tubeAndHalfDisc() throws {
        let tube = try CrossSection.properties([(.circle(center: SIMD2(0, 0), radius: 2), false),
                                                (.circle(center: SIMD2(0, 0), radius: 1), true)])
        #expect(approx(tube.area, 3 * .pi) && approx(tube.ix, 15 * .pi / 4) && approx(tube.polar, 15 * .pi / 2))
        #expect(approx(tube.sectionModulusX, 15 * .pi / 8))
        // Half disc of radius 3: y_T = 4r/3π, I_x = πr⁴/8 − A·y_T²
        let half = try CrossSection.properties([(.sector(center: SIMD2(0, 0), radius: 3, from: 0, to: .pi), false)])
        #expect(approx(half.centroid.y, 4 / .pi) && approx(half.centroid.x, 0))
        #expect(approx(half.ix, 81 * .pi / 8 - 72 / .pi) && approx(half.iy, 81 * .pi / 8))
        #expect(half.lowerLeft == SIMD2(-3, 0) && approx(half.upperRight.y, 3))
        #expect(throws: MathError.self) { try CrossSection.properties([(.rectangle(x: 0, y: 0, width: 1, height: 1), true)]) }
    }
}

@Suite struct FourierSeriesTests {
    func pieces(_ list: [(String, String)]) throws -> [FourierSeries.Piece] {
        try list.map { FourierSeries.Piece(expr: try parse($0.0), end: try parse($0.1)) }
    }

    @Test func sawtooth() throws {
        // x on [−π, π]: aₙ = 0, bₙ = 2(−1)ⁿ⁺¹/n
        let s = try FourierSeries.series(try pieces([("x", "pi")]), start: try parse("-pi"), kind: .full, terms: 10)
        #expect(s.a.allSatisfy { $0 == 0 })
        #expect(approx(s.b[1], 2) && approx(s.b[2], -1) && approx(s.b[3], 2.0 / 3))
        let bn = try #require(s.bnFormula)
        #expect(approx(try evaluate(bn, ["n": 5]), 0.4))
        #expect(approx(try evaluate(bn, ["n": 6]), -1.0 / 3))
    }

    @Test func squareWave() throws {
        // −1 on (−π, 0), 1 on (0, π): bₙ = 2(1 − (−1)ⁿ)/(nπ)
        let wave = try pieces([("-1", "0"), ("1", "pi")])
        let s = try FourierSeries.series(wave, start: try parse("-pi"), kind: .full, terms: 99)
        #expect(approx(s.b[1], 4 / .pi) && s.b[2] == 0 && approx(s.b[3], 4 / (3 * .pi)))
        #expect(s.a.allSatisfy { $0 == 0 })
        let bn = try #require(s.bnFormula)
        for n in 1...6 {
            #expect(approx(try evaluate(bn, ["n": Double(n)]), s.b[n]))
        }
        #expect(abs(s.value(at: .pi / 2, terms: 99) - 1) < 0.02)
        let extended = FourierSeries.periodicExtension(wave, start: try parse("-pi"), kind: .full)
        #expect(try evaluate(extended, ["x": 2 * .pi + 1]) == 1)
        #expect(try evaluate(extended, ["x": -.pi - 0.5]) == 1)
        #expect(try evaluate(extended, ["x": -0.5]) == -1)
    }

    @Test func halfRangeSeries() throws {
        // x on [0, π] extended evenly: a₀ = π, aₙ = 2((−1)ⁿ − 1)/(πn²)
        let even = try FourierSeries.series(try pieces([("x", "pi")]), start: .zero, kind: .cosine, terms: 8)
        #expect(approx(even.a[0], .pi) && approx(even.a[1], -4 / .pi) && even.a[2] == 0 && approx(even.a[3], -4 / (9 * .pi)))
        #expect(even.b.allSatisfy { $0 == 0 })
        // 1 on [0, π] extended oddly: bₙ = 2(1 − (−1)ⁿ)/(πn)
        let odd = try FourierSeries.series(try pieces([("1", "pi")]), start: .zero, kind: .sine, terms: 8)
        #expect(approx(odd.b[1], 4 / .pi) && odd.b[2] == 0 && odd.a.allSatisfy { $0 == 0 })
        let extended = FourierSeries.periodicExtension(try pieces([("x", "pi")]), start: .zero, kind: .sine)
        #expect(approx(try evaluate(extended, ["x": -1]), -1))
        #expect(approx(try evaluate(extended, ["x": 2 * .pi - 1]), -1))
    }

    @Test func recognizesCoefficients() throws {
        let fourOverPi = try #require(FourierSeries.recognize(4 / .pi))
        #expect(approx(try evaluate(fourOverPi, [:]), 4 / .pi))
        let fraction = try #require(FourierSeries.recognize(-2.0 / 9))
        #expect(approx(try evaluate(fraction, [:]), -2.0 / 9))
        #expect(FourierSeries.recognize(0.123456789123) == nil)
    }
}

@Suite struct GeodesyTests {
    typealias P = Geodesy.Point

    @Test func directionAndDistance() throws {
        let a = P(y: 100, x: 100)
        let diagonal = try #require(Geodesy.inverse(a, P(y: 200, x: 200)))
        #expect(approx(diagonal.direction, .pi / 4) && approx(diagonal.distance, 100 * 2.0.squareRoot()))
        let south = try #require(Geodesy.inverse(a, P(y: 100, x: 0)))
        let west = try #require(Geodesy.inverse(a, P(y: 0, x: 100)))
        #expect(approx(south.direction, .pi) && approx(west.direction, 1.5 * .pi))
        let b = Geodesy.polar(from: P(y: 0, x: 0), direction: .pi / 6, distance: 10)
        #expect(approx(b.y, 5) && approx(b.x, 5 * 3.0.squareRoot()))
        #expect(approx(Geodesy.gon(fromRadians: .pi / 2), 100))
    }

    @Test func intersections() throws {
        let a = P(y: 0, x: 0), b = P(y: 100, x: 0)
        let left = try #require(Geodesy.forwardIntersection(a, b, alpha: .pi / 4, beta: .pi / 4, left: true))
        #expect(approx(left.y, 50) && approx(left.x, 50))
        let right = try #require(Geodesy.forwardIntersection(a, b, alpha: .pi / 4, beta: .pi / 4, left: false))
        #expect(approx(right.y, 50) && approx(right.x, -50))
        let arc = try #require(Geodesy.arcIntersection(a, b, distanceA: 50 * 2.0.squareRoot(), distanceB: 50 * 2.0.squareRoot(), left: true))
        #expect(approx(arc.y, 50) && approx(arc.x, 50))
        #expect(Geodesy.arcIntersection(a, b, distanceA: 10, distanceB: 10, left: true) == nil)
    }

    @Test func resection() throws {
        let p = P(y: 12.3, x: -45.6)
        let a = P(y: 230.5, x: 410.2), b = P(y: 520.0, x: 95.7), c = P(y: 150.3, x: -380.4)
        let toA = try #require(Geodesy.inverse(p, a)), toB = try #require(Geodesy.inverse(p, b)), toC = try #require(Geodesy.inverse(p, c))
        let found = try #require(Geodesy.resection(a, b, c, alpha: Geodesy.normalized(toB.direction - toA.direction),
                                                   beta: Geodesy.normalized(toC.direction - toB.direction)))
        #expect(abs(found.y - p.y) < 1e-6 && abs(found.x - p.x) < 1e-6)
    }

    @Test func areaAndHelmert() throws {
        let square = [P(y: 500_000, x: 100_000), P(y: 500_000, x: 100_010), P(y: 500_010, x: 100_010), P(y: 500_010, x: 100_000)]
        #expect(Geodesy.area(square) == 100 && Geodesy.perimeter(square) == 40)
        // Turned by 30° (direction angles grow by 30°), scaled by 1,0001 and moved by (1000, 2000).
        let delta = Double.pi / 6, m = 1.0001
        let a = m * cos(-delta), b = m * sin(-delta)
        let source = [P(y: 0, x: 0), P(y: 100, x: 0), P(y: 0, x: 100), P(y: 100, x: 100)]
        let pairs = source.map { s in (source: s, target: P(y: a * s.y - b * s.x + 1000, x: b * s.y + a * s.x + 2000)) }
        let fit = try Geodesy.helmert(pairs)
        #expect(approx(fit.scale, m) && approx(fit.rotation, delta) && approx(fit.ty, 1000) && approx(fit.tx, 2000))
        #expect(fit.residuals.allSatisfy { abs($0.y) < 1e-8 && abs($0.x) < 1e-8 })
        #expect((fit.sigma ?? 1) < 1e-8)
    }

    @Test func sphere() throws {
        let r = 6371.0
        let quarter = Geodesy.greatCircle(latitude1: 0, longitude1: 0, latitude2: 0, longitude2: .pi / 2, radius: r)
        #expect(approx(quarter.distance, r * .pi / 2) && approx(quarter.initialAzimuth, .pi / 2) && approx(quarter.finalAzimuth, .pi / 2))
        let north = Geodesy.greatCircle(latitude1: 0, longitude1: 0, latitude2: .pi / 3, longitude2: 0, radius: r)
        #expect(approx(north.distance, r * .pi / 3) && approx(north.initialAzimuth, 0))
        let equator = try #require(Geodesy.rhumbLine(latitude1: 0, longitude1: 0, latitude2: 0, longitude2: .pi / 2, radius: r))
        #expect(approx(equator.distance, r * .pi / 2) && approx(equator.azimuth, .pi / 2))
        let meridian = try #require(Geodesy.rhumbLine(latitude1: 0, longitude1: 0, latitude2: .pi / 3, longitude2: 0, radius: r))
        #expect(approx(meridian.distance, r * .pi / 3) && approx(meridian.azimuth, 0))
    }

    @Test func anglesFromText() {
        #expect(approx(Geodesy.degrees(fromDMS: "123 45 36") ?? 0, 123.76))
        #expect(Geodesy.degrees(fromDMS: "−12°30′") == -12.5)
        #expect(Geodesy.degrees(fromDMS: "45,25") == 45.25)
        #expect(Geodesy.degrees(fromDMS: "10 75") == nil)
        #expect(Geodesy.degrees(fromDMS: "abc") == nil)
    }
}
