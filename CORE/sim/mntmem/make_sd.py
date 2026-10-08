#!/usr/bin/env python3
"""
SD card image for the test of remembering the mounted images (see run.sh): MBR with one FAT32 partition
(1 sector per cluster, contiguous files) that contains

    /ATARIST/STMOUNT                         the file that remembers the images (see the variants)
    /ATARIST/GAMES/DISK1.ST                  5000 bytes
    /ATARIST/TOS/TOS104.IMG                  7000 bytes
    /My Long Directory Name/Some Long Disk Image Name.st   3000 bytes (long file names)
    /ATARIST/BAD.ST                          100 bytes (the test's LOAD_IMAGE stub refuses it)

Variants for STMOUNT: zero (1536 x 0x00), ff (1536 x 0xFF), short (1535 bytes), none (no file).

Usage: make_sd.py <image> <variant>
"""

import struct
import sys

SECTOR = 512
PART_START = 2048
RESERVED = 32
DATA_CLUSTERS = 200


def short_name(name):
    if "." in name:
        base, ext = name.rsplit(".", 1)
    else:
        base, ext = name, ""
    return (base.upper()[:8].ljust(8) + ext.upper()[:3].ljust(3)).encode()


def lfn_checksum(sn):
    s = 0
    for c in sn:
        s = (((s & 1) << 7) + (s >> 1) + c) & 0xFF
    return s


def entries(name, sn, attr, cluster, size):
    """directory entries (LFN entries first, if the name is not 8.3) for one file or directory"""
    out = []
    if name.upper() != name or len(name.split(".")[0]) > 8 or " " in name:
        chk = lfn_checksum(sn)
        units = [ord(c) for c in name] + [0]
        while len(units) % 13:
            units.append(0xFFFF)
        parts = [units[i:i + 13] for i in range(0, len(units), 13)]
        for n in range(len(parts), 0, -1):
            p = parts[n - 1]
            e = bytearray(32)
            e[0] = n | (0x40 if n == len(parts) else 0)
            struct.pack_into("<5H", e, 1, *p[0:5])
            e[11], e[12], e[13] = 0x0F, 0, chk
            struct.pack_into("<6H", e, 14, *p[5:11])
            struct.pack_into("<2H", e, 28, *p[11:13])
            out.append(e)
    e = bytearray(32)
    e[0:11] = sn
    e[11] = attr
    struct.pack_into("<H", e, 20, cluster >> 16)
    struct.pack_into("<HI", e, 26, cluster & 0xFFFF, size)
    out.append(e)
    return out


def main():
    out, variant = sys.argv[1], sys.argv[2]
    fat_sectors = (4 * (DATA_CLUSTERS + 2) + SECTOR - 1) // SECTOR
    part_sectors = RESERVED + 2 * fat_sectors + DATA_CLUSTERS
    img = bytearray((PART_START + part_sectors) * SECTOR)

    mbr = bytearray(SECTOR)
    struct.pack_into("<B3sB3sII", mbr, 446, 0x00, b"\x00\x02\x00", 0x0C, b"\xfe\xff\xff", PART_START, part_sectors)
    mbr[510:512] = b"\x55\xaa"
    img[0:SECTOR] = mbr

    b = bytearray(SECTOR)
    b[0:3] = b"\xeb\x58\x90"
    b[3:11] = b"MSWIN4.1"
    struct.pack_into("<HBHBHHBHHHII", b, 11, SECTOR, 1, RESERVED, 2, 0, 0, 0xF8, 0, 63, 255, PART_START, part_sectors)
    struct.pack_into("<IHHIHH", b, 36, fat_sectors, 0, 0, 2, 1, 6)
    struct.pack_into("<BBBI11s8s", b, 64, 0x80, 0, 0x29, 0x12345678, b"MNTMEM     ", b"FAT32   ")
    b[510:512] = b"\x55\xaa"
    p0 = PART_START * SECTOR
    img[p0:p0 + SECTOR] = b
    img[p0 + 6 * SECTOR:p0 + 7 * SECTOR] = b
    fsinfo = bytearray(SECTOR)
    struct.pack_into("<I", fsinfo, 0, 0x41615252)
    struct.pack_into("<III", fsinfo, 484, 0x61417272, 0xFFFFFFFF, 0xFFFFFFFF)
    fsinfo[510:512] = b"\x55\xaa"
    img[p0 + SECTOR:p0 + 2 * SECTOR] = fsinfo

    fat = [0] * (DATA_CLUSTERS + 2)
    fat[0], fat[1] = 0x0FFFFFF8, 0x0FFFFFFF
    data0 = p0 + (RESERVED + 2 * fat_sectors) * SECTOR
    nxt = [2]

    def alloc(nbytes):
        n = max(1, (nbytes + SECTOR - 1) // SECTOR)
        first = nxt[0]
        for c in range(first, first + n - 1):
            fat[c] = c + 1
        fat[first + n - 1] = 0x0FFFFFFF
        nxt[0] += n
        return first

    def off(c):
        return data0 + (c - 2) * SECTOR

    def write_dir(cluster, ents):
        o = off(cluster)
        data = b"".join(ents)
        assert len(data) <= SECTOR
        img[o:o + len(data)] = data

    def add_file(nbytes, fill):
        c = alloc(nbytes)
        o = off(c)
        img[o:o + nbytes] = bytes([fill]) * nbytes
        return c

    root = alloc(SECTOR)
    atarist = alloc(SECTOR)
    games = alloc(SECTOR)
    tos = alloc(SECTOR)
    longdir = alloc(SECTOR)

    def dots(me, parent):
        return entries(".", b".          ", 0x10, me, 0) + entries("..", b"..         ", 0x10, parent, 0)

    root_ents = entries("ATARIST", short_name("ATARIST"), 0x10, atarist, 0)
    root_ents += entries("My Long Directory Name", b"MYLONG~1   ", 0x10, longdir, 0)
    write_dir(root, root_ents)

    at_ents = dots(atarist, 0)
    at_ents += entries("GAMES", short_name("GAMES"), 0x10, games, 0)
    at_ents += entries("TOS", short_name("TOS"), 0x10, tos, 0)
    at_ents += entries("BAD.ST", short_name("BAD.ST"), 0x20, add_file(100, 0x33), 100)
    sizes = {"zero": 1536, "ff": 1536, "short": 1535}
    if variant in sizes:
        fill = 0xFF if variant == "ff" else 0x00
        at_ents += entries("STMOUNT", short_name("STMOUNT"), 0x20, add_file(sizes[variant], fill), sizes[variant])
    write_dir(atarist, at_ents)

    write_dir(games, dots(games, atarist) + entries("DISK1.ST", short_name("DISK1.ST"), 0x20,
                                                     add_file(5000, 0x11), 5000))
    write_dir(tos, dots(tos, atarist) + entries("TOS104.IMG", short_name("TOS104.IMG"), 0x20,
                                                 add_file(7000, 0x22), 7000))
    write_dir(longdir, dots(longdir, 0) + entries("Some Long Disk Image Name.st", b"SOMELO~1ST ", 0x20,
                                                   add_file(3000, 0x44), 3000))

    fat_bytes = struct.pack("<%dI" % len(fat), *fat)
    for k in range(2):
        o = p0 + (RESERVED + k * fat_sectors) * SECTOR
        img[o:o + len(fat_bytes)] = fat_bytes

    with open(out, "wb") as fh:
        fh.write(img)


if __name__ == "__main__":
    main()
