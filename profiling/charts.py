#!/usr/bin/env python3
"""Draw the two charts in charts/ from data/dvui-callgrind-buckets.json.

    python3 profiling/charts.py            # after profiling/analyze.py

Every SVG starts with an opaque white rect: a file leaves this machine for a
tracker or a discussion, where a transparent one draws dark text on GitHub's
dark surface.
"""

import json
import os

HERE = os.path.dirname(os.path.abspath(__file__))
DATA = os.path.join(HERE, 'data')
OUT = os.path.join(HERE, 'charts')

d = json.load(open(os.path.join(DATA, 'dvui-callgrind-buckets.json')))
buckets = d['buckets']
PER, SETUP = d['per_frame'], d['setup']

FT, DVUI, SYS = '#cf222e', '#0969da', '#8c959f'


def color(name):
    if name.startswith('freetype'): return FT
    if name.startswith('dvui'): return DVUI
    return SYS


def esc(s):
    return s.replace('&', '&amp;').replace('<', '&lt;').replace('>', '&gt;')


def wrap(text, width_chars):
    words, lines, cur = text.split(' '), [], ''
    for w in words:
        if len(cur) + len(w) + 1 > width_chars and cur:
            lines.append(cur)
            cur = w
        else:
            cur = f'{cur} {w}' if cur else w
    if cur:
        lines.append(cur)
    return lines


def chart(path, title, subtitle, total, bars, footnote):
    bar_h, gap, top = 30, 14, 78
    x0, x1 = 430, 730
    width = 900
    note = wrap(footnote, 118)
    height = top + len(bars) * (bar_h + gap) + 40 + 18 * len(note) + 18
    vmax = max(v for _, v in bars)
    out = [f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {width} {height}" width="{width}" height="{height}" '
           'font-family="system-ui,-apple-system,Segoe UI,Helvetica,Arial,sans-serif">',
           f'<rect x="0" y="0" width="{width}" height="{height}" fill="#ffffff"/>',
           f'<text x="20" y="26" font-size="15" font-weight="600" fill="#1f2328">{esc(title)}</text>',
           f'<text x="20" y="44" font-size="11" fill="#57606a">{subtitle}</text>']
    for i, (label, val) in enumerate(bars):
        y = top + i * (bar_h + gap)
        w = max(1.5, (val / vmax) * (x1 - x0))
        pct = val / total * 100
        out.append(f'<text x="{x0 - 10}" y="{y + 20}" font-size="12" fill="#1f2328" text-anchor="end">{esc(label)}</text>')
        out.append(f'<rect x="{x0}" y="{y}" width="{w:.1f}" height="{bar_h}" fill="{color(label)}" rx="2"/>')
        out.append(f'<text x="{x0 + w + 8:.1f}" y="{y + 20}" font-size="12" font-weight="600" fill="#1f2328">'
                   f'{val / 1e6:.2f}M  {pct:.0f}%</text>')
    ly = top + len(bars) * (bar_h + gap) + 20
    for i, (c, text) in enumerate([(FT, 'freetype'), (DVUI, 'dvui'), (SYS, 'std, memory, allocator, other')]):
        x = 430 + i * 130
        out.append(f'<rect x="{x}" y="{ly - 11}" width="11" height="11" fill="{c}" rx="2"/>')
        out.append(f'<text x="{x + 17}" y="{ly}" font-size="11" fill="#1f2328">{text}</text>')
    for i, line in enumerate(note):
        out.append(f'<text x="20" y="{ly + 24 + 15 * i}" font-size="11" fill="#57606a">{esc(line)}</text>')
    out.append('</svg>')
    open(path, 'w').write('\n'.join(out) + '\n')


def bars_for(idx, floor):
    picked, rest = [], 0.0
    for name, vals in buckets.items():
        if vals[idx] >= floor:
            picked.append((name, vals[idx]))
        elif vals[idx] > 0:
            rest += vals[idx]
    picked.sort(key=lambda b: -b[1])
    if rest >= 1000:
        picked.append((f'long tail (each < {floor / 1e6:.2f}M)', rest))
    return picked


chart(os.path.join(OUT, 'dvui-setup-instructions.svg'),
      'dvui one-time setup: 131.4M instructions',
      'paid once per process, then amortized &#183; callgrind over the headless demo bench, freetype 2.14.1, ReleaseFast',
      SETUP,
      bars_for(1, 1_000_000),
      'Each glyph the demo shows is hinted, outlined and rasterized once; after that the atlas is reused. '
      'Measured as the first two frames minus two steady frames; the least-squares intercept gives the same within 1.5%.')

chart(os.path.join(OUT, 'dvui-per-frame-instructions.svg'),
      'dvui per-frame: 31.28M instructions',
      'steady state, setup excluded &#183; callgrind over the headless demo bench, freetype 2.14.1, ReleaseFast',
      PER,
      bars_for(0, 100_000),
      'Least-squares slope over 11, 21, 111 and 311 frames; every pair of runs agrees within 0.01%. '
      'Groups follow the source tree, not call depth: a callee counts in the group that owns it.')

print('charts written to', OUT)
