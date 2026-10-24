; ****************************************************************************
; MegaST: test of the Falcon NVRAM file (CORE/m2m-rom/nvram.asm) in the QNICE
; emulator, see run.sh. Runs the real nvram.asm and FAT32 library on an SD
; card image (../mntmem/make_sd.py nv: /atarist/fcnvram = (i*7+3) for bytes
; 0..61, counter 5, marker $A5). In the emulator the device window
; M2M$RAMROM_DATA is plain memory, i.e. the buffer of the core.
;
; 1. NV_RESTORE: the file is in the buffer, NV_ON = 1, NV_LAST = 5
; 2. NV_POLL without a change: nothing saved (NV_LAST stays 5)
; 3. byte 0 = $9C, counter = 6, NV_POLL: saved, NV_LAST = 6, the file has it
;
; This machine is based on AtariST_MiSTer
; Powered by MiSTer2MEGA65
; MEGA65 port done by Chris Freeman in 2026 and licensed under GPL v3
; ****************************************************************************

#define RELEASE
#include "../../../M2M/rom/main.asm"

START_FIRMWARE  MOVE    STR_START, R8
                SYSCALL(puts, 1)
                MOVE    FAILS, R0
                MOVE    0, @R0
                MOVE    M2M$RAMROM_DATA, R8     ; buffer "untouched"
                MOVE    64, R9
                MOVE    0x0055, R10
                SYSCALL(memset, 1)
                MOVE    HANDLE_DEV, R8          ; mount the SD card
                MOVE    1, R9
                SYSCALL(f32_mnt_sd, 1)

                ; 1. restore
                RSUB    NV_RESTORE, 1
                MOVE    NV_ON, R8
                MOVE    @R8, R8
                MOVE    1, R9
                RSUB    CHECK_EQ, 1
                MOVE    NV_LAST, R8
                MOVE    @R8, R8
                MOVE    5, R9
                RSUB    CHECK_EQ, 1
                MOVE    M2M$RAMROM_DATA, R0     ; the pattern
                MOVE    3, R1
                MOVE    62, R2
_T_1            MOVE    @R0++, R8
                MOVE    R1, R9
                RSUB    CHECK_EQ, 1
                ADD     7, R1
                AND     0x00FF, R1
                SUB     1, R2
                RBRA    _T_1, !Z
                MOVE    @R0++, R8               ; counter, marker
                MOVE    5, R9
                RSUB    CHECK_EQ, 1
                MOVE    @R0++, R8
                MOVE    0x00A5, R9
                RSUB    CHECK_EQ, 1

                ; 2. no change: no save
                MOVE    NV_COUNT, R0
                MOVE    0, @R0
                RSUB    NV_POLL, 1
                MOVE    NV_LAST, R8
                MOVE    @R8, R8
                MOVE    5, R9
                RSUB    CHECK_EQ, 1

                ; 3. a change: saved
                MOVE    M2M$RAMROM_DATA, R0
                MOVE    0x009C, @R0
                ADD     62, R0
                MOVE    6, @R0
                MOVE    NV_COUNT, R0
                MOVE    0, @R0
                RSUB    NV_POLL, 1
                MOVE    NV_LAST, R8
                MOVE    @R8, R8
                MOVE    6, R9
                RSUB    CHECK_EQ, 1
                ; the file again: byte 0 = $9C, byte 1 = 10, byte 62 = 6
                MOVE    HANDLE_DEV, R8
                MOVE    FDH2, R9
                MOVE    NV_FNAME, R10
                XOR     R11, R11
                SYSCALL(f32_fopen, 1)
                MOVE    R10, R8
                XOR     R9, R9
                RSUB    CHECK_EQ, 1
                MOVE    FDH2, R8
                SYSCALL(f32_fread, 1)
                MOVE    R9, R2
                SYSCALL(f32_fread, 1)
                MOVE    R9, R3
                MOVE    R2, R8
                MOVE    0x009C, R9
                RSUB    CHECK_EQ, 1
                MOVE    R3, R8
                MOVE    10, R9
                RSUB    CHECK_EQ, 1
                MOVE    60, R4                  ; to byte 62
_T_2            MOVE    FDH2, R8
                SYSCALL(f32_fread, 1)
                SUB     1, R4
                RBRA    _T_2, !Z
                MOVE    FDH2, R8
                SYSCALL(f32_fread, 1)
                MOVE    R9, R8
                MOVE    6, R9
                RSUB    CHECK_EQ, 1

                MOVE    FAILS, R0
                CMP     0, @R0
                RBRA    _T_FAIL, !Z
                MOVE    STR_OK, R8
                SYSCALL(puts, 1)
                HALT
_T_FAIL         MOVE    STR_FAIL, R8
                SYSCALL(puts, 1)
                MOVE    @R0, R8
                SYSCALL(puthex, 1)
                SYSCALL(crlf, 1)
                HALT

; R8 = got, R9 = expected (bytes): count and log a mismatch
CHECK_EQ        SYSCALL(enter, 1)
                AND     0x00FF, R8
                CMP     R8, R9
                RBRA    _CE_RET, Z
                MOVE    FAILS, R0
                ADD     1, @R0
                MOVE    R8, R0
                MOVE    STR_FAILT, R8
                SYSCALL(puts, 1)
                MOVE    R0, R8
                SYSCALL(puthex, 1)
                MOVE    STR_EXP, R8
                SYSCALL(puts, 1)
                MOVE    R9, R8
                SYSCALL(puthex, 1)
                SYSCALL(crlf, 1)
_CE_RET         SYSCALL(leave, 1)
                RET

; stubs for the parts of the shell that nvram.asm uses
VD_CACHE_DIRTY  .EQU    0
VD_ACTIVE       XOR     R8, R8                  ; no vdrives
                AND     0xFFFB, SR
                RET
VD_DRV_READ     XOR     R8, R8
                RET

#include "../../m2m-rom/nvram.asm"

STR_START       .ASCII_W "nvram test\n"
STR_OK          .ASCII_W "OK\n"
STR_FAIL        .ASCII_W "FAIL: failed checks: "
STR_FAILT       .ASCII_W "  FAIL: got "
STR_EXP         .ASCII_W " expected "

                .ORG    0x8000
HANDLE_DEV      .BLOCK  FAT32$DEV_STRUCT_SIZE
NV_FDH          .BLOCK  FAT32$FDH_STRUCT_SIZE
FDH2            .BLOCK  FAT32$FDH_STRUCT_SIZE
NV_ON           .BLOCK  1
NV_LAST         .BLOCK  1
NV_COUNT        .BLOCK  1
FAILS           .BLOCK  1

                .ORG    0xFEE0
#include "../../../M2M/rom/main_vars.asm"
