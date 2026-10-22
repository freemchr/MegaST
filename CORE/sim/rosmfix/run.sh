#!/usr/bin/env bash
# Test of the check of the loaded settings (M2M/rom/rosmfix.asm, ROSM_FIXGRP) in the QNICE emulator:
# the menu of CORE/vhdl/config.vhd with settings files that do not match it (no or several items selected
# in a group of options) and valid ones. gen.py computes the expected result independently.
#   ./run.sh [stcfg ...]   extra settings files to check, e.g. one from an SD card
# Needs gcc, python3 and the QNICE assembler (M2M/QNICE/tools/make-toolchain.sh).
set -e
cd "$(dirname "$0")"
Q=../../../M2M/QNICE
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT

gcc -fcommon -O2 -DUSE_UART -UUSE_SD -UUSE_TIMER -UUSE_VGA -UUSE_IDE -UDEBUG \
    $Q/emulator/qnice.c $Q/emulator/uart.c -lpthread -o "$W/qnice" 2>/dev/null
python3 gen.py ../../vhdl/config.vhd "$W/td.asm" "$W/expected.txt" "$@"
sed "s#\.\./\.\./\.\./#$PWD/../../../#" rosmfix_test.asm > "$W/rosmfix_test.asm"
gcc -xc -E -I"$W" "$W/rosmfix_test.asm" | sed '/^#.*/d' > "$W/t.asm"
$Q/assembler/qasm "$W/t.asm" "$W/t.out" > "$W/t.log" || { cat "$W/t.log"; exit 1; }
"$W/qnice" "$W/t.out" < /dev/null 2>&1 | tr -d '\r' > "$W/out.txt"
[ -n "$VERBOSE" ] && cat "$W/out.txt"
grep "^CASE" "$W/out.txt" > "$W/got.txt" || true
if diff "$W/expected.txt" "$W/got.txt" > "$W/diff.txt"; then
    echo "OK: $(wc -l < "$W/got.txt") cases"
    grep "^Config file" "$W/out.txt" | sort | uniq -c | sed 's/^/    /'
else
    echo "FAIL"; cat "$W/diff.txt"; exit 1
fi
