# Acute Calc 2

A modern, fully offline rebuild of *Acute Calculator* for iOS / iPadOS 27 — a structured
("WriteView") scientific calculator with GPU-accelerated graphing, made for studying for the
Slovenian **splošna matura** in mathematics and physics.

No network access, no accounts, no in-app purchases — every feature is unlocked.

## Features

**Calculator**
- Structured math editor: fractions, roots, powers, |x|, logₐ, d/dx, ∂/∂x, ∫, Σ, Π, lim,
  binomials, matrices and vectors (drag the size badge to resize), piecewise functions,
  sin²x / sin⁻¹x notation, Greek letters, vector arrows
- Live results with exact forms (fractions, surds, π), Sharp-style CHANGE
  (decimal, fraction, mixed, recurring, D°M′S″, SCI, ENG, prime factors), complex results
- Equations (exact roots, exponential substitution, periodic trig solutions, complex roots),
  inequalities as intervals (also systems and chains, periodic for trig), limits, improper
  integrals, infinite series, symbolic derivatives
- Matrices & vectors with exact fractions: det, inverse, transpose, rank, dot/cross product,
  angles, linear systems
- History, memories A–F/X/Y/M (numbers or matrices), STO/RCL, M+/M−, ANS
- Long-press-and-drag selection with an edit bar, auto-closing parentheses, (−) key,
  undo/redo (UndoManager: ⌘Z, three-finger swipe), system copy/cut/paste (⌘C/⌘X/⌘V),
  LaTeX import/export, hardware keyboard (typing `sin`, `sqrt`, `alpha` … turns into math),
  Apple Pencil Pro squeeze & double tap, Scribble

**Graphs** (Metal 4, 120 Hz)
- 2D: explicit, implicit and inequality graphs, parameters with animated sliders, special
  points (zeros, extrema, inflections, holes, intersections), tracing with tangent, shaded
  definite integrals (also between two curves), derivatives, Taylor polynomials, tables,
  full function analysis
- Input as in exercises: `f(x) = …`, `v(t) = …`; systems separated by commas
  (`x ≥ 0, y ≥ 0, x + y ≤ 4` → region, `y = 2x + 1, y = 4 − x` → intersection,
  `x² + y² = 4, y ≥ 0` → semicircle); chains `−1 ≤ y < 2`; sets of complex numbers
  (`|z − 1| ≤ 2`, `Re z ≥ −2`, `1 ≤ |z| ≤ 2`)
- Lines and conics in general form (circles, ellipses, hyperbolas, parabolas) are drawn
  exactly per pixel and analysed through their branches (vertices, intercepts, intersections)
- Equal scale on both axes by default (circles stay round); "fit" frames closed curves
- Rows can use each other (`g(x) = f(x − 2) + 1`), the calculator evaluates `f(2)`;
  inverse function and integral function ∫₀ˣ f per row; piecewise derivatives
- Dashed asymptotes (also of hyperbolas), filled/hollow ends of piecewise pieces, angle
  between curves at intersections, tangent and normal equations while tracing
- Sequences as points (`a_n = …`), points and polygons with area and perimeter
  (`A(1, 2), B(4, 5), C(6, 1)`), data polylines with the area under them, complex numbers
  and plane vectors as arrows (sums with the parallelogram)
- The x axis in multiples of π for trigonometric graphs
- 3D: z = f(x, y), solids of revolution, complex landscapes |f|, Re f, Im f
- ℂ: domain colouring (ζ, Γ, …) with probing

**Tools**: statistics with the seven Sharp regressions plus the line through the origin
(y = bx, for measurements), linearised axes (1/x, x², √x, ln x), the area under the data
and charts, an amortization plan, binomial / Poisson /
normal distributions, combinatorics, triangle solver, vectors, linear systems, complex
numbers, sequences, interest, N-BASE with logic operations, DRILL, unit converter,
CODATA 2022 constants.

**University tools** (first year at UL FE and FGG): differential equations (slope field,
initial value problems, closed forms checked by substitution), functions of several
variables (gradient, Hessian, tangent plane, extrema with and without constraints, double
and triple integrals in Cartesian, polar, cylindrical and spherical coordinates, contour
lines, Jacobians), vector analysis (div, curl, potentials, line and surface integrals),
Fourier series with general terms, Student t / χ² / F distributions with confidence
intervals and tests (t-test, χ² goodness of fit, ANOVA), lines and planes in space,
cross-sections (centroid, second moments, principal axes), beams (reactions, shear and
moment diagrams) and surveying (direction angle, polar method, intersections, resection,
Gauss area, Helmert transformation, least squares adjustment, spherical triangles, great
circle and rhumb line). In the calculator: `eig`, `charpoly`, `rref`, `ker`,
`tpdf`/`tcdf`/`invT`, `χ²pdf`/`χ²cdf`/`invχ²`, `fpdf`/`fcdf`/`invF`.

**Formulas**: matura formula sheets for mathematics and physics (rendered from LaTeX).

## Technology

- **SwiftUI** + **Liquid Glass**, Swift 6.4 language mode with default `MainActor` isolation
- **Metal 4** renderers (`MTL4CommandQueue`, argument tables, residency sets) with a Metal 3
  fallback; expressions run on the GPU through bytecode interpreters (real, dual numbers for
  normals, complex with Lanczos Γ and Borwein ζ)
- **AcuteCore**: a platform-independent math engine (Swift package) with tests — parser,
  exact arithmetic, CAS, solvers, numerics, statistics, matrices, LaTeX, formula library

## Building

The app is built on GitHub Actions (`runs-on: xcode-27`, Xcode 27.1, iOS 27.1 SDK,
deployment target iOS 27.0). Every push to `main` produces an **unsigned IPA** artifact
(`AcuteCalc-unsigned-ipa`); a simulator smoke test types sample input into the calculator
and the Graphs tab. When all checks pass, the IPA replaces `AcuteCalc.ipa` in the rolling
release **latest** (no new release per commit):
https://github.com/MarkPLacer/AcuteCalc/releases/latest/download/AcuteCalc.ipa. The build
number is the CI run number (shown in Nastavitve). Pushing a tag `v*` also attaches the IPA
to a versioned release.

```
swift test --package-path Packages/AcuteCore     # math engine tests (macOS)
xcodebuild -project AcuteCalc.xcodeproj -scheme AcuteCalc -sdk iphoneos \
  -configuration Release CODE_SIGNING_ALLOWED=NO build
```

Install the unsigned IPA with your own signing method (e.g. AltStore / SideStore /
Sideloadly with your Apple ID, or a signing service).

## Layout

| Path | Contents |
| --- | --- |
| `Packages/AcuteCore` | Math engine + tests (no UI) |
| `AcuteCalc/Calculator` | Calculator screen, keypad, palettes, results, history |
| `AcuteCalc/MathField` | Math layout engine, editor view, clipboard |
| `AcuteCalc/Graphing`, `Graph3D`, `ComplexPlot` | Graph workspaces |
| `AcuteCalc/Rendering` | Metal 4 / Metal 3 renderers and shaders |
| `AcuteCalc/Tools`, `AcuteCalc/Formulas` | Tools and formula sheets |
| `AcuteCalc/Resources` | Icon Composer app icons (4 variants) and assets |
