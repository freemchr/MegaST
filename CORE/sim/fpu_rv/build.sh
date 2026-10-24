#!/bin/sh
# Test bench of fpu_rv.v (the RISC-V of the Falcon's FPU) with a program image, see sim_main.cpp.
#    ../../falcon_fpu/rv/build.sh && ./build.sh [image.mem]  (default: the engine self-test)
#    ./obj_dir/Vfpu_rv
set -e
cd "$(dirname "$0")"
HEX="${1:-../../falcon_fpu/rv/selftest.mem}"
ln -sf "$HEX" fpu_rv.mem
verilator --cc --exe --build -j 8 -O3 -Wno-fatal -Wno-WIDTH -Wno-MULTIDRIVEN -Wno-CASEINCOMPLETE \
	--public-flat-rw --top-module fpu_rv -Mdir obj_dir ../../verilog/fpu_rv.v ../../picorv32/picorv32.v sim_main.cpp
echo "Done: obj_dir/Vfpu_rv (image: $HEX)"
