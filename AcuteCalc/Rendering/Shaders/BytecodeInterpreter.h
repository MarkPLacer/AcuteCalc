//
//  BytecodeInterpreter.h
//  Acute Calc
//
//  GPU interpreters for the AcuteCore bytecode (Metal only):
//  - bc_eval_real:    f(x, y)                 → float
//  - bc_eval_dual:    f(x, y) and ∇f          → float3 (value, ∂/∂x, ∂/∂y)
//  - bc_eval_complex: f(z) over ℂ             → float2
//  All angles are radians (the compiler inserts unit conversions).
//

#ifndef BytecodeInterpreter_h
#define BytecodeInterpreter_h

#include <metal_stdlib>
#include "ShaderTypes.h"
using namespace metal;

#define BC_NAN (as_type<float>(0x7fc00000u))
#define BC_PI 3.14159265358979f

// MARK: - Real helpers

static inline float bc_cbrt(float x) { return x < 0 ? -pow(-x, 1.0f / 3.0f) : pow(x, 1.0f / 3.0f); }

static inline float bc_root_n(float x, float n) {
    if (n == 0) return BC_NAN;
    // 0^(1/n) with n < 0 is a pole: undefined like 0^(−1) in bc_pow and bc_powi, not +∞.
    if (x == 0 && n < 0) return BC_NAN;
    if (x < 0) {
        int k = int(n);
        if (float(k) != n || (k & 1) == 0) return BC_NAN;
        return -pow(-x, 1.0f / n);
    }
    return pow(x, 1.0f / n);
}

static inline float bc_powi(float x, int n) {
    if (n == 0) return x == 0 ? BC_NAN : 1.0f;
    bool negative = n < 0;
    int e = abs(n);
    float result = 1.0f;
    float b = x;
    while (e > 0) {
        if (e & 1) result *= b;
        b *= b;
        e >>= 1;
    }
    if (negative) return x == 0 ? BC_NAN : 1.0f / result;
    return result;
}

static inline float bc_pow(float a, float b) {
    if (a == 0 && b <= 0) return BC_NAN;
    if (a < 0) {
        // Integer exponents keep real results for negative bases.
        if (floor(b) == b) return bc_powi(a, int(b));
        return BC_NAN;
    }
    return powr(a, b);
}

/// Lanczos approximation (g = 5, Numerical Recipes), float precision.
static inline float bc_lgamma_pos(float x) {
    const float c[6] = { 76.18009172947146f, -86.50532032941677f, 24.01409824083091f,
                         -1.231739572450155f, 0.1208650973866179e-2f, -0.5395239384953e-5f };
    float y = x;
    float tmp = x + 5.5f;
    tmp -= (x + 0.5f) * log(tmp);
    float ser = 1.000000000190015f;
    for (int j = 0; j < 6; j++) { y += 1.0f; ser += c[j] / y; }
    return -tmp + log(2.5066282746310005f * ser / x);
}

static inline float bc_gamma(float x) {
    if (x <= 0 && floor(x) == x) return BC_NAN;
    if (x < 0.5f) {
        // Reflection
        return BC_PI / (sin(BC_PI * x) * exp(bc_lgamma_pos(1.0f - x)));
    }
    return exp(bc_lgamma_pos(x));
}

/// Abramowitz & Stegun 7.1.26 (|error| < 1.5e−7).
static inline float bc_erf(float x) {
    float s = sign(x);
    float a = fabs(x);
    float t = 1.0f / (1.0f + 0.3275911f * a);
    float y = 1.0f - (((((1.061405429f * t - 1.453152027f) * t) + 1.421413741f) * t - 0.284496736f) * t + 0.254829592f) * t * exp(-a * a);
    return s * y;
}

static inline float bc_combination(float n, float r, bool permutation) {
    if (floor(n) != n || floor(r) != r || n < 0 || r < 0) return BC_NAN;
    if (r > n) return 0;
    float k = permutation ? r : min(r, n - r);
    // Beyond these k the result exceeds FLT_MAX (nPr ≥ r! ≥ 35! ≈ 1.0·10⁴⁰, nCr ≥ C(2k, k) ≥ C(132, 66) ≈ 3.8·10³⁸),
    // so return +∞ instead of running the loop k times per pixel (huge k times the GPU out).
    if (permutation ? k >= 35.0f : k >= 66.0f) return as_type<float>(0x7f800000u);
    float result = 1.0f;
    for (int i = 1; i <= int(k); i++) {
        result = permutation ? result * (n - k + float(i)) : result * (n - k + float(i)) / float(i);
        if (isinf(result)) break;
    }
    return permutation ? result : round(result);
}

static inline float bc_gcd(float a, float b) {
    if (floor(a) != a || floor(b) != b) return BC_NAN;
    int x = abs(int(a));
    int y = abs(int(b));
    for (int i = 0; i < 64 && y != 0; i++) { int t = x % y; x = y; y = t; }
    return float(x);
}

// MARK: - Complex helpers

static inline float2 c_mul(float2 a, float2 b) { return float2(a.x * b.x - a.y * b.y, a.x * b.y + a.y * b.x); }
static inline float2 c_div(float2 a, float2 b) {
    float d = dot(b, b);
    if (d == 0) return float2(BC_NAN);
    return float2(a.x * b.x + a.y * b.y, a.y * b.x - a.x * b.y) / d;
}
static inline float2 c_exp(float2 z) { float e = exp(z.x); return float2(e * cos(z.y), e * sin(z.y)); }
static inline float2 c_log(float2 z) { return float2(log(length(z)), atan2(z.y, z.x)); }
static inline float2 c_sqrt(float2 z) {
    float m = length(z);
    float re = sqrt(max(0.0f, (m + z.x) * 0.5f));
    float im = sqrt(max(0.0f, (m - z.x) * 0.5f));
    return float2(re, z.y < 0 ? -im : im);
}
static inline float2 c_pow(float2 a, float2 b) {
    if (a.x == 0 && a.y == 0) return (b.x > 0) ? float2(0) : float2(BC_NAN);
    return c_exp(c_mul(b, c_log(a)));
}
static inline float2 c_powi(float2 z, int n) {
    bool negative = n < 0;
    int e = abs(n);
    float2 result = float2(1, 0);
    float2 b = z;
    while (e > 0) {
        if (e & 1) result = c_mul(result, b);
        b = c_mul(b, b);
        e >>= 1;
    }
    return negative ? c_div(float2(1, 0), result) : result;
}
static inline float2 c_sin(float2 z) { return float2(sin(z.x) * cosh(z.y), cos(z.x) * sinh(z.y)); }
static inline float2 c_cos(float2 z) { return float2(cos(z.x) * cosh(z.y), -sin(z.x) * sinh(z.y)); }
static inline float2 c_tan(float2 z) { return c_div(c_sin(z), c_cos(z)); }
static inline float2 c_sinh(float2 z) { return float2(sinh(z.x) * cos(z.y), cosh(z.x) * sin(z.y)); }
static inline float2 c_cosh(float2 z) { return float2(cosh(z.x) * cos(z.y), sinh(z.x) * sin(z.y)); }
static inline float2 c_tanh(float2 z) { return c_div(c_sinh(z), c_cosh(z)); }
static inline float2 c_asin(float2 z) {
    // −i·ln(iz + √(1 − z²))
    float2 iz = float2(-z.y, z.x);
    float2 w = c_log(iz + c_sqrt(float2(1, 0) - c_mul(z, z)));
    return float2(w.y, -w.x);
}
static inline float2 c_acos(float2 z) { return float2(BC_PI * 0.5f, 0) - c_asin(z); }
static inline float2 c_atan(float2 z) {
    // (i/2)·ln((i + z)/(i − z))
    float2 w = c_log(c_div(float2(z.x, 1 + z.y), float2(-z.x, 1 - z.y)));
    return float2(-0.5f * w.y, 0.5f * w.x);
}
static inline float2 c_asinh(float2 z) { return c_log(z + c_sqrt(c_mul(z, z) + float2(1, 0))); }
static inline float2 c_acosh(float2 z) { return c_log(z + c_mul(c_sqrt(z + float2(1, 0)), c_sqrt(z - float2(1, 0)))); }
static inline float2 c_atanh(float2 z) { return 0.5f * c_log(c_div(float2(1, 0) + z, float2(1, 0) - z)); }

/// Γ(z), Lanczos (g = 5) with reflection.
static inline float2 c_gamma_pos(float2 z) {
    const float c[6] = { 76.18009172947146f, -86.50532032941677f, 24.01409824083091f,
                         -1.231739572450155f, 0.1208650973866179e-2f, -0.5395239384953e-5f };
    float2 x = z;
    float2 y = z;
    float2 tmp = x + float2(5.5f, 0);
    tmp = tmp - c_mul(x + float2(0.5f, 0), c_log(tmp));
    float2 ser = float2(1.000000000190015f, 0);
    for (int j = 0; j < 6; j++) { y = y + float2(1, 0); ser = ser + c_div(float2(c[j], 0), y); }
    float2 lg = -tmp + c_log(c_div(2.5066282746310005f * ser, x));
    return c_exp(lg);
}

static inline float2 c_gamma(float2 z) {
    if (z.x < 0.5f) {
        float2 s = c_sin(BC_PI * z);
        return c_div(float2(BC_PI, 0), c_mul(s, c_gamma_pos(float2(1, 0) - z)));
    }
    return c_gamma_pos(z);
}

/// Borwein coefficients cₖ = (−1)ᵏ(1 − dₖ/dₙ), n = 64 (normalised so they fit in float).
constant float bc_zeta_coefficients[64] = {
    1.000000000e+00, -1.000000000e+00, 1.000000000e+00, -1.000000000e+00,
    1.000000000e+00, -1.000000000e+00, 1.000000000e+00, -1.000000000e+00,
    1.000000000e+00, -1.000000000e+00, 1.000000000e+00, -1.000000000e+00,
    1.000000000e+00, -1.000000000e+00, 1.000000000e+00, -1.000000000e+00,
    1.000000000e+00, -1.000000000e+00, 1.000000000e+00, -1.000000000e+00,
    1.000000000e+00, -1.000000000e+00, 1.000000000e+00, -9.999999999e-01,
    9.999999991e-01, -9.999999947e-01, 9.999999719e-01, -9.999998629e-01,
    9.999993863e-01, -9.999974764e-01, 9.999904516e-01, -9.999667064e-01,
    9.998928560e-01, -9.996813238e-01, 9.991228711e-01, -9.977631603e-01,
    9.947085987e-01, -9.883755573e-01, 9.762561159e-01, -9.548503494e-01,
    9.199643690e-01, -8.675250995e-01, 7.948682804e-01, -7.021538058e-01,
    5.933087566e-01, -4.759028607e-01, 3.597310450e-01, -2.544827288e-01,
    1.673758986e-01, -1.016929869e-01, 5.671014439e-02, -2.883492921e-02,
    1.327352267e-02, -5.488624955e-03, 2.020586408e-03, -6.553535526e-04,
    1.849016901e-04, -4.466452572e-05, 9.048070477e-06, -1.494471972e-06,
    1.932218098e-07, -1.833491626e-08, 1.135182433e-09, -3.439946765e-11,
};

/// ζ(s) for Re s ≥ ½ via the Dirichlet η series with Borwein acceleration.
static inline float2 c_zeta_right(float2 s) {
    float2 sum = float2(0);
    for (int k = 0; k < 64; k++) {
        // (k+1)^(−s) = exp(−s·ln(k+1))
        float lnk = log(float(k + 1));
        float2 term = c_exp(float2(-s.x * lnk, -s.y * lnk));
        sum += bc_zeta_coefficients[k] * term;
    }
    // 1 − 2^(1−s)
    float2 twoPower = c_exp((float2(1, 0) - s) * log(2.0f));
    return c_div(sum, float2(1, 0) - twoPower);
}

static inline float2 c_zeta(float2 s) {
    if (s.x >= 0.5f) return c_zeta_right(s);
    // Functional equation: ζ(s) = 2ˢ πˢ⁻¹ sin(πs/2) Γ(1−s) ζ(1−s)
    float2 oneMinus = float2(1, 0) - s;
    // At s = 0 (also when 1 − s rounds to 1) it is 0·∞: ζ(0) = −1/2 (DLMF 25.6.1).
    if (oneMinus.x == 1 && oneMinus.y == 0) return float2(-0.5f, 0);
    float2 factor = c_mul(c_exp(s * log(2.0f)), c_exp((s - float2(1, 0)) * log(BC_PI)));
    factor = c_mul(factor, c_sin(0.5f * BC_PI * s));
    factor = c_mul(factor, c_gamma(oneMinus));
    return c_mul(factor, c_zeta_right(oneMinus));
}

/// Comparison opcodes with a relative tolerance for equality (float precision).
static inline bool bc_compare(uint op, float a, float b) {
    // An infinite operand (float overflow, e.g. e^89) made the tolerance ∞, so ∞ ≤ 5, −∞ ≥ 0 and ∞ = 5 held.
    // With exactly one side infinite, or ∞ against −∞, the order is exact (as on the CPU, RealVM.compare).
    // Equal infinities and NaN take the tolerance path as before.
    if ((isinf(a) || isinf(b)) && !isnan(a) && !isnan(b) && a != b) {
        switch (op) {
            case BCOpLt: case BCOpLe: return a < b;
            case BCOpGt: case BCOpGe: return a > b;
            case BCOpEq: return false;
            default: return true;
        }
    }
    const float tolerance = 1e-6f * max(1.0f, max(fabs(a), fabs(b)));
    switch (op) {
        case BCOpLt: return a < b;
        case BCOpLe: return a <= b + tolerance;
        case BCOpGt: return a > b;
        case BCOpGe: return a >= b - tolerance;
        case BCOpEq: return fabs(a - b) <= tolerance;
        default: return fabs(a - b) > tolerance;
    }
}

// MARK: - Interpreters

/// f(x, y) in float.
static inline float bc_eval_real(constant BCInstruction *code, int count, float x, float y, constant float *params) {
    float s[BC_MAX_STACK];
    int sp = 0;
    for (int pc = 0; pc < count; pc++) {
        const uint op = code[pc].op;
        const float v = code[pc].value;
        switch (op) {
            case BCOpConst: s[sp++] = v; break;
            case BCOpX: s[sp++] = x; break;
            case BCOpY: s[sp++] = y; break;
            case BCOpT: s[sp++] = 0; break;
            case BCOpZ: s[sp++] = x; break;
            case BCOpParam: s[sp++] = params[int(v)]; break;
            case BCOpImaginaryUnit: s[sp++] = BC_NAN; break;
            case BCOpAdd: sp--; s[sp - 1] += s[sp]; break;
            case BCOpSub: sp--; s[sp - 1] -= s[sp]; break;
            case BCOpMul: sp--; s[sp - 1] *= s[sp]; break;
            case BCOpDiv: sp--; s[sp - 1] = s[sp] == 0 ? BC_NAN : s[sp - 1] / s[sp]; break;
            case BCOpPow: sp--; s[sp - 1] = bc_pow(s[sp - 1], s[sp]); break;
            case BCOpNeg: s[sp - 1] = -s[sp - 1]; break;
            case BCOpMod: { sp--; float b = s[sp]; float r = fmod(s[sp - 1], b); s[sp - 1] = b == 0 ? BC_NAN : ((r != 0 && ((r < 0) != (b < 0))) ? r + b : r); break; }
            case BCOpPowInt: s[sp - 1] = bc_powi(s[sp - 1], int(v)); break;
            case BCOpSquare: s[sp - 1] *= s[sp - 1]; break;
            case BCOpCube: s[sp - 1] = s[sp - 1] * s[sp - 1] * s[sp - 1]; break;
            case BCOpRecip: s[sp - 1] = s[sp - 1] == 0 ? BC_NAN : 1.0f / s[sp - 1]; break;
            case BCOpSqrt: s[sp - 1] = s[sp - 1] < 0 ? BC_NAN : sqrt(s[sp - 1]); break;
            case BCOpCbrt: s[sp - 1] = bc_cbrt(s[sp - 1]); break;
            case BCOpRootN: sp--; s[sp - 1] = bc_root_n(s[sp - 1], s[sp]); break;
            case BCOpAbs: s[sp - 1] = fabs(s[sp - 1]); break;
            case BCOpSign: s[sp - 1] = sign(s[sp - 1]); break;
            case BCOpFloor: s[sp - 1] = floor(s[sp - 1]); break;
            case BCOpCeil: s[sp - 1] = ceil(s[sp - 1]); break;
            case BCOpRound: s[sp - 1] = round(s[sp - 1]); break;
            case BCOpFrac: s[sp - 1] = s[sp - 1] - trunc(s[sp - 1]); break;
            case BCOpTrunc: s[sp - 1] = trunc(s[sp - 1]); break;
            // min of an undefined value is undefined, as on the CPU (RealVM): Metal's min returns the other operand,
            // so min(y − ln x, 2 − y) was 2 − y where ln x is undefined. Not max: the max of the gaps of regions is
            // their union, which an undefined max would leave out wherever one region is undefined.
            case BCOpMin: sp--; s[sp - 1] = (isnan(s[sp - 1]) || isnan(s[sp])) ? BC_NAN : min(s[sp - 1], s[sp]); break;
            case BCOpMax: sp--; s[sp - 1] = max(s[sp - 1], s[sp]); break;
            case BCOpExp: s[sp - 1] = exp(s[sp - 1]); break;
            case BCOpLn: s[sp - 1] = s[sp - 1] <= 0 ? BC_NAN : log(s[sp - 1]); break;
            case BCOpLog10: s[sp - 1] = s[sp - 1] <= 0 ? BC_NAN : log10(s[sp - 1]); break;
            case BCOpLog2: s[sp - 1] = s[sp - 1] <= 0 ? BC_NAN : log2(s[sp - 1]); break;
            case BCOpLogBase: { sp--; float b = s[sp - 1]; float a = s[sp]; s[sp - 1] = (b <= 0 || b == 1 || a <= 0) ? BC_NAN : log(a) / log(b); break; }
            case BCOpSin: s[sp - 1] = sin(s[sp - 1]); break;
            case BCOpCos: s[sp - 1] = cos(s[sp - 1]); break;
            case BCOpTan: s[sp - 1] = tan(s[sp - 1]); break;
            // At an exact zero of the denominator (a pole) NaN, as BCOpDiv and BCOpRecip; cos is never 0 in float.
            case BCOpCot: { float t = tan(s[sp - 1]); s[sp - 1] = t == 0 ? BC_NAN : 1.0f / t; break; }
            case BCOpSec: s[sp - 1] = 1.0f / cos(s[sp - 1]); break;
            case BCOpCsc: { float sn = sin(s[sp - 1]); s[sp - 1] = sn == 0 ? BC_NAN : 1.0f / sn; break; }
            case BCOpAsin: s[sp - 1] = fabs(s[sp - 1]) > 1 ? BC_NAN : asin(s[sp - 1]); break;
            case BCOpAcos: s[sp - 1] = fabs(s[sp - 1]) > 1 ? BC_NAN : acos(s[sp - 1]); break;
            case BCOpAtan: s[sp - 1] = atan(s[sp - 1]); break;
            case BCOpAcot: { float a = s[sp - 1]; s[sp - 1] = a == 0 ? BC_PI * 0.5f : atan(1.0f / a) + (a < 0 ? BC_PI : 0.0f); break; }
            case BCOpAsec: s[sp - 1] = fabs(s[sp - 1]) < 1 ? BC_NAN : acos(1.0f / s[sp - 1]); break;
            case BCOpAcsc: s[sp - 1] = fabs(s[sp - 1]) < 1 ? BC_NAN : asin(1.0f / s[sp - 1]); break;
            case BCOpSinh: s[sp - 1] = sinh(s[sp - 1]); break;
            case BCOpCosh: s[sp - 1] = cosh(s[sp - 1]); break;
            case BCOpTanh: s[sp - 1] = tanh(s[sp - 1]); break;
            case BCOpCoth: { float t = tanh(s[sp - 1]); s[sp - 1] = t == 0 ? BC_NAN : 1.0f / t; break; }
            case BCOpSech: s[sp - 1] = 1.0f / cosh(s[sp - 1]); break;
            case BCOpCsch: { float sn = sinh(s[sp - 1]); s[sp - 1] = sn == 0 ? BC_NAN : 1.0f / sn; break; }
            case BCOpAsinh: s[sp - 1] = asinh(s[sp - 1]); break;
            case BCOpAcosh: s[sp - 1] = s[sp - 1] < 1 ? BC_NAN : acosh(s[sp - 1]); break;
            case BCOpAtanh: s[sp - 1] = fabs(s[sp - 1]) >= 1 ? BC_NAN : atanh(s[sp - 1]); break;
            case BCOpAcoth: { float a = s[sp - 1]; s[sp - 1] = fabs(a) <= 1 ? BC_NAN : 0.5f * log((a + 1) / (a - 1)); break; }
            case BCOpAsech: { float a = s[sp - 1]; s[sp - 1] = (a <= 0 || a > 1) ? BC_NAN : acosh(1.0f / a); break; }
            case BCOpAcsch: s[sp - 1] = s[sp - 1] == 0 ? BC_NAN : asinh(1.0f / s[sp - 1]); break;
            case BCOpGamma: s[sp - 1] = bc_gamma(s[sp - 1]); break;
            case BCOpFactorial: s[sp - 1] = bc_gamma(s[sp - 1] + 1); break;
            case BCOpZeta: s[sp - 1] = s[sp - 1] == 1 ? BC_NAN : c_zeta(float2(s[sp - 1], 0)).x; break;
            case BCOpErf: s[sp - 1] = bc_erf(s[sp - 1]); break;
            case BCOpNormcdf: s[sp - 1] = 0.5f * (1 + bc_erf(s[sp - 1] * 0.70710678f)); break;
            case BCOpNCr: sp--; s[sp - 1] = bc_combination(s[sp - 1], s[sp], false); break;
            case BCOpNPr: sp--; s[sp - 1] = bc_combination(s[sp - 1], s[sp], true); break;
            case BCOpGcd: sp--; s[sp - 1] = bc_gcd(s[sp - 1], s[sp]); break;
            case BCOpLcm: { sp--; float g = bc_gcd(s[sp - 1], s[sp]); s[sp - 1] = g == 0 ? 0 : fabs(s[sp - 1] * s[sp]) / g; break; }
            case BCOpRe: break;
            case BCOpConj: break;
            case BCOpIm: s[sp - 1] = 0; break;
            case BCOpArg: s[sp - 1] = s[sp - 1] < 0 ? BC_PI : 0.0f; break;
            case BCOpLt: case BCOpLe: case BCOpGt: case BCOpGe: case BCOpEq: case BCOpNe:
                sp--; s[sp - 1] = bc_compare(op, s[sp - 1], s[sp]) ? 1.0f : 0.0f; break;
            case BCOpSelect: sp -= 2; s[sp - 1] = s[sp + 1] != 0 ? s[sp] : s[sp - 1]; break;
            default: break;
        }
    }
    return sp > 0 ? s[0] : BC_NAN;
}

/// Forward-mode automatic differentiation: returns (f, ∂f/∂x, ∂f/∂y).
static inline float3 bc_eval_dual(constant BCInstruction *code, int count, float x, float y, constant float *params) {
    float3 s[BC_MAX_STACK];
    int sp = 0;
    for (int pc = 0; pc < count; pc++) {
        const uint op = code[pc].op;
        const float v = code[pc].value;
        switch (op) {
            case BCOpConst: s[sp++] = float3(v, 0, 0); break;
            case BCOpX: s[sp++] = float3(x, 1, 0); break;
            case BCOpY: s[sp++] = float3(y, 0, 1); break;
            case BCOpT: s[sp++] = float3(0); break;
            case BCOpZ: s[sp++] = float3(x, 1, 0); break;
            case BCOpParam: s[sp++] = float3(params[int(v)], 0, 0); break;
            case BCOpImaginaryUnit: s[sp++] = float3(BC_NAN); break;
            case BCOpAdd: sp--; s[sp - 1] += s[sp]; break;
            case BCOpSub: sp--; s[sp - 1] -= s[sp]; break;
            case BCOpMul: { sp--; float3 a = s[sp - 1]; float3 b = s[sp]; s[sp - 1] = float3(a.x * b.x, a.yz * b.x + b.yz * a.x); break; }
            case BCOpDiv: {
                sp--; float3 a = s[sp - 1]; float3 b = s[sp];
                if (b.x == 0) { s[sp - 1] = float3(BC_NAN); break; }
                s[sp - 1] = float3(a.x / b.x, (a.yz * b.x - a.x * b.yz) / (b.x * b.x));
                break;
            }
            case BCOpPow: {
                sp--; float3 a = s[sp - 1]; float3 b = s[sp];
                float value = bc_pow(a.x, b.x);
                float2 grad;
                if (b.y == 0 && b.z == 0) {
                    // constant exponent: b·a^(b−1)·a′
                    grad = a.x == 0 ? float2(0) : b.x * bc_pow(a.x, b.x - 1) * a.yz;
                } else {
                    // a^b·(b′·ln a + b·a′/a)
                    grad = a.x > 0 ? value * (b.yz * log(a.x) + b.x * a.yz / a.x) : float2(BC_NAN);
                }
                s[sp - 1] = float3(value, grad);
                break;
            }
            case BCOpNeg: s[sp - 1] = -s[sp - 1]; break;
            case BCOpMod: { sp--; float3 a = s[sp - 1]; float b = s[sp].x; float r = fmod(a.x, b); s[sp - 1] = float3(b == 0 ? BC_NAN : ((r != 0 && ((r < 0) != (b < 0))) ? r + b : r), a.yz); break; }
            case BCOpPowInt: { float3 a = s[sp - 1]; int n = int(v); s[sp - 1] = float3(bc_powi(a.x, n), float(n) * bc_powi(a.x, n - 1) * a.yz); break; }
            case BCOpSquare: { float3 a = s[sp - 1]; s[sp - 1] = float3(a.x * a.x, 2 * a.x * a.yz); break; }
            case BCOpCube: { float3 a = s[sp - 1]; s[sp - 1] = float3(a.x * a.x * a.x, 3 * a.x * a.x * a.yz); break; }
            case BCOpRecip: { float3 a = s[sp - 1]; s[sp - 1] = a.x == 0 ? float3(BC_NAN) : float3(1 / a.x, -a.yz / (a.x * a.x)); break; }
            case BCOpSqrt: { float3 a = s[sp - 1]; float r = sqrt(a.x); s[sp - 1] = a.x < 0 ? float3(BC_NAN) : float3(r, a.yz / (2 * r)); break; }
            case BCOpCbrt: { float3 a = s[sp - 1]; float r = bc_cbrt(a.x); s[sp - 1] = float3(r, a.yz / (3 * r * r)); break; }
            case BCOpRootN: { sp--; float3 a = s[sp - 1]; float n = s[sp].x; float r = bc_root_n(a.x, n); s[sp - 1] = float3(r, r / (n * a.x) * a.yz); break; }
            case BCOpAbs: { float3 a = s[sp - 1]; s[sp - 1] = float3(fabs(a.x), sign(a.x) * a.yz); break; }
            case BCOpSign: s[sp - 1] = float3(sign(s[sp - 1].x), 0, 0); break;
            case BCOpFloor: s[sp - 1] = float3(floor(s[sp - 1].x), 0, 0); break;
            case BCOpCeil: s[sp - 1] = float3(ceil(s[sp - 1].x), 0, 0); break;
            case BCOpRound: s[sp - 1] = float3(round(s[sp - 1].x), 0, 0); break;
            case BCOpFrac: s[sp - 1] = float3(s[sp - 1].x - trunc(s[sp - 1].x), s[sp - 1].yz); break;
            case BCOpTrunc: s[sp - 1] = float3(trunc(s[sp - 1].x), 0, 0); break;
            // A NaN operand of min wins (undefined, as in bc_eval_real; not for max, as there): the comparison alone is
            // false for a NaN first operand and kept the second, so y ≥ ln x, y ≤ 2 was filled where ln x is undefined.
            case BCOpMin: { sp--; s[sp - 1] = (isnan(s[sp - 1].x) || s[sp - 1].x <= s[sp].x) ? s[sp - 1] : s[sp]; break; }
            case BCOpMax: { sp--; s[sp - 1] = s[sp - 1].x >= s[sp].x ? s[sp - 1] : s[sp]; break; }
            case BCOpExp: { float3 a = s[sp - 1]; float e = exp(a.x); s[sp - 1] = float3(e, e * a.yz); break; }
            case BCOpLn: { float3 a = s[sp - 1]; s[sp - 1] = a.x <= 0 ? float3(BC_NAN) : float3(log(a.x), a.yz / a.x); break; }
            case BCOpLog10: { float3 a = s[sp - 1]; s[sp - 1] = a.x <= 0 ? float3(BC_NAN) : float3(log10(a.x), a.yz / (a.x * 2.30258509f)); break; }
            case BCOpLog2: { float3 a = s[sp - 1]; s[sp - 1] = a.x <= 0 ? float3(BC_NAN) : float3(log2(a.x), a.yz / (a.x * 0.69314718f)); break; }
            case BCOpLogBase: {
                sp--; float3 b = s[sp - 1]; float3 a = s[sp];
                if (b.x <= 0 || b.x == 1 || a.x <= 0) { s[sp - 1] = float3(BC_NAN); break; }
                float lb = log(b.x); float la = log(a.x);
                // d/dx (ln a / ln b) = (a′/a · ln b − ln a · b′/b) / ln² b
                s[sp - 1] = float3(la / lb, (a.yz / a.x * lb - la * b.yz / b.x) / (lb * lb));
                break;
            }
            case BCOpSin: { float3 a = s[sp - 1]; s[sp - 1] = float3(sin(a.x), cos(a.x) * a.yz); break; }
            case BCOpCos: { float3 a = s[sp - 1]; s[sp - 1] = float3(cos(a.x), -sin(a.x) * a.yz); break; }
            case BCOpTan: { float3 a = s[sp - 1]; float c = cos(a.x); s[sp - 1] = float3(tan(a.x), a.yz / (c * c)); break; }
            // NaN at a pole, as in bc_eval_real.
            case BCOpCot: { float3 a = s[sp - 1]; float sn = sin(a.x); float t = tan(a.x); s[sp - 1] = t == 0 ? float3(BC_NAN) : float3(1 / t, -a.yz / (sn * sn)); break; }
            case BCOpSec: { float3 a = s[sp - 1]; float c = cos(a.x); s[sp - 1] = float3(1 / c, tan(a.x) / c * a.yz); break; }
            case BCOpCsc: { float3 a = s[sp - 1]; float sn = sin(a.x); s[sp - 1] = sn == 0 ? float3(BC_NAN) : float3(1 / sn, -1 / (sn * tan(a.x)) * a.yz); break; }
            case BCOpAsin: { float3 a = s[sp - 1]; s[sp - 1] = fabs(a.x) > 1 ? float3(BC_NAN) : float3(asin(a.x), a.yz / sqrt(1 - a.x * a.x)); break; }
            case BCOpAcos: { float3 a = s[sp - 1]; s[sp - 1] = fabs(a.x) > 1 ? float3(BC_NAN) : float3(acos(a.x), -a.yz / sqrt(1 - a.x * a.x)); break; }
            case BCOpAtan: { float3 a = s[sp - 1]; s[sp - 1] = float3(atan(a.x), a.yz / (1 + a.x * a.x)); break; }
            case BCOpAcot: { float3 a = s[sp - 1]; float val = a.x == 0 ? BC_PI * 0.5f : atan(1 / a.x) + (a.x < 0 ? BC_PI : 0.0f); s[sp - 1] = float3(val, -a.yz / (1 + a.x * a.x)); break; }
            case BCOpAsec: { float3 a = s[sp - 1]; s[sp - 1] = fabs(a.x) < 1 ? float3(BC_NAN) : float3(acos(1 / a.x), a.yz / (fabs(a.x) * sqrt(a.x * a.x - 1))); break; }
            case BCOpAcsc: { float3 a = s[sp - 1]; s[sp - 1] = fabs(a.x) < 1 ? float3(BC_NAN) : float3(asin(1 / a.x), -a.yz / (fabs(a.x) * sqrt(a.x * a.x - 1))); break; }
            case BCOpSinh: { float3 a = s[sp - 1]; s[sp - 1] = float3(sinh(a.x), cosh(a.x) * a.yz); break; }
            case BCOpCosh: { float3 a = s[sp - 1]; s[sp - 1] = float3(cosh(a.x), sinh(a.x) * a.yz); break; }
            case BCOpTanh: { float3 a = s[sp - 1]; float c = cosh(a.x); s[sp - 1] = float3(tanh(a.x), a.yz / (c * c)); break; }
            case BCOpCoth: { float3 a = s[sp - 1]; float sn = sinh(a.x); float t = tanh(a.x); s[sp - 1] = t == 0 ? float3(BC_NAN) : float3(1 / t, -a.yz / (sn * sn)); break; }
            case BCOpSech: { float3 a = s[sp - 1]; float c = cosh(a.x); s[sp - 1] = float3(1 / c, -tanh(a.x) / c * a.yz); break; }
            case BCOpCsch: { float3 a = s[sp - 1]; float sn = sinh(a.x); s[sp - 1] = sn == 0 ? float3(BC_NAN) : float3(1 / sn, -1 / (sn * tanh(a.x)) * a.yz); break; }
            case BCOpAsinh: { float3 a = s[sp - 1]; s[sp - 1] = float3(asinh(a.x), a.yz / sqrt(a.x * a.x + 1)); break; }
            case BCOpAcosh: { float3 a = s[sp - 1]; s[sp - 1] = a.x < 1 ? float3(BC_NAN) : float3(acosh(a.x), a.yz / sqrt(a.x * a.x - 1)); break; }
            case BCOpAtanh: { float3 a = s[sp - 1]; s[sp - 1] = fabs(a.x) >= 1 ? float3(BC_NAN) : float3(atanh(a.x), a.yz / (1 - a.x * a.x)); break; }
            case BCOpAcoth: { float3 a = s[sp - 1]; s[sp - 1] = fabs(a.x) <= 1 ? float3(BC_NAN) : float3(0.5f * log((a.x + 1) / (a.x - 1)), a.yz / (1 - a.x * a.x)); break; }
            case BCOpAsech: { float3 a = s[sp - 1]; s[sp - 1] = (a.x <= 0 || a.x > 1) ? float3(BC_NAN) : float3(acosh(1 / a.x), -a.yz / (a.x * sqrt(1 - a.x * a.x))); break; }
            case BCOpAcsch: { float3 a = s[sp - 1]; s[sp - 1] = a.x == 0 ? float3(BC_NAN) : float3(asinh(1 / a.x), -a.yz / (fabs(a.x) * sqrt(1 + a.x * a.x))); break; }
            case BCOpErf: { float3 a = s[sp - 1]; s[sp - 1] = float3(bc_erf(a.x), 1.12837917f * exp(-a.x * a.x) * a.yz); break; }
            case BCOpNormcdf: { float3 a = s[sp - 1]; s[sp - 1] = float3(0.5f * (1 + bc_erf(a.x * 0.70710678f)), 0.39894228f * exp(-0.5f * a.x * a.x) * a.yz); break; }
            case BCOpLt: case BCOpLe: case BCOpGt: case BCOpGe: case BCOpEq: case BCOpNe: {
                sp--;
                s[sp - 1] = float3(bc_compare(op, s[sp - 1].x, s[sp].x) ? 1.0f : 0.0f, 0, 0);
                break;
            }
            case BCOpSelect: sp -= 2; s[sp - 1] = s[sp + 1].x != 0 ? s[sp] : s[sp - 1]; break;
            // arg of a real number: π below zero, 0 otherwise (as bc_eval_real); the derivative is 0.
            case BCOpArg: s[sp - 1] = float3(s[sp - 1].x < 0 ? BC_PI : 0.0f, 0, 0); break;
            // re of a real number is the number, value only like the functions below: CalculationEngine.regionEdges
            // relies on it to keep a factor out of the gradient.
            case BCOpRe: s[sp - 1] = float3(s[sp - 1].x, 0, 0); break;
            default: {
                // Functions without an implemented derivative: value only (numerically differentiated by callers if needed).
                int pops = (op == BCOpNCr || op == BCOpNPr || op == BCOpGcd || op == BCOpLcm) ? 2 : 1;
                if (pops == 2) {
                    sp--;
                    float a = s[sp - 1].x, b = s[sp].x;
                    float r = op == BCOpGcd ? bc_gcd(a, b) : (op == BCOpLcm ? (bc_gcd(a, b) == 0 ? 0 : fabs(a * b) / bc_gcd(a, b)) : bc_combination(a, b, op == BCOpNPr));
                    s[sp - 1] = float3(r, 0, 0);
                } else {
                    float a = s[sp - 1].x;
                    float r = op == BCOpGamma ? bc_gamma(a) : (op == BCOpFactorial ? bc_gamma(a + 1) : (op == BCOpZeta ? c_zeta(float2(a, 0)).x : a));
                    if (op == BCOpIm) r = 0;
                    s[sp - 1] = float3(r, 0, 0);
                }
                break;
            }
        }
    }
    return sp > 0 ? s[0] : float3(BC_NAN);
}

/// f(z) over the complex numbers.
static inline float2 bc_eval_complex(constant BCInstruction *code, int count, float2 z, constant float *params) {
    float2 s[BC_MAX_STACK];
    int sp = 0;
    for (int pc = 0; pc < count; pc++) {
        const uint op = code[pc].op;
        const float v = code[pc].value;
        switch (op) {
            case BCOpConst: s[sp++] = float2(v, 0); break;
            case BCOpX: s[sp++] = float2(z.x, 0); break;
            case BCOpY: s[sp++] = float2(z.y, 0); break;
            case BCOpZ: s[sp++] = z; break;
            case BCOpT: s[sp++] = float2(0); break;
            case BCOpParam: s[sp++] = float2(params[int(v)], 0); break;
            case BCOpImaginaryUnit: s[sp++] = float2(0, 1); break;
            case BCOpAdd: sp--; s[sp - 1] += s[sp]; break;
            case BCOpSub: sp--; s[sp - 1] -= s[sp]; break;
            case BCOpMul: sp--; s[sp - 1] = c_mul(s[sp - 1], s[sp]); break;
            case BCOpDiv: sp--; s[sp - 1] = c_div(s[sp - 1], s[sp]); break;
            case BCOpPow: sp--; s[sp - 1] = c_pow(s[sp - 1], s[sp]); break;
            case BCOpNeg: s[sp - 1] = -s[sp - 1]; break;
            case BCOpPowInt: s[sp - 1] = c_powi(s[sp - 1], int(v)); break;
            case BCOpSquare: s[sp - 1] = c_mul(s[sp - 1], s[sp - 1]); break;
            case BCOpCube: s[sp - 1] = c_mul(s[sp - 1], c_mul(s[sp - 1], s[sp - 1])); break;
            case BCOpRecip: s[sp - 1] = c_div(float2(1, 0), s[sp - 1]); break;
            case BCOpSqrt: s[sp - 1] = c_sqrt(s[sp - 1]); break;
            case BCOpCbrt: s[sp - 1] = c_pow(s[sp - 1], float2(1.0f / 3.0f, 0)); break;
            case BCOpRootN: sp--; s[sp - 1] = c_pow(s[sp - 1], c_div(float2(1, 0), s[sp])); break;
            case BCOpAbs: s[sp - 1] = float2(length(s[sp - 1]), 0); break;
            case BCOpExp: s[sp - 1] = c_exp(s[sp - 1]); break;
            case BCOpLn: s[sp - 1] = c_log(s[sp - 1]); break;
            case BCOpLog10: s[sp - 1] = c_log(s[sp - 1]) / 2.30258509f; break;
            case BCOpLog2: s[sp - 1] = c_log(s[sp - 1]) / 0.69314718f; break;
            case BCOpLogBase: sp--; s[sp - 1] = c_div(c_log(s[sp]), c_log(s[sp - 1])); break;
            case BCOpSin: s[sp - 1] = c_sin(s[sp - 1]); break;
            case BCOpCos: s[sp - 1] = c_cos(s[sp - 1]); break;
            case BCOpTan: s[sp - 1] = c_tan(s[sp - 1]); break;
            case BCOpCot: s[sp - 1] = c_div(float2(1, 0), c_tan(s[sp - 1])); break;
            case BCOpSec: s[sp - 1] = c_div(float2(1, 0), c_cos(s[sp - 1])); break;
            case BCOpCsc: s[sp - 1] = c_div(float2(1, 0), c_sin(s[sp - 1])); break;
            case BCOpAsin: s[sp - 1] = c_asin(s[sp - 1]); break;
            case BCOpAcos: s[sp - 1] = c_acos(s[sp - 1]); break;
            case BCOpAtan: s[sp - 1] = c_atan(s[sp - 1]); break;
            case BCOpAcot: s[sp - 1] = c_atan(c_div(float2(1, 0), s[sp - 1])); break;
            case BCOpAsec: s[sp - 1] = c_acos(c_div(float2(1, 0), s[sp - 1])); break;
            case BCOpAcsc: s[sp - 1] = c_asin(c_div(float2(1, 0), s[sp - 1])); break;
            case BCOpSinh: s[sp - 1] = c_sinh(s[sp - 1]); break;
            case BCOpCosh: s[sp - 1] = c_cosh(s[sp - 1]); break;
            case BCOpTanh: s[sp - 1] = c_tanh(s[sp - 1]); break;
            case BCOpCoth: s[sp - 1] = c_div(float2(1, 0), c_tanh(s[sp - 1])); break;
            case BCOpSech: s[sp - 1] = c_div(float2(1, 0), c_cosh(s[sp - 1])); break;
            case BCOpCsch: s[sp - 1] = c_div(float2(1, 0), c_sinh(s[sp - 1])); break;
            case BCOpAsinh: s[sp - 1] = c_asinh(s[sp - 1]); break;
            case BCOpAcosh: s[sp - 1] = c_acosh(s[sp - 1]); break;
            case BCOpAtanh: s[sp - 1] = c_atanh(s[sp - 1]); break;
            case BCOpAcoth: s[sp - 1] = c_atanh(c_div(float2(1, 0), s[sp - 1])); break;
            case BCOpAsech: s[sp - 1] = c_acosh(c_div(float2(1, 0), s[sp - 1])); break;
            case BCOpAcsch: s[sp - 1] = c_asinh(c_div(float2(1, 0), s[sp - 1])); break;
            case BCOpGamma: s[sp - 1] = c_gamma(s[sp - 1]); break;
            case BCOpFactorial: s[sp - 1] = c_gamma(s[sp - 1] + float2(1, 0)); break;
            case BCOpZeta: s[sp - 1] = c_zeta(s[sp - 1]); break;
            case BCOpRe: s[sp - 1] = float2(s[sp - 1].x, 0); break;
            case BCOpIm: s[sp - 1] = float2(s[sp - 1].y, 0); break;
            case BCOpArg: s[sp - 1] = float2(atan2(s[sp - 1].y, s[sp - 1].x), 0); break;
            case BCOpConj: s[sp - 1] = float2(s[sp - 1].x, -s[sp - 1].y); break;
            case BCOpLt: case BCOpLe: case BCOpGt: case BCOpGe: case BCOpEq: case BCOpNe: {
                // Conditions compare real parts.
                sp--;
                s[sp - 1] = float2(bc_compare(op, s[sp - 1].x, s[sp].x) ? 1.0f : 0.0f, 0);
                break;
            }
            case BCOpSelect: sp -= 2; s[sp - 1] = s[sp + 1].x != 0 ? s[sp] : s[sp - 1]; break;
            case BCOpMin: case BCOpMax: case BCOpMod: case BCOpNCr: case BCOpNPr: case BCOpGcd: case BCOpLcm: {
                sp--;
                float a = s[sp - 1].x, b = s[sp].x;
                float r = 0;
                // min of an undefined value is undefined (as bc_eval_real and the CPU; not max, as there).
                if (op == BCOpMin) r = (isnan(a) || isnan(b)) ? BC_NAN : min(a, b);
                else if (op == BCOpMax) r = max(a, b);
                else if (op == BCOpMod) {
                    // Sign of the divisor, as bc_eval_real and the CPU.
                    r = fmod(a, b);
                    r = b == 0 ? BC_NAN : ((r != 0 && ((r < 0) != (b < 0))) ? r + b : r);
                }
                else if (op == BCOpGcd) r = bc_gcd(a, b);
                else if (op == BCOpLcm) r = bc_gcd(a, b) == 0 ? 0 : fabs(a * b) / bc_gcd(a, b);
                else r = bc_combination(a, b, op == BCOpNPr);
                s[sp - 1] = float2(r, 0);
                break;
            }
            default: {
                // Real-only functions act on the real part.
                float a = s[sp - 1].x;
                float r = a;
                if (op == BCOpSign) r = sign(a);
                else if (op == BCOpFloor) r = floor(a);
                else if (op == BCOpCeil) r = ceil(a);
                else if (op == BCOpRound) r = round(a);
                else if (op == BCOpFrac) r = a - trunc(a);
                else if (op == BCOpTrunc) r = trunc(a);
                else if (op == BCOpErf) r = bc_erf(a);
                else if (op == BCOpNormcdf) r = 0.5f * (1 + bc_erf(a * 0.70710678f));
                s[sp - 1] = float2(r, 0);
                break;
            }
        }
    }
    return sp > 0 ? s[0] : float2(BC_NAN);
}

#endif /* BytecodeInterpreter_h */
