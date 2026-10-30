# Profiling dvui

Cost is measured in executed instructions, never in elapsed time.

**Always use callgrind.** Wall clock is not comparable across machines, and it is
not even comparable across runs on one machine overnight: frequency scaling,
other processes and swap move a timing number by more than most of the changes
being measured. Instructions retired for a fixed workload are the same everywhere
the binary is the same, so a number taken here means something on someone else's
machine, and a number taken in a review comment means something here.

## The benchmark

`examples/ds-bench.zig` drives the demo window headlessly for a fixed number of
frames and prints what the run produced (map activity, context-layer reads, layer
sizes). It is the workload every number in this tree is measured on.

```fish
zig build ds-bench -Dbackend=testing -Doptimize=ReleaseFast
```

`--frames N` sets the frame count, `--no-kerning` removes the kerning lookups so
the font caches can be bounded between the cached and uncached cases.

`ReleaseFast` is what is measured. A `Debug` build has comptime checks, safety
checks and no inlining, so a comparison between two `Debug` builds says little
about shipped behaviour; use one optimisation mode for every run in a comparison.

## Callgrind

```fish
valgrind --tool=callgrind --callgrind-out-file=/tmp/cg.out \
    ./zig-out/bin/ds-bench --frames 300
callgrind_annotate --inclusive=yes /tmp/cg.out | less
```

`callgrind_annotate --inclusive=yes` gives cost per function including callees;
`--inclusive=no` (the default) gives exclusive cost, which is what locates the
code actually doing the work. Both are instruction counts.

Callgrind runs the program under an instrumented emulator, so the count differs
from a native run and is much slower. That does not matter: every comparison is
between two callgrind runs of the same build shape.

## Per-frame numbers

A single cold run includes library setup, font loading and the first frame's
layout work. Report a steady-state frame by subtracting two runs over the same
code:

```fish
valgrind --tool=callgrind --callgrind-out-file=/tmp/cg300.out ./zig-out/bin/ds-bench --frames 300
valgrind --tool=callgrind --callgrind-out-file=/tmp/cg600.out ./zig-out/bin/ds-bench --frames 600
grep -h "summary:" /tmp/cg300.out /tmp/cg600.out
```

Then `(instructions(600) - instructions(300)) / 300` is the per-frame cost. The
demo is deterministic, so the two runs do the same work per frame.

`perf stat -e instructions` is a fine second opinion on this workstation, since it
counts the same thing natively, but it is not portable and must never stand in
for the callgrind number in a comparison.

## Built-in counters

Instrumentation is compiled out unless the build asks for it, so a normal build
carries none of it:

```fish
zig build ds-bench -Dbackend=testing -Doptimize=ReleaseFast -Dprofiling
```

`dvui.profiling` then records, per tracking map, puts, gets, hits, misses,
removes, retains, dead entries, rescans, live count and peak. `dvui.profiling.totals()`
sums them, `dvui.profiling.sample(allocator)` snapshots them and
`Profiling.report(writer, samples)` formats a table, and the `Profiler` panel shows
the live numbers.

`dvui.ContextLayer.read_stats` counts how often each option resolution path runs
per frame: plain getters, colors, fonts, sizes, layer combinations and whole-layer
copies. Those counts are what decide whether a cheaper storage shape for the
layers can pay for itself, because they say how many reads stand behind every
write.

## Reporting a result

State the build shape (`-Dbackend`, `-Doptimize`, `-Dfreetype`), the tool
(`callgrind`), the frame counts, and the arithmetic that produced the number.
A claimed saving without the two runs it came from is not a measurement.
