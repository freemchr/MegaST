#!/usr/bin/env python3
"""Check a hard disk image written by the boot sector of make_boot.py: sectors RECNO ..
RECNO+COUNT-1 must hold the pattern, all other sectors must be unchanged (zero).

Usage: check.py hd.img [count] [recno]
"""
import struct
import sys

img = open(sys.argv[1], "rb").read()
count = int(sys.argv[2]) if len(sys.argv) > 2 else 128
recno = int(sys.argv[3]) if len(sys.argv) > 3 else 16
bad = []
for s in range(len(img) // 512):
    data = img[s * 512:(s + 1) * 512]
    k = s - recno
    if 0 <= k < count:
        want = struct.pack(">256H", *[(k * 256 + i) & 0xFFFF for i in range(256)])
    else:
        want = bytes(512)
    if data != want:
        first = struct.unpack(">H", data[:2])[0]
        bad.append((s, "pattern of sector %d" % (recno + first // 256) if first or data[2:4] == b"\0\1" else "zero/other"))
if bad:
    print("FAIL: %d wrong sectors" % len(bad))
    for s, what in bad[:20]:
        print("  sector %d: contains %s" % (s, what))
    sys.exit(1)
print("OK: %d sectors from %d hold the pattern, the rest is unchanged" % (count, recno))
