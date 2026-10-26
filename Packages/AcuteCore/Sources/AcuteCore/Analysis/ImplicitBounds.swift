import Foundation

/// Where an implicit curve F(x, y) = 0 lies inside a search window, found from the sign
/// changes of F on a grid. Used to frame circles, ellipses and other relations.
public enum ImplicitBounds {
    public struct Result: Sendable, Equatable {
        public var x: ClosedRange<Double>
        public var y: ClosedRange<Double>
        /// False when the curve reaches the edge of the search window (lines, half-planes …).
        public var isBounded: Bool
    }

    /// `evaluateRow` returns F for a row of x values at one y.
    public static func find(x windowX: ClosedRange<Double>, y windowY: ClosedRange<Double>, resolution: Int = 160,
                            evaluateRow: (_ xs: [Double], _ y: Double) -> [Double]) -> Result? {
        let n = Swift.max(8, resolution)
        let dx = (windowX.upperBound - windowX.lowerBound) / Double(n)
        let dy = (windowY.upperBound - windowY.lowerBound) / Double(n)
        guard dx > 0, dy > 0, dx.isFinite, dy.isFinite else { return nil }
        let xs = (0...n).map { windowX.lowerBound + Double($0) * dx }
        var minI = Int.max, maxI = Int.min, minJ = Int.max, maxJ = Int.min
        var previous: [Double] = []
        for j in 0...n {
            let row = evaluateRow(xs, windowY.lowerBound + Double(j) * dy)
            guard row.count == xs.count else { return nil }
            if j > 0 {
                for i in 0..<n {
                    let a = previous[i], b = previous[i + 1], c = row[i], d = row[i + 1]
                    guard a.isFinite, b.isFinite, c.isFinite, d.isFinite else { continue }
                    let low = Swift.min(Swift.min(a, b), Swift.min(c, d))
                    let high = Swift.max(Swift.max(a, b), Swift.max(c, d))
                    // The cell holds part of the curve when F changes sign (or vanishes) in it.
                    guard low <= 0, high >= 0 else { continue }
                    minI = Swift.min(minI, i); maxI = Swift.max(maxI, i)
                    minJ = Swift.min(minJ, j - 1); maxJ = Swift.max(maxJ, j - 1)
                }
            }
            previous = row
        }
        guard minI <= maxI else { return nil }
        let bounded = minI > 0 && maxI < n - 1 && minJ > 0 && maxJ < n - 1
        return Result(x: (windowX.lowerBound + Double(minI) * dx)...(windowX.lowerBound + Double(maxI + 1) * dx),
                      y: (windowY.lowerBound + Double(minJ) * dy)...(windowY.lowerBound + Double(maxJ + 1) * dy),
                      isBounded: bounded)
    }

    /// Runs a compiled F(x, y) (slots x and y, parameters in order).
    public static func find(program: Program, parameters: [Double] = [], x windowX: ClosedRange<Double>,
                            y windowY: ClosedRange<Double>, resolution: Int = 160) -> Result? {
        let vm = RealVM(program: program, parameters: parameters)
        return find(x: windowX, y: windowY, resolution: resolution) { xs, y in vm.evaluate(xs: xs, y: y) }
    }
}
