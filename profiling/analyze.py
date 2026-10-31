#!/usr/bin/env python3
"""Turn the callgrind runs in data/ into the per-function table and the buckets
the charts are drawn from.

    python3 profiling/analyze.py

Reads  data/dvui-callgrind-frames-<n>.out.gz  for n in 0,1,2,11,21,111,311
Writes data/dvui-callgrind-per-function.tsv     one row per function
       data/dvui-callgrind-buckets.json         per-frame and setup Ir per group

Needs callgrind_annotate from valgrind on PATH.
"""

import collections
import gzip
import json
import os
import re
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
DATA = os.path.join(HERE, 'data')

# 11/21/111/311 carry the steady-state slope; 0/1/2 anchor the one-time setup.
FIT = [11, 21, 111, 311]
ALL = [0, 1, 2, 11, 21, 111, 311]

ROW = re.compile(r'^\s*([\d,]+)\s+(.+?)(?:\s+\[[^\]]*\])?$')


def annotate(n):
    """Per-function self cost of one run, keyed by `file:function`."""
    src = os.path.join(DATA, f'dvui-callgrind-frames-{n}.out.gz')
    with gzip.open(src, 'rb') as f, tempfile.NamedTemporaryFile(suffix='.out', delete=False) as tmp:
        tmp.write(f.read())
        path = tmp.name
    try:
        out = subprocess.run(
            ['callgrind_annotate', '--auto=no', '--threshold=100', '--show-percs=no', path],
            capture_output=True, text=True, check=True).stdout
    finally:
        os.unlink(path)
    rows = collections.Counter()
    for line in out.splitlines():
        m = ROW.match(line.rstrip('\n'))
        if not m:
            continue
        fn = m.group(2)
        if fn.startswith('PROGRAM TOTALS') or fn.startswith('Ir '):
            continue
        rows[fn] += int(m.group(1).replace(',', ''))
    return rows


def fit(xs, ys):
    n = len(xs)
    mx = sum(xs) / n
    my = sum(ys) / n
    slope = sum((x - mx) * (y - my) for x, y in zip(xs, ys)) / sum((x - mx) ** 2 for x in xs)
    return slope, my - slope * mx


FT = 'freetype-2.14.1'


def bucket(k):
    """Which group a function belongs to: by the source that owns it, not by call depth."""
    # callgrind names some functions by absolute path and some relative; the
    # committed outputs have machine paths rewritten, so strip the marker first.
    k = k.replace('<worktree>/', '', 1).removeprefix('./')
    if FT in k:
        if '/truetype/ttinterp.c' in k: return 'freetype: hinting interpreter'
        if '/autofit/' in k: return 'freetype: autohinter'
        if '/smooth/' in k: return 'freetype: rasterizer'
        if '/sfnt/ttcmap.c' in k or 'FT_Get_Char_Index' in k: return 'freetype: charmap lookup'
        if '/sfnt/ttkern.c' in k or 'Get_Kerning' in k or 'tt_get_kerning' in k or 'cff_get_kerning' in k:
            return 'freetype: kerning'
        if '/truetype/ttgload.c' in k or '/truetype/ttobjs.c' in k or '/base/ftoutln.c' in k:
            return 'freetype: outline load'
        return 'freetype: other'
    if 'src/FontCache.zig' in k or 'src/Font.zig' in k or 'renderText' in k or 'hash/fnv.zig:Font' in k:
        return 'dvui: text measure + vertex emit'
    if 'src/Options.zig' in k: return 'dvui: Options.override'
    if 'hash/fnv.zig' in k or 'hash_map.zig' in k or 'wyhash.zig' in k or 'src/Data.zig' in k:
        return 'maps + hashing'
    if 'memcpy' in k or 'memset' in k: return 'memcpy/memset'
    if 'Allocator.zig' in k or 'malloc' in k or 'free' in k: return 'allocator'
    if 'src/Path.zig' in k or 'src/render.zig' in k or 'src/Gradient' in k or 'src/Texture' in k:
        return 'dvui: render + geometry'
    if 'src/dvui.zig' in k or '/Id.zig' in k: return 'dvui: hover, capture, ids'
    if ('src/layout.zig' in k or 'src/WidgetData.zig' in k or 'src/Rect.zig' in k
            or 'src/Widget.zig' in k or 'widgets/' in k or 'src/Theme.zig' in k or 'src/enums.zig' in k):
        return 'dvui: layout + widget bookkeeping'
    if ('math' in k or 'log10' in k or 'pow' in k or 'sincos' in k or 'rem_pio2' in k
            or '/sin.zig' in k or '/exp.zig' in k or '/log.zig' in k):
        return 'std: math (plot ticks, geometry)'
    if 'unicode.zig' in k: return 'std: unicode decode'
    if '/sort.zig' in k: return 'std: sorting'
    if 'glibc' in k or 'rtld' in k or 'libc.so' in k or 'libm.so' in k or '.zvm' in k or '<zig>' in k:
        return 'runtime / std other'
    if k.startswith('src/'): return 'dvui: other'
    return 'other'


def main():
    runs = {n: annotate(n) for n in ALL}
    keys = set()
    for n in FIT:
        keys |= set(runs[n])

    per_total = fit(FIT, [sum(runs[n].values()) for n in FIT])[0]
    setup_total = sum(runs[2].values()) - 2 * per_total

    rows, buckets = [], collections.defaultdict(lambda: [0.0, 0.0])
    for k in keys:
        slope = fit(FIT, [runs[n][k] for n in FIT])[0]
        setup = runs[2][k] - 2 * slope
        rows.append((k, slope, setup, [runs[n][k] for n in FIT]))
        if slope < 2000 and setup < 2000:
            buckets['long tail (<2k each)'][0] += slope
            buckets['long tail (<2k each)'][1] += setup
            continue
        b = buckets[bucket(k)]
        b[0] += slope
        b[1] += setup

    tsv = os.path.join(DATA, 'dvui-callgrind-per-function.tsv')
    with open(tsv, 'w') as f:
        f.write('# dvui callgrind profile, per-function retired instructions\n')
        f.write('# per_frame_ir = least-squares slope over the 11/21/111/311-frame runs\n')
        f.write('# setup_ir     = ir_2 - 2 * per_frame_ir (one-time cost, anchored at frame 2)\n')
        f.write('function\tper_frame_ir\tsetup_ir\tir_11\tir_21\tir_111\tir_311\n')
        for k, s, b, ys in sorted(rows, key=lambda r: r[0]):
            f.write(f'{k}\t{s:.1f}\t{b:.1f}\t{ys[0]}\t{ys[1]}\t{ys[2]}\t{ys[3]}\n')

    out = os.path.join(DATA, 'dvui-callgrind-buckets.json')
    json.dump({'per_frame': per_total, 'setup': setup_total, 'buckets': buckets},
              open(out, 'w'), indent=1)

    print(f'per frame {per_total:,.0f}   setup {setup_total:,.0f}   functions {len(rows)}')
    for name, (s, b) in sorted(buckets.items(), key=lambda kv: -kv[1][0]):
        print(f'  {name:42} {s:>12,.0f} {b:>12,.0f}')


if __name__ == '__main__':
    sys.exit(main())
