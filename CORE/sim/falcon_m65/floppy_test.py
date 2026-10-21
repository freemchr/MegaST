#!/usr/bin/env python3
"""Floppy test image for the falcon_m65 test bench.

    python3 floppy_test.py make disk.st     720 KB FAT12 disk with \\AUTO\\WRTEST.PRG
    python3 floppy_test.py check disk.st.out  is A:\\OUT.TXT there with the expected text?

WRTEST.PRG (68000, hand assembled, PC relative): Fcreate("A:\\OUT.TXT"), Fwrite(TEXT),
Fclose, Pterm0. EmuTOS runs it from the AUTO folder of the boot disk, so a boot reads the
program from the disk and writes a file (data, FAT and directory) back to it.
"""
import struct, sys

TEXT = b"MegaST Falcon floppy write test\r\n"
SPT, HEADS, TRACKS = 9, 2, 80
SECTORS = SPT * HEADS * TRACKS          # 1440
SPC, RESERVED, NFATS, ROOT_ENTRIES, FAT_SECS = 2, 1, 2, 112, 5
ROOT_SECS = ROOT_ENTRIES * 32 // 512    # 7
DATA0 = RESERVED + NFATS * FAT_SECS + ROOT_SECS   # first data sector (18)


def wrtest_prg(drive=b"A"):
    fname = drive + b":\\OUT.TXT\0"
    code = bytearray()
    def w(*words):
        for x in words: code.extend(struct.pack('>H', x))
    fixups = []
    w(0x3F3C, 0x0000)                 # move.w #0,-(sp)        attribute
    fixups.append((len(code) + 2, 'fname')); w(0x487A, 0)   # pea fname(pc)
    w(0x3F3C, 0x003C)                 # move.w #$3C,-(sp)      Fcreate
    w(0x4E41)                         # trap #1
    w(0x508F)                         # addq.l #8,sp
    w(0x3E00)                         # move.w d0,d7           handle
    fixups.append((len(code) + 2, 'text')); w(0x487A, 0)    # pea text(pc)
    w(0x2F3C, 0x0000, len(TEXT))      # move.l #len,-(sp)
    w(0x3F07)                         # move.w d7,-(sp)
    w(0x3F3C, 0x0040)                 # move.w #$40,-(sp)      Fwrite
    w(0x4E41)                         # trap #1
    w(0x4FEF, 0x000C)                 # lea 12(sp),sp
    w(0x3F07)                         # move.w d7,-(sp)
    w(0x3F3C, 0x003E)                 # move.w #$3E,-(sp)      Fclose
    w(0x4E41)                         # trap #1
    w(0x588F)                         # addq.l #4,sp
    w(0x4267)                         # clr.w -(sp)            Pterm0
    w(0x4E41)                         # trap #1
    labels = {'fname': len(code)}
    code.extend(fname)
    labels['text'] = len(code)
    code.extend(TEXT)
    if len(code) & 1: code.append(0)
    for off, lab in fixups:           # displacement from the extension word
        struct.pack_into('>h', code, off, labels[lab] - off)
    hdr = struct.pack('>HIIIIIIH', 0x601A, len(code), 0, 0, 0, 0, 0, 0)
    return hdr + bytes(code) + b'\0\0\0\0'   # no relocations


def make(path):
    img = bytearray(SECTORS * 512)
    bs = bytearray(512)
    bs[0:2] = b'\x60\x38'             # bra (not executable: checksum not $1234)
    bs[2:8] = b'MegaST'
    bs[8:11] = b'\x12\x34\x56'        # serial
    struct.pack_into('<HBHBHHBHHH', bs, 11, 512, SPC, RESERVED, NFATS, ROOT_ENTRIES, SECTORS, 0xF9, FAT_SECS, SPT, HEADS)
    img[0:512] = bs
    fat = [0xFF9, 0xFFF]              # media, reserved
    root = bytearray(ROOT_SECS * 512)
    def alloc(data):
        n = max(1, (len(data) + SPC * 512 - 1) // (SPC * 512))
        first = len(fat)
        for i in range(n):
            fat.append(first + i + 1 if i < n - 1 else 0xFFF)
        for i in range(n):
            s = DATA0 + (first + i - 2) * SPC
            chunk = data[i * SPC * 512:(i + 1) * SPC * 512]
            img[s * 512:s * 512 + len(chunk)] = chunk
        return first
    def entry(name, ext, attr, clus, size):
        return name.ljust(8).encode() + ext.ljust(3).encode() + bytes([attr]) + bytes(10) + \
            struct.pack('<HHHI', 0, 0x5994, clus, size)   # date 2024-12-20
    prg = wrtest_prg()
    auto = bytearray(SPC * 512)
    auto_clus = alloc(auto)           # placeholder, filled below
    prg_clus = alloc(prg)
    auto[0:32] = entry('.', '', 0x10, auto_clus, 0)
    auto[32:64] = entry('..', '', 0x10, 0, 0)
    auto[64:96] = entry('WRTEST', 'PRG', 0x20, prg_clus, len(prg))
    s = DATA0 + (auto_clus - 2) * SPC
    img[s * 512:s * 512 + len(auto)] = auto
    root[0:32] = entry('AUTO', '', 0x10, auto_clus, 0)
    for f in range(NFATS):            # FAT12
        fb = bytearray(FAT_SECS * 512)
        for i, v in enumerate(fat):
            o = i * 3 // 2
            if i & 1: fb[o] = (fb[o] & 0x0F) | ((v << 4) & 0xF0); fb[o + 1] = v >> 4
            else:     fb[o] = v & 0xFF; fb[o + 1] = (fb[o + 1] & 0xF0) | (v >> 8)
        o = (RESERVED + f * FAT_SECS) * 512
        img[o:o + len(fb)] = fb
    o = (RESERVED + NFATS * FAT_SECS) * 512
    img[o:o + len(root)] = root
    open(path, 'wb').write(img)
    print(f"{path}: 720 KB, \\AUTO\\WRTEST.PRG ({len(prg)} bytes)")


def check(path):
    img = open(path, 'rb').read()
    fat = img[RESERVED * 512:(RESERVED + FAT_SECS) * 512]
    def nxt(c):
        o = c * 3 // 2
        v = fat[o] | fat[o + 1] << 8
        return v >> 4 if c & 1 else v & 0xFFF
    o = (RESERVED + NFATS * FAT_SECS) * 512
    for i in range(ROOT_ENTRIES):
        e = img[o + 32 * i:o + 32 * i + 32]
        if e[0] in (0, 0xE5): continue
        name = e[0:8].decode(errors='replace').strip() + '.' + e[8:11].decode(errors='replace').strip()
        clus, size = struct.unpack_from('<HI', e, 26)
        if name == 'OUT.TXT':
            data = b''
            while 2 <= clus < 0xFF0 and len(data) < size:
                s = DATA0 + (clus - 2) * SPC
                data += img[s * 512:(s + SPC) * 512]
                clus = nxt(clus)
            data = data[:size]
            ok = data == TEXT
            print(f"A:\\OUT.TXT found, {size} bytes: {data!r} -> {'PASS' if ok else 'FAIL'}")
            return 0 if ok else 1
    print("A:\\OUT.TXT not found -> FAIL")
    return 1


if __name__ == '__main__':
    if len(sys.argv) != 3 or sys.argv[1] not in ('make', 'check'):
        sys.exit(__doc__)
    sys.exit(make(sys.argv[2]) if sys.argv[1] == 'make' else check(sys.argv[2]))
