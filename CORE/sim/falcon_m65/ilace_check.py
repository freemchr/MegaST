#!/usr/bin/env python3
# Issue #38: checks the frames of tests/ilace.s (one per field, --frame-every 1) as the HDMI scaler weaves
# them: ascal puts field N one line down when ilace_fl was 0 in field N-1. Prints per field the first and
# last visible line with picture, then whether each woven pair gives the 400 picture rows in order.
#    [ROWS=480] ./ilace_check.py OUT.log OUT [first frame] [count]      (ROWS: picture lines, default 400)
# MEGA65 port done by Chris Freeman in 2026, licensed under GPL v3
import re, sys, os
log, d = sys.argv[1], sys.argv[2]
first = int(sys.argv[3]) if len(sys.argv) > 3 else 0
count = int(sys.argv[4]) if len(sys.argv) > 4 else 8
fl = {}
for l in open(log):
    m = re.search(r'frame (\d+): (\d+)x(\d+) fl (\d)', l)
    if m: fl[int(m.group(1))] = (int(m.group(2)), int(m.group(3)), int(m.group(4)))
names = {}
def nm(c):
    if c not in names: names[c] = len(names)
    return names[c]
shown = 0
for n in sorted(fl):
    if n < first or shown >= count: continue
    p = os.path.join(d, 'frame_%04d.ppm' % n)
    if not os.path.exists(p): continue
    b = open(p, 'rb').read()
    parts = b.split(b'\n', 3)
    w, h = map(int, parts[1].split())
    px = parts[3]
    x = w // 2
    col = [px[(y * w + x) * 3:(y * w + x) * 3 + 3] for y in range(h)]
    border = col[0]
    fr = next((y for y in range(h) if col[y] != border), -1)
    last = max((y for y in range(h) if col[y] != border), default=-1)
    seq = ' '.join('%d' % nm(c.hex()) for c in col[fr:fr + 10]) if fr >= 0 else ''
    print('frame %d: %dx%d fl %d  first picture DE row %d, last %d, colours %s' % (n, w, h, fl[n][2], fr, last, seq))
    shown += 1
print('colour ids:', {v: k for k, v in names.items()})

# Weave as ascal does: field N goes one line down when fl was 0 in field N-1. Picture row of a line =
# from its colour (1 + row mod 15); check consecutive picture lines of the woven frame step by +1 mod 15.
pal = {}
def frame_cols(n):
    b = open(os.path.join(d, 'frame_%04d.ppm' % n), 'rb').read().split(b'\n', 3)
    w, h = map(int, b[1].split()); px = b[3]; x = w // 2
    return [px[(y * w + x) * 3:(y * w + x) * 3 + 3] for y in range(h)]
ns = [n for n in sorted(fl) if n >= first and os.path.exists(os.path.join(d, 'frame_%04d.ppm' % n))][:count]
bad_total = 0
for a, b in zip(ns, ns[1:]):
    if b != a + 1: continue
    ca, cb = frame_cols(a), frame_cols(b)
    da = 1 if fl[a - 1][2] == 0 else 0 if (a - 1) in fl else None
    db = 1 if fl[a][2] == 0 else 0
    if da is None or da == db: continue
    h = max(len(ca), len(cb)); wv = [None] * (2 * h + 2)
    for k, c in enumerate(ca): wv[2 * k + da] = c
    for k, c in enumerate(cb): wv[2 * k + db] = c
    border = ca[0]
    pic = [c for c in wv if c is not None]
    # colour of picture row r is palette entry 1 + r mod 15: map by the order in the even-row field
    idx = [i for i, c in enumerate(pic) if c != border]
    seq = [pic[i] for i in range(idx[0], idx[-1] + 1)]
    # EmuTOS palette entries 1..15 (colour c = 1 + row mod 15)
    P = ['ff0000','00ff00','ffff00','0000ff','ff00ff','00ffff','bababa','8a8a8a','aa0000','00aa00','aaaa00','0000aa','aa00aa','00aaaa','000000']
    order = {bytes.fromhex(h): i for i, h in enumerate(P)}
    bad = sum(1 for i in range(1, len(seq)) if seq[i] not in order or seq[i - 1] not in order or
              (order[seq[i]] - order[seq[i - 1]]) % 15 != 1)
    if order.get(seq[0]) != 0 or len(seq) != int(os.environ.get("ROWS", "400")): bad += 1
    bad_total += bad
    print('weave of frames %d+%d: %d picture lines, %d out of order' % (a, b, len(seq), bad))
print('WEAVE', 'OK' if bad_total == 0 else 'FAIL')
