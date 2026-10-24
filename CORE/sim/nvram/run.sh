#!/usr/bin/env bash
# Test of the Falcon NVRAM file (CORE/m2m-rom/nvram.asm) in the QNICE emulator: restore from
# /atarist/fcnvram (../mntmem/make_sd.py nv), no save without a change, save after a change.
# Needs gcc, python3 and the QNICE assembler (M2M/QNICE/tools/make-toolchain.sh). Usage: ./run.sh
set -e
cd "$(dirname "$0")"
Q=../../../M2M/QNICE
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
gcc -fcommon -O2 -DUSE_SD -DUSE_UART -DUSE_TIMER -UUSE_VGA -UUSE_IDE -UDEBUG \
    $Q/emulator/qnice.c $Q/emulator/uart.c $Q/emulator/sd.c $Q/emulator/timer.c -lpthread -o "$W/qnice" 2>/dev/null
gcc -xc -E nvram_test.asm | sed '/^#.*/d' > "$W/t.asm"
$Q/assembler/qasm "$W/t.asm" "$W/t.out" > "$W/t.log" || { cat "$W/t.log"; exit 1; }
python3 ../mntmem/make_sd.py "$W/sd.img" nv
out=$("$W/qnice" -a "$W/sd.img" "$W/t.out" < /dev/null 2>&1 | tr -d '\r')
[ -n "$VERBOSE" ] && echo "$out"
echo "$out" | grep -E "^(OK|FAIL)|FAIL:|Falcon NVRAM" || echo "FAIL: no result"
echo "$out" | grep -q "^OK"
