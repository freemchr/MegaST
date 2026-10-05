#!/usr/bin/env python3
# Decode tools/probe3.tcl output: pressed ST matrix keys (column,row), the last 4 bytes the CPU read
# from the keyboard ACIA (oldest first) and the press counters
import sys
for l in open(sys.argv[1]):
    if not l.startswith("K "): continue
    v = int(l.split()[1], 16)
    keys = ["%d,%d" % (k // 8, k % 8) for k in range(120) if not (v >> k) & 1]
    b = (v >> 120) & 0xFFFFFFFF
    acia = " ".join("%02x" % ((b >> s) & 0xFF) for s in (24, 16, 8, 0))
    print("st keys %-16s acia %s  presses: m65 A %3d  S %3d  st A %3d" % (
        " ".join(keys) or "-", acia, (v >> 152) & 0xFF, (v >> 160) & 0xFF, (v >> 168) & 0xFF))
