#!/usr/bin/env bash
# GHDL test of fdc_bridge.vhd: every virtual drive must return its own sector buffer to QNICE, also
# while its sd_ack is low (issue #11, hard disk writes got the floppy buffer).
#
# Needs GHDL (e.g. from the OSS CAD Suite). Usage: ./run.sh
set -e
cd "$(dirname "$0")"
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
# the LLVM build of GHDL links with -lz: provide libz.so if only libz.so.1 is installed
mkdir -p "$W/lib"
for z in /lib/x86_64-linux-gnu/libz.so.1 /usr/lib/libz.so.1; do [ -e "$z" ] && ln -sf "$z" "$W/lib/libz.so" && break; done
mkdir -p "$W/xpm"
ghdl -a --std=08 --work=xpm --workdir="$W/xpm" ../tos_loader/xpm_stub.vhd
ghdl -a --std=08 --workdir="$W" -P"$W/xpm" vdrives_pkg_stub.vhd ../../vhdl/fdc_bridge.vhd tb_fdc_bridge.vhd
ghdl -e --std=08 --workdir="$W" -P"$W/xpm" -Wl,-L"$W/lib" -o "$W/tb" tb_fdc_bridge
"$W/tb"
