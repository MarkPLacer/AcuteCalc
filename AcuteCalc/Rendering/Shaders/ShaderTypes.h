//
//  ShaderTypes.h
//  Acute Calc
//
//  Types shared between Swift (via the bridging header) and the Metal shaders.
//  Keep `BCOp` in sync with `Opcode` in Packages/AcuteCore/Sources/AcuteCore/Bytecode/Bytecode.swift.
//

#ifndef ShaderTypes_h
#define ShaderTypes_h

#include <simd/simd.h>

#ifdef __METAL_VERSION__
#define AC_ENUM(_name, _type) enum _name : _type
#else
#import <Foundation/Foundation.h>
#define AC_ENUM(_name, _type) typedef NS_ENUM(_type, _name)
#endif

/// Bytecode opcodes (raw values match `Opcode` in AcuteCore).
AC_ENUM(BCOp, uint32_t) {
    BCOpEnd = 0, BCOpConst = 1, BCOpX = 2, BCOpY = 3, BCOpT = 4, BCOpParam = 5, BCOpZ = 6, BCOpImaginaryUnit = 7,
    BCOpAdd = 16, BCOpSub = 17, BCOpMul = 18, BCOpDiv = 19, BCOpPow = 20, BCOpNeg = 21, BCOpMod = 22, BCOpPowInt = 23,
    BCOpSquare = 24, BCOpCube = 25, BCOpRecip = 26, BCOpSqrt = 27, BCOpCbrt = 28, BCOpRootN = 29,
    BCOpAbs = 30, BCOpSign = 31, BCOpFloor = 32, BCOpCeil = 33, BCOpRound = 34, BCOpFrac = 35, BCOpTrunc = 36,
    BCOpMin = 37, BCOpMax = 38,
    BCOpExp = 48, BCOpLn = 49, BCOpLog10 = 50, BCOpLog2 = 51, BCOpLogBase = 52,
    BCOpSin = 64, BCOpCos = 65, BCOpTan = 66, BCOpCot = 67, BCOpSec = 68, BCOpCsc = 69,
    BCOpAsin = 70, BCOpAcos = 71, BCOpAtan = 72, BCOpAcot = 73, BCOpAsec = 74, BCOpAcsc = 75,
    BCOpSinh = 80, BCOpCosh = 81, BCOpTanh = 82, BCOpCoth = 83, BCOpSech = 84, BCOpCsch = 85,
    BCOpAsinh = 86, BCOpAcosh = 87, BCOpAtanh = 88, BCOpAcoth = 89, BCOpAsech = 90, BCOpAcsch = 91,
    BCOpGamma = 96, BCOpFactorial = 97, BCOpZeta = 98, BCOpErf = 99, BCOpNormcdf = 100,
    BCOpNCr = 101, BCOpNPr = 102, BCOpGcd = 103, BCOpLcm = 104,
    BCOpRe = 112, BCOpIm = 113, BCOpArg = 114, BCOpConj = 115,
    BCOpLt = 120, BCOpLe = 121, BCOpGt = 122, BCOpGe = 123, BCOpEq = 124, BCOpNe = 125, BCOpSelect = 126,
};

/// One bytecode instruction as uploaded to the GPU.
typedef struct {
    uint32_t op;
    float value;
} BCInstruction;

/// Maximum stack depth of the GPU interpreters (matches Program.maximumStackDepth).
#define BC_MAX_STACK 24

/// Buffer binding indices (argument table slots / setVertexBuffer indices).
AC_ENUM(BufferIndex, int32_t) {
    BufferIndexFrame = 0,
    BufferIndexGeometry = 1,
    BufferIndexDraw = 2,
    BufferIndexProgram = 3,
    BufferIndexParameters = 4,
};

/// Per-frame values shared by all 2D draws.
typedef struct {
    /// Drawable size in pixels.
    simd_float2 viewportSize;
    /// Graph units → pixels.
    simd_float2 pixelsPerUnit;
    /// Graph coordinate at the centre of the view, split into high and low parts for precision.
    simd_float2 centerHigh;
    simd_float2 centerLow;
    /// Screen scale (points → pixels).
    float contentScale;
    float time;
    /// 1 for a logarithmic x / y axis, whose plot coordinates are log₁₀ of the values.
    simd_float2 logarithmic;
} FrameUniforms;

/// Per-draw style for lines and points (instanced capsules). Geometry is given in
/// drawable pixels relative to the view centre (y up), transformed on the CPU.
typedef struct {
    simd_float4 color;
    /// Half line width in pixels.
    float halfWidth;
    /// Dash period in pixels (0 = solid).
    float dashPeriod;
    /// Ring thickness in pixels for hollow points (0 = filled).
    float ringThickness;
    /// 1 = segments are independent pairs (p0, p1), 0 = polyline (pᵢ, pᵢ₊₁).
    float pairs;
} LineStyle;

/// Analytic grid. All distances are in drawable pixels relative to the view centre (y up),
/// computed on the CPU in double precision so the GPU only handles small numbers.
typedef struct {
    simd_float4 background;
    simd_float4 minorColor;
    simd_float4 majorColor;
    simd_float4 axisColor;
    simd_float2 minorSpacing;
    simd_float2 majorSpacing;
    /// Pixel position of one minor / major line per axis.
    simd_float2 minorPhase;
    simd_float2 majorPhase;
    /// x: position of the y-axis, y: position of the x-axis.
    simd_float2 axisPosition;
    float showGrid;
    float showAxes;
    float lineWidth;
    float transparentBackground;
    simd_float2 padding;
    /// A logarithmic axis reads its lines (2 … 9 times a decade are not evenly spaced) from the
    /// tick list bound at BufferIndexGeometry: the pixel positions of the major x, minor x, major y
    /// and minor y lines follow each other there, each sorted, this many of each. A linear axis
    /// has none and uses the spacing and phase above.
    simd_uint4 tickCounts;
} GridStyle;

/// Implicit curve / inequality draw parameters.
typedef struct {
    simd_float4 color;
    simd_float4 fillColor;
    float halfWidth;
    /// 0: F = 0 curve, 1: F < 0, 2: F ≤ 0, 3: F > 0, 4: F ≥ 0
    int32_t mode;
    int32_t programLength;
    int32_t parameterCount;
} ImplicitStyle;

/// 3D surface uniforms.
typedef struct {
    simd_float4x4 viewProjection;
    simd_float4 lightDirection;
    simd_float4 cameraPosition;
    /// Domain: xMin, xMax, yMin, yMax
    simd_float4 domain;
    /// zMin, zMax (clip box), zScale, opacity
    simd_float4 zRange;
    simd_float4 baseColor;
    int32_t resolution;
    int32_t programLength;
    /// 0 = height colormap, 1 = base colour, 2 = complex phase (domain colouring)
    int32_t colorMode;
    /// 0 = height field z = f(x, y), 1 = solid of revolution of y = f(x) around the x axis,
    /// 2 = |f(z)|, 3 = Re f(z), 4 = Im f(z) over the complex plane z = x + iy,
    /// 5 = implicit surface F(x, y, z) = 0 (raymarched)
    int32_t surfaceKind;
    float gridLines;
    float time;
    simd_float2 padding;
} SurfaceUniforms;

/// Complex domain colouring uniforms.
typedef struct {
    simd_float2 viewportSize;
    simd_float2 pixelsPerUnit;
    simd_float2 center;
    int32_t programLength;
    int32_t style;
    float contourStrength;
    float gridStrength;
    simd_float2 padding;
} ComplexUniforms;

#endif /* ShaderTypes_h */
