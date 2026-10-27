#!/usr/bin/env python3
"""
Create a blank, formatted IDE hard disk image (.img) for the Falcon030 of MegaST.

The image has a PC partition table (MBR) with up to four primary FAT16 partitions in the
"TOS & Windows compatible" format: 1024-byte logical sectors and 2 sectors per cluster, so
that the GEMDOS of Atari's TOS, EmuTOS and a PC (Windows, Linux, mtools) can all use them.
Each partition is at most 32 MB (C:, D:, E:, F: in this order).

* EmuTOS (atarist/tosfalc.img) has its own IDE driver: it mounts the partitions as they are.
* Atari's TOS 4.0x has no hard disk driver: it needs an IDE-capable driver that understands
  PC partitions (for example HDDRIVER), installed on the image or run from the AUTO folder
  of a boot floppy.

Usage:
    python3 make_falcon_hd.py falcon.img                # 128 MB, four partitions of 32 MB
    python3 make_falcon_hd.py --size 64 falcon.img      # 64 MB: two partitions
    python3 make_falcon_hd.py --size 32 falcon.img      # one partition

Copy the image into /atarist on the SD card and choose it in the menu as "Hard disk 0".

Part of MegaST (Atari ST/STe/Falcon030 for MEGA65), done by Chris Freeman in 2026, licensed under GPL v3
"""

import argparse
import random
import struct
import sys

SEC = 512                      # physical sector
LSEC = 1024                    # logical sector of the partitions (TOS: 2 sectors per cluster)
SPC = 2
ROOT_ENTRIES = 512
PART_MAX = 65472               # physical sectors per partition (just under 32 MB)
FIRST = 64                     # first sector of the first partition


def bpb(start, secs, label, serial):
    """the boot sector of one partition (1024 bytes) and the sizes of its areas (logical sectors)"""
    lsecs = secs * SEC // LSEC
    root = ROOT_ENTRIES * 32 // LSEC
    fat = 1
    while True:                # smallest FAT that covers all clusters
        clusters = (lsecs - 1 - 2 * fat - root) // SPC
        if (clusters + 2) * 2 <= fat * LSEC:
            break
        fat += 1
    if not 4085 <= clusters <= 32766:
        raise SystemExit('partition of %d sectors: %d clusters, not FAT16 for TOS' % (secs, clusters))
    b = bytearray(LSEC)
    b[0:3] = b'\xEB\x3C\x90'
    b[3:11] = b'MEGAST  '
    struct.pack_into('<HBHBHHBHHHII', b, 11, LSEC, SPC, 1, 2, ROOT_ENTRIES, lsecs, 0xF8, fat,
                     32, 64, start, 0)
    struct.pack_into('<BBBI', b, 36, 0x80, 0, 0x29, serial)
    b[43:54] = label.ljust(11).encode()
    b[54:62] = b'FAT16   '
    b[510:512] = b'\x55\xAA'
    return b, fat, root, clusters


def make(path, size_mb):
    total = size_mb * 1024 * 1024 // SEC
    n = min(4, (total - FIRST) // PART_MAX + (1 if (total - FIRST) % PART_MAX >= 8192 else 0))
    if n < 1:
        raise SystemExit('at least 8 MB')
    img = bytearray(total * SEC)
    mbr = bytearray(SEC)
    struct.pack_into('<I', mbr, 440, random.getrandbits(32))      # disk signature
    start = FIRST
    info = []
    for i in range(n):
        secs = min(PART_MAX, total - start)
        label = 'DRIVE_' + 'CDEF'[i]
        boot, fat, root, clusters = bpb(start, secs, label, random.getrandbits(32))
        o = start * SEC
        img[o:o + LSEC] = boot
        for f in range(2):                                         # FAT[0] = media, FAT[1] = end
            fo = o + (1 + f * fat) * LSEC
            img[fo:fo + 4] = b'\xF8\xFF\xFF\xFF'
        ro = o + (1 + 2 * fat) * LSEC                              # volume label in the root
        img[ro:ro + 11] = label.ljust(11).encode()
        img[ro + 11] = 0x08
        ptype = 0x04 if secs < 65536 else 0x06                     # FAT16 < 32 MB
        struct.pack_into('<B3sB3sII', mbr, 446 + 16 * i, 0, b'\xFE\xFF\xFF', ptype, b'\xFE\xFF\xFF',
                         start, secs)
        info.append('%s: %d KB, %d clusters of %d bytes' % ('CDEF'[i], secs // 2, clusters, SPC * LSEC))
        start += secs
    mbr[510:512] = b'\x55\xAA'
    img[0:SEC] = mbr
    assert len(img) == total * SEC
    with open(path, 'wb') as f:
        f.write(img)
    print('%s: %d MB IDE hard disk image, %d partition(s)' % (path, size_mb, n))
    for s in info:
        print('  ' + s)


def main():
    ap = argparse.ArgumentParser(description='Blank IDE hard disk image for the MegaST Falcon030')
    ap.add_argument('image')
    ap.add_argument('--size', type=int, default=128, help='size in MB (8..128, default 128)')
    a = ap.parse_args()
    if not 8 <= a.size <= 128:
        sys.exit('--size: 8 to 128 MB (four partitions of at most 32 MB)')
    make(a.image, a.size)


if __name__ == '__main__':
    main()
