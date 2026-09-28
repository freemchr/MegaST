#!/usr/bin/env bash
# GHDL test of floppy_swap.vhd (swapping the floppy drives A: and B:). Needs GHDL (e.g. from the OSS CAD Suite).
# Usage: ./run.sh
set -e
cd "$(dirname "$0")"
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
# the LLVM build of GHDL links with -lz: provide libz.so if only libz.so.1 is installed
mkdir -p "$W/lib"
for z in /lib/x86_64-linux-gnu/libz.so.1 /usr/lib/libz.so.1; do [ -e "$z" ] && ln -sf "$z" "$W/lib/libz.so" && break; done
ghdl -a --std=08 --workdir="$W" ../../vhdl/floppy_swap.vhd tb_floppy_swap.vhd
ghdl -e --std=08 --workdir="$W" -Wl,-L"$W/lib" -o "$W/tb" tb_floppy_swap
"$W/tb"
