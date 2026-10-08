#!/usr/bin/env python3
"""Make a 720 KB floppy image (.st) with an executable boot sector that writes a test pattern to
the ACSI hard disk 0 with one BIOS Rwabs call (physical mode) and then shows the result:
green background = Rwabs returned 0, red = error.

The pattern: COUNT sectors from BUF, word i (0 .. COUNT*256-1) = i (big endian), written to
sector RECNO and the following ones. check.py verifies the hard disk image afterwards.

Usage: make_boot.py out.st [count] [recno]
"""
import struct
import sys

BUF = 0x80000            # 512 KB: free RAM in a 1 MB ST


def code(count, recno):
    words = count * 256 - 1
    c = b""
    c += bytes.fromhex("41F9") + struct.pack(">I", BUF)        # lea     BUF,a0
    c += bytes.fromhex("303C") + struct.pack(">H", words)      # move.w  #words,d0
    c += bytes.fromhex("7200")                                 # moveq   #0,d1
    c += bytes.fromhex("30C1")                                 # fill: move.w d1,(a0)+
    c += bytes.fromhex("5241")                                 # addq.w  #1,d1
    c += bytes.fromhex("51C8FFFA")                             # dbra    d0,fill
    c += bytes.fromhex("3F3C0002")                             # move.w  #2,-(sp)      dev: ACSI 0
    c += bytes.fromhex("3F3C") + struct.pack(">H", recno)      # move.w  #recno,-(sp)
    c += bytes.fromhex("3F3C") + struct.pack(">H", count)      # move.w  #count,-(sp)
    c += bytes.fromhex("2F3C") + struct.pack(">I", BUF)        # move.l  #BUF,-(sp)
    c += bytes.fromhex("3F3C0009")                             # move.w  #9,-(sp)      write, physical
    c += bytes.fromhex("3F3C0004")                             # move.w  #4,-(sp)      Rwabs
    c += bytes.fromhex("4E4D")                                 # trap    #13
    c += bytes.fromhex("4FEF000E")                             # lea     14(sp),sp
    c += bytes.fromhex("4A80")                                 # tst.l   d0
    c += bytes.fromhex("6608")                                 # bne.s   fail
    c += bytes.fromhex("31FC00708240")                         # move.w  #$070,$ffff8240.w
    c += bytes.fromhex("6006")                                 # bra.s   hang
    c += bytes.fromhex("31FC07008240")                         # fail: move.w #$700,$ffff8240.w
    c += bytes.fromhex("60FE")                                 # hang: bra.s hang
    return c


def main():
    out = sys.argv[1]
    count = int(sys.argv[2]) if len(sys.argv) > 2 else 128
    recno = int(sys.argv[3]) if len(sys.argv) > 3 else 16
    bs = bytearray(512)
    bs[0:2] = bytes.fromhex("601C")                            # bra.s to $1E
    bs[2:8] = b"MEGAST"
    # BPB: 512 bytes/sector, 2 sectors/cluster, 1 reserved, 2 FATs, 112 dir entries,
    # 1440 sectors, media $F9, 3 sectors/FAT, 9 sectors/track, 2 sides, 0 hidden
    bs[0x0B:0x1E] = struct.pack("<HBHBHHBHHHH", 512, 2, 1, 2, 112, 1440, 0xF9, 3, 9, 2, 0)[:0x13]
    c = code(count, recno)
    bs[0x1E:0x1E + len(c)] = c
    # executable: the sum of all 256 big endian words is $1234
    s = sum(struct.unpack(">256H", bs[:510] + b"\0\0")) & 0xFFFF
    bs[510:512] = struct.pack(">H", (0x1234 - s) & 0xFFFF)
    img = bytearray(737280)
    img[0:512] = bs
    for f in (1, 4):                                           # two FATs: media byte
        img[f * 512:f * 512 + 3] = bytes([0xF9, 0xFF, 0xFF])
    open(out, "wb").write(img)


if __name__ == "__main__":
    main()
