#!/bin/sh
# Builds FASTRAM.PRG from fastram.s (m68k toolchain as for CORE/sim/falcon_m65/run_prg.sh).
#    ./build.sh [OUT]          (default: FASTRAM.PRG next to this script)
# The program is position independent: a GEMDOS header (BSS 64 KB for the _FRB buffer, fast
# load flag) and an empty relocation table.
# MEGA65 port done by Chris Freeman in 2026, licensed under GPL v3
set -e
H=$(cd "$(dirname "$0")" && pwd)
OUT=${1:-$H/FASTRAM.PRG}
A=${M68K:-$HOME/opt/amiga/bin/m68k-amigaos}
T=$(mktemp -d)
$A-as -m68030 "$H/fastram.s" -o "$T/f.o"
$A-objcopy -O binary "$T/f.o" "$T/f.bin"
python3 -c "
import struct,sys
c=open(sys.argv[1],'rb').read(); c+=b'\0'*(len(c)&1)
open(sys.argv[2],'wb').write(struct.pack('>HIIIIIIH',0x601A,len(c),0,0x10000,0,0,1,0)+c+b'\0\0\0\0')" \
	"$T/f.bin" "$OUT"
rm -rf "$T"
echo "$OUT: $(wc -c < "$OUT") bytes"
