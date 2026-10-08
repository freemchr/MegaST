#!/usr/bin/env bash
# Test of remembering the mounted images (M2M/rom/mntmem.asm) in the QNICE emulator: path tracking of the
# file browser, saving the paths to /atarist/stmount on a FAT32 SD card image (make_sd.py) and restoring them
# (with long file names, a missing image, an unusable image, unmounting). The file variants "zero" and "ff"
# are valid files, "short" (wrong size) and "none" (no file) switch the feature off.
#
# Needs gcc, python3 and the QNICE assembler (M2M/QNICE/tools/make-toolchain.sh). Usage: ./run.sh
set -e
cd "$(dirname "$0")"
Q=../../../M2M/QNICE
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT

gcc -fcommon -O2 -DUSE_SD -DUSE_UART -DUSE_TIMER -UUSE_VGA -UUSE_IDE -UDEBUG \
    $Q/emulator/qnice.c $Q/emulator/uart.c $Q/emulator/sd.c $Q/emulator/timer.c -lpthread -o "$W/qnice" 2>/dev/null
for on in 0 1; do
    gcc -xc -E -DEXPECT_ON=$on mntmem_test.asm | sed '/^#.*/d' > "$W/t$on.asm"
    $Q/assembler/qasm "$W/t$on.asm" "$W/t$on.out" > "$W/t$on.asm.log" || { cat "$W/t$on.asm.log"; exit 1; }
done

rc=0
for variant in "zero 1" "ff 1" "short 0" "none 0"; do
    set -- $variant
    python3 make_sd.py "$W/sd.img" $1
    out=$("$W/qnice" -a "$W/sd.img" "$W/t$2.out" < /dev/null 2>&1 | tr -d '\r')
    res=$(echo "$out" | grep -E "^(OK|FAIL)" || echo "FAIL: no result")
    echo "stmount $1: $res"
    if ! echo "$res" | grep -q "^OK"; then
        echo "$out" | grep -E "FAIL|FATAL" | sed 's/^/    /'
        rc=1
    fi
    [ -n "$VERBOSE" ] && echo "$out"
done
exit $rc
