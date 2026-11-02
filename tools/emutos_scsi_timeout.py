#!/usr/bin/env python3
"""Patch the Falcon EmuTOS of the release (atarist/tosfalc.img) for the slow MEGA65 hard disks on SCSI.

    python3 emutos_scsi_timeout.py tosfalc.img tosfalc_patched.img

EmuTOS (bios/scsi.c, do_scsi_rw) gives a SCSI read or write the timeout
max(SHORT_TIMEOUT, buflen / BYTES_PER_CLOCK) ticks of 5 ms, with BYTES_PER_CLOCK = 1024: it
assumes that the disk transfers at least 200 KB/s. The MEGA65 serves the hard disk images
directly from the SD card (unbuffered virtual drives of the firmware), much slower than that,
above all for writes. So every transfer that takes longer than about a second fails with
EUNDEV, shown as "Your output device is not receiving data" (installing to or copying on a
SCSI hard disk, loading a large program). IDE is not affected (3 s per block of 16 sectors).

The patch makes the division by 1024 (asr.l #10) a division by 64 (asr.l #6): at least
12.8 KB/s, 40 ms per sector. The minimum of one second stays. The patched instruction is
checked first.
MEGA65 port done by Chris Freeman in 2026, licensed under GPL v3
"""
import sys

PATCHES = [   # (offset in the image, original bytes, new bytes)
    # do_scsi_rw: moveq #9,d0; lsl.l d0,d4; move.l d4,d6; moveq #10,d0 -> #6; asr.l d0,d6; cmpi.l #200,d6
    (0x16314, '7009e1ac2c04700ae0a60c86000000c8', '7009e1ac2c047006e0a60c86000000c8'),
]

if len(sys.argv) != 3:
    sys.exit(__doc__)
d = bytearray(open(sys.argv[1], 'rb').read())
for off, old, new in PATCHES:
    if d[off:off + len(old) // 2] != bytes.fromhex(old):
        sys.exit(f"{sys.argv[1]}: not the EmuTOS image of the 1.3 release (offset {off:#x})")
    d[off:off + len(new) // 2] = bytes.fromhex(new)
open(sys.argv[2], 'wb').write(d)
print(f"{sys.argv[2]}: {len(PATCHES)} patch(es)")
