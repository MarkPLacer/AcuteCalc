import Foundation

/// The solids of school geometry (matura and the first year): the cube and the cuboid, regular
/// prisms and pyramids and the frustum of a pyramid, the cylinder, the cone and its frustum, and
/// the sphere – volume, surface area, the lengths and angles asked about them, and a mesh to
/// draw. Bases lie in the xy plane centred on the origin; heights point along z.
public enum Solids {
    /// A named length, area or angle of a solid; angles are in radians.
    public struct Quantity: Sendable, Hashable {
        public var symbol: String
        public var title: String
        public var value: Double
        public var isAngle: Bool

        init(_ symbol: String, _ title: String, _ value: Double, angle: Bool = false) {
            self.symbol = symbol
            self.title = title
            self.value = value
            isAngle = angle
        }
    }

    /// A dashed segment drawn in the solid (a height, a radius) and its name.
    public struct Guide: Sendable, Hashable {
        public var start: [Double]
        public var end: [Double]
        public var label: String
    }

    /// A name written next to a point of the drawing (an edge's middle).
    public struct Mark: Sendable, Hashable {
        public var position: [Double]
        public var label: String
    }

    public enum Shape: Sendable, Hashable {
        case polyhedron(Sketch3D.Polyhedron)
        case sphere(radius: Double)
    }

    public struct Solid: Sendable, Hashable {
        public var volume: Double
        public var surface: Double
        /// Further lengths, areas and angles, in the order to show them.
        public var quantities: [Quantity]
        public var shape: Shape
        /// Names of the vertices of a polyhedron (none for curved solids).
        public var labels: [String] = []
        public var guides: [Guide] = []
        public var marks: [Mark] = []
    }

    // MARK: Prisms and pyramids

    public static func cube(_ a: Double) throws(MathError) -> Solid {
        try positive(a, "a")
        var solid = try cuboid(a, a, a)
        solid.quantities = [
            Quantity("a", "rob", a),
            Quantity("d", "ploskovna diagonala", a * 2.0.squareRoot()),
            Quantity("D", "telesna diagonala", a * 3.0.squareRoot()),
            Quantity("O", "osnovna ploskev", a * a),
            Quantity("Pl", "plašč", 4 * a * a),
            Quantity("R", "polmer očrtane krogle", a * 3.0.squareRoot() / 2),
            Quantity("r", "polmer včrtane krogle", a / 2),
            Quantity("φ", "kot med telesno diagonalo in osnovno ploskvijo", atan(1 / 2.0.squareRoot()), angle: true),
        ]
        solid.marks = [Mark(position: solid.marks[0].position, label: "a")]
        return try finite(solid)
    }

    /// A cuboid with the base a × b and the height c.
    public static func cuboid(_ a: Double, _ b: Double, _ c: Double) throws(MathError) -> Solid {
        try positive(a, "a")
        try positive(b, "b")
        try positive(c, "c")
        let base = [[b / 2, -a / 2, 0], [b / 2, a / 2, 0], [-b / 2, a / 2, 0], [-b / 2, -a / 2, 0]]
        let mesh = prismMesh(base, top: base.map { [$0[0], $0[1], c] })
        let d = (a * a + b * b).squareRoot()
        let diagonal = (a * a + b * b + c * c).squareRoot()
        return try finite(Solid(
            volume: a * b * c,
            surface: 2 * (a * b + b * c + a * c),
            quantities: [
                Quantity("d₁", "diagonala osnovne ploskve", d),
                Quantity("d₂", "diagonala ploskve b × c", (b * b + c * c).squareRoot()),
                Quantity("d₃", "diagonala ploskve a × c", (a * a + c * c).squareRoot()),
                Quantity("D", "telesna diagonala", diagonal),
                Quantity("O", "osnovna ploskev", a * b),
                Quantity("Pl", "plašč", 2 * (a + b) * c),
                Quantity("R", "polmer očrtane krogle", diagonal / 2),
                Quantity("φ", "kot med telesno diagonalo in osnovno ploskvijo", atan2(c, d), angle: true),
            ],
            shape: .polyhedron(mesh),
            labels: ["A", "B", "C", "D", "E", "F", "G", "H"],
            marks: [Mark(position: middle(mesh.vertices[0], mesh.vertices[1]), label: "a"),
                    Mark(position: middle(mesh.vertices[1], mesh.vertices[2]), label: "b"),
                    Mark(position: middle(mesh.vertices[1], mesh.vertices[5]), label: "c")]
        ))
    }

    /// A right prism whose base is a regular n-gon with the edge a; v is the height.
    public static func prism(sides n: Int, edge a: Double, height v: Double) throws(MathError) -> Solid {
        try check(sides: n)
        try positive(a, "a")
        try positive(v, "v")
        let polygon = RegularPolygon(sides: n, edge: a)
        let base = polygon.corners(z: 0)
        let mesh = prismMesh(base, top: polygon.corners(z: v))
        let lateral = Double(n) * a * v
        var quantities = [
            Quantity("O", "osnovna ploskev", polygon.area),
            Quantity("Pl", "plašč", lateral),
            Quantity("R", "polmer očrtanega kroga osnovne ploskve", polygon.circumradius),
            Quantity("ρ", "polmer včrtanega kroga osnovne ploskve", polygon.inradius),
            Quantity("d", "diagonala stranske ploskve", (a * a + v * v).squareRoot()),
        ]
        if n >= 4 {
            // The longest diagonal of the base joins opposite (or nearly opposite) corners.
            let longest = 2 * polygon.circumradius * sin(Double.pi * Double(n / 2) / Double(n))
            quantities.append(Quantity("D", "najdaljša telesna diagonala", (longest * longest + v * v).squareRoot()))
        }
        return try finite(Solid(
            volume: polygon.area * v,
            surface: 2 * polygon.area + lateral,
            quantities: quantities,
            shape: .polyhedron(mesh),
            labels: n <= 12 ? letters(n) + letters(n).map { $0 + "′" } : [],
            marks: [Mark(position: middle(mesh.vertices[0], mesh.vertices[1]), label: "a"),
                    Mark(position: middle(mesh.vertices[1], mesh.vertices[n + 1]), label: "v")]
        ))
    }

    /// A right pyramid whose base is a regular n-gon with the edge a; v is the height.
    public static func pyramid(sides n: Int, edge a: Double, height v: Double) throws(MathError) -> Solid {
        try check(sides: n)
        try positive(a, "a")
        try positive(v, "v")
        let polygon = RegularPolygon(sides: n, edge: a)
        let base = polygon.corners(z: 0)
        let apex = [0.0, 0, v]
        let mesh = Sketch3D.Polyhedron(vertices: base + [apex],
                                       faces: [Array((0..<n).reversed())] + (0..<n).map { [$0, ($0 + 1) % n, n] })
        let R = polygon.circumradius, rho = polygon.inradius
        let side = (v * v + R * R).squareRoot()
        let faceHeight = (v * v + rho * rho).squareRoot()
        let lateral = Double(n) * a * faceHeight / 2
        let front = middle(base[0], base[1])
        return try finite(Solid(
            volume: polygon.area * v / 3,
            surface: polygon.area + lateral,
            quantities: [
                Quantity("v", "višina", v),
                Quantity("s", "stranski rob", side),
                Quantity("vₐ", "višina stranske ploskve", faceHeight),
                Quantity("O", "osnovna ploskev", polygon.area),
                Quantity("Pl", "plašč", lateral),
                Quantity("R", "polmer očrtanega kroga osnovne ploskve", R),
                Quantity("ρ", "polmer včrtanega kroga osnovne ploskve", rho),
                Quantity("α", "kot med stranskim robom in osnovno ploskvijo", atan2(v, R), angle: true),
                Quantity("β", "kot med stransko ploskvijo in osnovno ploskvijo", atan2(v, rho), angle: true),
                Quantity("γ", "kot ob vrhu stranske ploskve", 2 * asin(Swift.min(1, a / (2 * side))), angle: true),
            ],
            shape: .polyhedron(mesh),
            labels: n <= 12 ? letters(n) + ["V"] : [],
            guides: [Guide(start: [0, 0, 0], end: apex, label: "v"), Guide(start: front, end: apex, label: "vₐ")],
            marks: [Mark(position: middle(base[0], base[1]), label: "a"), Mark(position: middle(base[1], apex), label: "s")]
        ))
    }

    /// A frustum of a regular pyramid: the lower base edge a, the upper b, the height v.
    public static func pyramidFrustum(sides n: Int, lower a: Double, upper b: Double, height v: Double) throws(MathError) -> Solid {
        try check(sides: n)
        try positive(a, "a")
        try positive(b, "b")
        try positive(v, "v")
        let lower = RegularPolygon(sides: n, edge: a), upper = RegularPolygon(sides: n, edge: b)
        let mesh = prismMesh(lower.corners(z: 0), top: upper.corners(z: v))
        let dR = Swift.abs(lower.circumradius - upper.circumradius), dRho = Swift.abs(lower.inradius - upper.inradius)
        let side = (v * v + dR * dR).squareRoot()
        let faceHeight = (v * v + dRho * dRho).squareRoot()
        let lateral = Double(n) * (a + b) / 2 * faceHeight
        return try finite(Solid(
            volume: v / 3 * (lower.area + upper.area + (lower.area * upper.area).squareRoot()),
            surface: lower.area + upper.area + lateral,
            quantities: [
                Quantity("s", "stranski rob", side),
                Quantity("vₐ", "višina stranske ploskve", faceHeight),
                Quantity("O₁", "spodnja osnovna ploskev", lower.area),
                Quantity("O₂", "zgornja osnovna ploskev", upper.area),
                Quantity("Pl", "plašč", lateral),
                Quantity("α", "kot med stranskim robom in osnovno ploskvijo", atan2(v, dR), angle: true),
                Quantity("β", "kot med stransko ploskvijo in osnovno ploskvijo", atan2(v, dRho), angle: true),
            ],
            shape: .polyhedron(mesh),
            labels: n <= 12 ? letters(n) + letters(n).map { $0 + "′" } : [],
            guides: [Guide(start: [0, 0, 0], end: [0, 0, v], label: "v")],
            marks: [Mark(position: middle(mesh.vertices[0], mesh.vertices[1]), label: "a"),
                    Mark(position: middle(mesh.vertices[n], mesh.vertices[n + 1]), label: "b")]
        ))
    }

    // MARK: Round solids

    public static func cylinder(radius r: Double, height v: Double) throws(MathError) -> Solid {
        try positive(r, "r")
        try positive(v, "v")
        let circle = roundCorners(radius: r, z: 0)
        let mesh = prismMesh(circle, top: roundCorners(radius: r, z: v), smooth: true)
        return try finite(Solid(
            volume: Double.pi * r * r * v,
            surface: 2 * Double.pi * r * (r + v),
            quantities: [
                Quantity("O", "osnovna ploskev", Double.pi * r * r),
                Quantity("Pl", "plašč", 2 * Double.pi * r * v),
                Quantity("o", "obseg osnovne ploskve", 2 * Double.pi * r),
                Quantity("S", "ploščina osnega preseka", 2 * r * v),
                Quantity("d", "diagonala osnega preseka", (4 * r * r + v * v).squareRoot()),
            ],
            shape: .polyhedron(mesh),
            guides: [Guide(start: [0, 0, 0], end: [0, r, 0], label: "r"), Guide(start: [0, 0, 0], end: [0, 0, v], label: "v")]
        ))
    }

    public static func cone(radius r: Double, height v: Double) throws(MathError) -> Solid {
        try positive(r, "r")
        try positive(v, "v")
        let circle = roundCorners(radius: r, z: 0)
        let n = circle.count
        let apex = [0.0, 0, v]
        let mesh = Sketch3D.Polyhedron(vertices: circle + [apex],
                                       faces: [Array((0..<n).reversed())] + (0..<n).map { [$0, ($0 + 1) % n, n] },
                                       smoothGroups: [nil] + Array(repeating: 0, count: n))
        let s = (r * r + v * v).squareRoot()
        return try finite(Solid(
            volume: Double.pi * r * r * v / 3,
            surface: Double.pi * r * (r + s),
            quantities: [
                Quantity("r", "polmer", r),
                Quantity("v", "višina", v),
                Quantity("s", "stranica (izvodnica)", s),
                Quantity("O", "osnovna ploskev", Double.pi * r * r),
                Quantity("Pl", "plašč", Double.pi * r * s),
                Quantity("S", "ploščina osnega preseka", r * v),
                Quantity("α", "kot med stranico in osnovno ploskvijo", atan2(v, r), angle: true),
                Quantity("γ", "kot ob vrhu osnega preseka", 2 * atan2(r, v), angle: true),
                Quantity("φ", "središčni kot razvitega plašča", 2 * Double.pi * r / s, angle: true),
            ],
            shape: .polyhedron(mesh),
            labels: Array(repeating: "", count: n) + ["V"],
            guides: [Guide(start: [0, 0, 0], end: [0, r, 0], label: "r"), Guide(start: [0, 0, 0], end: apex, label: "v")],
            marks: [Mark(position: middle([0, r, 0], apex), label: "s")]
        ))
    }

    /// A frustum of a cone: the lower radius r₁, the upper r₂, the height v.
    public static func coneFrustum(lower r1: Double, upper r2: Double, height v: Double) throws(MathError) -> Solid {
        try positive(r1, "r₁")
        try positive(r2, "r₂")
        try positive(v, "v")
        let mesh = prismMesh(roundCorners(radius: r1, z: 0), top: roundCorners(radius: r2, z: v), smooth: true)
        let dr = Swift.abs(r1 - r2)
        let s = (v * v + dr * dr).squareRoot()
        return try finite(Solid(
            volume: Double.pi * v / 3 * (r1 * r1 + r1 * r2 + r2 * r2),
            surface: Double.pi * (r1 * r1 + r2 * r2 + (r1 + r2) * s),
            quantities: [
                Quantity("s", "stranica (izvodnica)", s),
                Quantity("O₁", "spodnja osnovna ploskev", Double.pi * r1 * r1),
                Quantity("O₂", "zgornja osnovna ploskev", Double.pi * r2 * r2),
                Quantity("Pl", "plašč", Double.pi * (r1 + r2) * s),
                Quantity("S", "ploščina osnega preseka", (r1 + r2) * v),
                Quantity("α", "kot med stranico in osnovno ploskvijo", atan2(v, dr), angle: true),
            ],
            shape: .polyhedron(mesh),
            guides: [Guide(start: [0, 0, 0], end: [0, r1, 0], label: "r₁"), Guide(start: [0, 0, v], end: [0, r2, v], label: "r₂"),
                     Guide(start: [0, 0, 0], end: [0, 0, v], label: "v")]
        ))
    }

    public static func sphere(radius r: Double) throws(MathError) -> Solid {
        try positive(r, "r")
        return try finite(Solid(
            volume: 4 * Double.pi * r * r * r / 3,
            surface: 4 * Double.pi * r * r,
            quantities: [
                Quantity("r", "polmer", r),
                Quantity("d", "premer", 2 * r),
                Quantity("S", "ploščina glavnega kroga", Double.pi * r * r),
                Quantity("o", "obseg glavnega kroga", 2 * Double.pi * r),
            ],
            shape: .sphere(radius: r),
            guides: [Guide(start: [0, 0, 0], end: [0, r, 0], label: "r")]
        ))
    }

    // MARK: Other givens

    /// The height of a regular pyramid from its side edge s: s² = v² + R².
    public static func pyramidHeight(sides n: Int, edge a: Double, sideEdge s: Double) throws(MathError) -> Double {
        try check(sides: n)
        try positive(a, "a")
        try positive(s, "s")
        return try leg(hypotenuse: s, RegularPolygon(sides: n, edge: a).circumradius, "stranski rob mora biti daljši od polmera očrtanega kroga osnovne ploskve")
    }

    /// The height of a regular pyramid from the height of a side face: vₐ² = v² + ρ².
    public static func pyramidHeight(sides n: Int, edge a: Double, faceHeight h: Double) throws(MathError) -> Double {
        try check(sides: n)
        try positive(a, "a")
        try positive(h, "vₐ")
        return try leg(hypotenuse: h, RegularPolygon(sides: n, edge: a).inradius, "višina stranske ploskve mora biti daljša od polmera včrtanega kroga osnovne ploskve")
    }

    /// The height of a cone from its radius and slant height: s² = r² + v².
    public static func coneHeight(radius r: Double, slant s: Double) throws(MathError) -> Double {
        try positive(r, "r")
        try positive(s, "s")
        return try leg(hypotenuse: s, r, "stranica mora biti daljša od polmera")
    }

    /// The radius of a cone from its height and slant height.
    public static func coneRadius(height v: Double, slant s: Double) throws(MathError) -> Double {
        try positive(v, "v")
        try positive(s, "s")
        return try leg(hypotenuse: s, v, "stranica mora biti daljša od višine")
    }

    /// The edge of a cube from its body diagonal, volume or surface area.
    public static func cubeEdge(diagonal: Double) throws(MathError) -> Double {
        try positive(diagonal, "D")
        return diagonal / 3.0.squareRoot()
    }

    public static func cubeEdge(volume: Double) throws(MathError) -> Double {
        try positive(volume, "V")
        return Foundation.cbrt(volume)
    }

    public static func cubeEdge(surface: Double) throws(MathError) -> Double {
        try positive(surface, "P")
        return (surface / 6).squareRoot()
    }

    /// The radius of a sphere from its volume or surface area.
    public static func sphereRadius(volume: Double) throws(MathError) -> Double {
        try positive(volume, "V")
        // ∛V·∛(3/(4π)) instead of ∛(3V/(4π)), so a huge V does not overflow.
        return Foundation.cbrt(volume) * Foundation.cbrt(3 / (4 * Double.pi))
    }

    public static func sphereRadius(surface: Double) throws(MathError) -> Double {
        try positive(surface, "P")
        return (surface / (4 * Double.pi)).squareRoot()
    }

    // MARK: Helpers

    /// A regular n-gon with the edge a, exact for the triangle, the square and the hexagon.
    struct RegularPolygon {
        let sides: Int
        let edge: Double

        var circumradius: Double {
            switch sides {
            case 3: edge / 3.0.squareRoot()
            case 4: edge / 2.0.squareRoot()
            case 6: edge
            default: edge / (2 * sin(Double.pi / Double(sides)))
            }
        }

        var inradius: Double {
            switch sides {
            case 3: edge / (2 * 3.0.squareRoot())
            case 4: edge / 2
            case 6: edge * 3.0.squareRoot() / 2
            default: edge / (2 * tan(Double.pi / Double(sides)))
            }
        }

        var area: Double {
            switch sides {
            case 3: edge * edge * 3.0.squareRoot() / 4
            case 4: edge * edge
            case 6: 3 * 3.0.squareRoot() * edge * edge / 2
            default: Double(sides) * edge * inradius / 2
            }
        }

        /// The corners counter-clockwise from above, the first edge facing the x axis (towards
        /// the viewer of the standard sketch).
        func corners(z: Double) -> [[Double]] {
            (0..<sides).map { k in
                let angle = Double.pi * Double(2 * k - 1) / Double(sides)
                return [circumradius * cos(angle), circumradius * sin(angle), z]
            }
        }
    }

    /// A circle drawn as a regular 72-gon.
    static func roundCorners(radius r: Double, z: Double) -> [[Double]] {
        (0..<72).map { k in
            let angle = Double.pi * Double(2 * k - 1) / 72
            return [r * cos(angle), r * sin(angle), z]
        }
    }

    /// The mesh between a base and a top with the same number of corners (prism, frustum,
    /// cylinder); the side faces of a round solid share one smooth surface.
    static func prismMesh(_ base: [[Double]], top: [[Double]], smooth: Bool = false) -> Sketch3D.Polyhedron {
        let n = base.count
        let sides = (0..<n).map { [$0, ($0 + 1) % n, ($0 + 1) % n + n, $0 + n] }
        return Sketch3D.Polyhedron(vertices: base + top,
                                   faces: [Array((0..<n).reversed()), Array(n..<2 * n)] + sides,
                                   smoothGroups: [nil, nil] + Array(repeating: smooth ? 0 : nil, count: n))
    }

    static func middle(_ p: [Double], _ q: [Double]) -> [Double] { zip(p, q).map { ($0 + $1) / 2 } }

    static func letters(_ n: Int) -> [String] { (0..<n).map { String(UnicodeScalar(UInt8(65 + $0))) } }

    /// The other leg of a right triangle; an error when the hypotenuse is not the longest side.
    private static func leg(hypotenuse c: Double, _ a: Double, _ message: String) throws(MathError) -> Double {
        guard c > a else { throw .domain(message) }
        // c·√((1 − a/c)(1 + a/c)), so the squares of huge lengths do not overflow.
        let ratio = a / c
        return c * ((1 - ratio) * (1 + ratio)).squareRoot()
    }

    /// The solid when all its measures fit in a double; huge lengths overflow.
    private static func finite(_ solid: Solid) throws(MathError) -> Solid {
        guard solid.volume.isFinite, solid.surface.isFinite, solid.quantities.allSatisfy({ $0.value.isFinite }) else {
            throw .overflow
        }
        return solid
    }

    private static func positive(_ x: Double, _ name: String) throws(MathError) {
        guard x > 0, x.isFinite else { throw .domain("\(name) mora biti pozitivno število") }
    }

    private static func check(sides n: Int) throws(MathError) {
        guard (3...100).contains(n) else { throw .domain("osnovna ploskev mora imeti od 3 do 100 stranic") }
    }
}
