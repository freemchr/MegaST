#!/usr/bin/env bash
# Test of the fast seek for unbuffered virtual drives (M2M/rom/vd_fastseek.asm) in the QNICE emulator:
# a FAT32 SD card image with fragmented or contiguous files (make_fat32.py), random reads and writes that are
# compared with the f32_fseek of the FAT32 library. Runs with 1, 8 and 64 sectors per cluster, with the
# default checkpoint spacing (2 MB) and with a small one (the spacing grows with the file size), and
# with f32_fseek only to compare the speed (executed QNICE instructions).
#
# Needs gcc, python3 and the QNICE assembler (M2M/QNICE/tools/make-toolchain.sh). Usage: ./run.sh
set -e
cd "$(dirname "$0")"
Q=../../../M2M/QNICE
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT

gcc -fcommon -O2 -DUSE_SD -DUSE_UART -DUSE_TIMER -UUSE_VGA -UUSE_IDE -UDEBUG \
    $Q/emulator/qnice.c $Q/emulator/uart.c $Q/emulator/sd.c $Q/emulator/timer.c -lpthread -o "$W/qnice" 2>/dev/null
for v in fast small ref mnt; do
    D=""; [ $v = ref ] && D="-DREF_ONLY"; [ $v = small ] && D="-DVD_UB_CP_SHIFT=3" ; [ $v = mnt ] && D="-DMNT_SIM"
    gcc -xc -E $D fastseek_test.asm | sed '/^#.*/d' > "$W/$v.asm"
    $Q/assembler/qasm "$W/$v.asm" "$W/$v.out" > "$W/$v.asm.log" || { cat "$W/$v.asm.log"; exit 1; }
done

# Both variants seek FH_REF with f32_fseek; the difference of the executed instructions is the
# difference between the fast seek and f32_fseek for FH_FAST.
rc=0
for layout in "1 frag" "8 frag" "8 contig" "64 contig"; do
    set -- $layout; spc=$1
    python3 make_fat32.py "$W/sd.img" $spc 6291456 $2
    for v in fast small ref mnt; do
        out=$("$W/qnice" -a "$W/sd.img" "$W/$v.out" < /dev/null 2>&1 | tr -d '\r')
        res=$(echo "$out" | grep -E "^(OK|FAIL)" || echo "FAIL: no result")
        n=$(echo "$out" | grep -o "[0-9]* instructions have been executed" | cut -d' ' -f1)
        echo "  $v: $res"
        echo "$res" | grep -q "^OK" || rc=1
        eval "n_$v=$n"
    done
    # instructions for the seeks of FH_FAST: ref / 2 with f32_fseek, fast - ref / 2 with the fast seek
    python3 -c "r=$n_ref/2; f=$n_fast-r; print('  seeking FH_FAST: f32_fseek %.0fM, fast seek %.0fM QNICE instructions: %.1f times faster' % (r/1e6, f/1e6, r/f))"
done
exit $rc
