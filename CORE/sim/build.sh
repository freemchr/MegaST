#!/usr/bin/env bash
# Verilator simulation of the Atari ST machine (atarist_m65.sv) with a behavioral SDRAM model.
#
# Needs Verilator 5 (e.g. from the OSS CAD Suite: https://github.com/YosysHQ/oss-cad-suite-build).
#
# Usage:
#    ./build.sh                     (VFLAGS=-DACSI_TRACE ./build.sh: trace the ACSI transfers,
#                                    VFLAGS=-DKBD_TRACE: trace the bytes the IKBD sends;
#                                    run with KEY=<column*8+row> KEY_AT=<frame> to press a key,
#                                    VFLAGS=-DBRAM_MEM: MEGA65 R3 variant with block RAM, 512 KB;
#                                    run with MONO=1 for the SM124 monochrome monitor (71 Hz),
#                                    DUMP_FROM=<frame> writes every frame from <frame> on,
#                                    MEM=0..5: 512 KB, 1, 2, 4, 8, 14 MB ST RAM, default 1 MB)
#    cd obj_dir && ./simst <tos.img> <frames> [out_prefix] [ste] [hd.img]
#
# Every 10th frame is written as <out_prefix>_NNN.ppm (convert: python3 ../ppm2png.py in.ppm out.png)
#
# The upstream `ifdef VERILATOR code paths of the MiSTer core are not maintained, therefore the
# RTL is copied to ./rtl_sim with these paths disabled: the simulated code is exactly what Vivado
# synthesizes.
set -e
cd "$(dirname "$0")"
C=..
rm -rf rtl_sim && mkdir -p rtl_sim
cp -r $C/AtariST_MiSTer $C/verilog rtl_sim/
grep -rl 'ifn\?def VERILATOR' rtl_sim | xargs sed -i 's/`ifdef VERILATOR/`ifdef VERILATOR_UPSTREAM_SIM/; s/`ifndef VERILATOR/`ifndef VERILATOR_UPSTREAM_SIM/'
R=rtl_sim/AtariST_MiSTer/rtl
FILES="rtl_sim/verilog/atarist_m65.sv rtl_sim/verilog/sdram_m65.v rtl_sim/verilog/cegen_m65.v
  rtl_sim/verilog/bram_m65.v rtl_sim/verilog/acsi_ctrl.sv rtl_sim/verilog/viking_scale.sv rtl_sim/verilog/rp5c15_m65.sv $R/viking.v $R/cubase2_dongle.v $R/cubase3_dongle.v
  $R/fx68k/fx68k.sv $R/fx68k/fx68kAlu.sv $R/fx68k/uaddrPla.sv
  $R/gstmcu/gstmcu.v $R/gstmcu/gstshifter.v $R/gstmcu/clockgen.v $R/gstmcu/latch.v $R/gstmcu/mcucontrol.v
  $R/gstmcu/register.v $R/gstmcu/shifter_video.v $R/gstmcu/hdegen.v $R/gstmcu/hsyncgen.v $R/gstmcu/modules.v
  $R/gstmcu/sndcnt.v $R/gstmcu/vdegen.v $R/gstmcu/vidcnt.v $R/gstmcu/vsyncgen.v
  $R/ikbd/ikbd.sv $R/ikbd/ps2.sv $R/ikbd/rom/MCU_BIROM.v
  $R/ikbd/hd63701/HD63701.v $R/ikbd/hd63701/HD63701_ALU.v $R/ikbd/hd63701/HD63701_CORE.v
  $R/ikbd/hd63701/HD63701_EXEC.v $R/ikbd/hd63701/HD63701_MCROM.v $R/ikbd/hd63701/HD63701_SEQ.v
  $R/mfp/mfp.v $R/mfp/mfp_hbit16.v $R/mfp/mfp_srff16.v $R/mfp/mfp_timer.v
  $R/fdc1772/fdc1772.sv $R/fdc1772/floppy.v
  $R/acia.v $R/acsi.v $R/dma.v $R/mste_ctrl.v $R/ym2149.sv $R/ste_joypad.v $R/stBlitter.sv"
verilator --cc --exe --build -j 8 -O3 --no-assert --top-module tb_top $VFLAGS \
  -Wno-fatal -Wno-lint -Wno-style -Wno-WIDTH -Wno-MULTIDRIVEN -Wno-UNOPTFLAT -Wno-LATCH -Wno-COMBDLY \
  -Wno-INITIALDLY -Wno-TIMESCALEMOD -Wno-MULTITOP -Wno-BLKANDNBLK --timescale 1ns/1ns \
  -I$R/ikbd/hd63701 $FILES sim_stubs.v sdram_model.v tb_top.sv tb.cpp -o simst
cp $R/fx68k/microrom.mem $R/fx68k/nanorom.mem $R/ikbd/rom/ikbd.mem obj_dir/
echo "Done: obj_dir/simst"
