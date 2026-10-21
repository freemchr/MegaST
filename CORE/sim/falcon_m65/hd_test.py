#!/usr/bin/env python3
"""IDE hard disk test image for the falcon_m65 test bench.

    python3 hd_test.py make hd.img     16 MB, MBR, one FAT16 partition with \\AUTO\\WRTEST.PRG
    python3 hd_test.py check hd.img.out  is C:\\OUT.TXT there with the expected text?

Without a floppy EmuTOS boots from C: and runs WRTEST.PRG (floppy_test.py, here writing
C:\\OUT.TXT), so a boot reads the program over IDE and writes a file back to the disk.
"""
import struct, sys
from floppy_test import wrtest_prg, TEXT

PART0 = 1                               # first sector of the partition
SECTORS = 32768                         # partition size (16 MB)
SPC, RESERVED, NFATS, ROOT_ENTRIES, FAT_SECS = 4, 1, 2, 512, 32
ROOT_SECS = ROOT_ENTRIES * 32 // 512    # 32
DATA0 = RESERVED + NFATS * FAT_SECS + ROOT_SECS   # first data sector in the partition


def make(path):
    img = bytearray((PART0 + SECTORS) * 512)
    mbr = bytearray(512)                # one partition, type $04 (FAT16 < 32 MB)
    mbr[446:462] = struct.pack('<B3sB3sII', 0x00, b'\0\x02\0', 0x04, b'\xfe\xff\xff', PART0, SECTORS)
    mbr[510:512] = b'\x55\xAA'
    img[0:512] = mbr
    p = PART0 * 512
    bs = bytearray(512)
    bs[0:3] = b'\xEB\x3C\x90'
    bs[3:11] = b'MEGAST  '
    struct.pack_into('<HBHBHHBHHHII', bs, 11, 512, SPC, RESERVED, NFATS, ROOT_ENTRIES, SECTORS, 0xF8,
                     FAT_SECS, 32, 64, PART0, 0)
    bs[36:39] = b'\x80\x00\x29'
    bs[39:43] = b'\x12\x34\x56\x78'
    bs[43:54] = b'MEGAST     '
    bs[54:62] = b'FAT16   '
    bs[510:512] = b'\x55\xAA'
    img[p:p + 512] = bs
    fat = [0xFFF8, 0xFFFF]
    def alloc(data):
        n = max(1, (len(data) + SPC * 512 - 1) // (SPC * 512))
        first = len(fat)
        for i in range(n):
            fat.append(first + i + 1 if i < n - 1 else 0xFFFF)
        for i in range(n):
            s = DATA0 + (first + i - 2) * SPC
            chunk = data[i * SPC * 512:(i + 1) * SPC * 512]
            img[p + s * 512:p + s * 512 + len(chunk)] = chunk
        return first
    def entry(name, ext, attr, clus, size):
        return name.ljust(8).encode() + ext.ljust(3).encode() + bytes([attr]) + bytes(10) + \
            struct.pack('<HHHI', 0, 0x5994, clus, size)
    prg = wrtest_prg(b"C")
    auto = bytearray(SPC * 512)
    auto_clus = alloc(auto)
    prg_clus = alloc(prg)
    auto[0:32] = entry('.', '', 0x10, auto_clus, 0)
    auto[32:64] = entry('..', '', 0x10, 0, 0)
    auto[64:96] = entry('WRTEST', 'PRG', 0x20, prg_clus, len(prg))
    s = DATA0 + (auto_clus - 2) * SPC
    img[p + s * 512:p + s * 512 + len(auto)] = auto
    root = bytearray(ROOT_SECS * 512)
    root[0:32] = entry('AUTO', '', 0x10, auto_clus, 0)
    fb = b''.join(struct.pack('<H', v) for v in fat)
    for f in range(NFATS):
        o = p + (RESERVED + f * FAT_SECS) * 512
        img[o:o + len(fb)] = fb
    o = p + (RESERVED + NFATS * FAT_SECS) * 512
    img[o:o + len(root)] = root
    open(path, 'wb').write(img)
    print(f"{path}: 16 MB FAT16, \\AUTO\\WRTEST.PRG ({len(prg)} bytes)")


def check(path):
    img = open(path, 'rb').read()
    p = PART0 * 512
    fat = img[p + RESERVED * 512:p + (RESERVED + FAT_SECS) * 512]
    o = p + (RESERVED + NFATS * FAT_SECS) * 512
    for i in range(ROOT_ENTRIES):
        e = img[o + 32 * i:o + 32 * i + 32]
        if e[0] in (0, 0xE5): continue
        name = e[0:8].decode(errors='replace').strip() + '.' + e[8:11].decode(errors='replace').strip()
        clus, size = struct.unpack_from('<HI', e, 26)
        if name == 'OUT.TXT':
            data = b''
            while 2 <= clus < 0xFFF0 and len(data) < size:
                s = DATA0 + (clus - 2) * SPC
                data += img[p + s * 512:p + (s + SPC) * 512]
                clus = struct.unpack_from('<H', fat, 2 * clus)[0]
            data = data[:size]
            ok = data == TEXT
            print(f"C:\\OUT.TXT found, {size} bytes: {data!r} -> {'PASS' if ok else 'FAIL'}")
            return 0 if ok else 1
    print("C:\\OUT.TXT not found -> FAIL")
    return 1


if __name__ == '__main__':
    if len(sys.argv) != 3 or sys.argv[1] not in ('make', 'check'):
        sys.exit(__doc__)
    sys.exit(make(sys.argv[2]) if sys.argv[1] == 'make' else check(sys.argv[2]))
