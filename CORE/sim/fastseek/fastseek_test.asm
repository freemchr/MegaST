; ****************************************************************************
; MegaST: test of the fast seek for unbuffered virtual drives
; (M2M/rom/vd_fastseek.asm) in the QNICE emulator, see run.sh
;
; HD0.IMG is opened twice: FH_FAST is positioned with VD_UB_FSEEK, FH_REF with
; the FAT32 library (f32_fseek, always from the start of the file). At random
; positions (and sometimes right behind the previous one), both handles have
; to read the same bytes, which have to match the file content
; ((pos * 7 + pos / 512) & 0xFF, see make_fat32.py). Every 8th access writes
; through FH_FAST and reads it back through FH_REF.
;
; REF_ONLY defined: FH_FAST also uses f32_fseek (to compare the speed)
; MNT_SIM defined: sequential reads skip the seek (like VD_UB_SEEK) and every
; 16th access writes HD1.IMG through a third handle, like MNT_SAVE writes
; /atarist/stmount (FILE_OPEN takes over the sector buffer without flushing
; it, so the hard disk sector has to be flushed before, as the firmware does)
; VD_UB_CP_SHIFT=3: checkpoints at least every 8 sectors: for the 6 MB file
; the shift has to become 5 (the 512 checkpoints cover 8 MB)
;
; This machine is based on AtariST_MiSTer
; Powered by MiSTer2MEGA65
; MEGA65 port done by Chris Freeman in 2026 and licensed under GPL v3
; ****************************************************************************

#define RELEASE
#include "../../../M2M/rom/main.asm"

ITERATIONS      .EQU    400
FILE_SIZE_HI    .EQU    0x0060                  ; 6 MB = 0x00600000

START_FIRMWARE  MOVE    STR_START, R8
                SYSCALL(puts, 1)
                SYSCALL(crlf, 1)

                MOVE    DEVH, R8                ; mount partition 1
                MOVE    1, R9
                RSUB    FAT32$MOUNT_SD, 1
                CMP     0, R9
                RBRA    ERR_MOUNT, !Z

                MOVE    FH_FAST, R9             ; open HD0.IMG twice
                RSUB    OPEN_FILE, 1
                MOVE    FH_REF, R9
                RSUB    OPEN_FILE, 1

                MOVE    VD_UB_CP, R8            ; like shell.asm at startup
                MOVE    0xFFFF, @R8
                ADD     VD_UB_CP_SLOTSZ, R8
                MOVE    0xFFFF, @R8
                MOVE    2, R8                   ; like shell.asm after a mount
                MOVE    FH_FAST, R9
                RSUB    VD_UB_CP_CLAIM, 1

#ifdef CLAIM_ONLY
                RBRA    _RESULT, 1              ; large sparse image: claim only
#endif
                MOVE    RND_LO_S, R8            ; seeds (RND_HI_S follows)
                MOVE    0xACE1, @R8++
                MOVE    0x1234, @R8

                MOVE    ITERATIONS, R7          ; R7: iterations left
                XOR     R4, R4                  ; R5|R4: position
                XOR     R5, R5

                ; next position: random, right behind the last access (every
                ; 4th) or some sectors behind it (every 5th)
_LOOP           MOVE    R7, R8
                AND     0x0003, R8
                RBRA    _POS_SEQ, Z
                MOVE    R7, R8
                MOVE    5, R9
                RSUB    MOD16, 1
                CMP     0, R8
                RBRA    _POS_NEAR, Z
                RSUB    RANDOM, 1               ; R9|R8: random
                MOVE    R8, R4
                AND     0xFFFC, R4              ; stay 4 bytes before the end
                MOVE    R9, R5
                AND     0x007F, R5
                CMP     FILE_SIZE_HI, R5        ; hi < 0x60?
                RBRA    _LOOP_1, N
                SUB     0x0020, R5              ; no: 2 MB lower
                RBRA    _LOOP_1, 1
_POS_SEQ        ADD     4, R4                   ; the last access read 4 bytes
                ADDC    0, R5
                RBRA    _LOOP_1, 1
_POS_NEAR       RSUB    RANDOM, 1
                AND     0x3FFC, R8              ; up to 16 kB behind
                ADD     R8, R4
                ADDC    0, R5
_LOOP_1         CMP     FILE_SIZE_HI, R5        ; still in the file?
                RBRA    _LOOP_2, N
                XOR     R4, R4
                XOR     R5, R5

                ; seek both handles and compare 4 bytes with the expected content
_LOOP_2
#ifdef MNT_SIM
                MOVE    FH_FAST, R8             ; like VD_UB_SEEK: sequential
                ADD     FAT32$FDH_ACCESS_LO, R8 ; access needs no seek
                CMP     @R8, R4
                RBRA    _LOOP_2S, !Z
                MOVE    FH_FAST, R8
                ADD     FAT32$FDH_ACCESS_HI, R8
                CMP     @R8, R5
                RBRA    _LOOP_2R, Z
_LOOP_2S
#endif
                MOVE    FH_FAST, R8
                MOVE    R4, R9
                MOVE    R5, R10
                MOVE    2, R11
#ifdef REF_ONLY
                SYSCALL(f32_fseek, 1)
#else
                RSUB    VD_UB_FSEEK, 1
#endif
                CMP     0, R9
                RBRA    ERR_SEEK, !Z
_LOOP_2R        MOVE    FH_REF, R8
                MOVE    R4, R9
                MOVE    R5, R10
                SYSCALL(f32_fseek, 1)
                CMP     0, R9
                RBRA    ERR_SEEK, !Z

                MOVE    R7, R8                  ; every 8th access: write
                AND     0x0007, R8
                RBRA    _WRITE, Z

                XOR     R6, R6                  ; R6: byte 0..3
_CMP_1          MOVE    FH_FAST, R8
                RSUB    FAT32$FILE_RB, 1
                CMP     0, R10
                RBRA    ERR_READ, !Z
                MOVE    R9, R0                  ; R0: fast
                MOVE    FH_REF, R8
                RSUB    FAT32$FILE_RB, 1
                CMP     0, R10
                RBRA    ERR_READ, !Z
                CMP     R0, R9
                RBRA    ERR_DIFF, !Z
                RSUB    EXPECTED, 1             ; R8: expected byte
                CMP     R0, R8
                RBRA    ERR_CONTENT, !Z
                ADD     1, R6
                CMP     4, R6
                RBRA    _CMP_1, !Z
                RBRA    _NEXT, 1

                ; write 4 bytes through FH_FAST, read them through FH_REF
                ; and restore the original content
_WRITE          XOR     R6, R6
_WRITE_1        MOVE    FH_FAST, R8
                MOVE    R6, R9
                ADD     0x00A5, R9
                AND     0x00FF, R9
                RSUB    FAT32$FILE_WB, 1
                CMP     0, R9
                RBRA    ERR_WRITE, !Z
                ADD     1, R6
                CMP     4, R6
                RBRA    _WRITE_1, !Z
                MOVE    FH_REF, R8              ; (flushes the sector of FH_FAST)
                MOVE    R4, R9
                MOVE    R5, R10
                SYSCALL(f32_fseek, 1)
                CMP     0, R9
                RBRA    ERR_SEEK, !Z
                XOR     R6, R6
_WRITE_2        MOVE    FH_REF, R8
                RSUB    FAT32$FILE_RB, 1
                CMP     0, R10
                RBRA    ERR_READ, !Z
                MOVE    R6, R0
                ADD     0x00A5, R0
                AND     0x00FF, R0
                CMP     R0, R9
                RBRA    ERR_WRCHK, !Z
                ADD     1, R6
                CMP     4, R6
                RBRA    _WRITE_2, !Z
                MOVE    FH_FAST, R8             ; restore the content
                MOVE    R4, R9
                MOVE    R5, R10
                MOVE    2, R11
#ifdef REF_ONLY
                SYSCALL(f32_fseek, 1)
#else
                RSUB    VD_UB_FSEEK, 1
#endif
                CMP     0, R9
                RBRA    ERR_SEEK, !Z
                XOR     R6, R6
_WRITE_3        RSUB    EXPECTED, 1
                MOVE    R8, R9
                MOVE    FH_FAST, R8
                RSUB    FAT32$FILE_WB, 1
                CMP     0, R9
                RBRA    ERR_WRITE, !Z
                ADD     1, R6
                CMP     4, R6
                RBRA    _WRITE_3, !Z

_NEXT
#ifdef MNT_SIM
                MOVE    R7, R8                  ; every 16th access (right
                AND     0x000F, R8              ; after a write): write
                RBRA    _NEXT_1, !Z             ; another file through its
                MOVE    FH_FAST, R8             ; own handle (like MNT_SAVE
                RSUB    FAT32$FLUSH, 1          ; with /atarist/stmount); the
                CMP     0, R9                   ; firmware flushes every
                RBRA    ERR_WRITE, !Z           ; hard disk write at once
                RSUB    SIM_SAVE, 1
_NEXT_1
#endif
                SUB     1, R7
                RBRA    _LOOP, !Z

                ; count the recorded checkpoints
_RESULT         MOVE    VD_UB_CP, R0
                ADD     3, R0
                MOVE    VD_UB_CP_ENTRIES, R1
                XOR     R2, R2
_CNT_1          MOVE    @R0++, R3
                OR      @R0++, R3
                RBRA    _CNT_2, Z
                ADD     1, R2
_CNT_2          SUB     1, R1
                RBRA    _CNT_1, !Z
                MOVE    STR_OK, R8
                SYSCALL(puts, 1)
                MOVE    R2, R8
                SYSCALL(puthex, 1)
                MOVE    STR_SHIFT, R8
                SYSCALL(puts, 1)
                MOVE    VD_UB_CP, R8
                ADD     2, R8
                MOVE    @R8, R8
                SYSCALL(puthex, 1)
                MOVE    STR_CONTIG, R8
                SYSCALL(puts, 1)
                MOVE    VD_UB_CP, R8
                ADD     1, R8
                MOVE    @R8, R8
                SYSCALL(puthex, 1)
                SYSCALL(crlf, 1)
                HALT

#ifdef MNT_SIM
; like MNT_SAVE: open HD1.IMG with FH_OTH, write its first 1536 bytes (with
; their original content, (pos * 7 + pos / 512 + 1) & 0xFF) and flush
SIM_SAVE        INCRB
                MOVE    DEVH, R8
                MOVE    FH_OTH, R9
                MOVE    FNAME1, R10
                XOR     R11, R11
                RSUB    FAT32$FILE_OPEN, 1
                CMP     0, R10
                RBRA    ERR_OPEN, !Z
                XOR     R0, R0                  ; R0: position
_SIMS_1         MOVE    R0, R1                  ; pos * 7
                ADD     R1, R1
                ADD     R0, R1
                ADD     R1, R1
                ADD     R0, R1
                MOVE    R0, R2                  ; + pos / 512
                AND     0xFFFB, SR
                SHR     9, R2
                ADD     R2, R1
                ADD     1, R1                   ; + file number
                AND     0x00FF, R1
                MOVE    FH_OTH, R8
                MOVE    R1, R9
                RSUB    FAT32$FILE_WB, 1
                CMP     0, R9
                RBRA    ERR_WRITE, !Z
                ADD     1, R0
                CMP     1536, R0
                RBRA    _SIMS_1, !Z
                MOVE    FH_OTH, R8
                RSUB    FAT32$FLUSH, 1
                CMP     0, R9
                RBRA    ERR_WRITE, !Z
                DECRB
                RET
#endif

; open HD0.IMG into the file handle R9
OPEN_FILE       INCRB
                MOVE    DEVH, R8
                MOVE    FNAME, R10
                XOR     R11, R11
                RSUB    FAT32$FILE_OPEN, 1
                CMP     0, R10
                RBRA    ERR_OPEN, !Z
                DECRB
                RET

; expected byte at position R5|R4 + R6 (registers of the bank of the caller):
; (pos * 7 + pos / 512) & 0xFF, result in R8, R9..R12 are changed
EXPECTED        MOVE    R4, R8
                ADD     R6, R8                  ; low word of pos (+ carry to
                MOVE    R5, R9                  ;  the high word)
                ADDC    0, R9
                MOVE    R8, R10                 ; pos * 7 (low byte only)
                ADD     R10, R10
                ADD     R8, R10
                ADD     R10, R10
                ADD     R8, R10
                MOVE    R8, R11                 ; pos / 512: low byte
                AND     0xFFFB, SR              ; clear C (SHR fills with C)
                SHR     9, R11
                MOVE    R9, R12
                AND     0xFFFD, SR              ; clear X (SHL fills with X)
                SHL     7, R12
                OR      R12, R11
                ADD     R11, R10
                AND     0x00FF, R10
                MOVE    R10, R8
                RET

; R8 = R8 mod R9 (16 bit, unsigned)
MOD16           INCRB
                MOVE    R9, R0
_MOD16_1        CMP     R0, R8
                RBRA    _MOD16_2, N             ; R8 < R0: done
                SUB     R0, R8
                RBRA    _MOD16_1, 1
_MOD16_2        DECRB
                RET

; R9|R8: two 16 bit xorshift generators
RANDOM          INCRB
                MOVE    RND_LO_S, R0
                RSUB    _XORSHIFT, 1
                MOVE    R1, R8
                MOVE    RND_HI_S, R0
                RSUB    _XORSHIFT, 1
                MOVE    R1, R9
                DECRB
                RET
_XORSHIFT       MOVE    @R0, R1                 ; x ^= x << 7
                MOVE    R1, R2
                AND     0xFFFD, SR              ; clear X (SHL fills with X)
                SHL     7, R2
                XOR     R2, R1
                MOVE    R1, R2                  ; x ^= x >> 9
                AND     0xFFFB, SR              ; clear C (SHR fills with C)
                SHR     9, R2
                XOR     R2, R1
                MOVE    R1, R2                  ; x ^= x << 8
                AND     0xFFFD, SR              ; clear X (SHL fills with X)
                SHL     8, R2
                XOR     R2, R1
                MOVE    R1, @R0
                RET

ERR_MOUNT       MOVE    STR_MOUNT, R8
                RBRA    ERR_END, 1
ERR_OPEN        MOVE    STR_OPEN, R8
                RBRA    ERR_END, 1
ERR_SEEK        MOVE    STR_SEEK, R8
                RBRA    ERR_END, 1
ERR_READ        MOVE    STR_READ, R8
                RBRA    ERR_END, 1
ERR_WRITE       MOVE    STR_WRITE, R8
                RBRA    ERR_END, 1
ERR_WRCHK       MOVE    STR_WRCHK, R8
                RBRA    ERR_END, 1
ERR_DIFF        MOVE    STR_DIFF, R8
                RBRA    ERR_END, 1
ERR_CONTENT     MOVE    STR_CONTENT, R8
ERR_END         SYSCALL(puts, 1)
                MOVE    STR_AT, R8
                SYSCALL(puts, 1)
                MOVE    R5, R8
                SYSCALL(puthex, 1)
                MOVE    R4, R8
                SYSCALL(puthex, 1)
                MOVE    STR_ITER, R8
                SYSCALL(puts, 1)
                MOVE    R7, R8
                SYSCALL(puthex, 1)
                SYSCALL(crlf, 1)
                HALT

STR_START       .ASCII_W "Fast seek test: HD0.IMG, 6 MB"
STR_OK          .ASCII_W "OK: all positions read and written correctly, checkpoints: "
STR_SHIFT       .ASCII_W ", shift: "
STR_CONTIG      .ASCII_W ", contiguous: "
STR_MOUNT       .ASCII_W "FAIL: mount"
STR_OPEN        .ASCII_W "FAIL: open"
STR_SEEK        .ASCII_W "FAIL: seek error"
STR_READ        .ASCII_W "FAIL: read error"
STR_WRITE       .ASCII_W "FAIL: write error"
STR_WRCHK       .ASCII_W "FAIL: written bytes not read back"
STR_DIFF        .ASCII_W "FAIL: fast seek and f32_fseek read different bytes"
STR_CONTENT     .ASCII_W "FAIL: wrong file content"
STR_AT          .ASCII_W " at position "
STR_ITER        .ASCII_W ", iterations left: "
FNAME           .ASCII_W "HD0.IMG"
FNAME1          .ASCII_W "HD1.IMG"

#include "../../../M2M/rom/vd_fastseek.asm"

; ----------------------------------------------------------------------------
; Variables
; ----------------------------------------------------------------------------

                .ORG    0x8000

VD_UB_CP_SLOTS  .EQU    2                       ; like shell_vars.asm
VD_UB_CP_ENTRIES .EQU   512
VD_UB_CP_SLOTSZ .EQU    1027
VD_UB_CP        .BLOCK  2054
VD_UB_NOFDH     .BLOCK  FAT32$FDH_STRUCT_SIZE

DEVH            .BLOCK  FAT32$DEV_STRUCT_SIZE
FH_FAST         .BLOCK  FAT32$FDH_STRUCT_SIZE
FH_REF          .BLOCK  FAT32$FDH_STRUCT_SIZE
FH_OTH          .BLOCK  FAT32$FDH_STRUCT_SIZE
RND_LO_S        .BLOCK  1
RND_HI_S        .BLOCK  1

                .ORG    0xFEE0
#include "../../../M2M/rom/main_vars.asm"
