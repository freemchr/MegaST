#!/usr/bin/env python3
# Decodes tools/probe5.tcl: the Falcon's 68030 and DSP state (see the USER2 probe in CORE/vhdl/mega65.vhd)
import sys
prev = None
for l in open(sys.argv[1]):
    if not l.startswith("F "): continue
    v = int(l.split()[1], 16)
    f = lambda lo, n: (v >> lo) & ((1 << n) - 1)
    clk = f(72, 24)
    pf, dev, we = f(96, 32), f(128, 24), f(152, 1)
    pc, r6, r7, lc = f(160, 16), f(176, 16), f(192, 16), f(208, 16)
    txw, ssisr, hsr, isr = f(224, 8), f(232, 8), f(240, 8), f(248, 8)
    d = "" if prev is None else " (+%d)" % ((txw - prev) & 0xFF)
    prev = txw
    print("68030 fetch %08x dev %s %06x | DSP pc %04x r6 %04x r7 %04x lc %04x | TX writes %3d%s SSISR %02x | "
          "host ISR %02x HSR %02x | clk %06x" % (pf, "W" if we else "R", dev, pc, r6, r7, lc, txw, d, ssisr,
                                               isr, hsr, clk))
