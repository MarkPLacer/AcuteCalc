import AcuteCore
import CoreGraphics
import Foundation
import Metal
@testable import AcuteCalc

/// Anchor class of the test bundle, whose default Metal library holds ShaderPrecisionKernels.metal.
final class ShaderPrecisionToken {}

nonisolated struct ShaderPrecisionFailure: Error, CustomStringConvertible {
    var description: String
}

/// Runs AcuteCore programs with the app's GPU bytecode interpreters (BytecodeInterpreter.h) through
/// the test kernel `shader_precision_evaluate`.
@MainActor
final class ShaderPrecisionGPU {
    enum Interpreter: Int32 {
        case real = 0, dual = 1, complex = 2
    }

    let device: MTLDevice
    private let queue: MTLCommandQueue
    private let pipeline: MTLComputePipelineState

    init() throws {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else {
            throw ShaderPrecisionFailure(description: "no Metal device")
        }
        let library = try device.makeDefaultLibrary(bundle: Bundle(for: ShaderPrecisionToken.self))
        guard let function = library.makeFunction(name: "shader_precision_evaluate") else {
            throw ShaderPrecisionFailure(description: "shader_precision_evaluate is missing from the test bundle's Metal library")
        }
        self.device = device
        self.queue = queue
        self.pipeline = try device.makeComputePipelineState(function: function)
    }

    /// `program` at each point: (f, 0, 0, 0) real, (f, ∂f/∂x, ∂f/∂y, 0) dual, (Re f, Im f, 0, 0) complex
    /// with z = x + iy. `duration` is the wall time from commit to completion.
    func evaluate(_ program: Program, _ interpreter: Interpreter, at points: [SIMD2<Float>],
                  parameters: [Float] = [0]) throws -> (values: [SIMD4<Float>], duration: Duration) {
        // BCInstruction { uint32 op; float value; }, as Graph2DEncoder uploads it.
        var words: [UInt32] = []
        for instruction in program.instructions {
            words.append(instruction.op.rawValue)
            words.append(Float(instruction.value).bitPattern)
        }
        let arguments: [Int32] = [Int32(program.instructions.count), interpreter.rawValue, Int32(points.count), 0]
        let parameterValues = parameters.isEmpty ? [Float(0)] : parameters
        guard !words.isEmpty, !points.isEmpty,
              let code = device.makeBuffer(bytes: words, length: words.count * MemoryLayout<UInt32>.stride, options: .storageModeShared),
              let pointBuffer = device.makeBuffer(bytes: points, length: points.count * MemoryLayout<SIMD2<Float>>.stride, options: .storageModeShared),
              let output = device.makeBuffer(length: points.count * MemoryLayout<SIMD4<Float>>.stride, options: .storageModeShared),
              let commands = queue.makeCommandBuffer(),
              let encoder = commands.makeComputeCommandEncoder() else {
            throw ShaderPrecisionFailure(description: "could not create the Metal buffers")
        }
        encoder.setComputePipelineState(pipeline)
        encoder.setBuffer(code, offset: 0, index: 0)
        encoder.setBytes(arguments, length: arguments.count * MemoryLayout<Int32>.stride, index: 1)
        encoder.setBuffer(pointBuffer, offset: 0, index: 2)
        encoder.setBuffer(output, offset: 0, index: 3)
        encoder.setBytes(parameterValues, length: parameterValues.count * MemoryLayout<Float>.stride, index: 4)
        let width = max(1, min(pipeline.threadExecutionWidth, points.count))
        let groups = (points.count + width - 1) / width
        encoder.dispatchThreadgroups(MTLSize(width: groups, height: 1, depth: 1),
                                     threadsPerThreadgroup: MTLSize(width: width, height: 1, depth: 1))
        encoder.endEncoding()
        let start = ContinuousClock.now
        commands.commit()
        commands.waitUntilCompleted()
        let duration = ContinuousClock.now - start
        guard commands.status == .completed else {
            throw ShaderPrecisionFailure(description: "GPU error: \(String(describing: commands.error))")
        }
        let results = output.contents().bindMemory(to: SIMD4<Float>.self, capacity: points.count)
        return ((0..<points.count).map { results[$0] }, duration)
    }
}

/// Renders a `GraphScene` with the app's own `Graph2DEncoder` and shaders (the Metal 3 path, as in the
/// simulator) into an offscreen .bgra8Unorm texture on a black background without grid and axes.
@MainActor
enum GraphRenderHarness {
    /// One byte per pixel (the red channel; white drawings on black, so it is the coverage),
    /// rows from top to bottom. The view is centred at `center`.
    static func render(_ scene: GraphScene, pointsPerUnit: Double, contentScale: Double, width: Int, height: Int,
                       center: SIMD2<Double> = .zero) throws -> [UInt8] {
        guard let device = MetalContext.shared.device, let queue = device.makeCommandQueue(),
              let ring = FrameRing(device: device) else {
            throw ShaderPrecisionFailure(description: "no Metal device")
        }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
        descriptor.usage = [.renderTarget]
        descriptor.storageMode = .private
        guard let texture = device.makeTexture(descriptor: descriptor),
              let readback = device.makeBuffer(length: width * height * 4, options: .storageModeShared),
              let commands = queue.makeCommandBuffer() else {
            throw ShaderPrecisionFailure(description: "could not create the render target")
        }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        pass.colorAttachments[0].storeAction = .store
        guard let renderEncoder = commands.makeRenderCommandEncoder(descriptor: pass) else {
            throw ShaderPrecisionFailure(description: "could not create the render encoder")
        }
        var viewport = GraphViewport()
        viewport.center = center
        viewport.scale = SIMD2(repeating: pointsPerUnit)
        viewport.size = CGSize(width: Double(width) / contentScale, height: Double(height) / contentScale)
        var theme = GraphTheme.dark
        theme.showGrid = false
        theme.showAxes = false
        ring.beginFrame(0)
        Graph2DEncoder().encode(scene: scene, viewport: viewport, theme: theme, contentScale: contentScale,
                                encoder: ClassicEncoder(encoder: renderEncoder),
                                info: RenderPassInfo(drawableSize: CGSize(width: width, height: height), sampleCount: 1, hasDepth: false),
                                ring: ring, backend: .metal3)
        renderEncoder.endEncoding()
        guard let blit = commands.makeBlitCommandEncoder() else {
            throw ShaderPrecisionFailure(description: "could not create the blit encoder")
        }
        blit.copy(from: texture, sourceSlice: 0, sourceLevel: 0, sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                  sourceSize: MTLSize(width: width, height: height, depth: 1), to: readback, destinationOffset: 0,
                  destinationBytesPerRow: width * 4, destinationBytesPerImage: width * height * 4)
        blit.endEncoding()
        commands.commit()
        commands.waitUntilCompleted()
        guard commands.status == .completed else {
            throw ShaderPrecisionFailure(description: "GPU error: \(String(describing: commands.error))")
        }
        let bytes = readback.contents().bindMemory(to: UInt8.self, capacity: width * height * 4)
        // .bgra8Unorm stores B, G, R, A.
        return (0..<(width * height)).map { bytes[$0 * 4 + 2] }
    }
}
