import OSLog

/// Intervals for the Points of Interest track in Instruments (os_signpost, Time Profiler,
/// Animation Hitches): evaluation, curve sampling, function analysis, pipeline compilation and
/// the frames of the 2D graph.
nonisolated enum Signposts {
    static let signposter = OSSignposter(subsystem: "com.markplacer.acutecalc", category: .pointsOfInterest)

    /// Runs `work` inside an interval named `name`.
    static func interval<T>(_ name: StaticString, _ work: () throws -> T) rethrows -> T {
        try signposter.withIntervalSignpost(name, id: signposter.makeSignpostID(), around: work)
    }
}
