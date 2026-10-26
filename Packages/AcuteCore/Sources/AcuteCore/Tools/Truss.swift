import Foundation

/// Plane trusses (Osnove statike at FGG) by the method of joints: the equilibrium of every joint,
/// ΣF_x = 0 and ΣF_y = 0, solved together for the axial forces of the bars (tension positive)
/// and the support reactions. Joints are numbered from 0.
public enum Truss {
    public struct Bar: Sendable, Hashable {
        public var from: Int
        public var to: Int

        public init(from: Int, to: Int) {
            self.from = from
            self.to = to
        }
    }

    public enum Support: Sendable, Hashable {
        /// A pin (nepomična podpora): both components of the reaction.
        case pin(Int)
        /// A roller (pomična podpora): one reaction along `angle` from the x axis (π/2: vertical).
        case roller(Int, angle: Double)

        var joint: Int {
            switch self {
            case .pin(let j), .roller(let j, _): j
            }
        }
    }

    public struct Load: Sendable, Hashable {
        public var joint: Int
        public var fx: Double
        public var fy: Double

        public init(joint: Int, fx: Double, fy: Double) {
            self.joint = joint
            self.fx = fx
            self.fy = fy
        }
    }

    public struct Reaction: Sendable, Hashable {
        public var joint: Int
        public var x: Double
        public var y: Double
    }

    public struct Solution: Sendable, Hashable {
        /// N of each bar, tension positive.
        public var forces: [Double]
        public var reactions: [Reaction]
    }

    public static func solve(joints: [SIMD2<Double>], bars: [Bar], supports: [Support], loads: [Load]) throws(MathError) -> Solution {
        let n = joints.count
        guard n >= 2, !bars.isEmpty else { throw .domain("paličje potrebuje vsaj dve vozlišči in eno palico") }
        guard joints.allSatisfy({ $0.x.isFinite && $0.y.isFinite }), loads.allSatisfy({ $0.fx.isFinite && $0.fy.isFinite }) else {
            throw .domain("koordinate in sile morajo biti končna števila")
        }
        for support in supports {
            if case .roller(_, let angle) = support, !angle.isFinite { throw .domain("smer pomične podpore mora biti končna") }
        }
        for bar in bars {
            guard (0..<n).contains(bar.from), (0..<n).contains(bar.to), bar.from != bar.to else {
                throw .domain("palica povezuje neobstoječi ali isti vozlišči")
            }
            guard length(joints[bar.to] - joints[bar.from]) > 0 else { throw .domain("palica ima dolžino 0") }
        }
        guard supports.allSatisfy({ (0..<n).contains($0.joint) }), loads.allSatisfy({ (0..<n).contains($0.joint) }) else {
            throw .domain("podpora ali obtežba je v neobstoječem vozlišču")
        }
        let reactionCount = supports.reduce(0) { count, support in
            switch support {
            case .pin: count + 2
            case .roller: count + 1
            }
        }
        let unknowns = bars.count + reactionCount
        guard unknowns == 2 * n else {
            throw .domain(unknowns > 2 * n ? "paličje je statično nedoločeno (palic in reakcij je več kot 2·vozlišč)"
                                           : "paličje je mehanizem (palic in reakcij je manj kot 2·vozlišč)")
        }
        // Rows: x and y of every joint; columns: bar forces, then the reaction components.
        var matrix = [[Double]](repeating: [Double](repeating: 0, count: unknowns), count: 2 * n)
        var rhs = [Double](repeating: 0, count: 2 * n)
        for (k, bar) in bars.enumerated() {
            let d = joints[bar.to] - joints[bar.from]
            let u = d / length(d)
            // Tension pulls each joint towards the other end of the bar.
            matrix[2 * bar.from][k] += u.x
            matrix[2 * bar.from + 1][k] += u.y
            matrix[2 * bar.to][k] -= u.x
            matrix[2 * bar.to + 1][k] -= u.y
        }
        var column = bars.count
        for support in supports {
            switch support {
            case .pin(let j):
                matrix[2 * j][column] = 1
                matrix[2 * j + 1][column + 1] = 1
                column += 2
            case .roller(let j, let angle):
                matrix[2 * j][column] = cos(angle)
                matrix[2 * j + 1][column] = sin(angle)
                column += 1
            }
        }
        for load in loads {
            rhs[2 * load.joint] -= load.fx
            rhs[2 * load.joint + 1] -= load.fy
        }
        guard let x = Multivariable.solveLinear(matrix, rhs) else {
            throw .domain("paličje je geometrijsko nestabilno (enačbe ravnotežja niso enolično rešljive)")
        }
        let clean = NumericCalculus.clean
        var reactions: [Reaction] = []
        column = bars.count
        for support in supports {
            switch support {
            case .pin(let j):
                reactions.append(Reaction(joint: j, x: clean(x[column]), y: clean(x[column + 1])))
                column += 2
            case .roller(let j, let angle):
                reactions.append(Reaction(joint: j, x: clean(x[column] * cos(angle)), y: clean(x[column] * sin(angle))))
                column += 1
            }
        }
        return Solution(forces: x.prefix(bars.count).map(clean), reactions: reactions)
    }

    static func length(_ v: SIMD2<Double>) -> Double { (v * v).sum().squareRoot() }
}
