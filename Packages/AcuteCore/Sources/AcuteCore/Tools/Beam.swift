import Foundation

/// A straight beam in the plane (Osnove statike at FGG): support reactions and the shear force
/// V(x) and bending moment M(x) from point forces, linearly varying distributed loads and
/// couples. Forces and loads are positive downwards, couples positive counterclockwise;
/// V is the resultant of the forces left of the section (upwards positive) and M is positive
/// when the beam sags (tension at the bottom), so dM/dx = V and dV/dx = −q.
public struct Beam: Sendable, Hashable {
    public enum Support: Sendable, Hashable {
        /// A pin at `left` and a roller at `right` (overhangs allowed).
        case simple(left: Double, right: Double)
        /// Fixed at x = 0, free at x = L.
        case fixedLeft
        /// Fixed at x = L, free at x = 0.
        case fixedRight
    }

    public enum Load: Sendable, Hashable {
        case force(Double, at: Double)
        /// q(s) from `start` at x = `from` to `end` at x = `to`, varying linearly.
        case distributed(start: Double, end: Double, from: Double, to: Double)
        case couple(Double, at: Double)
    }

    public struct Reaction: Sendable, Hashable {
        public var position: Double
        /// Upwards positive.
        public var force: Double
    }

    public struct Reactions: Sendable, Hashable {
        public var forces: [Reaction]
        /// The fixed-end moment (counterclockwise positive) of a cantilever.
        public var moment: Double?
    }

    public var length: Double
    public var support: Support
    public var loads: [Load]

    public init(length: Double, support: Support, loads: [Load]) {
        self.length = length
        self.support = support
        self.loads = loads
    }

    /// Checks the geometry: a positive length, supports and loads on the beam.
    public func validated() throws(MathError) -> Beam {
        guard length > 0, length.isFinite else { throw .domain("dolžina nosilca mora biti pozitivna") }
        if case .simple(let a, let b) = support {
            guard a >= 0, b <= length, a < b else { throw .domain("podpori morata biti na nosilcu, leva pred desno") }
        }
        for load in loads {
            switch load {
            case .force(let f, let x), .couple(let f, let x):
                guard f.isFinite, x >= 0, x <= length else { throw .domain("obtežba mora biti na nosilcu") }
            case .distributed(let q1, let q2, let x1, let x2):
                guard q1.isFinite, q2.isFinite, x1 >= 0, x2 <= length, x1 < x2 else {
                    throw .domain("zvezna obtežba mora biti na nosilcu, z začetkom pred koncem")
                }
            }
        }
        return self
    }

    // MARK: Loads left of a section

    /// The loads left of x (at x itself only when `including`): their resultant Σ F + ∫ q ds,
    /// their moment about the section Σ F·(x − x_F) + ∫ q(s)·(x − s) ds and the sum of couples.
    func loadsLeft(of x: Double, including: Bool) -> (force: Double, moment: Double, couples: Double) {
        var force = 0.0, moment = 0.0, couples = 0.0
        for load in loads {
            switch load {
            case .force(let f, let at):
                if at < x || (including && at == x) {
                    force += f
                    moment += f * (x - at)
                }
            case .couple(let c, let at):
                if at < x || (including && at == x) { couples += c }
            case .distributed(let q1, let q2, let x1, let x2):
                guard x > x1 else { continue }
                let t = Swift.min(x, x2) - x1, k = (q2 - q1) / (x2 - x1)
                let resultant = q1 * t + k * t * t / 2
                // ∫ q(s)·(s − x₁) ds over the loaded part
                let first = q1 * t * t / 2 + k * t * t * t / 3
                force += resultant
                moment += resultant * (x - x1) - first
            }
        }
        return (force, moment, couples)
    }

    /// The vertical reactions and, for a cantilever, the fixed-end moment.
    public func reactions() -> Reactions {
        let all = loadsLeft(of: length, including: true)
        let clean = NumericCalculus.clean
        switch support {
        case .simple(let a, let b):
            // Moments about the right support: −(b − a)·R_a + Σ F·(b − x_F) + ∫ q·(b − s) ds + Σ C = 0,
            // where the moment of all loads about b is their moment about L minus (L − b)·Σ F.
            let aboutB = all.moment - (length - b) * all.force
            let ra = (aboutB + all.couples) / (b - a)
            return Reactions(forces: [Reaction(position: a, force: clean(ra)), Reaction(position: b, force: clean(all.force - ra))], moment: nil)
        case .fixedLeft:
            // Moments about 0: M_A − Σ F·x_F − ∫ q·s ds + Σ C = 0, with Σ F·x_F = L·Σ F − (moment about L).
            let aboutStart = length * all.force - all.moment
            return Reactions(forces: [Reaction(position: 0, force: clean(all.force))], moment: clean(aboutStart - all.couples))
        case .fixedRight:
            // Moments about L: M_B + Σ F·(L − x_F) + ∫ q·(L − s) ds + Σ C = 0.
            return Reactions(forces: [Reaction(position: length, force: clean(all.force))], moment: clean(-all.moment - all.couples))
        }
    }

    /// V(x): the resultant of the forces left of the section (just right of x when `rightSide`).
    public func shear(at x: Double, rightSide: Bool = true) -> Double {
        let left = loadsLeft(of: x, including: rightSide)
        var v = -left.force
        for r in reactions().forces where r.position < x || (rightSide && r.position == x) { v += r.force }
        return v
    }

    /// M(x), sagging positive (just right of x when `rightSide`).
    public func moment(at x: Double, rightSide: Bool = true) -> Double {
        let left = loadsLeft(of: x, including: rightSide)
        let r = reactions()
        var m = -left.moment - left.couples
        for reaction in r.forces where reaction.position < x || (rightSide && reaction.position == x) {
            m += reaction.force * (x - reaction.position)
        }
        // The fixed-end moment at 0 acts like a couple applied there.
        if case .fixedLeft = support, let fixed = r.moment, x > 0 || rightSide { m -= fixed }
        return m
    }

    /// Positions where V or M may jump or change form: the ends, supports and loads.
    public var keyPoints: [Double] {
        var points: Set<Double> = [0, length]
        if case .simple(let a, let b) = support { points.formUnion([a, b]) }
        for load in loads {
            switch load {
            case .force(_, let x), .couple(_, let x): points.insert(x)
            case .distributed(_, _, let x1, let x2): points.formUnion([x1, x2])
            }
        }
        return points.filter { $0 >= 0 && $0 <= length }.sorted()
    }

    /// The largest |M| and where it occurs: at a key point or where V changes sign.
    public func maximumMoment() -> (position: Double, value: Double) {
        var candidates: [(position: Double, value: Double)] = []
        let points = keyPoints
        for x in points {
            if x > 0 { candidates.append((x, moment(at: x, rightSide: false))) }
            if x < length { candidates.append((x, moment(at: x, rightSide: true))) }
        }
        for (lo, hi) in zip(points, points.dropFirst()) where hi > lo {
            // Inside a segment V is continuous and at most quadratic: look for sign changes.
            let steps = 64, h = (hi - lo) / Double(steps)
            var previous = shear(at: lo)
            for i in 1...steps {
                let x = i == steps ? hi - h * 1e-9 : lo + h * Double(i)
                let v = shear(at: x)
                if v == 0 {
                    candidates.append((x, moment(at: x)))
                } else if previous != 0, (previous < 0) != (v < 0),
                          let root = RootFinder.brent({ shear(at: $0) }, x - h, x) {
                    candidates.append((root, moment(at: root)))
                }
                previous = v
            }
        }
        let best = candidates.max { Swift.abs($0.value) < Swift.abs($1.value) } ?? (0, 0)
        return (NumericCalculus.clean(best.position), NumericCalculus.clean(best.value))
    }
}
