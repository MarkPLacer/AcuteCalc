//
//  Surface3D.metal
//  Acute Calc
//
//  Procedural 3D surfaces: the vertex shader evaluates z = f(x, y) (or the radius of a
//  solid of revolution) with forward-mode differentiation for exact normals, so the CPU
//  never builds meshes and parameter sliders update at the display refresh rate.
//

#include <metal_stdlib>
#include <metal_raytracing>
#include "ShaderTypes.h"
#include "BytecodeInterpreter.h"
using namespace metal;

struct SurfaceOut {
    float4 position [[position]];
    float3 world;
    float3 normal;
    float2 graph;      // (x, y) in graph units (for grid lines)
    float height;      // normalised height 0…1 for colouring
    // w = f(z) for complex surfaces; the fragment takes its angle. An interpolated arg jumps
    // from 1 to 0 across a triangle (jagged rainbow lines), and w/|w| would move the colour
    // seams away from where w itself crosses them near a zero. Inside a triangle the colour is
    // that of the linear interpolation of f: it turns once around a simple zero, and near a pole
    // it is as coarse as the mesh, like the heights.
    float2 phase;
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

    out.phase = float2(1, 0);
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
        out.phase = all(isfinite(w)) ? w : float2(1, 0);
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

/// Light from ray tracing: the share of direct light that reaches the point (1 without
/// shadow rays) and the colour seen in the mirror direction with its weight.
struct SurfaceLighting {
    float shadow;
    float3 reflection;
    float reflectionWeight;
};

static inline float4 surface_shade(SurfaceOut in, bool frontFacing, constant SurfaceUniforms &u, SurfaceLighting light) {
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
        float arg = atan2(in.phase.y, in.phase.x) / (2 * M_PI_F);
        float hue = arg < 0 ? arg + 1 : arg;
        float3 k = fmod(float3(5, 3, 1) + hue * 6.0f, 6.0f);
        base = 0.95f - 0.95f * 0.8f * clamp(min(k, 4.0f - k), 0.0f, 1.0f);
    } else {
        base = u.colorMode == 0 ? turbo(in.height) : u.baseColor.rgb;
    }
    float rim = pow(1.0f - fabs(dot(normal, viewDir)), 3.0f) * 0.35f;
    float3 color = base * (0.28f + 0.72f * diffuse * light.shadow) + specular * light.shadow + rim * base;
    color = mix(color, light.reflection, light.reflectionWeight);

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

fragment float4 surface_fragment(SurfaceOut in [[stage_in]],
                                 bool frontFacing [[front_facing]],
                                 constant SurfaceUniforms &u [[buffer(BufferIndexFrame)]]) {
    return surface_shade(in, frontFacing, u, SurfaceLighting { 1.0f, float3(0), 0.0f });
}

/// Height field with hardware ray tracing from the fragment function (MSL "Ray-Tracing
/// Functions"; pipelines are only built when the device reports `supportsRaytracingFromRender`):
/// one any-hit shadow ray toward the light and one closest-hit ray in the mirror direction.
fragment float4 surface_fragment_rt(SurfaceOut in [[stage_in]],
                                    bool frontFacing [[front_facing]],
                                    constant SurfaceUniforms &u [[buffer(BufferIndexFrame)]],
                                    raytracing::primitive_acceleration_structure scene [[buffer(BufferIndexAccelerationStructure)]]) {
    if (in.valid < 0.999f) discard_fragment();
    float3 n = normalize(in.normal) * (frontFacing ? 1.0f : -1.0f);
    float3 viewDir = normalize(u.cameraPosition.xyz - in.world);
    if (dot(n, viewDir) < 0) n = -n;
    float3 lightDir = normalize(u.lightDirection.xyz);

    raytracing::intersector<raytracing::triangle_data> intersector;
    intersector.assume_geometry_type(raytracing::geometry_type::triangle);
    intersector.force_opacity(raytracing::forced_opacity::opaque);
    raytracing::ray ray;
    // Offset along the normal so a ray does not hit its own triangle (the traced mesh is coarser).
    ray.origin = in.world + n * 4e-3f;
    ray.min_distance = 1e-3f;
    ray.max_distance = 8.0f;

    SurfaceLighting light = { 1.0f, float3(0), 0.0f };
    if (u.rayTracing != 0) {
        intersector.accept_any_intersection(true);
        ray.direction = lightDir;
        if (intersector.intersect(ray, scene).type != raytracing::intersection_type::none) light.shadow = 0.45f;

        intersector.accept_any_intersection(false);
        ray.direction = reflect(-viewDir, n);
        auto hit = intersector.intersect(ray, scene);
        if (hit.type != raytracing::intersection_type::none) {
            float3 p = ray.origin + ray.direction * hit.distance;
            float height = clamp((p.y / max(u.zRange.z, 1e-6f) + 1) * 0.5f, 0.0f, 1.0f);
            float3 seen = u.colorMode == 0 ? turbo(height) : u.baseColor.rgb;
            // Schlick's Fresnel term, capped so the surface keeps its own colour.
            float fresnel = 0.04f + 0.96f * pow(1.0f - saturate(dot(n, viewDir)), 5.0f);
            light.reflection = seen * 0.6f;
            light.reflectionWeight = min(fresnel, 0.35f);
        }
    }
    return surface_shade(in, frontFacing, u, light);
}

// MARK: - Implicit surfaces F(x, y, z) = 0

struct ImplicitOut {
    float4 position [[position]];
    float3 world;
};

// Depth qualifiers per the MSL specification (§5.2.3.4): from outside the box the hit is never
// nearer than the front face being rasterised, so `depth(greater)` keeps early depth rejection
// valid; with the camera inside the box the back face is rasterised and the hit may be nearer, so
// that pipeline writes `depth(any)`.
struct ImplicitFragmentOutside {
    float4 color [[color(0)]];
    float depth [[depth(greater)]];
};

struct ImplicitFragmentInside {
    float4 color [[color(0)]];
    float depth [[depth(any)]];
};

struct ImplicitShade {
    float4 color;
    float depth;
};

/// The bounding box [−1, 1] × [−h, h] × [−1, 1] as 12 triangles; the fragment shader marches the
/// view ray through it from the face it rasterises (the entry face from outside, the exit face
/// from inside, chosen by the position of the fragment, so the winding does not matter).
vertex ImplicitOut implicit_surface_vertex(uint vid [[vertex_id]],
                                   constant SurfaceUniforms &u [[buffer(BufferIndexFrame)]]) {
    const uint faces[36] = { 0, 2, 1, 1, 2, 3,  4, 5, 6, 5, 7, 6,  0, 1, 4, 1, 5, 4,
                             2, 6, 3, 3, 6, 7,  0, 4, 2, 2, 4, 6,  1, 3, 5, 3, 7, 5 };
    uint c = faces[vid];
    float h = u.zRange.z;
    float3 p = float3((c & 1) ? 1.0f : -1.0f, (c & 2) ? h : -h, (c & 4) ? 1.0f : -1.0f);
    ImplicitOut out;
    out.world = p;
    out.position = u.viewProjection * float4(p, 1);
    return out;
}

/// World (X, Y up, Z depth) → graph (x, y, z), the mapping of surface_vertex.
static inline float3 implicit_graph(float3 p, constant SurfaceUniforms &u) {
    float zHalf = max((u.zRange.y - u.zRange.x) * 0.5f, 1e-6f);
    float zMid = (u.zRange.y + u.zRange.x) * 0.5f;
    return float3(mix(u.domain.x, u.domain.y, (p.x + 1) * 0.5f),
                  mix(u.domain.z, u.domain.w, (1 - p.z) * 0.5f),
                  zMid + p.y / max(u.zRange.z, 1e-6f) * zHalf);
}

static inline float implicit_value(float3 p, constant SurfaceUniforms &u, constant BCInstruction *code, constant float *params) {
    float3 g = implicit_graph(p, u);
    return bc_eval_real(code, u.programLength, g.x, g.y, params, g.z);
}

/// Marches the ray through the fragment's box face; `inside` is whether the camera is in the box.
static inline ImplicitShade implicit_shade(ImplicitOut in, constant SurfaceUniforms &u, constant BCInstruction *code,
                                          constant float *params, bool inside) {
    float3 ro = u.cameraPosition.xyz;
    float3 rd = normalize(in.world - ro);
    float3 box = float3(1, u.zRange.z, 1);
    // Slab test: the ray enters the box at t0 and leaves it at t1.
    float3 inv = 1.0f / rd;
    float3 ta = (-box - ro) * inv;
    float3 tb = (box - ro) * inv;
    float3 tmin = min(ta, tb);
    float3 tmax = max(ta, tb);
    float t0 = max(max(max(tmin.x, tmin.y), tmin.z), 0.0f);
    float t1 = min(min(tmax.x, tmax.y), tmax.z);
    // Each pixel marches once: from outside only on the entry face, from inside only on the exit face.
    float faceDistance = length(in.world - ro);
    if (t1 <= t0 || (inside ? faceDistance < t1 - 1e-4f : faceDistance > t0 + 1e-4f)) discard_fragment();

    // March for a sign change of F, then bisect. A sign change across a pole (F → ±∞, as in
    // 1/x = …) is not a surface: there |F| grows while the bracket shrinks, while at a root it
    // falls below both ends. A zero of even multiplicity ((x² + y² + z² − 4)² = 0) touches 0
    // without a sign change: a local minimum of |F| is refined by golden-section search and
    // accepted when it is (relatively) zero.
    const int steps = 144;
    float dt = (t1 - t0) / float(steps);
    float ta0 = t0;
    float fa = implicit_value(ro + rd * ta0, u, code, params);
    float fPrev = NAN;
    bool hit = false;
    float tHit = t1;
    for (int i = 1; i <= steps && !hit; i++) {
        float tb0 = t0 + dt * float(i);
        float fb = implicit_value(ro + rd * tb0, u, code, params);
        if (isfinite(fa) && isfinite(fb) && (fa < 0) != (fb < 0)) {
            float lo = ta0, hi = tb0, flo = fa, fhi = fb;
            for (int k = 0; k < 12; k++) {
                float mid = 0.5f * (lo + hi);
                float fm = implicit_value(ro + rd * mid, u, code, params);
                if ((fm < 0) == (flo < 0)) { lo = mid; flo = fm; } else { hi = mid; fhi = fm; }
            }
            // A sample exactly on the root is a hit before the pole test (planes would get holes).
            if (fa == 0.0f || fb == 0.0f || max(fabs(flo), fabs(fhi)) <= max(min(fabs(fa), fabs(fb)), 1e-6f)) {
                hit = true;
                tHit = fa == 0.0f ? ta0 : (fb == 0.0f ? tb0 : 0.5f * (lo + hi));
            }
        } else if (isfinite(fa) && isfinite(fb) && isfinite(fPrev) && i >= 2 &&
                   fabs(fa) < fabs(fPrev) && fabs(fa) <= fabs(fb)) {
            // |F| has a local minimum near ta0 without a sign change.
            float lo = ta0 - dt, hi = tb0;
            const float g = 0.618034f;
            for (int k = 0; k < 14; k++) {
                float m1 = hi - g * (hi - lo), m2 = lo + g * (hi - lo);
                float f1 = fabs(implicit_value(ro + rd * m1, u, code, params));
                float f2 = fabs(implicit_value(ro + rd * m2, u, code, params));
                if (f1 < f2) hi = m2; else lo = m1;
            }
            float tm = 0.5f * (lo + hi);
            float fm = fabs(implicit_value(ro + rd * tm, u, code, params));
            // Relative to the neighbouring samples, so the test does not depend on the scale of F.
            if (isfinite(fm) && fm <= 1e-4f * max(fabs(fPrev), fabs(fb))) {
                hit = true;
                tHit = tm;
            }
        }
        fPrev = fa;
        ta0 = tb0;
        fa = fb;
    }

    float3 p = ro + rd * tHit;
    float3 g = implicit_graph(p, u);
    // Grid lines where x, y or z crosses a multiple of the grid step (computed before the
    // discard so the derivatives stay defined).
    float line = 0;
    if (u.gridLines > 0) {
        float3 coordinate = g / u.gridLines;
        float3 w = max(fwidth(coordinate), float3(1e-6f));
        float3 grid = fabs(fract(coordinate - 0.5f) - 0.5f) / w;
        line = 1.0f - clamp(min(min(grid.x, grid.y), grid.z), 0.0f, 1.0f);
    }
    if (!hit) discard_fragment();

    float e = 2e-3f;
    float3 n = float3(implicit_value(p + float3(e, 0, 0), u, code, params) - implicit_value(p - float3(e, 0, 0), u, code, params),
                      implicit_value(p + float3(0, e, 0), u, code, params) - implicit_value(p - float3(0, e, 0), u, code, params),
                      implicit_value(p + float3(0, 0, e), u, code, params) - implicit_value(p - float3(0, 0, e), u, code, params));
    n = all(isfinite(n)) && length(n) > 0 ? normalize(n) : -rd;
    if (dot(n, rd) > 0) n = -n;

    float3 lightDir = normalize(u.lightDirection.xyz);
    float3 viewDir = -rd;
    float diffuse = fabs(dot(n, lightDir));
    float specular = pow(max(dot(n, normalize(lightDir + viewDir)), 0.0f), 48.0f) * 0.35f;
    float rim = pow(1.0f - fabs(dot(n, viewDir)), 3.0f) * 0.35f;
    float height = clamp((p.y / max(u.zRange.z, 1e-6f) + 1) * 0.5f, 0.0f, 1.0f);
    float3 base = u.colorMode == 0 ? turbo(height) : u.baseColor.rgb;
    float3 color = base * (0.28f + 0.72f * diffuse) + specular + rim * base;
    color = mix(color, color * 0.35f, line * 0.8f);

    ImplicitShade out;
    float alpha = u.zRange.w;
    out.color = float4(color * alpha, alpha);
    float4 clip = u.viewProjection * float4(p, 1);
    out.depth = clip.z / clip.w;
    return out;
}

fragment ImplicitFragmentOutside implicit_surface_fragment(ImplicitOut in [[stage_in]],
                                                   constant SurfaceUniforms &u [[buffer(BufferIndexFrame)]],
                                                   constant BCInstruction *code [[buffer(BufferIndexProgram)]],
                                                   constant float *params [[buffer(BufferIndexParameters)]]) {
    ImplicitShade shade = implicit_shade(in, u, code, params, false);
    // The hit lies on or behind the entry face; max() keeps rounding from breaking depth(greater).
    return { shade.color, max(shade.depth, in.position.z) };
}

fragment ImplicitFragmentInside implicit_surface_fragment_inside(ImplicitOut in [[stage_in]],
                                                         constant SurfaceUniforms &u [[buffer(BufferIndexFrame)]],
                                                         constant BCInstruction *code [[buffer(BufferIndexProgram)]],
                                                         constant float *params [[buffer(BufferIndexParameters)]]) {
    ImplicitShade shade = implicit_shade(in, u, code, params, true);
    return { shade.color, shade.depth };
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
