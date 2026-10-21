#!/bin/sh
# Test bench of the Falcon machine as the core uses it (CORE/verilog/falcon_m65.sv), see sim_main.cpp.
#    ./build.sh
#    ./obj_dir/Vtb_top etos512us.img --ms 6000 --frames out [--fda disk.st] [--key IDX:T]
set -e
cd "$(dirname "$0")"
R=../../Falcon_MiSTer/rtl
F=$R/falcon
V=../../verilog
# FPU=1: with the 68882 (the bridge's service on the RISC-V, fpu_rv.v; image falcon_fpu/rv/fpu_rv.hex),
# built into obj_fpu
if [ -n "$FPU" ]; then
	DEFS="+define+FALCON_FPU_LOCAL"; EXTRA="$V/fpu_rv.v ../../picorv32/picorv32.v"; MDIR=obj_fpu
	ln -sf ../../falcon_fpu/rv/fpu_rv.hex fpu_rv.hex
else
	DEFS="+define+FALCON_NO_FPU"; EXTRA=""; MDIR=${MDIR:-obj_dir}
fi
# the .mem tables ($readmemb with the file name only) are read from the directory the test runs in
ln -sf $F/falcon_psg_vol.mem falcon_psg_vol.mem
ln -sf $F/falcon_optbl.mem falcon_optbl.mem
verilator --cc --exe --build -j 8 -O3 --x-assign fast --x-initial fast \
	-Wno-fatal -Wno-WIDTH -Wno-CASEINCOMPLETE -Wno-PINMISSING -Wno-TIMESCALEMOD -Wno-MULTIDRIVEN -Wno-UNOPTFLAT \
	-Wno-INITIALDLY -Wno-BLKANDNBLK -Wno-LATCH \
	--top-module tb_top -Mdir $MDIR $DEFS \
	-I$R/AP68030/rtl -I$R/AP68030/rtl/core -I$F -I$F/dsp \
	tb_top.sv $V/falcon_m65.sv $V/falcon_kbd_map.v $V/falcon_sdram.v $V/sdram_pinstage.v $EXTRA \
	../falcon_sdram/sdram_strict.v ../sim_stubs.v \
	$R/AP68030/rtl/*.v $F/*.sv $F/dsp/*.sv sim_main.cpp
echo "Done: $MDIR/Vtb_top"
