#!/usr/bin/env bash
# Hard disk write test in the Verilator simulation (../build.sh must have been run):
# a floppy boot sector (make_boot.py) writes 128 sectors (64 KB) with one Rwabs call to the
# ACSI hard disk; check.py verifies the image afterwards. With a delay, every sector write
# takes 20 ms like the slow SD path of the M2M firmware.
#
# Usage: ./run.sh <emutos tos.img> [delay cycles, default 0; 641666 = 20 ms] [frames]
# EmuTOS boots the floppy at about frame 345; the write takes ~3 frames without delay and
# ~130 frames with 20 ms per sector.
set -e
cd "$(dirname "$0")"
TOS=$(realpath "$1")
DELAY=${2:-0}
FRAMES=${3:-$([ "$DELAY" = 0 ] && echo 360 || echo 700)}
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
python3 make_boot.py "$W/boot.st"
head -c 1048576 /dev/zero > "$W/hd.img"
(cd ../obj_dir && FLOPPY="$W/boot.st" HD_WR_DELAY=$DELAY HD_OUT="$W/out.img" \
    ./simst "$TOS" "$FRAMES" "$W/f" 0 "$W/hd.img" > "$W/log.txt" 2>&1)
python3 - "$W/f_$(printf %03d $((FRAMES - 1))).ppm" <<'PY'
import sys
d = open(sys.argv[1], 'rb').read(); d = d[d.index(b'255\n') + 4:]
print("screen:", "green (Rwabs returned 0)" if b'\x00\xee\x00' in d or b'\x00\xff\x00' in d
      else "red (Rwabs error)" if b'\xee\x00\x00' in d or b'\xff\x00\x00' in d else "unknown")
PY
python3 check.py "$W/out.img"
