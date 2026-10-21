#!/bin/sh
# falcon_fpu for the RISC-V in the FPGA (fpu_rv.v, PicoRV32 RV32IM): the engine (Hatari's fpp.c +
# softfloat through ../engine, unmodified) and
#   fpu_rv.hex     the FPU service (fpu_rv.c), the block RAM image of the FPGA build
#   bench.hex      bench.c: RISC-V cycles per instruction (simulation)
#   selftest.hex   ../engine/fpe_selftest.c (the engine against fpp.c driven with real EAs), for
#                  the simulation (CORE/sim/fpu_rv)
# A .hex is one 32-bit word per line for $readmemh, the whole RAM (256 KB).
#   HATARI  Hatari source tree (default ~/opt/src/hatari-2.6.1)
#   RVGCC   RISC-V compiler (default riscv-none-elf-gcc: xPack GNU RISC-V Embedded GCC)
#
# MEGA65 port done by Chris Freeman in 2026, licensed under GPL v3
set -e
cd "$(dirname "$0")"
HATARI="${HATARI:-$HOME/opt/src/hatari-2.6.1}"
H="$HATARI/src"
CC="${RVGCC:-riscv-none-elf-gcc}"
P="${CC%gcc}"
E=../engine
O=build
mkdir -p $O
ARCH="-march=rv32im_zicsr -mabi=ilp32"
INC="-Ishim -I$E -I$E/shim -I$H/cpu -I$H/cpu/softfloat -I$H/includes -I$H/debug"
# as in ../engine/build.sh (-fwrapv: Hatari builds with it, -w: Hatari's code is warning-noisy);
# int32_t is long here, which Hatari's int/int32_t pointer mix does not expect: same size, harmless
HF="$ARCH -std=gnu99 -O2 -w -fwrapv -ffunction-sections -fdata-sections -Wno-incompatible-pointer-types"
LF="$ARCH -nostartfiles -specs=nano.specs -T link.ld -Wl,--gc-sections"

objs=""
for f in $E/fpe_fpp.c $H/cpu/fpp_softfloat.c $H/cpu/softfloat/softfloat.c $H/cpu/softfloat/softfloat_fpsp.c \
         $H/cpu/softfloat/softfloat_decimal.c $E/fpe_shim.c; do
	o="$O/$(basename "$f" .c).o"; $CC $HF $INC -c "$f" -o "$o"; objs="$objs $o"
done
$CC $ARCH -c start.S -o $O/start.o
$CC $ARCH -std=gnu99 -O2 -Wall -Wextra -I. -c sys.c -o $O/sys.o
$CC $ARCH -std=gnu99 -O2 -Wall -Wextra -Wno-unused-parameter -I. -I.. -c fpu_rv.c -o $O/fpu_rv.o
$CC $ARCH -std=gnu99 -O2 -Wall -I. -I.. $BENCHF -c bench.c -o $O/bench.o
$CC $HF $INC -c $E/fpe_selftest.c -o $O/fpe_selftest.o

link() {    # $1 name, rest: objects
	n=$1; shift
	$CC $LF -Wl,-Map=$O/$n.map $O/start.o "$@" $O/sys.o $objs -lm -o $O/$n.elf
	${P}objcopy -O binary $O/$n.elf $O/$n.bin
	python3 - "$O/$n.bin" "$n.hex" <<'EOF'
import sys
b = open(sys.argv[1], 'rb').read()
if len(b) > 256 * 1024 - 8192: sys.exit(f"{sys.argv[1]}: {len(b)} bytes, too big for the 256 KB RAM")
b += bytes(-len(b) % 4)
w = [int.from_bytes(b[i:i + 4], 'little') for i in range(0, len(b), 4)]
w += [0] * (65536 - len(w))
open(sys.argv[2], 'w').write(''.join(f'{x:08x}\n' for x in w))
EOF
	${P}size $O/$n.elf | tail -1
}
link fpu_rv $O/fpu_rv.o
link selftest $O/fpe_selftest.o
link bench $O/bench.o
echo "built: fpu_rv.hex selftest.hex bench.hex"
