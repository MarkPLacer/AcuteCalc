//
//  Common.metal
//  Acute Calc
//
//  Shared helpers for all shaders.
//

#include <metal_stdlib>
#include "ShaderTypes.h"
using namespace metal;

/// Fullscreen triangle covering the viewport (vertex ids 0, 1, 2).
struct FullscreenOut {
    float4 position [[position]];
    float2 uv;
};

vertex FullscreenOut fullscreen_vertex(uint vid [[vertex_id]]) {
    float2 uv = float2((vid << 1) & 2, vid & 2);
    FullscreenOut out;
    out.position = float4(uv * float2(2, -2) + float2(-1, 1), 0, 1);
    out.uv = uv;
    return out;
}
