import Metal

/// A region of a frame buffer holding data for one draw.
struct BufferSlice {
    let buffer: MTLBuffer
    let offset: Int
}

/// Per-frame upload memory: one buffer per in-flight frame, bump-allocated each frame.
/// Everything a frame needs (uniforms, transformed curves, bytecode) is copied here,
/// so buffers never change while the GPU reads them and no per-draw allocations happen.
final class FrameRing {
    static let framesInFlight = 3
    private let device: MTLDevice
    private(set) var buffers: [MTLBuffer] = []
    private var capacity: Int
    private var current = 0
    private var offset = 0
    /// Called when buffers are (re)created so residency sets can be updated.
    var onBuffersChanged: (([MTLBuffer], [MTLBuffer]) -> Void)?

    init?(device: MTLDevice, capacity: Int = 1 << 20) {
        self.device = device
        self.capacity = capacity
        guard allocateBuffers(capacity: capacity) else { return nil }
    }

    @discardableResult
    private func allocateBuffers(capacity: Int) -> Bool {
        let old = buffers
        var created: [MTLBuffer] = []
        for i in 0..<FrameRing.framesInFlight {
            guard let b = device.makeBuffer(length: capacity, options: .storageModeShared) else { return false }
            b.label = "FrameRing[\(i)]"
            created.append(b)
        }
        buffers = created
        self.capacity = capacity
        onBuffersChanged?(old, created)
        return true
    }

    func beginFrame(_ frameNumber: UInt64) {
        current = Int(frameNumber % UInt64(FrameRing.framesInFlight))
        offset = 0
    }

    /// Grows the ring when a frame needed more space than available (applies from the next frame).
    private var requestedCapacity = 0

    func endFrame() {
        if requestedCapacity > capacity {
            var newCapacity = capacity
            while newCapacity < requestedCapacity { newCapacity *= 2 }
            requestedCapacity = 0
            allocateBuffers(capacity: newCapacity)
        }
    }

    private func reserve(_ length: Int, alignment: Int = 256) -> BufferSlice? {
        let aligned = (offset + alignment - 1) / alignment * alignment
        guard aligned + length <= capacity else {
            requestedCapacity = max(requestedCapacity, (aligned + length) * 2)
            return nil
        }
        offset = aligned + length
        return BufferSlice(buffer: buffers[current], offset: aligned)
    }

    func write<T>(_ value: T) -> BufferSlice? {
        var copy = value
        let size = MemoryLayout<T>.stride
        guard let slice = reserve(max(size, 16)) else { return nil }
        withUnsafeBytes(of: &copy) { raw in
            slice.buffer.contents().advanced(by: slice.offset).copyMemory(from: raw.baseAddress!, byteCount: size)
        }
        return slice
    }

    func write<T>(array: [T]) -> BufferSlice? {
        let size = MemoryLayout<T>.stride * array.count
        guard let slice = reserve(max(size, 16)) else { return nil }
        if size > 0 {
            array.withUnsafeBytes { raw in
                slice.buffer.contents().advanced(by: slice.offset).copyMemory(from: raw.baseAddress!, byteCount: size)
            }
        }
        return slice
    }

    /// Reserves space and lets the caller fill it in place (avoids an intermediate array).
    func write<T>(count: Int, of type: T.Type, _ fill: (UnsafeMutableBufferPointer<T>) -> Void) -> BufferSlice? {
        let size = MemoryLayout<T>.stride * count
        guard count > 0, let slice = reserve(size) else { return nil }
        let pointer = slice.buffer.contents().advanced(by: slice.offset).bindMemory(to: T.self, capacity: count)
        fill(UnsafeMutableBufferPointer(start: pointer, count: count))
        return slice
    }
}

/// The subset of render-encoder functionality the graph renderers need, implemented for
/// both Metal 4 (argument tables) and Metal 3 (per-encoder bindings).
protocol GPUEncoder {
    func setPipeline(_ state: MTLRenderPipelineState)
    /// Binds `slice` at `index` for the shader `stages` whose functions read it. Metal 3 binds each stage on
    /// its own; Metal 4 has one argument table for both stages, so there `stages` changes nothing.
    func bind(_ slice: BufferSlice, at index: Int, stages: MTLRenderStages)
    func draw(_ type: MTLPrimitiveType, vertexStart: Int, vertexCount: Int, instanceCount: Int)
    func setDepthState(_ state: MTLDepthStencilState?)
    func setCullMode(_ mode: MTLCullMode)
    /// Binds an acceleration structure for fragment functions that trace rays. That is all a traced draw
    /// needs: a built structure references none of the buffers it was built from, Metal 3 makes a resource
    /// bound to a stage resident without `useResources`, and Metal 4 takes it from the residency set.
    func bindAccelerationStructure(_ structure: MTLAccelerationStructure, at index: Int)
}

extension GPUEncoder {
    func draw(_ type: MTLPrimitiveType, vertexCount: Int, instanceCount: Int = 1) {
        draw(type, vertexStart: 0, vertexCount: vertexCount, instanceCount: instanceCount)
    }
}

#if !targetEnvironment(simulator)
final class Metal4Encoder: GPUEncoder {
    let encoder: MTL4RenderCommandEncoder
    let table: MTL4ArgumentTable
    /// Whether the frame bound an acceleration structure, i.e. traces rays (Metal4Backend reports its failure).
    private(set) var tracesRays = false

    init(encoder: MTL4RenderCommandEncoder, table: MTL4ArgumentTable) {
        self.encoder = encoder
        self.table = table
    }

    func setPipeline(_ state: MTLRenderPipelineState) { encoder.setRenderPipelineState(state) }

    func bind(_ slice: BufferSlice, at index: Int, stages: MTLRenderStages) {
        // The table serves both stages (Metal4Backend sets it for vertex and fragment). Metal snapshots it at
        // each draw, so rebinding between draws is safe.
        table.setAddress(slice.buffer.gpuAddress + UInt64(slice.offset), index: index)
    }

    func bindAccelerationStructure(_ structure: MTLAccelerationStructure, at index: Int) {
        // Residency comes from the backend's residency set (RenderBackend.makeResident).
        table.setResource(structure.gpuResourceID, bufferIndex: index)
        tracesRays = true
    }

    func draw(_ type: MTLPrimitiveType, vertexStart: Int, vertexCount: Int, instanceCount: Int) {
        guard vertexCount > 0, instanceCount > 0 else { return }
        encoder.drawPrimitives(primitiveType: type, vertexStart: vertexStart, vertexCount: vertexCount, instanceCount: instanceCount)
    }

    func setDepthState(_ state: MTLDepthStencilState?) { encoder.setDepthStencilState(state) }
    func setCullMode(_ mode: MTLCullMode) { encoder.setCullMode(mode) }
}
#endif

final class ClassicEncoder: GPUEncoder {
    let encoder: MTLRenderCommandEncoder
    /// Whether the frame bound an acceleration structure, i.e. traces rays (ClassicBackend reports its failure).
    private(set) var tracesRays = false
    /// The slice bound at each index of each stage. All slices of a frame lie in the same FrameRing buffer, so
    /// the next one usually only moves the offset, which setVertexBufferOffset / setFragmentBufferOffset do
    /// ("typically more efficient than rebinding"); binding the same buffer again is a redundant setting.
    private var vertexSlices: [Int: BufferSlice] = [:]
    private var fragmentSlices: [Int: BufferSlice] = [:]

    init(encoder: MTLRenderCommandEncoder) {
        self.encoder = encoder
    }

    func setPipeline(_ state: MTLRenderPipelineState) { encoder.setRenderPipelineState(state) }

    func bind(_ slice: BufferSlice, at index: Int, stages: MTLRenderStages) {
        if stages.contains(.vertex) {
            if let bound = vertexSlices[index], bound.buffer === slice.buffer {
                if bound.offset != slice.offset { encoder.setVertexBufferOffset(slice.offset, index: index) }
            } else {
                encoder.setVertexBuffer(slice.buffer, offset: slice.offset, index: index)
            }
            vertexSlices[index] = slice
        }
        if stages.contains(.fragment) {
            if let bound = fragmentSlices[index], bound.buffer === slice.buffer {
                if bound.offset != slice.offset { encoder.setFragmentBufferOffset(slice.offset, index: index) }
            } else {
                encoder.setFragmentBuffer(slice.buffer, offset: slice.offset, index: index)
            }
            fragmentSlices[index] = slice
        }
    }

    func bindAccelerationStructure(_ structure: MTLAccelerationStructure, at index: Int) {
        encoder.setFragmentAccelerationStructure(structure, bufferIndex: index)
        // The structure takes the fragment slot: a slice bound there later is bound anew.
        fragmentSlices[index] = nil
        tracesRays = true
    }

    func draw(_ type: MTLPrimitiveType, vertexStart: Int, vertexCount: Int, instanceCount: Int) {
        guard vertexCount > 0, instanceCount > 0 else { return }
        encoder.drawPrimitives(type: type, vertexStart: vertexStart, vertexCount: vertexCount, instanceCount: instanceCount)
    }

    func setDepthState(_ state: MTLDepthStencilState?) { encoder.setDepthStencilState(state) }
    func setCullMode(_ mode: MTLCullMode) { encoder.setCullMode(mode) }
}
