---
name: screens
description: See Acute Calc's UI without a Mac. Captures simulator screenshots of the app's showcase scenes on GitHub Actions and downloads them so you can look at them with Read. Use after any change to what the app shows, before saying a UI change works, to compare a branch with main, and when a screen needs a new scene.
---

# Screenshots of the app

The app only builds on GitHub's macOS runners, so you look at the UI through the **Screenshots**
workflow (`.github/workflows/screenshots.yml`). It builds the branch, launches the app once on a
simulator, shows the requested *scenes* one after another (`AcuteCalc/App/Showcase.swift`) and
saves a PNG of each once the app has settled. The job takes 7–11 minutes, and the run may first
wait several minutes for a free macOS runner when other builds are going. Almost all of it is the
build, the simulator boot and XCTest starting up; a scene adds only a few seconds, so ask for
every scene you need in one run. The simulator usually starts warm, as an earlier run left it
(`"warmSimulator": true` in `index.json`); a new one, after a runner image update, can make
XCTest wait several minutes more on a busy runner. A warm simulator that does not boot within
five minutes is replaced by a new one; to start from a new one anyway, dispatch
`gh workflow run screenshots.yml --ref <branch> -f warm=false` and fetch the pictures with
`bash scripts/screens.sh --run <id>`.

## Take screenshots

1. Commit and push the branch: the runner builds what is on GitHub.
2. Run the script with the Bash tool **in the background** (`run_in_background`); with the queue it
   can take a quarter of an hour, longer than a foreground command may run. You are told when it
   ends. Or dispatch with `--no-wait` and fetch the pictures later with `--run`:

   ```bash
   bash scripts/screens.sh -s graphs,calculator -a dark
   ```

   | Option | Values | Default |
   |---|---|---|
   | `-s` | `graphs`, `analysis`, `calculator`, `surface`, `landscape`, `complex`, `tools`, `formulas`, comma-separated; `scene@light` for one look; `all` | `all` |
   | `-a` | `dark`, `light`, `both` | `dark` |
   | `-d` | `ipad` (iPad Pro 13-inch), `iphone` (the largest iPhone Pro Max) | `ipad` |
   | `-o` | `auto` (iPad landscape, iPhone portrait), `landscape`, `portrait` | `auto` |
   | `-r` | another branch, e.g. `main` for a *before* picture | the current branch |
   | `--run ID` | download the pictures of an existing run, e.g. a pull request's | |
   | `--no-wait` | dispatch only; fetch later with `--run` | |

3. The script prints the paths of the pictures in `build/screens/<run>/`. Look at the `small/`
   ones with Read (1600 px, the whole screen at once); open `full/` only for fine detail.
   `index.json` lists the shots, how long each took to settle, the commit and the device.

## Look properly

- Check every picture against what you meant to change: clipped or overlapping text, a formula
  cut off in the 420 pt function list, colours that do not work in light mode, an empty or
  badly framed graph, a missing label or result.
- `"settled": false` in `index.json` means the app was still working when the wait ran out, and
  `"steady": false` that the screen was still changing; either way the picture may show the scene
  half drawn, so look at it closely and take it again if anything is missing. `"problems"` lists
  what the app could not build as asked (a missing example, a view whose hook never came): that
  picture is not the scene you meant.
- When you change existing UI, compare with `main` (`-r main`). In the PR, say which scenes you
  checked and link the run.
- Small misalignments of a pixel or two are easy to miss at this size: crop `full/` when
  alignment matters.

## Add a scene

A screen that no scene shows cannot be checked. In `AcuteCalc/App/Showcase.swift`:

1. Add the name to `Showcase.scenes`.
2. Add a `case` to `show(_:…)` that sets the state directly: `store`, `settings`,
   `use(.plane)`/`use(.space)`/`use(.complex)` for the Graphs tab, `select(tab)`. Type input as
   a student would (`typed("…")` takes keypad keys, see `SmokeTest.keys`).
3. To act on a view (frame the graph, open a tool), wait for its hook as the other scenes do
   (`hook`, `frame`; the hooks are in `SmokeHooks`). Do not sleep: the session waits until the
   app is idle (`ShowcaseSync.settle`).
4. Keep scenes deterministic: no dates, random values or animations that keep running.

## Limits

- `gh workflow run` works only once `screenshots.yml` is on `main`. Until then, and for every
  pull request that touches the workflow, `Showcase*.swift`, `AcuteCalc/Rendering/` or the UI
  test, a run with all scenes starts by itself; fetch its pictures with `--run <id>`.
- The free plan runs 5 macOS jobs at a time and every push already takes 3, so one run with all
  the scenes you need is better than several small ones.
