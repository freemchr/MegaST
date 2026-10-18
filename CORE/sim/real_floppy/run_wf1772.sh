#!/usr/bin/env bash
# GHDL equivalence test of the WF1772IP clock enable conversion (CORE/vhdl/floppy/wf1772ip/README.md):
# the original IP (with the bug fixes of tools/wf1772_ce.py) on 16 MHz and the converted IP on 32 MHz
# with CE, same CPU accesses, same drive model.
# Needs GHDL (e.g. from the OSS CAD Suite). Takes about 10 minutes with the mcode backend.
# Usage: ./run_wf1772.sh
set -e
cd "$(dirname "$0")"
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
python3 -I ../../../tools/wf1772_ce.py --fix-only ../../vhdl/floppy/wf1772ip/orig "$W/fixed"
# one work directory per library (the LLVM build of GHDL names its object files after the source file)
mkdir -p "$W/orig" "$W/ce" "$W/tb" "$W/lib"
# the LLVM build of GHDL links with -lz: provide libz.so if only libz.so.1 is installed
for z in /lib/x86_64-linux-gnu/libz.so.1 /usr/lib/libz.so.1; do [ -e "$z" ] && ln -sf "$z" "$W/lib/libz.so" && break; done
F="--std=08 -fsynopsys -frelaxed"
ORDER="pkg am_detector control crc_logic digital_pll registers transceiver top_soc"
for f in $ORDER; do
   ghdl -a $F --work=wf_orig --workdir="$W/orig" "$W/fixed/wf1772ip_$f.vhd"
   ghdl -a $F --work=wf_ce   --workdir="$W/ce"   ../../vhdl/floppy/wf1772ip/wf1772ip_$f.vhd
done
T="$F --workdir=$W/tb -P$W/orig -P$W/ce"
ghdl -a $T floppy_model.vhd tb_wf1772_ce.vhd
# the IP's arithmetic warns about 'U' operands before the reset: filter these warnings
if ghdl --version | grep -q mcode; then
   ghdl --elab-run $T tb_wf1772_ce --assert-level=error 2>&1 | grep -v "std_logic_arith\|^$"
else
   ghdl -e $T -Wl,-L"$W/lib" -o "$W/tb/tb" tb_wf1772_ce
   "$W/tb/tb" --assert-level=error 2>&1 | grep -v "std_logic_arith\|^$"
fi
test "${PIPESTATUS[0]}" -eq 0
