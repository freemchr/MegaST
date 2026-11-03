#!/usr/bin/env python3
"""Patch the Falcon EmuTOS of the release (atarist/tosfalc.img) for the slow MEGA65 hard disks on SCSI.

    python3 emutos_scsi_timeout.py tosfalc.img tosfalc_patched.img

EmuTOS (bios/scsi.c, do_scsi_rw) gives a SCSI read or write the timeout
max(SHORT_TIMEOUT, buflen / BYTES_PER_CLOCK) ticks of 5 ms, with SHORT_TIMEOUT = 1 s and
BYTES_PER_CLOCK = 1024: it assumes that the disk transfers at least 200 KB/s. The MEGA65 serves
the hard disk images directly from the SD card (unbuffered virtual drives of the firmware, one
system call per byte), much slower than that, above all for writes. So transfers that take too
long fail with EUNDEV, shown as "Your output device is not receiving data" (installing to or
copying on a SCSI hard disk, loading a large program). IDE is not affected (3 s per block of 16
sectors).

The patch makes the division by 1024 (asr.l #10) a division by 8 (asr.l #3): at least 1.6 KB/s,
320 ms per sector; and the minimum 2000 ticks (10 s) instead of 200 (cmpi.l #200 and
moveq #$37 / not.b, which makes 200, become cmpi.l #2000 and move.w #2000: the value is below
2000 there, so its upper word is 0). Version 1.4 had asr.l #6 (12.8 KB/s) and the 1 s minimum,
too little for some SD cards. The patched instructions are checked first.
MEGA65 port done by Chris Freeman in 2026, licensed under GPL v3
"""
import sys

PATCHES = [   # (offset in the image, original bytes, new bytes)
    # do_scsi_rw: moveq #9,d0; lsl.l d0,d4; move.l d4,d6; moveq #10,d0 -> #3; asr.l d0,d6;
    # cmpi.l #200,d6 -> #2000; bcc.s; moveq #$37,d6; not.b d6 -> move.w #2000,d6
    (0x16314, '7009e1ac2c04700ae0a60c86000000c864047c374606',
              '7009e1ac2c047003e0a60c86000007d064043c3c07d0'),
]

if len(sys.argv) != 3:
    sys.exit(__doc__)
d = bytearray(open(sys.argv[1], 'rb').read())
for off, old, new in PATCHES:
    if d[off:off + len(old) // 2] != bytes.fromhex(old):
        sys.exit(f"{sys.argv[1]}: not the original EmuTOS image of the 1.3 release (offset {off:#x})")
    d[off:off + len(new) // 2] = bytes.fromhex(new)
open(sys.argv[2], 'wb').write(d)
print(f"{sys.argv[2]}: {len(PATCHES)} patch(es)")
