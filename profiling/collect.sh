#!/bin/sh
# Re-create data/dvui-callgrind-frames-*.out.gz from the bench.
#
#   ./profiling/collect.sh              # every run, ~2 minutes under valgrind
#   FRAMES="21 111" ./profiling/collect.sh
#
# Needs zig 0.17 and valgrind 3.25 on PATH. The absolute paths callgrind
# records are rewritten to neutral tokens afterwards, so the committed files
# carry no machine paths; the counters are untouched by that.
set -eu
cd "$(dirname "$0")/.."

zig build ds-bench -Dbackend=testing -Doptimize=ReleaseFast -Dfreetype=true

FRAMES="${FRAMES:-0 1 2 11 15 21 111 311}"
for n in $FRAMES; do
    echo "== frames=$n"
    valgrind --tool=callgrind \
        --callgrind-out-file="profiling/data/dvui-callgrind-frames-$n.out" \
        ./zig-out/bin/ds-bench --frames "$n"
    gzip -9f "profiling/data/dvui-callgrind-frames-$n.out"
done

echo
echo "now: python3 profiling/analyze.py && python3 profiling/charts.py"
