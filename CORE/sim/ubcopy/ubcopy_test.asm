; ****************************************************************************
; MegaST: test of the sector-wise transfer for unbuffered virtual drives
; (M2M/rom/vd_ubcopy.asm) in the QNICE emulator, see run.sh
;
; HD0.IMG is opened twice: FH_A is read and written with VD_UB_RDATA and
; VD_UB_WDATA (drive buffer = VD_UBC_SIMBUF), FH_REF only byte by byte with the FAT32
; library. HD1.IMG (FH_OTH) is read in between, so that FH_A loses the buffer
; of the SD controller between two requests. Every byte of HD0.IMG is
; (pos * 7 + pos / 512) & 0xFF (make_fat32.py).
;
; Each iteration: a position (random, unaligned every 3rd time, or right
; behind the previous request without a seek, like VD_UB_SEEK) and a length
; (512, 1024, 1536 or random 1 .. 1023), then
;   * VD_UB_RDATA, every byte compared with the file content (behind the end
;     of the file: 0)
;   * every 4th time: VD_UB_WDATA of the content XOR 0xA5, flush, read back
;     through FH_REF, then the original content written back the same way
;
; SPEED defined: only 256 KB read and 256 KB written in 512 byte requests
; (SLOW defined: with the old byte loop of shell.asm), to compare the number
; of executed QNICE instructions
;
; This machine is based on AtariST_MiSTer
; Powered by MiSTer2MEGA65
; MEGA65 port done by Chris Freeman in 2026 and licensed under GPL v3
; ****************************************************************************

#define RELEASE
#define VD_UBC_SIM
#include "../../../M2M/rom/main.asm"

ITERATIONS      .EQU    300
FILE_SIZE_HI    .EQU    0x0060                  ; 6 MB = 0x00600000
FILE_LAST_HI    .EQU    0x005F

START_FIRMWARE  MOVE    STR_START, R8
                SYSCALL(puts, 1)
                SYSCALL(crlf, 1)

                MOVE    DEVH, R8                ; mount partition 1
                MOVE    1, R9
                RSUB    FAT32$MOUNT_SD, 1
                CMP     0, R9
                RBRA    ERR_MOUNT, !Z

                MOVE    FH_A, R9                ; HD0.IMG twice, HD1.IMG
                MOVE    FNAME, R10
                RSUB    OPEN_FILE, 1
                MOVE    FH_REF, R9
                MOVE    FNAME, R10
                RSUB    OPEN_FILE, 1
                MOVE    FH_OTH, R9
                MOVE    FNAME1, R10
                RSUB    OPEN_FILE, 1

                XOR     R4, R4                  ; R5|R4: position
                XOR     R5, R5
                XOR     R7, R7

#ifdef SPEED
                ; 512 requests of 512 bytes from position 0: read, then write
                MOVE    512, R7
_SPD_R          MOVE    FH_A, R8
                MOVE    512, R9
#ifdef SLOW
                RSUB    SLOW_RDATA, 1
#else
                RSUB    VD_UB_RDATA, 1
#endif
                SUB     1, R7
                RBRA    _SPD_R, !Z
                MOVE    VD_UBC_SIMBUF, R8              ; the last request: check
                MOVE    0x0003, R5              ; (position 0x3FE00)
                MOVE    0xFE00, R4
                MOVE    512, R6
                RSUB    CHECK_BUF, 1
                MOVE    FH_A, R8                ; write the same 256 KB back
                XOR     R9, R9
                XOR     R10, R10
                SYSCALL(f32_fseek, 1)
                CMP     0, R9
                RBRA    ERR_SEEK, !Z
                XOR     R4, R4
                XOR     R5, R5
                MOVE    512, R7
_SPD_W          MOVE    512, R6                 ; content of this request
                RSUB    FILL_BUF, 1
                MOVE    FH_A, R8
                MOVE    512, R9
#ifdef SLOW
                RSUB    SLOW_WDATA, 1
#else
                MOVE    0, R10
                RSUB    VD_UB_WDATA, 1
#endif
                CMP     0, R9
                RBRA    ERR_WRITE, !Z
                MOVE    FH_A, R8                ; like VD_UB_WRITE
                SYSCALL(f32_fflush, 1)
                ADD     512, R4
                ADDC    0, R5
                SUB     1, R7
                RBRA    _SPD_W, !Z
                RBRA    _RESULT, 1
#endif

                MOVE    RND_LO_S, R8            ; seeds (RND_HI_S follows)
                MOVE    0xACE1, @R8++
                MOVE    0x1234, @R8
                MOVE    ITERATIONS, R7          ; R7: iterations left

                ; next position
_LOOP           MOVE    R7, R8
                AND     0x0003, R8
                RBRA    _POS_SEQ, Z             ; every 4th: sequential
                RSUB    RANDOM, 1               ; R9|R8: random
                MOVE    R8, R4
                MOVE    R7, R10                 ; every 3rd: unaligned
                MOVE    3, R11
                RSUB    MOD16, 1
                CMP     0, R11
                RBRA    _POS_1, Z
                AND     0xFE00, R4              ; otherwise sector aligned
_POS_1          MOVE    R9, R5
                AND     0x007F, R5
                CMP     FILE_SIZE_HI, R5        ; hi < 0x60?
                RBRA    _POS_2, N
                SUB     0x0020, R5              ; no: 2 MB lower
_POS_2          MOVE    R7, R8                  ; every 16th: near the end
                AND     0x000F, R8
                CMP     0x0005, R8
                RBRA    _POS_3, !Z
                MOVE    FILE_SIZE_HI, R5        ; 0x5FFFxx
                SUB     1, R5
                MOVE    R4, R8
                AND     0x01FF, R8
                MOVE    0xFE00, R4
                ADD     R8, R4
_POS_3          MOVE    FH_A, R8                ; seek FH_A
                MOVE    R4, R9
                MOVE    R5, R10
                SYSCALL(f32_fseek, 1)
                CMP     0, R9
                RBRA    ERR_SEEK, !Z
                RBRA    _LEN, 1
_POS_SEQ        MOVE    R4, R8                  ; behind the previous request
                ADD     R6, R4
                ADDC    0, R5
                MOVE    FH_A, R8                ; (still in the file?)
                ADD     FAT32$FDH_ACCESS_LO, R8
                CMP     @R8, R4
                RBRA    _POS_SEQ1, !Z
                MOVE    FH_A, R8
                ADD     FAT32$FDH_ACCESS_HI, R8
                CMP     @R8, R5
                RBRA    _LEN, Z
_POS_SEQ1       XOR     R4, R4                  ; behind the end: restart
                XOR     R5, R5
                RBRA    _POS_3, 1

                ; length
_LEN            MOVE    R7, R8
                AND     0x0003, R8
                MOVE    LENGTHS, R9
                ADD     R8, R9
                MOVE    @R9, R6                 ; R6: length
                CMP     0, R6
                RBRA    _LEN_1, !Z
                RSUB    RANDOM, 1               ; random 1 .. 1023
                MOVE    R8, R6
                AND     0x03FF, R6
                ADD     1, R6

                ; steal the SD buffer every other time
_LEN_1          MOVE    R7, R8
                AND     0x0001, R8
                RBRA    _READ, Z
                MOVE    FH_OTH, R8
                SYSCALL(f32_fread, 1)
                CMP     0, R10
                RBRA    ERR_READ, !Z

                ; read and check
_READ           MOVE    FH_A, R8
                MOVE    R6, R9
                RSUB    VD_UB_RDATA, 1
                MOVE    VD_UBC_SIMBUF, R8
                RSUB    CHECK_BUF, 1

                ; every 4th: write XOR 0xA5, check, write back, check
                MOVE    R7, R8
                AND     0x0003, R8
                CMP     0x0002, R8
                RBRA    _NEXT, !Z
                MOVE    0x00A5, R8
                RSUB    WRITE_CHECK, 1
                XOR     R8, R8
                RSUB    WRITE_CHECK, 1
                MOVE    FH_A, R8                ; FH_A: continue behind it
                MOVE    R4, R9
                ADD     R6, R9
                MOVE    R5, R10
                ADDC    0, R10
                SYSCALL(f32_fseek, 1)

_NEXT           SUB     1, R7
                RBRA    _LOOP, !Z

_RESULT         MOVE    STR_OK, R8
                SYSCALL(puts, 1)
                SYSCALL(crlf, 1)
                HALT

; write R6 bytes at position R5|R4 through FH_A: content XOR R8, flush, read
; back through FH_REF and check (bytes behind the end of the file are not
; written by VD_UB_WDATA: FILE_WB cannot append)
WRITE_CHECK     MOVE    WR_XOR, R9              ; remember the XOR value
                MOVE    R8, @R9
                MOVE    R6, R0                  ; R0: original length
                RSUB    IN_FILE, 1              ; R3: bytes in the file
                MOVE    R8, R3
                CMP     0, R3
                RBRA    _WRC_RET, Z
                MOVE    R3, R6
                RSUB    FILL_BUF, 1
                MOVE    VD_UBC_SIMBUF, R8              ; XOR
                MOVE    R3, R9
                MOVE    WR_XOR, R10
_WRC_1          XOR     @R10, @R8++
                SUB     1, R9
                RBRA    _WRC_1, !Z
                MOVE    FH_A, R8
                MOVE    R4, R9
                MOVE    R5, R10
                SYSCALL(f32_fseek, 1)
                CMP     0, R9
                RBRA    ERR_SEEK, !Z
                MOVE    FH_A, R8
                MOVE    R3, R9
                MOVE    0, R10
                RSUB    VD_UB_WDATA, 1
                CMP     0, R9
                RBRA    ERR_WRITE, !Z
                MOVE    FH_A, R8                ; like VD_UB_WRITE
                SYSCALL(f32_fflush, 1)
                CMP     0, R9
                RBRA    ERR_WRITE, !Z
                MOVE    FH_REF, R8              ; read back
                MOVE    R4, R9
                MOVE    R5, R10
                SYSCALL(f32_fseek, 1)
                CMP     0, R9
                RBRA    ERR_SEEK, !Z
                XOR     R1, R1                  ; R1: offset
_WRC_2          MOVE    FH_REF, R8
                SYSCALL(f32_fread, 1)
                CMP     0, R10
                RBRA    ERR_READ, !Z
                MOVE    R9, R2                  ; R2: byte read back
                MOVE    R1, R8
                RSUB    EXPECTED, 1
                MOVE    WR_XOR, R9
                XOR     @R9, R8
                CMP     R8, R2
                RBRA    ERR_WRCHK, !Z
                ADD     1, R1
                CMP     R1, R3
                RBRA    _WRC_2, !Z
_WRC_RET        MOVE    R0, R6
                RET

; R8 = how many of the R6 bytes at R5|R4 are in the file
IN_FILE         MOVE    R6, R8
                CMP     FILE_LAST_HI, R5
                RBRA    _INF_RET, !Z            ; not in the last 64 KB
                MOVE    R4, R9                  ; rest = 0x10000 - R4
                XOR     R10, R10
                SUB     R9, R10
                CMP     0, R4
                RBRA    _INF_RET, Z             ; rest is 64 KB
                CMP     R8, R10                 ; R6 > rest?
                RBRA    _INF_RET, !N
                MOVE    R10, R8
_INF_RET        RET

; compare R6 words at R8 with the content at position R5|R4 (0 behind the
; end of the file)
CHECK_BUF       MOVE    R8, R2
                XOR     R1, R1                  ; R1: offset
_CHK_1          MOVE    R1, R8
                RSUB    EXPECTED, 1
                CMP     @R2++, R8
                RBRA    ERR_CONTENT, !Z
                ADD     1, R1
                CMP     R1, R6
                RBRA    _CHK_1, !Z
                RET

; fill VD_UBC_SIMBUF with the content of R6 bytes at R5|R4
FILL_BUF        MOVE    VD_UBC_SIMBUF, R2
                XOR     R1, R1
_FILL_1         MOVE    R1, R8
                RSUB    EXPECTED, 1
                MOVE    R8, @R2++
                ADD     1, R1
                CMP     R1, R6
                RBRA    _FILL_1, !Z
                RET

; content at position R5|R4 + R8: (pos * 7 + pos / 512) & 0xFF, 0 behind
; the end of the file; result in R8, R9..R12 are changed
EXPECTED        MOVE    R4, R9                  ; R10|R9: pos
                ADD     R8, R9
                MOVE    R5, R10
                ADDC    0, R10
                CMP     FILE_SIZE_HI, R10
                RBRA    _EXP_1, N               ; hi < FILE_SIZE_HI
                XOR     R8, R8
                RET
_EXP_1          MOVE    R9, R11                 ; pos * 7 (low byte only)
                ADD     R11, R11
                ADD     R9, R11
                ADD     R11, R11
                ADD     R9, R11
                MOVE    R9, R12                 ; pos / 512: low byte
                AND     0xFFFB, SR              ; clear C (SHR fills with C)
                SHR     9, R12
                AND     0xFFFD, SR              ; clear X (SHL fills with X)
                SHL     7, R10
                OR      R10, R12
                ADD     R12, R11
                AND     0x00FF, R11
                MOVE    R11, R8
                RET

; open the file R10 into the file handle R9
OPEN_FILE       INCRB
                MOVE    DEVH, R8
                XOR     R11, R11
                RSUB    FAT32$FILE_OPEN, 1
                CMP     0, R10
                RBRA    ERR_OPEN, !Z
                DECRB
                RET

; R11 = R10 mod R11 (16 bit, unsigned)
MOD16           INCRB
                MOVE    R11, R0
_MOD16_1        CMP     R0, R10
                RBRA    _MOD16_2, N             ; R10 < R0: done
                SUB     R0, R10
                RBRA    _MOD16_1, 1
_MOD16_2        MOVE    R10, R11
                DECRB
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
                AND     0xFFFD, SR
                SHL     7, R2
                XOR     R2, R1
                MOVE    R1, R2                  ; x ^= x >> 9
                AND     0xFFFB, SR
                SHR     9, R2
                XOR     R2, R1
                MOVE    R1, R2                  ; x ^= x << 8
                AND     0xFFFD, SR
                SHL     8, R2
                XOR     R2, R1
                MOVE    R1, @R0
                RET

#ifdef SLOW
; the old byte loops of VD_UB_READ / VD_UB_WRITE (shell.asm up to 1.6-test6),
; with the four vdrives calls per byte replaced by calls of the same length
SLOW_RDATA      INCRB
                MOVE    R8, R1
                MOVE    R9, R2
                XOR     R3, R3
_SLR_LOOP       CMP     R3, R2
                RBRA    _SLR_RET, Z
                MOVE    R1, R8
                SYSCALL(f32_fread, 1)
                CMP     0, R10
                RBRA    _SLR_1, Z
                XOR     R9, R9
_SLR_1          MOVE    R9, R4
                MOVE    VD_UBC_SIMBUF, R8
                ADD     R3, R8
                MOVE    R4, @R8
                MOVE    VD_B_ADDR, R8
                MOVE    R3, R9
                RSUB    DUMMY_CAD, 1
                MOVE    VD_B_DOUT, R8
                MOVE    R4, R9
                RSUB    DUMMY_CAD, 1
                MOVE    VD_B_WREN, R8
                MOVE    1, R9
                RSUB    DUMMY_CAD, 1
                XOR     R9, R9
                RSUB    DUMMY_CAD, 1
                ADD     1, R3
                RBRA    _SLR_LOOP, 1
_SLR_RET        DECRB
                RET

SLOW_WDATA      INCRB
                MOVE    R8, R1
                MOVE    R9, R2
                XOR     R3, R3
_SLW_LOOP       XOR     R9, R9
                CMP     R3, R2
                RBRA    _SLW_RET, Z
                MOVE    VD_B_ADDR, R8
                MOVE    R3, R9
                RSUB    DUMMY_CAD, 1
                MOVE    0, R8
                MOVE    VD_B_DIN, R9
                RSUB    DUMMY_CAD, 1
                MOVE    VD_UBC_SIMBUF, R8
                ADD     R3, R8
                MOVE    @R8, R9
                MOVE    R1, R8
                SYSCALL(f32_fwrite, 1)
                CMP     0, R9
                RBRA    _SLW_RET, !Z
                ADD     1, R3
                RBRA    _SLW_LOOP, 1
_SLW_RET        DECRB
                RET

; as long as VD_CAD_WRITE / VD_DRV_READ (vdrives.asm), without the device
DUMMY_CAD       INCRB
                MOVE    DUMMY_VAR, R0
                MOVE    DUMMY_VAR, R1
                MOVE    @R1, @R0
                MOVE    DUMMY_VAR, R0
                MOVE    VD_WIN_CAD, @R0
                MOVE    DUMMY_VAR, R0
                DECRB
                RET
#endif

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
ERR_CONTENT     MOVE    STR_CONTENT, R8
ERR_END         SYSCALL(puts, 1)
                MOVE    STR_AT, R8
                SYSCALL(puts, 1)
                MOVE    R5, R8
                SYSCALL(puthex, 1)
                MOVE    R4, R8
                SYSCALL(puthex, 1)
                MOVE    STR_OFS, R8
                SYSCALL(puts, 1)
                MOVE    R1, R8
                SYSCALL(puthex, 1)
                MOVE    STR_LEN, R8
                SYSCALL(puts, 1)
                MOVE    R6, R8
                SYSCALL(puthex, 1)
                MOVE    STR_ITER, R8
                SYSCALL(puts, 1)
                MOVE    R7, R8
                SYSCALL(puthex, 1)
                SYSCALL(crlf, 1)
                HALT

LENGTHS         .DW     512, 0, 1024, 1536
STR_START       .ASCII_W "Sector-wise transfer test: HD0.IMG, 6 MB"
STR_OK          .ASCII_W "OK: all requests read and written correctly"
STR_MOUNT       .ASCII_W "FAIL: mount"
STR_OPEN        .ASCII_W "FAIL: open"
STR_SEEK        .ASCII_W "FAIL: seek error"
STR_READ        .ASCII_W "FAIL: read error"
STR_WRITE       .ASCII_W "FAIL: write error"
STR_WRCHK       .ASCII_W "FAIL: written bytes not read back"
STR_CONTENT     .ASCII_W "FAIL: wrong content"
STR_AT          .ASCII_W " at position "
STR_OFS         .ASCII_W ", offset "
STR_LEN         .ASCII_W ", length "
STR_ITER        .ASCII_W ", iterations left: "
FNAME           .ASCII_W "HD0.IMG"
FNAME1          .ASCII_W "HD1.IMG"

#include "../../../M2M/rom/vd_ubcopy.asm"

; ----------------------------------------------------------------------------
; Variables
; ----------------------------------------------------------------------------

                .ORG    0x8000

DEVH            .BLOCK  FAT32$DEV_STRUCT_SIZE
FH_A            .BLOCK  FAT32$FDH_STRUCT_SIZE
FH_REF          .BLOCK  FAT32$FDH_STRUCT_SIZE
FH_OTH          .BLOCK  FAT32$FDH_STRUCT_SIZE
RND_LO_S        .BLOCK  1
RND_HI_S        .BLOCK  1
DUMMY_VAR       .BLOCK  1
WR_XOR          .BLOCK  1
VD_UBC_SIMBUF   .BLOCK  1536                    ; drive buffer (vd_ubcopy.asm)

                .ORG    0xFEE0
#include "../../../M2M/rom/main_vars.asm"
