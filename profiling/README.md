# dvui callgrind profile

Two measurements of the same workload, split by when the work happens: what a
process pays once, and what a frame pays after that.

| chart | what it shows |
|---|---|
| `charts/dvui-setup-instructions.svg` | 131.4M instructions paid once, then amortized |
| `charts/dvui-per-frame-instructions.svg` | 31.28M instructions per steady-state frame |

Workload: `examples/ds-bench.zig` running `dvui.Examples.demo(.lite)` in the
demo window through the testing backend, 1000x700 logical at 2x, built
`-Doptimize=ReleaseFast` with freetype 2.14.1. Instrument: valgrind 3.25.1
callgrind, counting retired instructions only.

## Reproduce

```sh
./profiling/collect.sh        # zig build + valgrind at 0,1,2,11,15,21,111,311 frames
python3 profiling/analyze.py  # per-function table, then the groups
python3 profiling/charts.py   # the two SVGs
```

`collect.sh` needs zig 0.17 and valgrind. `analyze.py` needs
`callgrind_annotate`; `charts.py` needs only Python. The committed
`data/*.out.gz` let the last two steps run without valgrind at all, and they
reproduce `charts/*.svg` byte for byte.

## Method

The bench runs a fixed number of identical frames, so total instructions are
`setup + frames * per_frame`. Four runs (11, 21, 111, 311 frames) give the
slope; they agree to within 0.01%, so no drift has to be modelled. The
one-time part is `Ir(2 frames) - 2 * per_frame`, which anchors it at real
measurements instead of extrapolating from the long runs (the least-squares
intercept over the four points agrees within 1.5%).

Per frame, the same slope is fitted for every function separately, so a
function that only runs during setup comes out with a slope of zero and a
positive setup value. Groups are assigned by the source that owns a function,
not by call depth: a callee counts in the group that owns it.

Instruction counts are deterministic: two 111-frame runs produced the same
3,605,605,747 every time.

| frames | total Ir |
|---:|---:|
| 0 | 613,794 |
| 1 | 136,445,374 |
| 2 | 193,980,317 |
| 11 | 477,585,036 |
| 15 | 602,689,390 |
| 21 | 790,382,472 |
| 111 | 3,605,605,747 |
| 311 | 9,862,046,376 |

* steady per-frame: 31,281,572
* one-time setup: 131,417,173
* frame 1: 135,831,580; frame 2: 57,534,943

## Files

* `data/dvui-callgrind-frames-<n>.out.gz` — raw callgrind output per run.
  Absolute paths were rewritten to `<worktree>`, `<home>` and `<zig>`; the
  counters are untouched, and `callgrind_annotate` reads them as they are.
* `data/dvui-callgrind-per-function.tsv` — per-function instructions for every
  run plus the fitted `per_frame_ir` and `setup_ir` columns.
* `data/dvui-callgrind-frame-totals.txt` — the run totals and the derivation.
* `data/dvui-callgrind-buckets.json` — the group totals the charts read.

## Caveats

The demo is the most text-heavy screen in the tree, and the plots demo is in
it, so the std-math group is plot ticks rather than dvui. A text-light screen
moves weight toward the map and layout groups. Setup does not grow with frame
count: it is 22% of a 15-frame run and 1.3% of a 300-frame one, so any
percentage quoted from a short run is inflated by it.
