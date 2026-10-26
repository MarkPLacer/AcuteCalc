import Foundation
import Testing
@testable import AcuteCore

// MARK: 3D sketches and solids

@Suite struct Sketch3DTests {
    @Test func standardViewOrientsTheAxes() {
        let view = Sketch3D.View.standard
        let x = view.project([1, 0, 0]), y = view.project([0, 1, 0]), z = view.project([0, 0, 1])
        // x towards the viewer and down to the left, y to the right, z up.
        #expect(x.x < 0 && x.y < 0 && x.depth > 0)
        #expect(y.x > 0 && abs(y.y) < y.x)
        #expect(z.x == 0 && z.y > 0.9)
        // The plane drawing: x to the right, y up.
        #expect(approx(Sketch3D.View.top.project([1, 0, 0]).x, 1))
        #expect(approx(Sketch3D.View.top.project([0, 1, 0]).y, 1))
        // Turning keeps the elevation between the poles.
        #expect(view.turned(yaw: 0, pitch: 10).pitch == .pi / 2)
    }

    @Test func linesAreCutToTheBox() throws {
        let box = Sketch3D.Box(lower: [-1, -1, -1], upper: [1, 1, 1])
        let part = try #require(Sketch3D.clip(SpatialGeometry.Line(point: [0, 0, 0], direction: [2, 0, 0]), to: box))
        #expect(part.start == [-1, 0, 0] && part.end == [1, 0, 0])
        let diagonal = try #require(Sketch3D.clip(SpatialGeometry.Line(point: [0, 0, 0], direction: [1, 1, 1]), to: box))
        #expect(approx(diagonal.start[0], -1) && approx(diagonal.end[2], 1))
        #expect(Sketch3D.clip(SpatialGeometry.Line(point: [0, 3, 0], direction: [1, 0, 0]), to: box) == nil)
    }

    @Test func planesAreCutToPolygons() {
        let box = Sketch3D.Box(lower: [-1, -1, -1], upper: [1, 1, 1])
        #expect(Sketch3D.section(SpatialGeometry.Plane(normal: [0, 0, 1], d: 0), in: box).count == 4)
        // x + y + z = 0 cuts a regular hexagon with the side √2, its corners in order.
        let hexagon = Sketch3D.section(SpatialGeometry.Plane(normal: [1, 1, 1], d: 0), in: box)
        #expect(hexagon.count == 6)
        for k in hexagon.indices {
            #expect(approx(VectorGeometry.length(zip(hexagon[k], hexagon[(k + 1) % hexagon.count]).map(-)), 2.0.squareRoot()))
        }
        // x + y + z = 3 only touches a corner; a face of the box is its own section.
        #expect(Sketch3D.section(SpatialGeometry.Plane(normal: [1, 1, 1], d: -3), in: box).isEmpty)
        #expect(Sketch3D.section(SpatialGeometry.Plane(normal: [0, 0, 1], d: -1), in: box).count == 4)
    }

    @Test func boxFitsThePoints() {
        let box = Sketch3D.Box.around([[0, 0, 0], [4, -2, 1]])
        #expect(box.contains([4, -2, 1]) && box.contains([0, 0, 0]))
        // A flat drawing keeps some depth.
        let flat = Sketch3D.Box.around([[0, 0, 0], [6, 0, 0]])
        #expect(flat.upper[1] - flat.lower[1] >= 2 && flat.upper[2] - flat.lower[2] >= 2)
    }

    @Test func hiddenEdgesOfACube() throws {
        guard case .polyhedron(let mesh) = try Solids.cube(2).shape else {
            Issue.record("a cube is a polyhedron")
            return
        }
        // Every face points outwards from the centre (0, 0, 1).
        for f in mesh.faces.indices {
            let center = (0..<3).map { i in mesh.faces[f].reduce(0) { $0 + mesh.vertices[$1][i] } / Double(mesh.faces[f].count) }
            #expect(VectorGeometry.dot(mesh.normal(of: f), zip(center, [0, 0, 1]).map(-)) > 0)
        }
        // Seen from (1, 1, 1) three faces are in front: nine edges visible, three hidden.
        let view = Sketch3D.View(yaw: .pi / 4, pitch: atan(1 / 2.0.squareRoot()))
        let edges = Sketch3D.edges(of: mesh, in: view)
        #expect(edges.count == 12)
        #expect(edges.filter(\.visible).count == 9)
        #expect(Sketch3D.frontFaces(of: mesh, in: view).count == 3)
        // The faces come from back to front, for the translucent fill (a view without ties).
        let tilted = Sketch3D.View(yaw: 0.3, pitch: 0.5)
        let depths = Sketch3D.frontFaces(of: mesh, in: tilted).map { Sketch3D.depth($0, tilted) }
        #expect(depths.count == 3 && zip(depths, depths.dropFirst()).allSatisfy { $0 < $1 })
    }

    @Test func roundSolidsShowTheirOutline() throws {
        guard case .polyhedron(let mesh) = try Solids.cylinder(radius: 1, height: 2).shape else {
            Issue.record("a cylinder is drawn as a polyhedron")
            return
        }
        let edges = Sketch3D.edges(of: mesh, in: .standard)
        // Two generators on the outline and the two circles.
        let generators = edges.filter { $0.start[2] != $0.end[2] }
        #expect(generators.count == 2 && generators.allSatisfy(\.visible))
        #expect(edges.count == 2 + 2 * 72)
        // Seen from above, the back half of the bottom circle is hidden.
        let bottom = edges.filter { $0.start[2] == 0 && $0.end[2] == 0 }
        #expect(bottom.count == 72 && bottom.contains(where: \.visible) && bottom.contains { !$0.visible })
        guard case .polyhedron(let cone) = try Solids.cone(radius: 1, height: 2).shape else {
            Issue.record("a cone is drawn as a polyhedron")
            return
        }
        let coneEdges = Sketch3D.edges(of: cone, in: .standard)
        let coneGenerators = coneEdges.filter { $0.start[2] != $0.end[2] }
        #expect(coneEdges.count == 2 + 72 && coneGenerators.count == 2 && coneGenerators.allSatisfy(\.visible))
    }
}

@Suite struct SolidsTests {
    private func quantity(_ solid: Solids.Solid, _ symbol: String) -> Double {
        solid.quantities.first { $0.symbol == symbol }?.value ?? .nan
    }

    @Test func cubeAndCuboid() throws {
        let cube = try Solids.cube(2)
        #expect(approx(cube.volume, 8) && approx(cube.surface, 24))
        #expect(approx(quantity(cube, "D"), 2 * 3.0.squareRoot()))
        let box = try Solids.cuboid(3, 4, 12)
        #expect(approx(box.volume, 144) && approx(box.surface, 192))
        #expect(approx(quantity(box, "d₁"), 5) && approx(quantity(box, "D"), 13))
        #expect(approx(try Solids.cubeEdge(diagonal: 3 * 3.0.squareRoot()), 3))
        #expect(approx(try Solids.cubeEdge(volume: 27), 3))
        #expect(approx(try Solids.cubeEdge(surface: 54), 3))
    }

    @Test func prismsAndPyramids() throws {
        // A hexagonal prism a = 2, v = 5: O = 6√3, the longest diagonal √(4² + 5²).
        let prism = try Solids.prism(sides: 6, edge: 2, height: 5)
        #expect(approx(prism.volume, 30 * 3.0.squareRoot()) && approx(prism.surface, 12 * 3.0.squareRoot() + 60))
        #expect(approx(quantity(prism, "D"), 41.0.squareRoot()))
        // A square pyramid a = 6, v = 4: the face height 5 (3, 4, 5), the side edge √34.
        let pyramid = try Solids.pyramid(sides: 4, edge: 6, height: 4)
        #expect(approx(pyramid.volume, 48) && approx(pyramid.surface, 96))
        #expect(approx(quantity(pyramid, "vₐ"), 5) && approx(quantity(pyramid, "s"), 34.0.squareRoot()))
        #expect(approx(try Solids.pyramidHeight(sides: 4, edge: 6, sideEdge: 34.0.squareRoot()), 4))
        #expect(approx(try Solids.pyramidHeight(sides: 4, edge: 6, faceHeight: 5), 4))
        #expect(throws: MathError.self) { try Solids.pyramidHeight(sides: 4, edge: 6, sideEdge: 4) }
        // The regular tetrahedron with the edge 1: v = √(2/3), V = √2/12, every edge 1.
        let tetrahedron = try Solids.pyramid(sides: 3, edge: 1, height: (2.0 / 3).squareRoot())
        #expect(approx(tetrahedron.volume, 2.0.squareRoot() / 12) && approx(quantity(tetrahedron, "s"), 1))
        // A frustum 6 → 2 with v = 3: V = (36 + 4 + 12)·3/3 = 52, vₐ = √(3² + 2²).
        let frustum = try Solids.pyramidFrustum(sides: 4, lower: 6, upper: 2, height: 3)
        #expect(approx(frustum.volume, 52) && approx(quantity(frustum, "vₐ"), 13.0.squareRoot()))
        #expect(throws: MathError.self) { try Solids.prism(sides: 2, edge: 1, height: 1) }
    }

    @Test func roundSolids() throws {
        let cone = try Solids.cone(radius: 3, height: 4)
        #expect(approx(quantity(cone, "s"), 5) && approx(cone.volume, 12 * .pi) && approx(cone.surface, 24 * .pi))
        // The developed lateral surface is a sector of 360°·r/s = 216°.
        #expect(approx(quantity(cone, "φ") * 180 / .pi, 216))
        #expect(approx(try Solids.coneHeight(radius: 3, slant: 5), 4))
        #expect(approx(try Solids.coneRadius(height: 4, slant: 5), 3))
        let cylinder = try Solids.cylinder(radius: 2, height: 5)
        #expect(approx(cylinder.volume, 20 * .pi) && approx(cylinder.surface, 28 * .pi))
        let frustum = try Solids.coneFrustum(lower: 4, upper: 2, height: 3)
        #expect(approx(frustum.volume, 28 * .pi) && approx(frustum.surface, .pi * (20 + 6 * 13.0.squareRoot())))
        let sphere = try Solids.sphere(radius: 3)
        #expect(approx(sphere.volume, 36 * .pi) && approx(sphere.surface, 36 * .pi))
        #expect(approx(try Solids.sphereRadius(volume: 36 * .pi), 3))
        #expect(approx(try Solids.sphereRadius(surface: 36 * .pi), 3))
        #expect(throws: MathError.self) { try Solids.cone(radius: -1, height: 2) }
        // Huge lengths: an overflowing volume is an error, the givens themselves do not overflow.
        #expect(throws: MathError.self) { try Solids.cube(1e200) }
        #expect(try Solids.sphereRadius(volume: 1e308).isFinite)
        #expect(approx(try Solids.coneHeight(radius: 3e200, slant: 5e200) / 1e200, 4))
    }
}
