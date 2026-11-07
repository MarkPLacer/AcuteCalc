import Foundation
import Metal
import Observation

/// Domain and code of a failed GPU command buffer. Unlike its message they are not localized, so they name
/// the error on any device (MTLCommandBufferError.Code; on Metal 4 also MTL4CommandQueueError.Code).
nonisolated struct GPUFailure: Equatable, Sendable {
    var domain: String
    var code: Int

    init(domain: String, code: Int) {
        self.domain = domain
        self.code = code
    }

    init(_ error: NSError) {
        self.init(domain: error.domain, code: error.code)
    }
}

/// GPU failures since launch, for Nastavitve › Sence in odsevi: the log (Logger, category "Metal") needs a
/// Mac, and the app is tested on devices without one.
@Observable
final class GPUDiagnostics {
    static let shared = GPUDiagnostics()

    /// The first failure since launch. After a GPU fault the system often fails further work only because of
    /// it, so the first one is kept, not the last.
    private(set) var firstFailure: GPUFailure?
    /// The first failure that stopped ray tracing: a frame that traced rays failed. From then on surfaces are
    /// drawn without ray tracing until the app restarts; the setting keeps its value.
    private(set) var rayTracingFailure: GPUFailure?

    func record(_ failure: GPUFailure, stopsRayTracing: Bool) {
        if firstFailure == nil { firstFailure = failure }
        if stopsRayTracing, rayTracingFailure == nil { rayTracingFailure = failure }
    }

    /// Records `error` from a completion or commit feedback handler, which run on any thread, on the main actor.
    nonisolated static func report(_ error: NSError, stopsRayTracing: Bool) {
        // Work committed after the app moved to the background fails as "not permitted" (Preparing your Metal
        // app to run in the background). That is no GPU fault, and the next frame, once the app is active
        // again, works.
        guard !isNotPermitted(error) else { return }
        let failure = GPUFailure(error)
        Task { @MainActor in
            GPUDiagnostics.shared.record(failure, stopsRayTracing: stopsRayTracing)
        }
    }

    /// Whether `error` is the "not permitted" error of a Metal 3 command buffer or a Metal 4 commit.
    nonisolated static func isNotPermitted(_ error: NSError) -> Bool {
        if error.domain == MTLCommandBufferError.errorDomain {
            return error.code == Int(MTLCommandBufferError.notPermitted.rawValue)
        }
        #if !targetEnvironment(simulator)
        if error.domain == MTL4CommandQueueError.errorDomain {
            return error.code == Int(MTL4CommandQueueError.notPermitted.rawValue)
        }
        #endif
        return false
    }
}
