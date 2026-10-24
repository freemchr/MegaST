#!/usr/bin/env python3
"""A faster booting copy of the EmuTOS 1.4 Falcon image of the test builds, for the test bench only.

    python3 simrom.py tosfalc.img tosfalc_sim.img

EmuTOS spends seconds of simulated time at boot: 250 ms per SCSI selection timeout (scsi.c,
SELECTION_TIMEOUT, several selections per SCSI ID) and 3 s on the welcome screen
(initinfo.c, INITINFO_DURATION). This copy waits 2 ticks (10 ms) per selection and 20 ticks
(100 ms) on the welcome screen. The patched instructions are checked first.
MEGA65 port done by Chris Freeman in 2026, licensed under GPL v3
"""
import sys

PATCHES = [   # (offset in the image, original bytes, new bytes)
    (0x156A0, '41e80032', '41e80002'),      # scsi_select: lea 50(a0),a0 (hz_200 + SELECTION_TIMEOUT)
    (0x0D6A4, '00000258', '00000014'),      # initinfo: addi.l #600 (INITINFO_DURATION * 200)
    (0x0D77A, '00000258', '00000014'),
]

if len(sys.argv) != 3:
    sys.exit(__doc__)
d = bytearray(open(sys.argv[1], 'rb').read())
for off, old, new in PATCHES:
    if d[off:off + len(old) // 2] != bytes.fromhex(old):
        sys.exit(f"{sys.argv[1]}: not the EmuTOS 1.4 image of the test builds (offset {off:#x})")
    d[off:off + len(new) // 2] = bytes.fromhex(new)
open(sys.argv[2], 'wb').write(d)
print(f"{sys.argv[2]}: {len(PATCHES)} patches")
