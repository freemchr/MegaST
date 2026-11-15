#!/bin/sh
# Test bench of fpu_rv.v (the RISC-V of the Falcon's FPU) with a program image, see sim_main.cpp.
#    ../../falcon_fpu/rv/build.sh && ./build.sh [image.mem]  (default: the engine self-test)
#    ./obj_dir/Vfpu_rv
# H3=1: fpu_rv_h3.v (Hazard3) into obj_h3/, image default selftest_h3.mem (rv/build.sh with H3=1)
set -e
cd "$(dirname "$0")"
if [ -n "$H3" ]; then
	HEX="${1:-../../falcon_fpu/rv/selftest_h3.mem}"; M=obj_h3; L=fpu_rv_h3.mem
	SRC="-DH3 -CFLAGS -DH3 -I../../hazard3/hdl ../../verilog/fpu_rv_h3.v $(sed -n 's|^file |../../hazard3/hdl/|p' ../../hazard3/hdl/hazard3.f)"
else
	HEX="${1:-../../falcon_fpu/rv/selftest.mem}"; M=obj_dir; L=fpu_rv.mem
	SRC="../../verilog/fpu_rv.v ../../picorv32/picorv32.v"
fi
ln -sf "$HEX" $L
verilator --cc --exe --build -j 8 -O3 -Wno-fatal -Wno-WIDTH -Wno-MULTIDRIVEN -Wno-CASEINCOMPLETE \
	--public-flat-rw --top-module fpu_rv -Mdir $M $SRC sim_main.cpp
echo "Done: $M/Vfpu_rv (image: $HEX)"
