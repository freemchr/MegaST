#!/bin/sh
# Test bench of the Falcon machine as the core uses it (CORE/verilog/falcon_m65.sv), see sim_main.cpp.
#    ./build.sh
#    ./obj_dir/Vtb_top etos512us.img --ms 6000 --frames out [--fda disk.st] [--key IDX:T]
set -e
cd "$(dirname "$0")"
R=../../Falcon_MiSTer/rtl
F=$R/falcon
V=../../verilog
# the .mem tables ($readmemb with the file name only) are read from the directory the test runs in
ln -sf $F/falcon_psg_vol.mem falcon_psg_vol.mem
ln -sf $F/falcon_optbl.mem falcon_optbl.mem
verilator --cc --exe --build -j 16 -O3 --x-assign fast --x-initial fast \
	-Wno-fatal -Wno-WIDTH -Wno-CASEINCOMPLETE -Wno-PINMISSING -Wno-TIMESCALEMOD -Wno-MULTIDRIVEN -Wno-UNOPTFLAT \
	-Wno-INITIALDLY -Wno-BLKANDNBLK -Wno-LATCH \
	--top-module tb_top -Mdir obj_dir +define+FALCON_NO_FPU \
	-I$R/AP68030/rtl -I$R/AP68030/rtl/core -I$F -I$F/dsp \
	tb_top.sv $V/falcon_m65.sv $V/falcon_kbd_map.v $V/falcon_sdram.v $V/sdram_pinstage.v \
	../falcon_sdram/sdram_strict.v ../sim_stubs.v \
	$R/AP68030/rtl/*.v $F/*.sv $F/dsp/*.sv sim_main.cpp
echo "Done: obj_dir/Vtb_top"
