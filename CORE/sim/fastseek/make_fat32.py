#!/usr/bin/env python3
"""
Test SD card image for the fast seek test (see run.sh): MBR with one FAT32 partition that contains
two files, HD0.IMG and HD1.IMG, whose cluster chains are interleaved and shuffled (fragmented like
on a well used SD card, with backward jumps). Every byte of a file is (position * 7 + position / 512
+ file number) & 0xFF.

Usage: make_fat32.py <image> <sectors per cluster> <file size in bytes>
"""

import random
import struct
import sys

SECTOR = 512
PART_START = 2048


def content(pos, fileno):
    return (pos * 7 + pos // SECTOR + fileno) & 0xFF


def main():
    out, spc, fsize = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
    random.seed(1234)
    csize = spc * SECTOR
    nclus_file = (fsize + csize - 1) // csize
    data_clusters = 2 * nclus_file + 64 + 1             # two files, some free clusters, root dir
    reserved = 32
    fat_sectors = (4 * (data_clusters + 2) + SECTOR - 1) // SECTOR
    part_sectors = reserved + 2 * fat_sectors + data_clusters * spc
    img = bytearray((PART_START + part_sectors) * SECTOR)

    # MBR: one FAT32 (LBA) partition
    mbr = bytearray(SECTOR)
    struct.pack_into("<B3sB3sII", mbr, 446, 0x00, b"\x00\x02\x00", 0x0C, b"\xfe\xff\xff", PART_START, part_sectors)
    mbr[510:512] = b"\x55\xaa"
    img[0:SECTOR] = mbr

    # FAT32 boot sector (BPB)
    b = bytearray(SECTOR)
    b[0:3] = b"\xeb\x58\x90"
    b[3:11] = b"MSWIN4.1"
    struct.pack_into("<HBHBHHBHHHII", b, 11, SECTOR, spc, reserved, 2, 0, 0, 0xF8, 0, 63, 255, PART_START, part_sectors)
    struct.pack_into("<IHHIHH", b, 36, fat_sectors, 0, 0, 2, 1, 6)
    struct.pack_into("<BBBI11s8s", b, 64, 0x80, 0, 0x29, 0x12345678, b"FASTSEEK   ", b"FAT32   ")
    b[510:512] = b"\x55\xaa"
    p0 = PART_START * SECTOR
    img[p0:p0 + SECTOR] = b
    img[p0 + 6 * SECTOR:p0 + 7 * SECTOR] = b            # backup boot sector
    fsinfo = bytearray(SECTOR)
    struct.pack_into("<I", fsinfo, 0, 0x41615252)
    struct.pack_into("<III", fsinfo, 484, 0x61417272, 0xFFFFFFFF, 0xFFFFFFFF)
    fsinfo[510:512] = b"\x55\xaa"
    img[p0 + SECTOR:p0 + 2 * SECTOR] = fsinfo

    fat = [0] * (data_clusters + 2)
    fat[0], fat[1] = 0x0FFFFFF8, 0x0FFFFFFF
    fat[2] = 0x0FFFFFFF                                  # root directory

    # fragmented allocation: chunks of 1..7 clusters, alternately for both files, chunk order shuffled
    free = list(range(3, data_clusters + 2))
    chunks = []
    i = 0
    while i < len(free):
        n = random.randint(1, 7)
        chunks.append(free[i:i + n])
        i += n
    random.shuffle(chunks)
    chains = [[], []]
    f = 0
    for ch in chunks:
        if len(chains[f]) >= nclus_file:
            f ^= 1
        chains[f].extend(ch[:nclus_file - len(chains[f])])
        f ^= 1
        if len(chains[0]) >= nclus_file and len(chains[1]) >= nclus_file:
            break
    assert len(chains[0]) == nclus_file and len(chains[1]) == nclus_file
    for chain in chains:
        for a, nxt in zip(chain, chain[1:]):
            fat[a] = nxt
        fat[chain[-1]] = 0x0FFFFFFF

    fat_bytes = struct.pack("<%dI" % len(fat), *fat)
    for k in range(2):
        o = p0 + (reserved + k * fat_sectors) * SECTOR
        img[o:o + len(fat_bytes)] = fat_bytes

    data0 = p0 + (reserved + 2 * fat_sectors) * SECTOR

    def clus_off(c):
        return data0 + (c - 2) * csize

    # root directory: the two files
    root = clus_off(2)
    for fileno, chain in enumerate(chains):
        e = bytearray(32)
        e[0:11] = b"HD%d     IMG" % fileno
        e[11] = 0x20
        struct.pack_into("<HH", e, 20, chain[0] >> 16, 0)
        struct.pack_into("<HI", e, 26, chain[0] & 0xFFFF, fsize)
        img[root + 32 * fileno:root + 32 * fileno + 32] = e

    # file contents
    for fileno, chain in enumerate(chains):
        for n, c in enumerate(chain):
            o = clus_off(c)
            for k in range(csize):
                pos = n * csize + k
                if pos < fsize:
                    img[o + k] = content(pos, fileno)

    with open(out, "wb") as fh:
        fh.write(img)
    backward = sum(1 for a, b2 in zip(chains[0], chains[0][1:]) if b2 < a)
    print("%s: %d sectors/cluster, 2 files of %d bytes, %d clusters each, %d backward jumps in HD0.IMG"
          % (out, spc, fsize, nclus_file, backward))


if __name__ == "__main__":
    main()
