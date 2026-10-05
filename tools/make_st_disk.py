#!/usr/bin/env python3
"""
Create a blank, formatted Atari ST floppy disk image (.st) for MegaST (or any ST emulator).

The image has the layout that TOS creates when it formats a disk: an ST boot sector (not
executable), two FAT12 tables and an empty root directory, so it can be used right away as a
data or save disk. Copy it into /atarist on the SD card and mount it in the MegaST menu.

Usage:
    python3 make_st_disk.py blank.st                 # 720 kB, double sided (the default)
    python3 make_st_disk.py --size 360 blank.st      # 360 kB, single sided
    python3 make_st_disk.py --size 800 blank.st      # 800 kB, 10 sectors per track
    python3 make_st_disk.py --size 1440 blank.st     # 1.44 MB high density (Mega STe, TT, Falcon)
    python3 make_st_disk.py --label GAMES blank.st   # with a volume label

Part of MegaST (Atari ST/STe for MEGA65), done by Chris Freeman in 2026, licensed under GPL v3
"""

import argparse
import os
import random
import struct
import sys

# size in kB: (sectors per track, sides, tracks, sectors per cluster, root dir entries, sectors per FAT, media byte)
FORMATS = {
    360:  ( 9, 1, 80, 2, 112, 5, 0xF8),
    720:  ( 9, 2, 80, 2, 112, 5, 0xF9),
    800:  (10, 2, 80, 2, 112, 5, 0xF9),
    1440: (18, 2, 80, 1, 224, 9, 0xF0),
}

SECTOR = 512


def boot_sector(spt, sides, tracks, spc, ndirs, spf, media):
    b = bytearray(SECTOR)
    b[0:2] = b"\x60\x38"                                   # BRA.S (like TOS)
    b[2:8] = b"MegaST"                                     # OEM / filler
    b[8:11] = bytes(random.randrange(256) for _ in range(3))   # serial number: disk change detection
    total = spt * sides * tracks
    # BPB: little endian (like MS-DOS)
    struct.pack_into("<HBHBHHBHHHH", b, 11,
                     SECTOR,       # bytes per sector
                     spc,          # sectors per cluster
                     1,            # reserved sectors (the boot sector)
                     2,            # number of FATs
                     ndirs,        # root directory entries
                     total,        # total sectors
                     media,        # media descriptor
                     spf,          # sectors per FAT
                     spt,          # sectors per track
                     sides,        # number of sides
                     0)            # hidden sectors
    # The boot sector is executable if the big endian word sum is 0x1234: make sure it is not
    s = sum(struct.unpack(">256H", bytes(b))) & 0xFFFF
    if s == 0x1234:
        b[510] ^= 0x01
    return bytes(b)


def make_image(size_kb, label=None):
    spt, sides, tracks, spc, ndirs, spf, media = FORMATS[size_kb]
    img = bytearray(spt * sides * tracks * SECTOR)
    img[0:SECTOR] = boot_sector(spt, sides, tracks, spc, ndirs, spf, media)

    # Two FATs: the first two FAT12 entries hold the media byte, everything else is free
    for f in range(2):
        o = (1 + f * spf) * SECTOR
        img[o:o + 3] = bytes([media, 0xFF, 0xFF])

    # Root directory: optional volume label
    if label:
        name = label.upper().encode("ascii", "replace")[:11].ljust(11, b" ")
        o = (1 + 2 * spf) * SECTOR
        img[o:o + 11] = name
        img[o + 11] = 0x08                               # attribute: volume label
    return bytes(img)


def main():
    p = argparse.ArgumentParser(description="Create a blank, formatted Atari ST floppy disk image (.st)")
    p.add_argument("output", help="image file to create, e.g. blank.st")
    p.add_argument("--size", type=int, default=720, choices=sorted(FORMATS), help="size in kB (default 720)")
    p.add_argument("--label", help="volume label (up to 11 characters)")
    p.add_argument("--force", action="store_true", help="overwrite an existing file")
    a = p.parse_args()

    if os.path.exists(a.output) and not a.force:
        sys.exit(f"{a.output} exists already (use --force to overwrite it)")
    with open(a.output, "wb") as f:
        f.write(make_image(a.size, a.label))
    print(f"{a.output}: {a.size} kB Atari ST floppy disk image")


if __name__ == "__main__":
    main()
