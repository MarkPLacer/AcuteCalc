import Foundation
import Metal
import Testing
@testable import AcuteCalc

/// When the frame ring grows, Metal 4 frames still in flight read the old buffers (Metal 4 command
/// buffers keep no references), so Metal4Backend keeps them alive and resident until the shared
/// event shows that their last frame completed (Audit: MTL-02). The bookkeeping is plain logic and
/// runs in the simulator; the Metal 4 backend itself needs a device.
@MainActor
@Suite struct RetiredBuffersTests {
    @Test func buffersStayUntilTheirLastFrameCompleted() {
        var retired = RetiredBuffers<Int>()
        retired.retire([10, 11, 12], lastFrame: 7)    // the ring grew after submitting frame 7
        let afterFrame5 = retired.release(completedThrough: 5)
        let afterFrame6 = retired.release(completedThrough: 6)    // frame 7 may still run
        let stillKept = !retired.isEmpty
        let afterFrame7 = retired.release(completedThrough: 7)
        let emptied = retired.isEmpty
        let again = retired.release(completedThrough: 9)
        #expect(afterFrame5.isEmpty)
        #expect(afterFrame6.isEmpty)
        #expect(stillKept)
        #expect(afterFrame7 == [10, 11, 12])
        #expect(emptied)
        #expect(again.isEmpty)    // released only once
    }

    @Test func eachGrowthIsReleasedOnItsOwn() {
        var retired = RetiredBuffers<Int>()
        retired.retire([1, 2, 3], lastFrame: 4)
        retired.retire([4, 5, 6], lastFrame: 9)
        let first = retired.release(completedThrough: 8)
        let none = retired.release(completedThrough: 8)
        let second = retired.release(completedThrough: 12)
        #expect(first == [1, 2, 3])
        #expect(none.isEmpty)
        #expect(second == [4, 5, 6])
        #expect(retired.isEmpty)
    }

    @Test func nothingToRetireKeepsNothing() {
        var retired = RetiredBuffers<Int>()
        retired.retire([], lastFrame: 3)
        #expect(retired.isEmpty)
    }

    /// The real case: the buffers a FrameRing growth replaces stay alive while retired and are
    /// freed once released.
    @Test(.enabled(if: MTLCreateSystemDefaultDevice() != nil, "needs a Metal device"))
    func ringGrowthBuffersLiveUntilReleased() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        weak var old: (any MTLBuffer)?
        var retired = RetiredBuffers<any MTLBuffer>()
        var overflowed = false
        var replacedAll = false
        try autoreleasepool {
            let ring = try #require(FrameRing(device: device, capacity: 4096))
            ring.onBuffersChanged = { replaced, _ in retired.retire(replaced, lastFrame: 3) }
            old = ring.buffers[0]
            ring.beginFrame(3)
            overflowed = ring.write(array: [UInt8](repeating: 0, count: 8192)) == nil    // too big: grow
            ring.endFrame()
            replacedAll = ring.buffers[0] !== old
        }
        let aliveWhileRetired = old != nil    // frame 3 may still read it
        var tooEarly = 0
        var released = 0
        autoreleasepool {
            tooEarly = retired.release(completedThrough: 2).count
            released = retired.release(completedThrough: 3).count
        }
        let freed = old == nil
        #expect(overflowed)
        #expect(replacedAll)
        #expect(aliveWhileRetired)
        #expect(tooEarly == 0)
        #expect(released == FrameRing.framesInFlight)
        #expect(freed)
    }
}
