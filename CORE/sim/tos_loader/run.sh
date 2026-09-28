#!/usr/bin/env bash
# GHDL test of tos_loader.vhd: a QNICE-like master (samples wait at its rising clock edge, like
# qnice_cpu.vhd) writes 4 kB, the core side acknowledges each word. Every word must arrive once.
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
ghdl -a --std=08 --work=xpm --workdir="$W/xpm" xpm_stub.vhd
ghdl -a --std=08 --workdir="$W" -P"$W/xpm" ../../vhdl/tos_loader.vhd tb_tos_loader.vhd
ghdl -e --std=08 --workdir="$W" -P"$W/xpm" -Wl,-L"$W/lib" -o "$W/tb" tb_tos_loader
echo "TOS auto-load:";   "$W/tb"
echo "TOS from the menu:"; "$W/tb" -gMANUAL=true
