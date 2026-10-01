#!/usr/bin/env python3
"""Decode MegaST JTAG probe samples (lines 'S <hex64>') against the ROM listing."""
import bisect, collections, re, sys
lis = open(sys.argv[2], errors="replace").read().split("\n")
syms, code = [], {}
for l in lis:
    for name, addr in re.findall(r"(\S+)\s*:\s*0x([0-9A-F]{4})", l):
        syms.append((int(addr, 16), name))
    m = re.match(r"^\d{6}\s+([0-9A-F]{4})\s+[0-9A-F]{4}(?:\s+[0-9A-F]{4})*\s{2,}(.*)$", l)
    if m:
        code.setdefault(int(m.group(1), 16), m.group(2).strip())
syms.sort(); keys = [a for a, _ in syms]
def where(a):
    i = bisect.bisect_right(keys, a) - 1
    return "%s+%d" % (syms[i][1], a - syms[i][0]) if i >= 0 else "?"
samples = [int(l.split()[1], 16) for l in open(sys.argv[1]) if l.startswith("S ")]
cnts = [s >> 40 for s in samples]
print("samples: %d, clock counter %s" % (len(samples), "running" if len(set(cnts)) > 1 else "STOPPED"))
flags = collections.Counter(((s >> 32) & 0x3F) for s in samples)
print("flags (bit0 dir, 1 valid, 2 wait, 3 ramrom_wait, 4 halt, 5 reset):",
      ", ".join("%02x x%d" % kv for kv in flags.most_common()))
addrs = collections.Counter(s & 0xFFFF for s in samples)
print("addresses (most frequent first):")
for a, c in addrs.most_common(60):
    print("  %04X x%-4d %-28s %s" % (a, c, where(a), code.get(a, "(data access)")))
