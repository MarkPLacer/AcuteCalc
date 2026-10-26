//
//  Graph2D.metal
//  Acute Calc
//
//  2D graph rendering: analytic grid, anti-aliased curves (instanced capsules),
//  filled integral areas and per-pixel implicit curves / inequality regions.
//
//  Coordinate convention: geometry arrives in drawable pixels relative to the view
//  centre with y pointing up (computed on the CPU in double precision).
//

#include <metal_stdlib>
#include "ShaderTypes.h"
#include "BytecodeInterpreter.h"
using namespace metal;

static inline float2 pixel_to_ndc(float2 p, constant FrameUniforms &frame) {
    return p / (frame.viewportSize * 0.5f);
}

/// Fragment position (y down, origin top-left) → pixels relative to centre (y up).
static inline float2 fragment_to_centered(float2 position, constant FrameUniforms &frame) {
    return float2(position.x - frame.viewportSize.x * 0.5f, frame.viewportSize.y * 0.5f - position.y);
}

static inline float4 premultiply(float4 c) { return float4(c.rgb * c.a, c.a); }

// MARK: - Grid

struct GridOut {
    float4 position [[position]];
};

vertex GridOut grid_vertex(uint vid [[vertex_id]]) {
    float2 uv = float2((vid << 1) & 2, vid & 2);
    GridOut out;
    out.position = float4(uv * float2(2, -2) + float2(-1, 1), 0, 1);
    return out;
}

/// Coverage of lines repeating every `spacing` px through `phase`, `width` px wide.
static inline float line_coverage(float coordinate, float phase, float spacing, float width) {
    if (spacing < 2) return 0;
    float d = fabs(fract((coordinate - phase) / spacing + 0.5f) - 0.5f) * spacing;
    return clamp(0.5f * width + 0.5f - d, 0.0f, 1.0f);
}

fragment float4 grid_fragment(GridOut in [[stage_in]],
                              constant FrameUniforms &frame [[buffer(BufferIndexFrame)]],
                              constant GridStyle &grid [[buffer(BufferIndexDraw)]]) {
    float2 p = fragment_to_centered(in.position.xy, frame);
    float4 color = grid.transparentBackground > 0.5f ? float4(0) : premultiply(grid.background);
    float width = grid.lineWidth;
    if (grid.showGrid > 0.5f) {
        float minor = max(line_coverage(p.x, grid.minorPhase.x, grid.minorSpacing.x, width),
                          line_coverage(p.y, grid.minorPhase.y, grid.minorSpacing.y, width));
        float major = max(line_coverage(p.x, grid.majorPhase.x, grid.majorSpacing.x, width),
                          line_coverage(p.y, grid.majorPhase.y, grid.majorSpacing.y, width));
        float4 minorColor = premultiply(grid.minorColor) * minor;
        color = minorColor + color * (1 - minorColor.a);
        float4 majorColor = premultiply(grid.majorColor) * major;
        color = majorColor + color * (1 - majorColor.a);
    }
    if (grid.showAxes > 0.5f) {
        float axisWidth = width * 1.6f;
        float ax = clamp(0.5f * axisWidth + 0.5f - fabs(p.x - grid.axisPosition.x), 0.0f, 1.0f);
        float ay = clamp(0.5f * axisWidth + 0.5f - fabs(p.y - grid.axisPosition.y), 0.0f, 1.0f);
        float4 axisColor = premultiply(grid.axisColor) * max(ax, ay);
        color = axisColor + color * (1 - axisColor.a);
    }
    return color;
}

// MARK: - Lines and points

struct LineOut {
    float4 position [[position]];
    float2 local;
    float2 a [[flat]];
    float2 b [[flat]];
    float valid [[flat]];
};

vertex LineOut line_vertex(uint vid [[vertex_id]],
                           uint iid [[instance_id]],
                           constant FrameUniforms &frame [[buffer(BufferIndexFrame)]],
                           const device float2 *points [[buffer(BufferIndexGeometry)]],
                           constant LineStyle &style [[buffer(BufferIndexDraw)]]) {
    uint first = style.pairs > 0.5f ? iid * 2 : iid;
    float2 a = points[first];
    float2 b = points[first + 1];
    LineOut out;
    bool valid = all(isfinite(a)) && all(isfinite(b));
    if (!valid) {
        out.position = float4(0, 0, 0, 1);
        out.local = float2(0);
        out.a = float2(0);
        out.b = float2(0);
        out.valid = 0;
        return out;
    }
    float r = style.halfWidth + 1.5f;
    float2 dir = b - a;
    float len = length(dir);
    float2 t = len > 1e-4f ? dir / len : float2(1, 0);
    float2 n = float2(-t.y, t.x);
    float along = (vid & 1) ? 1.0f : -1.0f;
    float across = (vid & 2) ? 1.0f : -1.0f;
    float2 p = (along < 0 ? a - t * r : b + t * r) + n * across * r;
    out.position = float4(pixel_to_ndc(p, frame), 0, 1);
    out.local = p;
    out.a = a;
    out.b = b;
    out.valid = 1;
    return out;
}

fragment float4 line_fragment(LineOut in [[stage_in]],
                              constant LineStyle &style [[buffer(BufferIndexDraw)]]) {
    if (in.valid < 0.5f) discard_fragment();
    float2 pa = in.local - in.a;
    float2 ba = in.b - in.a;
    float denom = max(dot(ba, ba), 1e-6f);
    float h = clamp(dot(pa, ba) / denom, 0.0f, 1.0f);
    float distance = length(pa - ba * h);
    float d;
    if (style.ringThickness > 0) {
        // Hollow point: ring of the given thickness at the outer radius.
        float ringRadius = style.halfWidth - style.ringThickness * 0.5f;
        d = fabs(distance - ringRadius) - style.ringThickness * 0.5f;
    } else {
        d = distance - style.halfWidth;
    }
    float alpha = clamp(0.5f - d, 0.0f, 1.0f);
    if (style.dashPeriod > 0) {
        float s = h * sqrt(denom);
        float phase = fract(s / style.dashPeriod);
        alpha *= phase < 0.6f ? 1.0f : 0.0f;
    }
    if (alpha <= 0) discard_fragment();
    return premultiply(style.color) * alpha;
}

// MARK: - Filled regions (definite integrals)

struct FillOut {
    float4 position [[position]];
    float2 local;
};

vertex FillOut fill_vertex(uint vid [[vertex_id]],
                           constant FrameUniforms &frame [[buffer(BufferIndexFrame)]],
                           const device float2 *points [[buffer(BufferIndexGeometry)]]) {
    float2 p = points[vid];
    FillOut out;
    out.position = all(isfinite(p)) ? float4(pixel_to_ndc(p, frame), 0, 1) : float4(0, 0, 0, 1);
    out.local = p;
    return out;
}

fragment float4 fill_fragment(FillOut in [[stage_in]],
                              constant LineStyle &style [[buffer(BufferIndexDraw)]]) {
    // Subtle diagonal hatching on top of the translucent fill reads well on glass.
    float hatch = fract((in.local.x + in.local.y) / 14.0f) < 0.12f ? 0.35f : 0.0f;
    float4 c = style.color;
    c.a = clamp(c.a + hatch * c.a, 0.0f, 1.0f);
    return premultiply(c);
}

// MARK: - Implicit curves and inequalities

fragment float4 implicit_fragment(GridOut in [[stage_in]],
                                  constant FrameUniforms &frame [[buffer(BufferIndexFrame)]],
                                  constant ImplicitStyle &style [[buffer(BufferIndexDraw)]],
                                  constant BCInstruction *code [[buffer(BufferIndexProgram)]],
                                  constant float *params [[buffer(BufferIndexParameters)]]) {
    float2 centered = fragment_to_centered(in.position.xy, frame);
    float2 offset = centered / frame.pixelsPerUnit;
    float2 g = frame.centerHigh + (frame.centerLow + offset);

    float3 F = bc_eval_dual(code, style.programLength, g.x, g.y, params);
    float4 color = float4(0);

    // Inequality regions
    if (style.mode != 0 && isfinite(F.x)) {
        bool inside = false;
        switch (style.mode) {
            case 1: inside = F.x < 0; break;
            case 2: inside = F.x <= 0; break;
            case 3: inside = F.x > 0; break;
            case 4: inside = F.x >= 0; break;
            default: break;
        }
        if (inside) color = premultiply(style.fillColor);
    }

    // Boundary curve: distance estimate |F| / |∇F| in pixels.
    if (isfinite(F.x) && all(isfinite(F.yz))) {
        float2 gradPixels = F.yz / frame.pixelsPerUnit;
        float gradLength = length(gradPixels);
        if (gradLength > 1e-12f) {
            float distance = fabs(F.x) / gradLength;
            float width = style.halfWidth;
            if (distance < width + 2.0f) {
                // Newton check: step towards the zero and make sure F really vanishes there,
                // which rejects false lines at poles (F jumps from +∞ to −∞). After one step
                // |F(q)|/|F| ≈ (1 − 1/m)^m < 1/e near a zero of multiplicity m, but (1 + 1/p)^(−p)
                // near a pole of order p (0.5 for 1/u, 0.444 for 1/u²; below 0.4 only from p = 6).
                // The step never jumps over a pole, so a change of sign means a zero was crossed.
                float2 stepUnits = -F.x * F.yz / max(dot(F.yz, F.yz), 1e-30f);
                float2 q = g + stepUnits;
                float Fq = bc_eval_real(code, style.programLength, q.x, q.y, params);
                bool crossed = (Fq < 0) != (F.x < 0);
                bool genuine = isfinite(Fq) && (fabs(Fq) <= max(fabs(F.x) * 0.4f, 1e-6f * (1.0f + fabs(F.x)))
                                                || (crossed && fabs(Fq) <= fabs(F.x)));
                if (genuine) {
                    float alpha = clamp(width + 0.5f - distance, 0.0f, 1.0f);
                    if (style.mode == 1 || style.mode == 3) {
                        // Strict inequality: dashed boundary. The dash coordinate runs along the
                        // dominant axis of the tangent (dot(centered, tangent) is 0 all along a
                        // circle around the view centre); on lines it is the arc length as before.
                        float2 tangent = normalize(float2(-gradPixels.y, gradPixels.x));
                        float s = fabs(tangent.x) >= fabs(tangent.y) ? centered.x / fabs(tangent.x) : centered.y / fabs(tangent.y);
                        alpha *= fract(s / 12.0f) < 0.55f ? 1.0f : 0.0f;
                    }
                    float4 lineColor = premultiply(style.color) * alpha;
                    color = lineColor + color * (1 - lineColor.a);
                }
            }
        }
    }
    if (color.a <= 0) discard_fragment();
    return color;
}
