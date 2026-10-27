import Metal
import Testing
@testable import AcuteCalc

/// The background warm-up compiles `MetalContext.knownPipelines` (Audit: MTL-07); a wrong name
/// or format there would only waste the warm-up and log an error. Metal 3 path (simulator); the
/// Metal 4 compiler needs a device.
@MainActor
@Suite(.enabled(if: MTLCreateSystemDefaultDevice() != nil, "needs a Metal device"))
struct PipelineWarmUpTests {
    @Test func everyKnownPipelineCompiles() {
        let context = MetalContext.shared
        let specs = MetalContext.knownPipelines
        let compiled = specs.filter { context.pipeline($0, backend: .metal3) != nil }
        #expect(specs.count == 8)
        #expect(compiled.count == specs.count)
        #expect(Set(specs).count == specs.count)    // no duplicates
    }
}
