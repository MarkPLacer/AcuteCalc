import Foundation
import Metal
import Testing
@testable import AcuteCalc

/// Audit critic:1: GPU errors were only logged, and the log needs a Mac. Nastavitve › Sence in odsevi shows
/// the first failure since launch (later ones are often only its consequences), and a failed frame that
/// traced rays turns ray tracing off until the app restarts.
@MainActor
@Suite struct GPUDiagnosticsTests {
    @Test func theFirstFailureIsKept() {
        let diagnostics = GPUDiagnostics()
        let first = GPUFailure(domain: MTLCommandBufferError.errorDomain, code: Int(MTLCommandBufferError.pageFault.rawValue))
        let later = GPUFailure(domain: MTLCommandBufferError.errorDomain, code: Int(MTLCommandBufferError.timeout.rawValue))
        diagnostics.record(first, stopsRayTracing: false)
        diagnostics.record(later, stopsRayTracing: false)
        #expect(diagnostics.firstFailure == first)
        #expect(diagnostics.rayTracingFailure == nil)
    }

    @Test func aFailedTracedFrameStopsRayTracing() {
        let diagnostics = GPUDiagnostics()
        let untraced = GPUFailure(domain: "A", code: 1)
        let traced = GPUFailure(domain: "B", code: 2)
        diagnostics.record(untraced, stopsRayTracing: false)
        diagnostics.record(traced, stopsRayTracing: true)
        diagnostics.record(GPUFailure(domain: "C", code: 3), stopsRayTracing: true)
        #expect(diagnostics.firstFailure == untraced)
        #expect(diagnostics.rayTracingFailure == traced)
    }

    /// Work committed after the app moved to the background fails as "not permitted": no GPU fault.
    @Test func notPermittedIsNoGPUFault() {
        let notPermitted = NSError(domain: MTLCommandBufferError.errorDomain, code: Int(MTLCommandBufferError.notPermitted.rawValue))
        let pageFault = NSError(domain: MTLCommandBufferError.errorDomain, code: Int(MTLCommandBufferError.pageFault.rawValue))
        let elsewhere = NSError(domain: "Other", code: Int(MTLCommandBufferError.notPermitted.rawValue))
        #expect(GPUDiagnostics.isNotPermitted(notPermitted))
        #expect(!GPUDiagnostics.isNotPermitted(pageFault))
        #expect(!GPUDiagnostics.isNotPermitted(elsewhere))
        #expect(GPUFailure(pageFault) == GPUFailure(domain: MTLCommandBufferError.errorDomain, code: Int(MTLCommandBufferError.pageFault.rawValue)))
    }
}
