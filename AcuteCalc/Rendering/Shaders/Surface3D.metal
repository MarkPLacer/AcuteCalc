//
//  Surface3D.metal
//  Acute Calc
//
//  Procedural 3D surfaces: the vertex shader evaluates z = f(x, y) (or the radius of a
//  solid of revolution) with forward-mode differentiation for exact normals, so the CPU
//  never builds meshes and parameter sliders update at the display refresh rate.
//

#include <metal_stdlib>
#include "ShaderTypes.h"
#include "BytecodeInterpreter.h"
using namespace metal;

struct SurfaceOut {
    float4 position [[position]];
    float3 world;
    float3 normal;
    float2 graph;      // (x, y) in graph units (for grid lines)
    float height;      // normalised height 0…1 for colouring
    float phase;       // arg f(z) / 2π for complex surfaces
    float valid;
};

/// Height of a complex surface: |w|, Re w or Im w.
static inline float complex_height(float2 w, int kind) {
    return kind == 2 ? length(w) : (kind == 3 ? w.x : w.y);
}

/// World space: x → X, y → −Z (depth), z → Y (up); the domain maps to [−1, 1].
vertex SurfaceOut surface_vertex(uint vid [[vertex_id]],
                                 constant SurfaceUniforms &u [[buffer(BufferIndexFrame)]],
                                 constant BCInstruction *code [[buffer(BufferIndexProgram)]],
                                 constant float *params [[buffer(BufferIndexParameters)]]) {
    int n = max(u.resolution, 2);
    uint quad = vid / 6;
    uint corner = vid % 6;
    // Two triangles per quad: (0,0) (1,0) (0,1) / (1,0) (1,1) (0,1)
    const uint2 offsets[6] = { uint2(0, 0), uint2(1, 0), uint2(0, 1), uint2(1, 0), uint2(1, 1), uint2(0, 1) };
    uint qi = quad % uint(n - 1);
    uint qj = quad / uint(n - 1);
    uint2 ij = uint2(qi, qj) + offsets[corner];
    float2 uv = float2(ij) / float(n - 1);

    SurfaceOut out;
    float zMin = u.zRange.x, zMax = u.zRange.y, zScale = u.zRange.z;
    float zHalf = max((zMax - zMin) * 0.5f, 1e-6f);
    float zMid = (zMax + zMin) * 0.5f;

    out.phase = 0;
    if (u.surfaceKind >= 2) {
        // Complex landscape over z = x + iy. Gradient by central differences.
        float x = mix(u.domain.x, u.domain.y, uv.x);
        float y = mix(u.domain.z, u.domain.w, uv.y);
        float2 w = bc_eval_complex(code, u.programLength, float2(x, y), params);
        float h = complex_height(w, u.surfaceKind);
        float hx = (u.domain.y - u.domain.x) * 1e-3f;
        float hy = (u.domain.w - u.domain.z) * 1e-3f;
        float fxp = complex_height(bc_eval_complex(code, u.programLength, float2(x + hx, y), params), u.surfaceKind);
        float fxm = complex_height(bc_eval_complex(code, u.programLength, float2(x - hx, y), params), u.surfaceKind);
        float fyp = complex_height(bc_eval_complex(code, u.programLength, float2(x, y + hy), params), u.surfaceKind);
        float fym = complex_height(bc_eval_complex(code, u.programLength, float2(x, y - hy), params), u.surfaceKind);
        float dx = (fxp - fxm) / (2 * hx);
        float dy = (fyp - fym) / (2 * hy);
        bool valid = isfinite(h) && isfinite(dx) && isfinite(dy);
        float z = valid ? clamp(h, zMin - zHalf, zMax + zHalf) : zMid;
        float sx = (u.domain.y - u.domain.x) * 0.5f;
        float sy = (u.domain.w - u.domain.z) * 0.5f;
        float3 nGraph = float3(-dx * sx, -dy * sy, zHalf / max(zScale, 1e-6f));
        out.world = float3(uv.x * 2 - 1, (z - zMid) / zHalf * zScale, -(uv.y * 2 - 1));
        out.normal = valid ? normalize(float3(nGraph.x, nGraph.z, -nGraph.y)) : float3(0, 1, 0);
        out.graph = float2(x, y);
        out.height = clamp((z - zMin) / max(zMax - zMin, 1e-6f), 0.0f, 1.0f);
        float arg = atan2(w.y, w.x) / (2 * M_PI_F);
        out.phase = arg < 0 ? arg + 1 : arg;
        out.valid = valid ? 1.0f : 0.0f;
    } else if (u.surfaceKind == 0) {
        float x = mix(u.domain.x, u.domain.y, uv.x);
        float y = mix(u.domain.z, u.domain.w, uv.y);
        float3 F = bc_eval_dual(code, u.programLength, x, y, params);
        bool valid = isfinite(F.x) && all(isfinite(F.yz));
        float z = valid ? F.x : zMid;
        float X = uv.x * 2 - 1;
        float Zd = -(uv.y * 2 - 1);
        float Y = (z - zMid) / zHalf * zScale;
        // Normal of (x, y, f): (−f_x, −f_y, 1) scaled to world units.
        float sx = (u.domain.y - u.domain.x) * 0.5f;
        float sy = (u.domain.w - u.domain.z) * 0.5f;
        float3 nGraph = float3(-F.y * sx, -F.z * sy, zHalf / max(zScale, 1e-6f));
        float3 normal = normalize(float3(nGraph.x, nGraph.z, -nGraph.y));
        out.world = float3(X, Y, Zd);
        out.normal = valid ? normal : float3(0, 1, 0);
        out.graph = float2(x, y);
        out.height = clamp((z - zMin) / max(zMax - zMin, 1e-6f), 0.0f, 1.0f);
        out.valid = valid ? 1.0f : 0.0f;
    } else {
        // Solid of revolution of y = f(x) around the x axis, x ∈ [a, b] = domain.xy.
        float x = mix(u.domain.x, u.domain.y, uv.x);
        float theta = uv.y * 2 * M_PI_F;
        float3 F = bc_eval_dual(code, u.programLength, x, 0, params);
        bool valid = isfinite(F.x) && isfinite(F.y);
        float r = valid ? F.x : 0;
        float X = uv.x * 2 - 1;
        float scale = 1.0f / max(zHalf, 1e-6f) * zScale;
        float Y = r * cos(theta) * scale;
        float Zd = r * sin(theta) * scale;
        float sx = (u.domain.y - u.domain.x) * 0.5f;
        // Surface (x, r cos θ, r sin θ): normal ∝ (−r·r′, r cos θ, r sin θ) in graph units.
        float3 normal = normalize(float3(-F.y * scale * sx, cos(theta), sin(theta)));
        out.world = float3(X, Y, Zd);
        out.normal = valid ? normal : float3(0, 1, 0);
        out.graph = float2(x, theta);
        out.height = clamp(uv.x, 0.0f, 1.0f);
        out.valid = valid ? 1.0f : 0.0f;
    }
    out.position = u.viewProjection * float4(out.world, 1);
    return out;
}

/// Smooth "turbo"-like colormap (Google, Apache-2.0 polynomial approximation).
static inline float3 turbo(float t) {
    const float4 kRedVec4 = float4(0.13572138f, 4.61539260f, -42.66032258f, 132.13108234f);
    const float4 kGreenVec4 = float4(0.09140261f, 2.19418839f, 4.84296658f, -14.18503333f);
    const float4 kBlueVec4 = float4(0.10667330f, 12.64194608f, -60.58204836f, 110.36276771f);
    const float2 kRedVec2 = float2(-152.94239396f, 59.28637943f);
    const float2 kGreenVec2 = float2(4.27729857f, 2.82956604f);
    const float2 kBlueVec2 = float2(-89.90310912f, 27.34824973f);
    t = clamp(t, 0.0f, 1.0f);
    float4 v4 = float4(1.0f, t, t * t, t * t * t);
    float2 v2 = v4.zw * v4.z;
    return float3(dot(v4, kRedVec4) + dot(v2, kRedVec2),
                  dot(v4, kGreenVec4) + dot(v2, kGreenVec2),
                  dot(v4, kBlueVec4) + dot(v2, kBlueVec2));
}

fragment float4 surface_fragment(SurfaceOut in [[stage_in]],
                                 bool frontFacing [[front_facing]],
                                 constant SurfaceUniforms &u [[buffer(BufferIndexFrame)]]) {
    if (in.valid < 0.999f) discard_fragment();
    // Clip to the bounding box (not for solids of revolution).
    if (fabs(in.world.y) > u.zRange.z * 1.0001f && u.surfaceKind != 1) discard_fragment();

    float3 normal = normalize(in.normal) * (frontFacing ? 1.0f : -1.0f);
    float3 lightDir = normalize(u.lightDirection.xyz);
    float3 viewDir = normalize(u.cameraPosition.xyz - in.world);
    float diffuse = fabs(dot(normal, lightDir));
    float3 halfway = normalize(lightDir + viewDir);
    float specular = pow(max(dot(normal, halfway), 0.0f), 48.0f) * 0.35f;

    float3 base;
    if (u.colorMode == 2) {
        // Domain colouring on the surface: hue = arg f(z)
        float3 k = fmod(float3(5, 3, 1) + in.phase * 6.0f, 6.0f);
        base = 0.95f - 0.95f * 0.8f * clamp(min(k, 4.0f - k), 0.0f, 1.0f);
    } else {
        base = u.colorMode == 0 ? turbo(in.height) : u.baseColor.rgb;
    }
    float3 color = base * (0.28f + 0.72f * diffuse) + specular;

    // Grid lines on the surface (unit spacing in graph coordinates, anti-aliased with fwidth).
    if (u.gridLines > 0) {
        float2 coordinate = in.graph / u.gridLines;
        float2 w = fwidth(coordinate);
        float2 grid = fabs(fract(coordinate - 0.5f) - 0.5f) / max(w, float2(1e-6f));
        float line = 1.0f - clamp(min(grid.x, grid.y), 0.0f, 1.0f);
        color = mix(color, color * 0.35f, line * 0.8f);
    }
    float alpha = u.zRange.w;
    return float4(color * alpha, alpha);
}

// MARK: - Axes / bounding box lines

struct AxisOut {
    float4 position [[position]];
    float4 color;
};

struct AxisVertex {
    packed_float3 position;
    packed_float4 color;
};

vertex AxisOut axis_vertex(uint vid [[vertex_id]],
                           constant SurfaceUniforms &u [[buffer(BufferIndexFrame)]],
                           const device AxisVertex *vertices [[buffer(BufferIndexGeometry)]]) {
    AxisOut out;
    out.position = u.viewProjection * float4(float3(vertices[vid].position), 1);
    out.color = float4(vertices[vid].color);
    return out;
}

fragment float4 axis_fragment(AxisOut in [[stage_in]]) {
    return float4(in.color.rgb * in.color.a, in.color.a);
}
