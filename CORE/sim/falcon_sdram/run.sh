#!/usr/bin/env bash
# Falcon SDRAM adapter (CORE/verilog/falcon_sdram.v): random reads and writes against a
# reference memory, SDRAM timing checked by a strict model. Needs Verilator 5 (--timing).
#    ./run.sh [ops]      (default 40000 commands)
set -e
cd "$(dirname "$0")"
verilator --binary --timing -j 8 -O2 --top-module tb -Wno-fatal -Wno-lint -Wno-style -Wno-WIDTH \
  -Wno-MULTIDRIVEN -Wno-INITIALDLY -Wno-BLKANDNBLK ../../verilog/falcon_sdram.v ../../verilog/falcon_sdram_pins.v sdram_strict.v ../sim_stubs.v tb.sv \
  --Mdir obj_dir -o tb > build.log 2>&1 || { tail -30 build.log; exit 1; }
./obj_dir/tb +ops=${1:-40000}
