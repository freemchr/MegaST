#!/usr/bin/env bash
# Test of the switch between the ST and the Falcon (CORE/m2m-rom/fcswitch.asm) in the QNICE emulator:
# which TOS is loaded again after a switch (stubs for the menu bit and the loaders).
# Needs gcc and the QNICE assembler (M2M/QNICE/tools/make-toolchain.sh). Usage: ./run.sh
set -e
cd "$(dirname "$0")"
Q=../../../M2M/QNICE
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
gcc -fcommon -O2 -DUSE_UART -UUSE_SD -UUSE_TIMER -UUSE_VGA -UUSE_IDE -UDEBUG \
    $Q/emulator/qnice.c $Q/emulator/uart.c -lpthread -o "$W/qnice" 2>/dev/null
gcc -xc -E fcswitch_test.asm | sed '/^#.*/d' > "$W/t.asm"
$Q/assembler/qasm "$W/t.asm" "$W/t.out" > "$W/t.log" || { cat "$W/t.log"; exit 1; }
out=$("$W/qnice" "$W/t.out" < /dev/null 2>&1 | tr -d '\r')
[ -n "$VERBOSE" ] && echo "$out"
echo "$out" | grep -E "^(OK|FAIL)|FAIL:" || echo "FAIL: no result"
echo "$out" | grep -q "^OK"
