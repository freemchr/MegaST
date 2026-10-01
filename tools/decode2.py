#!/usr/bin/env python3
import sys
names = ["up(p1)", "down(p2)", "left(p3)", "right(p4)", "fire(p6)"]
prev = None
for l in open(sys.argv[1]):
    if not l.startswith("J "): continue
    v = int(l.split()[1], 16)
    j1 = v & 0x1F; j2 = (v >> 5) & 0x1F; menu = (v >> 10) & 7
    px = (v >> 16) & 0xFF; py = (v >> 24) & 0xFF
    cnt = [(v >> (32 + 8 * i)) & 0xFF for i in range(5)]
    free = v >> 72
    d = "" if prev is None else " +" + "/".join(str((c - p) & 0xFF) for c, p in zip(cnt, prev))
    prev = cnt
    print("p1 %s p2 %s amiga=%d 1351=%d swap=%d pot1 x=%3d y=%3d edges u/d/l/r/f %s%s clk %06x" % (
        format(j1, "05b"), format(j2, "05b"), menu & 1, (menu >> 1) & 1, (menu >> 2) & 1, px, py,
        "/".join(map(str, cnt)), d, free))
