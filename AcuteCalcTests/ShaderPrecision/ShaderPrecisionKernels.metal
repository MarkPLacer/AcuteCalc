//
//  ShaderPrecisionKernels.metal
//  AcuteCalcTests
//
//  Test-only compute kernel: runs the app's GPU bytecode interpreters (BytecodeInterpreter.h)
//  at given points, so the tests can compare them with the CPU virtual machines of AcuteCore.
//

#include <metal_stdlib>
#include "../../AcuteCalc/Rendering/Shaders/BytecodeInterpreter.h"
using namespace metal;

/// Matches the four Int32 values ShaderPrecisionGPU.Runner passes.
struct ShaderPrecisionArguments {
    int count;        // program length
    int interpreter;  // 0 = bc_eval_real, 1 = bc_eval_dual, 2 = bc_eval_complex
    int points;       // number of points
    int padding;
};

/// out[i] = (f, 0, 0, 0) for the real, (f, ∂f/∂x, ∂f/∂y, 0) for the dual and (Re f, Im f, 0, 0)
/// for the complex interpreter at points[i] (x, y), respectively z = x + iy.
kernel void shader_precision_evaluate(constant BCInstruction *code [[buffer(0)]],
                                      constant ShaderPrecisionArguments &arguments [[buffer(1)]],
                                      const device float2 *points [[buffer(2)]],
                                      device float4 *out [[buffer(3)]],
                                      constant float *params [[buffer(4)]],
                                      uint i [[thread_position_in_grid]]) {
    if (int(i) >= arguments.points) return;
    float2 p = points[i];
    if (arguments.interpreter == 1) {
        out[i] = float4(bc_eval_dual(code, arguments.count, p.x, p.y, params), 0);
    } else if (arguments.interpreter == 2) {
        out[i] = float4(bc_eval_complex(code, arguments.count, p, params), 0, 0);
    } else {
        out[i] = float4(bc_eval_real(code, arguments.count, p.x, p.y, params), 0, 0, 0);
    }
}
