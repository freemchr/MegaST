#!/bin/sh
# Runs a program from \AUTO on an IDE hard disk in the falcon_m65 test bench.
#    ./run_prg.sh OUT PROG [DIR] -- [Vtb_top options]
# PROG is a .s file (assembled with the m68k toolchain into a .PRG without relocations, see
# tests/) or a .PRG/.TOS. DIR (optional) goes into the root of C: (data files of a demo). The image
# (OUT.img), the frames (OUT/) and the log (OUT.log) are written next to OUT. Without TOS= the
# EmuTOS of the Falcon test builds is used (simrom.py makes a faster booting copy for TOS=);
# SIM= selects the model (default obj_fpu). Test programs (.s) get the fast load flag (no TPA clear).
# MEGA65 port done by Chris Freeman in 2026, licensed under GPL v3
set -e
H=$(cd "$(dirname "$0")" && pwd)
OUT=$1; PROG=$2; shift 2
DIR=
if [ "$1" != "--" ] && [ -n "$1" ]; then DIR=$1; shift; fi
[ "$1" = "--" ] && shift
TOS=${TOS:-$HOME/MegaST-release/MegaST-v1.1.4-falcon-test4/atarist/tosfalc.img}
SIM=${SIM:-$H/obj_fpu/Vtb_top}
ST=$OUT.stage
rm -rf "$ST" "$OUT"; mkdir -p "$ST/root/AUTO" "$OUT"
case "$PROG" in
*.s)
	A=$HOME/opt/amiga/bin/m68k-amigaos
	$A-as -m68030 -m68882 "$PROG" -o "$ST/p.o"
	$A-objcopy -O binary "$ST/p.o" "$ST/p.bin"
	python3 -c "
import struct,sys
c=open(sys.argv[1],'rb').read(); c+=b'\0'*(len(c)&1)
open(sys.argv[2],'wb').write(struct.pack('>HIIIIIIH',0x601A,len(c),0,0,0,0,1,0)+c+b'\0\0\0\0')" \
		"$ST/p.bin" "$ST/root/AUTO/TEST.PRG" ;;
*)	B=$(basename "$PROG"); cp "$PROG" "$ST/root/AUTO/${B%.*}.PRG" ;;   # \AUTO runs .PRG only
esac
if [ -n "$DIR" ]; then
	# the data files in C:\ and in \AUTO (the current directory of a program from \AUTO), the
	# other programs only in C:\ (all of \AUTO\*.PRG would run)
	cp -r "$DIR"/. "$ST/root/"
	find "$DIR" -maxdepth 1 -type f ! -iname '*.prg' ! -iname '*.tos' ! -iname '*.ttp' ! -iname '*.app' \
		-exec cp {} "$ST/root/AUTO/" \;
	find "$DIR" -mindepth 1 -maxdepth 1 -type d -exec cp -r {} "$ST/root/AUTO/" \;
fi
MB=$(( $(du -sm "$ST/root" | cut -f1) * 2 + 40 ))   # FAT16 with 8 KB clusters: at least 32 MB
python3 "$H/mkfat16.py" "$OUT.img" "C:$MB:$ST/root" > "$ST/mkfat16.log"
cd "$H"
"$SIM" "$TOS" --hda "$OUT.img" --frames "$OUT" "$@" > "$OUT.log" 2>&1
tail -n 4 "$OUT.log"
