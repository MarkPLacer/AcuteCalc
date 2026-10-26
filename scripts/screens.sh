#!/usr/bin/env bash
# Screenshots of Acute Calc from CI, for agents and people without a Mac: dispatches the
# Screenshots workflow (.github/workflows/screenshots.yml) for a pushed branch, waits for it,
# downloads the pictures and prints where they are.
#
#   bash scripts/screens.sh [-s SCENES] [-a dark|light|both] [-d ipad|iphone]
#                           [-o auto|landscape|portrait] [-r BRANCH] [-D DIR] [--no-wait]
#   bash scripts/screens.sh --run RUN_ID [-D DIR]    (the pictures of an existing run)
#
# SCENES (Showcase.swift): graphs, analysis, calculator, surface, landscape, complex, tools,
# formulas, comma-separated, scene@light for one look, or all (default); dark unless -a says.
# The pictures land in build/screens/<run>/: small/ (1600 px, for looking at), full/ (every
# pixel) and index.json (the shots, their timings, the commit and the device).
set -euo pipefail

scenes=all appearance=dark device=ipad orientation=auto ref="" dir="" run="" wait=1
workflow=screenshots.yml
usage() { sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'; }
while [ $# -gt 0 ]; do
  case "$1" in
    -s|--scenes) scenes=$2; shift 2 ;;
    -a|--appearance) appearance=$2; shift 2 ;;
    -d|--device) device=$2; shift 2 ;;
    -o|--orientation) orientation=$2; shift 2 ;;
    -r|--ref) ref=$2; shift 2 ;;
    -D|--dir) dir=$2; shift 2 ;;
    --run) run=$2; shift 2 ;;
    --no-wait) wait=0; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "screens: unknown option $1" >&2; usage >&2; exit 2 ;;
  esac
done

if [ -z "$run" ]; then
  current=$(git rev-parse --abbrev-ref HEAD)
  ref=${ref:-$current}
  # The runner builds the branch as it is on GitHub.
  remote=$(git ls-remote origin "refs/heads/$ref" | cut -f1)
  if [ -z "$remote" ]; then
    echo "screens: $ref is not on GitHub; push it first" >&2
    exit 1
  fi
  if [ "$ref" = "$current" ] && [ "$remote" != "$(git rev-parse HEAD)" ]; then
    echo "screens: GitHub has $ref at ${remote:0:7}, your HEAD is $(git rev-parse --short HEAD); push first" >&2
    exit 1
  fi
  started=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  output=$(gh workflow run "$workflow" --ref "$ref" -f scenes="$scenes" -f appearance="$appearance" \
    -f device="$device" -f orientation="$orientation" 2>&1) || { echo "$output" >&2; exit 1; }
  run=$(printf '%s\n' "$output" | grep -o 'actions/runs/[0-9]*' | head -n 1 | cut -d/ -f3 || true)
  # gh before 2.87 does not print the run: take the newest one dispatched since.
  for _ in 1 2 3 4 5 6; do
    [ -n "$run" ] && break
    sleep 5
    run=$(gh run list --workflow "$workflow" --branch "$ref" --event workflow_dispatch --limit 1 \
      --json databaseId,createdAt --jq ".[] | select(.createdAt >= \"$started\") | .databaseId" || true)
  done
  if [ -z "$run" ]; then
    echo "screens: dispatched, but no run showed up; see gh run list --workflow $workflow" >&2
    exit 1
  fi
  echo "Run $run ($scenes, $appearance, $device on $ref): $(gh run view "$run" --json url --jq .url)"
  if [ "$wait" = 0 ]; then
    echo "Pictures later: bash scripts/screens.sh --run $run"
    exit 0
  fi
fi

failed=0
gh run watch "$run" --exit-status --interval 10 > /dev/null 2>&1 || failed=1
echo "Run $run $(gh run view "$run" --json conclusion,createdAt,updatedAt \
  --jq '"\(.conclusion) after \((.updatedAt | fromdateiso8601) - (.createdAt | fromdateiso8601)) s"')"

if [ -z "$dir" ]; then
  dir="$(git rev-parse --show-toplevel)/build/screens/$run"
  rm -rf "$dir"
fi
mkdir -p "$dir"
gh run download "$run" --name screenshots --dir "$dir" > /dev/null 2>&1 ||
  echo "screens: run $run has no screenshots artifact" >&2

if [ "$failed" = 1 ]; then
  echo "screens: the run failed; the errors:" >&2
  gh run view "$run" --log-failed 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g' |
    grep -E "##\[error\]|error:|XCTUnwrap|XCTAssert|failed" | tail -n 20 >&2 || true
fi

# Paths the Read tool can open (Windows paths under Git Bash).
show() { if command -v cygpath > /dev/null; then cygpath -w "$1"; else printf '%s\n' "$1"; fi; }
count=0
for file in "$dir"/small/*.png; do
  [ -e "$file" ] || continue
  show "$file"
  count=$((count + 1))
done
[ -f "$dir/index.json" ] && echo "Index: $(show "$dir/index.json")"
echo "$count pictures: small/ to look at, full/ has every pixel."
[ "$failed" = 0 ]
