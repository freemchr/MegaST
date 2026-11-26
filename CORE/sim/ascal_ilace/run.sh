#!/usr/bin/env bash
# GHDL test for issue #38: ascal weaves the two fields of the Falcon's interlaced modes into one picture
# (digital_pipeline.vhd: INTER => true, i_fl from falcon_videl.sv ilace_fl). Also the progressive case.
# Usage: ./run.sh
set -e
cd "$(dirname "$0")"
[ -d ~/opt/oss-cad-suite/bin ] && PATH=~/opt/oss-cad-suite/bin:$PATH
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
mkdir -p "$W/lib"
for z in /lib/x86_64-linux-gnu/libz.so.1 /usr/lib/libz.so.1; do [ -e "$z" ] && ln -sf "$z" "$W/lib/libz.so" && break; done
V=../../../M2M/vhdl
# the same bound check wraps as in ../ascal_reset/run.sh (the hardware wraps, GHDL stops)
cp $V/av_pipeline/ascal.vhd "$W/ascal.vhd"
sed -i -e 's/o_pshift<=o_off(0) -1;/o_pshift<=(o_off(0)+15) MOD 16;/' -e 's/o_pshift<=o_pshift-1;/o_pshift<=(o_pshift+15) MOD 16;/' \
   -e 's/o_ihsizem<=o_ihsize + o_off(0) - 2;/o_ihsizem<=(o_ihsize + o_off(0) + 4094) MOD 4096;/' \
   "$W/ascal.vhd"
ghdl -a --std=08 -frelaxed -Wno-hide -Wno-shared --workdir="$W" "$W/ascal.vhd" $V/memory/avm_decrease.vhd $V/memory/avm_arbit.vhd \
   $V/memory/avm_arbit_general.vhd tb_ascal_ilace.vhd
ghdl -e --std=08 -frelaxed --workdir="$W" -Wl,-L"$W/lib" -o "$W/tb" tb_ascal_ilace
rc=0
for il in true false; do
   out=$("$W/tb" -gG_ILACE=$il ${HA:+-gG_HA=$HA} ${LEAD:+-gG_LEAD=$LEAD} --ieee-asserts=disable 2>&1 | grep -v "^$")
   echo "interlaced=$il:"; echo "$out" | grep -E "RESULT|frame |error|bound" | sed "s/^.*(report note): /   /"
   echo "$out" | grep -q "RESULT: OK" || rc=1
done
exit $rc
