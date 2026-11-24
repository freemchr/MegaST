#!/usr/bin/env bash
# Test of the sector-wise transfer for unbuffered virtual drives (M2M/rom/vd_ubcopy.asm) in the QNICE
# emulator: a FAT32 SD card image with fragmented or contiguous files (../fastseek/make_fat32.py), random
# reads and writes of 1 .. 1536 bytes (aligned, unaligned, sequential, across the end of the file, with
# another file taking the SD buffer in between), checked against the file content and read back byte by
# byte. Runs with 1, 8 and 64 sectors per cluster. Then the number of executed QNICE instructions for
# 256 KB read and 256 KB written in 512 byte requests, new code vs. the old byte loop.
#
# Needs gcc, python3 and the QNICE assembler (M2M/QNICE/tools/make-toolchain.sh). Usage: ./run.sh
set -e
cd "$(dirname "$0")"
Q=../../../M2M/QNICE
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT

gcc -fcommon -O2 -DUSE_SD -DUSE_UART -DUSE_TIMER -UUSE_VGA -UUSE_IDE -UDEBUG \
    $Q/emulator/qnice.c $Q/emulator/uart.c $Q/emulator/sd.c $Q/emulator/timer.c -lpthread -o "$W/qnice" 2>/dev/null
for v in test fast slow; do
    D=""; [ $v = fast ] && D="-DSPEED"; [ $v = slow ] && D="-DSPEED -DSLOW"
    gcc -xc -E $D ubcopy_test.asm | sed '/^#.*/d' > "$W/$v.asm"
    $Q/assembler/qasm "$W/$v.asm" "$W/$v.out" > "$W/$v.asm.log" || { cat "$W/$v.asm.log"; exit 1; }
done

run() {
    out=$("$W/qnice" -a "$W/sd.img" "$W/$1.out" < /dev/null 2>&1 | tr -d '\r')
    res=$(echo "$out" | grep -E "^(OK|FAIL)" || echo "FAIL: no result")
    n=$(echo "$out" | grep -o "[0-9]* instructions have been executed" | cut -d' ' -f1)
}

rc=0
for layout in "1 frag" "8 frag" "8 contig" "64 contig"; do
    set -- $layout
    echo "$1 sectors per cluster, $2:"
    python3 ../fastseek/make_fat32.py "$W/sd.img" $1 6291456 $2
    run test
    echo "  test: $res"
    echo "$res" | grep -q "^OK" || rc=1
done

# speed: fresh image each time (the slow run writes the same content back)
python3 ../fastseek/make_fat32.py "$W/sd.img" 8 6291456 frag
run fast; echo "  speed, new code: $res"; echo "$res" | grep -q "^OK" || rc=1; n_fast=$n
python3 ../fastseek/make_fat32.py "$W/sd.img" 8 6291456 frag
run slow; echo "  speed, byte loop: $res"; echo "$res" | grep -q "^OK" || rc=1; n_slow=$n
python3 -c "print('  256 KB read + 256 KB written: byte loop %.1fM, new code %.1fM QNICE instructions: %.1f times fewer' % ($n_slow/1e6, $n_fast/1e6, $n_slow/$n_fast))"
exit $rc
