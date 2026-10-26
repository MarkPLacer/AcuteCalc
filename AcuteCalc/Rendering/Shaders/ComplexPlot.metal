//
//  ComplexPlot.metal
//  Acute Calc
//
//  Domain colouring of w = f(z): hue = arg w, brightness bands = log₂|w| contours,
//  plus optional phase lines. Zeros appear as colour wheels, poles as inverted wheels.
//

#include <metal_stdlib>
#include "ShaderTypes.h"
#include "BytecodeInterpreter.h"
using namespace metal;

struct ComplexOut {
    float4 position [[position]];
    float2 uv;
};

vertex ComplexOut complex_vertex(uint vid [[vertex_id]]) {
    float2 uv = float2((vid << 1) & 2, vid & 2);
    ComplexOut out;
    out.position = float4(uv * float2(2, -2) + float2(-1, 1), 0, 1);
    out.uv = uv;
    return out;
}

static inline float3 hsv_to_rgb(float h, float s, float v) {
    float3 k = fmod(float3(5, 3, 1) + h * 6.0f, 6.0f);
    return v - v * s * clamp(min(k, 4.0f - k), 0.0f, 1.0f);
}

/// Renders into a target of size `viewportSize` (may be a reduced-resolution texture).
fragment float4 complex_fragment(ComplexOut in [[stage_in]],
                                 constant ComplexUniforms &u [[buffer(BufferIndexFrame)]],
                                 constant BCInstruction *code [[buffer(BufferIndexProgram)]],
                                 constant float *params [[buffer(BufferIndexParameters)]]) {
    float2 centered = float2(in.uv.x - 0.5f, 0.5f - in.uv.y) * u.viewportSize;
    float2 z = u.center + centered / u.pixelsPerUnit;
    float2 w = bc_eval_complex(code, u.programLength, z, params);
    if (!all(isfinite(w))) {
        // Poles / undefined: white
        return float4(1, 1, 1, 1);
    }
    float magnitude = length(w);
    float hue = atan2(w.y, w.x) / (2 * M_PI_F);
    hue = hue < 0 ? hue + 1 : hue;
    float logMag = log2(max(magnitude, 1e-30f));
    // Modulus bands: brightness ramps within each power of two.
    float band = fract(logMag);
    float brightness = mix(1.0f, 0.62f + 0.38f * band, u.contourStrength);
    // Phase lines every 30°.
    float phaseLine = fabs(fract(hue * 12.0f + 0.5f) - 0.5f);
    float phaseWidth = fwidth(hue * 12.0f);
    float phase = 1.0f - clamp(phaseLine / max(phaseWidth, 1e-4f), 0.0f, 1.0f);
    brightness *= mix(1.0f, 0.55f, phase * u.gridStrength);
    // Very small / large magnitudes fade to black / white so zeros and poles stand out.
    float3 rgb = hsv_to_rgb(hue, 0.85f, brightness);
    float zeroFade = clamp(magnitude * 8.0f, 0.0f, 1.0f);
    float poleFade = clamp(1.0f / max(magnitude, 1e-30f) * 64.0f, 0.0f, 1.0f);
    rgb = mix(float3(0), rgb, zeroFade);
    rgb = mix(float3(1), rgb, poleFade);
    return float4(rgb, 1);
}

/// Draws the (possibly lower resolution) domain-colouring texture to the drawable.
fragment float4 complex_blit_fragment(ComplexOut in [[stage_in]],
                                      texture2d<float> source [[texture(0)]]) {
    constexpr sampler linearSampler(filter::linear, address::clamp_to_edge);
    return source.sample(linearSampler, in.uv);
}
