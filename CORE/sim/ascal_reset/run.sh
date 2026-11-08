#!/usr/bin/env bash
# GHDL test for issue #26: does the HDMI scaler (ascal + avm_decrease + arbiter) recover from resets?
# Usage: ./run.sh [trials] [seed]
set -e
cd "$(dirname "$0")"
[ -d ~/opt/oss-cad-suite/bin ] && PATH=~/opt/oss-cad-suite/bin:$PATH
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
mkdir -p "$W/lib"
for z in /lib/x86_64-linux-gnu/libz.so.1 /usr/lib/libz.so.1; do [ -e "$z" ] && ln -sf "$z" "$W/lib/libz.so" && break; done
V=../../../M2M/vhdl
# simulation copies of ascal, avm_arbit, avm_decrease with a state report (probes.py, dbg_pkg.vhd). In ascal: o_pshift (0..15) gets o_off-1 = -1 and o_pshift-1 = -1 while it is not used;
# the hardware wraps, GHDL stops with a bound check. Wrap explicitly in the copy only. Likewise o_ihsizem
# (12 bits) while o_ihsize is still 0 after a reset.
python3 probes.py $V "$W"
sed -i -e 's/o_pshift<=o_off(0) -1;/o_pshift<=(o_off(0)+15) MOD 16;/' -e 's/o_pshift<=o_pshift-1;/o_pshift<=(o_pshift+15) MOD 16;/' \
   -e 's/o_ihsizem<=o_ihsize + o_off(0) - 2;/o_ihsizem<=(o_ihsize + o_off(0) + 4094) MOD 4096;/' \
   "$W/ascal.vhd"
# BUG=1: the original M2M line (issue #26): avl_write_i not reset, a pending write survives the reset
[ -n "$BUG" ] && sed -i "s/^      avl_write_i<='0'; -- MegaST.*/      --avl_write_i<='0';/" "$W/ascal.vhd" && grep -n "^      --avl_write_i" "$W/ascal.vhd" | head -1
ghdl -a --std=08 -frelaxed -Wno-hide -Wno-shared --workdir="$W" dbg_pkg.vhd "$W/ascal.vhd" "$W/avm_decrease.vhd" \
   "$W/avm_arbit.vhd" $V/memory/avm_arbit_general.vhd tb_ascal_reset.vhd
ghdl -e --std=08 -frelaxed --workdir="$W" -Wl,-L"$W/lib" -o "$W/tb" tb_ascal_reset
"$W/tb" -gG_TRIALS="${1:-40}" -gG_SEED="${2:-7}" ${PROBE_TEST:+-gG_PROBE_TEST=true} --ieee-asserts=disable 2>&1 | grep -v "^$"
