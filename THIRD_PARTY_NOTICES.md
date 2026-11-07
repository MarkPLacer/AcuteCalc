# Third-party notices

Acute Calc 2 includes the following code under a third-party open-source licence. The full text
of each licence is in [`LICENSES`](LICENSES).

## Turbo colour map, polynomial approximation

- **Where:** `turbo()` in `AcuteCalc/Rendering/Shaders/Surface3D.metal`, which colours 3D
  surfaces by height (the Višina colouring in Grafi › 3D). It is a port of the GLSL function
  to the Metal Shading Language, with the same coefficients.
- **Source:** “Turbo Colormap Polynomial Approximation in GLSL”,
  https://gist.github.com/mikhailov-work/0d177465a8151eb6ede1768d51d476c7
- **Copyright:** Copyright 2019 Google LLC.
- **Authors:** Anton Mikhailov (colormap design) and Ruofei Du (GLSL approximation)
- **Licence:** Apache License 2.0 (`SPDX-License-Identifier: Apache-2.0`), see
  [LICENSES/Apache-2.0.txt](LICENSES/Apache-2.0.txt)
