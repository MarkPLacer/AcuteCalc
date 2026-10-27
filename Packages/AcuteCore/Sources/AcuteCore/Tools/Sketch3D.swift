import Foundation

/// The geometry behind the 3D sketches of the vector, space geometry and solids tools: an
/// orthographic view turned by two angles, lines and planes cut to a box around the drawing,
/// and the edges of a polyhedron split into visible ones and hidden ones (drawn dashed).
public enum Sketch3D {
    /// An orthographic view from the direction with azimuth `yaw` (from the x axis towards y)
    /// and elevation `pitch` above the xy plane; the z axis points up on the screen.
    public struct View: Sendable, Hashable {
        public var yaw: Double
        public var pitch: Double

        public init(yaw: Double, pitch: Double) {
            self.yaw = yaw
            self.pitch = Swift.min(Double.pi / 2, Swift.max(-Double.pi / 2, pitch))
        }

        /// The textbook view: x towards the viewer and down to the left, y to the right, z up.
        public static let standard = View(yaw: 0.5, pitch: 0.35)
        /// The xy plane as in a plane drawing: x to the right, y up.
        public static let top = View(yaw: -Double.pi / 2, pitch: Double.pi / 2)
        /// The standard view turned to look from the front (y to the right, z up), from the
        /// right (x to the left) and from above (y to the right, x down).
        public static let front = View(yaw: 0, pitch: 0)
        public static let side = View(yaw: Double.pi / 2, pitch: 0)
        public static let above = View(yaw: 0, pitch: Double.pi / 2)

        /// The unit vector from the drawing towards the viewer.
        public var eye: [Double] { [cos(pitch) * cos(yaw), cos(pitch) * sin(yaw), sin(pitch)] }
        /// The unit vectors of the screen's right and up directions.
        public var right: [Double] { [-sin(yaw), cos(yaw), 0] }
        public var up: [Double] { [-sin(pitch) * cos(yaw), -sin(pitch) * sin(yaw), cos(pitch)] }

        /// Screen coordinates (x to the right, y up) and the depth towards the viewer.
        public func project(_ p: [Double]) -> (x: Double, y: Double, depth: Double) {
            (VectorGeometry.dot(p, right), VectorGeometry.dot(p, up), VectorGeometry.dot(p, eye))
        }

        /// The view turned by a drag: right moves the eye around the z axis, up raises it.
        public func turned(yaw dYaw: Double, pitch dPitch: Double) -> View {
            View(yaw: yaw + dYaw, pitch: pitch + dPitch)
        }
    }

    /// An axis-aligned box [lower, upper].
    public struct Box: Sendable, Hashable {
        public var lower: [Double]
        public var upper: [Double]

        public init(lower: [Double], upper: [Double]) {
            self.lower = lower
            self.upper = upper
        }

        /// The smallest box around the points, widened on every side by `margin` times its
        /// largest side; every axis gets at least a third of the largest side, so a flat drawing
        /// keeps depth. The box follows the drawing's own size (a cube 0,2 wide fills it like one
        /// 200 wide); points that all coincide get the side `minimumSide` before the margin.
        public static func around(_ points: [[Double]], margin: Double = 0.12, minimumSide: Double = 2) -> Box {
            let finite = points.filter { $0.count == 3 && $0.allSatisfy(\.isFinite) }
            guard !finite.isEmpty else {
                return Box(lower: Array(repeating: -minimumSide / 2, count: 3), upper: Array(repeating: minimumSide / 2, count: 3))
            }
            var lower = finite[0], upper = finite[0]
            for p in finite.dropFirst() {
                for i in 0..<3 {
                    lower[i] = Swift.min(lower[i], p[i])
                    upper[i] = Swift.max(upper[i], p[i])
                }
            }
            // Half sides and middles from the halved ends stay finite even between −10³⁰⁸ and 10³⁰⁸;
            // the widened ends are kept within the doubles.
            var halves = (0..<3).map { upper[$0] / 2 - lower[$0] / 2 }
            let middles = (0..<3).map { lower[$0] / 2 + upper[$0] / 2 }
            if (0..<3).allSatisfy({ lower[$0] == upper[$0] }) {
                halves = Array(repeating: minimumSide / 2, count: 3)
            } else if (halves.max() ?? 0) < .leastNormalMagnitude {
                // A drawing narrower than the smallest normal double: its halves, thirds and margins
                // would round away, so every axis gets that smallest normal half side and the box
                // keeps a width and a radius.
                halves = Array(repeating: .leastNormalMagnitude, count: 3)
            }
            let largest = halves.max() ?? 0
            for i in 0..<3 {
                let half = Swift.max(halves[i], largest / 3) + 2 * margin * largest
                lower[i] = Swift.max(middles[i] - half, -.greatestFiniteMagnitude)
                upper[i] = Swift.min(middles[i] + half, .greatestFiniteMagnitude)
                // Next to the largest doubles the widening can round away; the ends then step apart.
                if lower[i] == upper[i] {
                    lower[i] = Swift.max(lower[i].nextDown, -.greatestFiniteMagnitude)
                    upper[i] = Swift.min(upper[i].nextUp, .greatestFiniteMagnitude)
                }
            }
            return Box(lower: lower, upper: upper)
        }

        public var center: [Double] { zip(lower, upper).map { $0 / 2 + $1 / 2 } }

        /// Half the diagonal: the radius of the sphere around the box, the same in every view. (A box
        /// narrower than the smallest normal double, which `around` never makes, may round it to 0.)
        public var radius: Double { Sketch3D.length(zip(upper, lower).map { $0 / 2 - $1 / 2 }) }

        public var corners: [[Double]] {
            (0..<8).map { k in (0..<3).map { i in (k >> i) & 1 == 0 ? lower[i] : upper[i] } }
        }

        public func contains(_ p: [Double], tolerance: Double = 0) -> Bool {
            (0..<3).allSatisfy { p[$0] >= lower[$0] - tolerance && p[$0] <= upper[$0] + tolerance }
        }

        /// The twelve edges as pairs of corner indices.
        static let edges: [(Int, Int)] = [(0, 1), (2, 3), (4, 5), (6, 7), (0, 2), (1, 3), (4, 6), (5, 7), (0, 4), (1, 5), (2, 6), (3, 7)]
    }

    /// The part of the line A + t·s⃗ inside the box (Liang–Barsky), ordered along s⃗; nil when
    /// the line misses the box or only touches it.
    public static func clip(_ line: SpatialGeometry.Line, to box: Box) -> (start: [Double], end: [Double])? {
        var low = -Double.infinity, high = Double.infinity
        for i in 0..<3 {
            let p = line.point[i], s = line.direction[i]
            if s == 0 {
                guard p >= box.lower[i], p <= box.upper[i] else { return nil }
                continue
            }
            let t1 = (box.lower[i] - p) / s, t2 = (box.upper[i] - p) / s
            low = Swift.max(low, Swift.min(t1, t2))
            high = Swift.min(high, Swift.max(t1, t2))
        }
        // A piece no longer than rounding noise next to the box is a touch, measured in space
        // (the direction may be 10¹⁵ or 10⁻¹⁵ long).
        let speed = length(line.direction)
        guard low.isFinite, high.isFinite, speed > 0, high - low > 1e-12 * box.radius / speed else { return nil }
        return (line.at(low), line.at(high))
    }

    /// The polygon the plane cuts from the box, its corners in order around the plane's normal;
    /// empty when the plane misses the box or only touches an edge or a corner.
    public static func section(_ plane: SpatialGeometry.Plane, in box: Box) -> [[Double]] {
        let corners = box.corners
        let values = corners.map { plane.value($0) }
        let size = box.radius
        var points: [[Double]] = []
        func add(_ p: [Double]) {
            // Halved differences and the scaled length, so corners of a huge box still compare.
            guard !points.contains(where: { length(zip($0, p).map { $0 / 2 - $1 / 2 }) <= 0.5e-9 * size }) else { return }
            points.append(p)
        }
        for (i, j) in Box.edges {
            let fi = values[i], fj = values[j]
            if fi == 0 { add(corners[i]) }
            if fj == 0 { add(corners[j]) }
            if (fi < 0 && fj > 0) || (fi > 0 && fj < 0) {
                let t = fi / (fi - fj)
                add(zip(corners[i], corners[j]).map { $0 + t * ($1 - $0) })
            }
        }
        guard points.count >= 3 else { return [] }
        // Order the corners by their angle about the centre in the plane's own basis.
        let n = plane.normal
        let helper: [Double] = Swift.abs(n[0]) <= Swift.abs(n[1]) && Swift.abs(n[0]) <= Swift.abs(n[2]) ? [1, 0, 0]
            : (Swift.abs(n[1]) <= Swift.abs(n[2]) ? [0, 1, 0] : [0, 0, 1])
        let u = VectorGeometry.cross(n, helper)
        let v = VectorGeometry.cross(n, u)
        let center = (0..<3).map { i in points.reduce(0) { $0 + $1[i] } / Double(points.count) }
        return points.sorted { p, q in
            let a = zip(p, center).map(-), b = zip(q, center).map(-)
            return atan2(VectorGeometry.dot(a, v), VectorGeometry.dot(a, u)) < atan2(VectorGeometry.dot(b, v), VectorGeometry.dot(b, u))
        }
    }

    /// |v| without overflow or underflow of the squares (a box 10²⁰⁰ wide).
    static func length(_ v: [Double]) -> Double {
        let largest = v.map(Swift.abs).max() ?? 0
        guard largest > 0, largest.isFinite else { return largest }
        return largest * v.reduce(0) { $0 + ($1 / largest) * ($1 / largest) }.squareRoot()
    }

    // MARK: Polyhedra

    /// A polyhedron to draw. Each face lists its corners counter-clockwise as seen from outside;
    /// faces with the same smooth group approximate one curved surface, so the edges between
    /// them are drawn only where the surface turns away from the viewer (its outline).
    public struct Polyhedron: Sendable, Hashable {
        public var vertices: [[Double]]
        public var faces: [[Int]]
        public var smoothGroups: [Int?]

        /// Faces with fewer than three corners, or with a corner outside `vertices` or without
        /// three coordinates, are left out; a missing smooth group means a sharp face.
        public init(vertices: [[Double]], faces: [[Int]], smoothGroups: [Int?]? = nil) {
            self.vertices = vertices
            let groups = smoothGroups ?? []
            var keptFaces: [[Int]] = [], keptGroups: [Int?] = []
            for (k, face) in faces.enumerated()
            where face.count >= 3 && face.allSatisfy({ vertices.indices.contains($0) && vertices[$0].count == 3 }) {
                keptFaces.append(face)
                keptGroups.append(k < groups.count ? groups[k] : nil)
            }
            self.faces = keptFaces
            self.smoothGroups = keptGroups
        }

        /// The outward normal of a face (Newell's method, so it also holds for slightly
        /// non-planar faces); its length is twice the face's area.
        public func normal(of face: Int) -> [Double] {
            Self.newell(faces[face].map { vertices[$0] })
        }

        /// Whether a face is turned towards the viewer. The normal is taken of the corners moved
        /// to the first one and divided by the largest coordinate, so a face 10⁻²⁰⁰ or 10²⁰⁰ wide
        /// neither vanishes nor overflows. Only a side shorter than the smallest subnormal fraction
        /// of the longest (about 10⁻³²³ of it) rounds to zero, and such a face counts as edge-on.
        public func isFrontFacing(_ face: Int, in view: View) -> Bool {
            let corners = faces[face].map { vertices[$0] }
            // Halved before subtracting, so corners at ±10³⁰⁸ give finite offsets.
            let offsets = corners.map { p in zip(p, corners[0]).map { $0 / 2 - $1 / 2 } }
            let largest = offsets.joined().map { Swift.abs($0) }.max() ?? 0
            guard largest > 0, largest.isFinite else { return false }
            let n = Self.newell(offsets.map { $0.map { $0 / largest } })
            return VectorGeometry.dot(n, view.eye) > 1e-9 * Sketch3D.length(n)
        }

        private static func newell(_ corners: [[Double]]) -> [Double] {
            var n = [0.0, 0, 0]
            for (k, p) in corners.enumerated() {
                let q = corners[(k + 1) % corners.count]
                n[0] += (p[1] - q[1]) * (p[2] + q[2])
                n[1] += (p[2] - q[2]) * (p[0] + q[0])
                n[2] += (p[0] - q[0]) * (p[1] + q[1])
            }
            return n
        }
    }

    public struct Edge: Sendable, Hashable {
        public var start: [Double]
        public var end: [Double]
        public var visible: Bool
    }

    /// The edges to draw: a sharp edge is visible when one of its faces is turned towards the
    /// viewer and hidden otherwise; a smooth edge is drawn only on the outline, where one of
    /// its faces is turned towards the viewer and the other away. An edge of a single face
    /// counts as sharp.
    public static func edges(of solid: Polyhedron, in view: View) -> [Edge] {
        var adjacent: [Int: [Int]] = [:]
        var order: [Int] = []
        let count = solid.vertices.count
        for (f, face) in solid.faces.enumerated() {
            for (k, i) in face.enumerated() {
                let j = face[(k + 1) % face.count]
                let key = Swift.min(i, j) * count + Swift.max(i, j)
                if adjacent[key] == nil { order.append(key) }
                adjacent[key, default: []].append(f)
            }
        }
        let front = (0..<solid.faces.count).map { solid.isFrontFacing($0, in: view) }
        var result: [Edge] = []
        for key in order {
            let around = adjacent[key] ?? []
            let i = key / count, j = key % count
            let facing = around.map { front[$0] }
            let groups = around.map { solid.smoothGroups[$0] }
            let smooth = around.count == 2 && groups[0] != nil && groups[0] == groups[1]
            if smooth {
                guard facing[0] != facing[1] else { continue }
                result.append(Edge(start: solid.vertices[i], end: solid.vertices[j], visible: true))
            } else {
                result.append(Edge(start: solid.vertices[i], end: solid.vertices[j], visible: facing.contains(true)))
            }
        }
        return result
    }

    /// The faces turned towards the viewer as lists of corners, the farthest first, for a
    /// translucent fill.
    public static func frontFaces(of solid: Polyhedron, in view: View) -> [[[Double]]] {
        (0..<solid.faces.count)
            .filter { solid.isFrontFacing($0, in: view) }
            .map { solid.faces[$0].map { solid.vertices[$0] } }
            .sorted { depth($0, view) < depth($1, view) }
    }

    /// The mean depth of a polygon towards the viewer.
    public static func depth(_ corners: [[Double]], _ view: View) -> Double {
        guard !corners.isEmpty else { return 0 }
        return corners.reduce(0) { $0 + view.project($1).depth } / Double(corners.count)
    }
}
