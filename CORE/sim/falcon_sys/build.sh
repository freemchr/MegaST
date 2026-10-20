#!/bin/sh
# Full-system simulation of the Falcon (CORE/Falcon_MiSTer) with the MEGA65 SDRAM path:
# Falcon_MiSTer's tb/system test bench (tb_top.sv, sim_main.cpp, copied with MEGA65 changes),
# its DDR3 model replaced by ddr3_m65.sv = falcon_sdram.v on a strict SDRAM model.
# No FPU (the MEGA65 has no ARM for the FPU service).
#    ./build.sh
#    python3 rom2hex64.py etos512us.img etos512us.hex
#    ./obj_dir/Vtb_top +rom=etos512us.hex --ms 3000 --frames out [options, see sim_main.cpp]
set -e
cd "$(dirname "$0")"
R=../../Falcon_MiSTer/rtl
F=$R/falcon
SRCS="$F/falcon_system.sv $F/falcon_cpubus.sv $F/falcon_cpuclk.sv $F/falcon_pipescan.sv $F/falcon_tstat.sv $F/falcon_l2.sv $F/falcon_memarb.sv $F/falcon_combel.sv
 $F/falcon_videl.sv $F/falcon_psg.sv $F/falcon_mfp.sv $F/falcon_mfp_timer.sv $F/falcon_mfp_usart.sv
 $F/falcon_acia.sv $F/falcon_ikbd.sv $F/falcon_ikbd_keymap.sv $F/falcon_nvram.sv $F/falcon_mbox_test.sv $F/falcon_fpu_bridge.sv
 $F/falcon_blitter.sv $F/falcon_crossbar.sv $(ls $F/falcon_ide*.sv) $(ls $F/falcon_fdc*.sv) $F/falcon_scsi.sv $(ls $F/dsp/*.sv)"
# the .mem tables are found relative to the project root, as in Quartus
mkdir -p rtl/falcon
ln -sf ../../$F/falcon_psg_vol.mem rtl/falcon/falcon_psg_vol.mem
ln -sf ../../$F/falcon_optbl.mem rtl/falcon/falcon_optbl.mem
verilator --cc --exe --build -j 16 -O3 --x-assign fast --x-initial fast \
	-Wno-fatal -Wno-WIDTH -Wno-CASEINCOMPLETE -Wno-PINMISSING -Wno-TIMESCALEMOD -Wno-MULTIDRIVEN -Wno-UNOPTFLAT \
	-Wno-INITIALDLY -Wno-BLKANDNBLK -Wno-LATCH \
	--top-module tb_top -Mdir obj_dir +define+FALCON_NO_FPU \
	-I$R/AP68030/rtl -I$R/AP68030/rtl/core -I$F -I$F/dsp \
	tb_top.sv ddr3_m65.sv ../../verilog/falcon_sdram.v ../../verilog/falcon_sdram_pins.v ../falcon_sdram/sdram_strict.v ../sim_stubs.v \
	$R/AP68030/rtl/*.v $SRCS sim_main.cpp
echo "Done: obj_dir/Vtb_top"
