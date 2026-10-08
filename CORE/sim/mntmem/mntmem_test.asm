; ****************************************************************************
; MegaST: test of remembering the mounted images (M2M/rom/mntmem.asm) in the
; QNICE emulator, see run.sh
;
; Runs the real mntmem.asm and the real FAT32 library on an SD card image
; (make_sd.py); the rest of the shell (LOAD_IMAGE, the vdrives, the screen)
; is replaced by stubs that log what they are asked to do. LOAD_IMAGE opens
; the file like the real one, so the paths have to be right.
;
; EXPECT_ON=1: /atarist/stmount is valid (all 0x00 or all 0xFF): full test
; EXPECT_ON=0: the file is missing or has the wrong size: feature off
;
; This machine is based on AtariST_MiSTer
; Powered by MiSTer2MEGA65
; MEGA65 port done by Chris Freeman in 2026 and licensed under GPL v3
; ****************************************************************************

#define RELEASE
#include "../../../M2M/rom/main.asm"

VDRIVES_MAX     .EQU    4                       ; like globals.asm of MegaST
CRTROM_MAN_MAX  .EQU    2
MNT_ENTRIES     .EQU    6
MNT_BUF_SIZE    .EQU    1536
LOG_PATH_SZ     .EQU    64

START_FIRMWARE  MOVE    STR_START, R8
                SYSCALL(puts, 1)

                MOVE    FAILS, R0
                MOVE    0, @R0
                MOVE    VDRIVES_NUM, R0
                MOVE    4, @R0
                MOVE    CRTROM_MAN_NUM, R0
                MOVE    2, @R0
                MOVE    OPTM_SCOUNT, R0
                MOVE    1, @R0
                MOVE    SCR$OSM_O_DX, R0
                MOVE    20, @R0
                MOVE    OPTM_HEAP, R0
                MOVE    OSM_BUF, @R0
                MOVE    HANDLE_DEV, R0
                MOVE    0, @R0
                MOVE    SF_CONTEXT, R0
                MOVE    0, @R0
                MOVE    M2M$CSR, R8             ; the SD card "at startup"
                MOVE    @R8, R8
                AND     M2M$CSR_SD_ACTIVE, R8
                MOVE    INITIAL_SD, R0
                MOVE    R8, @R0
                MOVE    STR_CFGFILE, R8         ; MNT_FILE as config.vhd
                MOVE    M2M$RAMROM_DATA, R9     ; would deliver it
                SYSCALL(strcpy, 1)
                RSUB    CLEAR_LOG, 1
                MOVE    OSM_BUF, R8             ; "untouched" marker
                MOVE    200, R9
                MOVE    0x5555, R10
                SYSCALL(memset, 1)

                ; ------------------------------------------------------------
                ; Path tracking of the file browser
                ; ------------------------------------------------------------

                MOVE    P_ATARIST, R8
                RSUB    FBP_SET, 1
                MOVE    P_GAMES_REL, R8
                RSUB    FBP_CD, 1
                MOVE    P_GAMES, R9
                MOVE    T_CD_DOWN, R10
                RSUB    CHECK_FBP, 1

                MOVE    FN_UPDIR, R8
                RSUB    FBP_CD, 1
                MOVE    P_ATARIST, R9
                MOVE    T_CD_UP, R10
                RSUB    CHECK_FBP, 1

                MOVE    FN_UPDIR, R8
                RSUB    FBP_CD, 1
                MOVE    FN_ROOT_DIR, R9
                MOVE    T_CD_UP_ROOT, R10
                RSUB    CHECK_FBP, 1

                MOVE    P_GAMES_REL, R8         ; from the root: no "//"
                RSUB    FBP_CD, 1
                MOVE    P_ROOT_GAMES, R9
                MOVE    T_CD_ROOT_DOWN, R10
                RSUB    CHECK_FBP, 1

                MOVE    FBP_DOT, R8
                RSUB    FBP_CD, 1
                MOVE    P_ROOT_GAMES, R9
                MOVE    T_CD_DOT, R10
                RSUB    CHECK_FBP, 1

                MOVE    FN_ROOT_DIR, R8         ; ".." in the root stays
                RSUB    FBP_SET, 1
                MOVE    FN_UPDIR, R8
                RSUB    FBP_CD, 1
                MOVE    FN_ROOT_DIR, R9
                MOVE    T_CD_UP_IN_ROOT, R10
                RSUB    CHECK_FBP, 1

                RSUB    MAKE_LONG, 1            ; 299 characters: too long
                MOVE    LONGBUF, R8
                RSUB    FBP_SET, 1
                MOVE    FB_PATH, R8
                MOVE    @R8, R8
                XOR     R9, R9
                MOVE    T_TOO_LONG, R10
                RSUB    CHECK_EQ, 1
                MOVE    P_GAMES_REL, R8         ; unknown stays unknown
                RSUB    FBP_CD, 1
                MOVE    FB_PATH, R8
                MOVE    @R8, R8
                XOR     R9, R9
                MOVE    T_UNKNOWN_CD, R10
                RSUB    CHECK_EQ, 1

                MOVE    LONGBUF, R8             ; 250 + "/" + 10 > 255
                ADD     250, R8
                MOVE    0, @R8
                MOVE    LONGBUF, R8
                RSUB    FBP_SET, 1
                MOVE    P_TEN, R8
                RSUB    FBP_CD, 1
                MOVE    FB_PATH, R8
                MOVE    @R8, R8
                XOR     R9, R9
                MOVE    T_CD_TOO_LONG, R10
                RSUB    CHECK_EQ, 1

                ; ------------------------------------------------------------
                ; Startup with the file as it is on the SD card
                ; ------------------------------------------------------------

                RSUB    MNT_RESTORE, 1
                MOVE    MNT_ON, R8
                MOVE    @R8, R8
                MOVE    EXPECT_ON, R9
                MOVE    T_ON, R10
                RSUB    CHECK_EQ, 1
                MOVE    LOADS, R8
                MOVE    @R8, R8
                XOR     R9, R9
                MOVE    T_NOTHING, R10
                RSUB    CHECK_EQ, 1
#if EXPECT_ON == 0
                MOVE    P_GAMES, R8             ; off: nothing is remembered
                RSUB    FBP_SET, 1
                XOR     R8, R8
                XOR     R9, R9
                MOVE    N_DISK1, R10
                RSUB    MNT_REMEMBER, 1
                MOVE    MNT_DIRTY, R8
                MOVE    @R8, R8
                XOR     R9, R9
                MOVE    T_OFF_CLEAN, R10
                RSUB    CHECK_EQ, 1
                RBRA    RESULT, 1
#endif

                ; ------------------------------------------------------------
                ; Remember four images and save them
                ; ------------------------------------------------------------

                MOVE    P_GAMES, R8             ; vdrive 0
                RSUB    FBP_SET, 1
                XOR     R8, R8
                XOR     R9, R9
                MOVE    N_DISK1, R10
                RSUB    MNT_REMEMBER, 1
                MOVE    MNT_PATHS, R8
                MOVE    F_DISK1, R9
                MOVE    T_REM_PATH, R10
                RSUB    CHECK_STR, 1

                MOVE    P_TOS, R8               ; CRT/ROM 1 (TOS)
                RSUB    FBP_SET, 1
                MOVE    1, R8
                MOVE    1, R9
                MOVE    N_TOS, R10
                RSUB    MNT_REMEMBER, 1
                MOVE    MNT_PATHS, R8           ; entry 4 + 1
                ADD     1280, R8
                MOVE    F_TOS, R9
                MOVE    T_REM_ROM, R10
                RSUB    CHECK_STR, 1

                MOVE    P_LONG, R8              ; vdrive 2: long names
                RSUB    FBP_SET, 1
                MOVE    2, R8
                XOR     R9, R9
                MOVE    N_LONG, R10
                RSUB    MNT_REMEMBER, 1

                MOVE    P_ATARIST, R8           ; vdrive 3: LOAD_IMAGE fails
                RSUB    FBP_SET, 1
                MOVE    3, R8
                XOR     R9, R9
                MOVE    N_BAD, R10
                RSUB    MNT_REMEMBER, 1

                MOVE    MNT_DIRTY, R8
                MOVE    @R8, R8
                MOVE    1, R9
                MOVE    T_DIRTY, R10
                RSUB    CHECK_EQ, 1
                RSUB    MNT_SAVE, 1
                MOVE    MNT_DIRTY, R8
                MOVE    @R8, R8
                XOR     R9, R9
                MOVE    T_SAVED, R10
                RSUB    CHECK_EQ, 1

                ; ------------------------------------------------------------
                ; "Power cycle": restore from the SD card
                ; ------------------------------------------------------------

                RSUB    CLEAR_LOG, 1
                RSUB    MNT_RESTORE, 1
                MOVE    LOADS, R8               ; TOS, vdrive 0, 2, 3
                MOVE    @R8, R8
                MOVE    4, R9
                MOVE    T_LOADS4, R10
                RSUB    CHECK_EQ, 1

                MOVE    LOG_PATHS, R8           ; CRTs/ROMs first
                MOVE    F_TOS, R9
                MOVE    T_LOAD0, R10
                RSUB    CHECK_STR, 1
                MOVE    LOG_MODE, R8
                MOVE    @R8, R8
                MOVE    1, R9
                MOVE    T_LOAD0_MODE, R10
                RSUB    CHECK_EQ, 1
                MOVE    LOG_ID, R8
                MOVE    @R8, R8
                MOVE    1, R9
                MOVE    T_LOAD0_ID, R10
                RSUB    CHECK_EQ, 1
                MOVE    LOG_PATHS, R8
                ADD     LOG_PATH_SZ, R8
                MOVE    F_DISK1, R9
                MOVE    T_LOAD1, R10
                RSUB    CHECK_STR, 1
                MOVE    LOG_PATHS, R8
                ADD     128, R8
                MOVE    F_LONG, R9
                MOVE    T_LOAD2, R10
                RSUB    CHECK_STR, 1

                MOVE    STROBES, R8             ; vdrive 0 and 2, not 3
                MOVE    @R8, R8
                MOVE    2, R9
                MOVE    T_STROBES, R10
                RSUB    CHECK_EQ, 1
                MOVE    STROBE_ID, R8
                MOVE    @R8, R8
                XOR     R9, R9
                MOVE    T_STROBE0_ID, R10
                RSUB    CHECK_EQ, 1
                MOVE    STROBE_LO, R8
                MOVE    @R8, R8
                MOVE    5000, R9
                MOVE    T_STROBE0_SZ, R10
                RSUB    CHECK_EQ, 1
                MOVE    STROBE_ID, R8
                ADD     1, R8
                MOVE    @R8, R8
                MOVE    2, R9
                MOVE    T_STROBE1_ID, R10
                RSUB    CHECK_EQ, 1
                MOVE    STROBE_LO, R8
                ADD     1, R8
                MOVE    @R8, R8
                MOVE    3000, R9
                MOVE    T_STROBE1_SZ, R10
                RSUB    CHECK_EQ, 1

                MOVE    MNT_PATHS, R8           ; the bad image is forgotten
                ADD     768, R8
                MOVE    @R8, R8
                XOR     R9, R9
                MOVE    T_BAD_GONE, R10
                RSUB    CHECK_EQ, 1
                MOVE    MNT_DIRTY, R8
                MOVE    @R8, R8
                MOVE    1, R9
                MOVE    T_BAD_DIRTY, R10
                RSUB    CHECK_EQ, 1
                MOVE    SF_CONTEXT, R8
                MOVE    @R8, R8
                XOR     R9, R9
                MOVE    T_CTX, R10
                RSUB    CHECK_EQ, 1

                ; file names for the menu
                RSUB    MNT_OSM_NAMES, 1
                MOVE    OSM_BUF, R8
                MOVE    N_DISK1, R9
                MOVE    T_OSM0, R10
                RSUB    CHECK_STR, 1
                MOVE    OSM_BUF, R8             ; vdrive 2: 18 + 1 characters
                ADD     40, R8                  ; (ellipsis trigger)
                MOVE    N_LONG19, R9
                MOVE    T_OSM2, R10
                RSUB    CHECK_STR, 1
                MOVE    OSM_BUF, R8             ; (4 vdrives + 1 submenu + 1)
                ADD     120, R8                 ; * 20
                MOVE    N_TOS, R9
                MOVE    T_OSM_ROM, R10
                RSUB    CHECK_STR, 1
                MOVE    OSM_BUF, R8             ; "%s replaced" flag
                ADD     19, R8
                MOVE    @R8, R8
                XOR     R9, R9
                MOVE    T_OSM_FLAG, R10
                RSUB    CHECK_EQ, 1
                MOVE    OSM_BUF, R8             ; vdrive 1: nothing written
                ADD     20, R8
                MOVE    @R8, R8
                MOVE    0x5555, R9
                MOVE    T_OSM_EMPTY, R10
                RSUB    CHECK_EQ, 1
                MOVE    OSM_BUF, R8             ; pending names are done
                MOVE    40, R9
                MOVE    0x5555, R10
                SYSCALL(memset, 1)
                RSUB    MNT_OSM_NAMES, 1
                MOVE    OSM_BUF, R8
                MOVE    @R8, R8
                MOVE    0x5555, R9
                MOVE    T_OSM_ONCE, R10
                RSUB    CHECK_EQ, 1

                ; ------------------------------------------------------------
                ; Unmount, a missing image and an unknown path
                ; ------------------------------------------------------------

                XOR     R8, R8                  ; unmount vdrive 0
                XOR     R9, R9
                RSUB    MNT_FORGET, 1
                MOVE    P_NOPE, R8              ; vdrive 1: file missing
                RSUB    FBP_SET, 1
                MOVE    1, R8
                XOR     R9, R9
                MOVE    N_X, R10
                RSUB    MNT_REMEMBER, 1
                RSUB    MNT_SAVE, 1
                RSUB    CLEAR_LOG, 1
                RSUB    MNT_RESTORE, 1
                MOVE    LOADS, R8               ; TOS and vdrive 2
                MOVE    @R8, R8
                MOVE    2, R9
                MOVE    T_LOADS2, R10
                RSUB    CHECK_EQ, 1
                MOVE    MNT_PATHS, R8           ; the missing one is kept
                ADD     256, R8
                MOVE    F_NOPE, R9
                MOVE    T_MISSING_KEPT, R10
                RSUB    CHECK_STR, 1
                MOVE    MNT_PATHS, R8           ; vdrive 0 is empty
                MOVE    @R8, R8
                XOR     R9, R9
                MOVE    T_FORGOTTEN, R10
                RSUB    CHECK_EQ, 1

                MOVE    LONGBUF, R8             ; path unknown: entry empty
                RSUB    FBP_SET, 1
                MOVE    P_TEN, R8
                RSUB    FBP_CD, 1
                MOVE    2, R8
                XOR     R9, R9
                MOVE    N_X, R10
                RSUB    MNT_REMEMBER, 1
                MOVE    MNT_PATHS, R8
                ADD     512, R8
                MOVE    @R8, R8
                XOR     R9, R9
                MOVE    T_UNKNOWN_REM, R10
                RSUB    CHECK_EQ, 1

                MOVE    LONGBUF, R8             ; 250 + "/" + 3: fits, but..
                RSUB    FBP_SET, 1              ; .. + "/" + "X.ST" not
                MOVE    P_THREE, R8
                RSUB    FBP_CD, 1
                MOVE    2, R8
                XOR     R9, R9
                MOVE    N_X, R10
                RSUB    MNT_REMEMBER, 1
                MOVE    MNT_PATHS, R8
                ADD     512, R8
                MOVE    @R8, R8
                XOR     R9, R9
                MOVE    T_REM_TOO_LONG, R10
                RSUB    CHECK_EQ, 1

RESULT          MOVE    FAILS, R8
                CMP     0, @R8
                RBRA    _RESULT_F, !Z
                MOVE    STR_OK, R8
                SYSCALL(puts, 1)
                HALT
_RESULT_F       MOVE    STR_FAIL, R8
                SYSCALL(puts, 1)
                MOVE    FAILS, R8
                MOVE    @R8, R8
                SYSCALL(puthex, 1)
                SYSCALL(crlf, 1)
                HALT

; ----------------------------------------------------------------------------
; Test helpers
; ----------------------------------------------------------------------------

; R8: actual string, R9: expected string, R10: test name
CHECK_STR       SYSCALL(enter, 1)
                MOVE    R10, R0
                MOVE    R8, R1
                SYSCALL(strcmp, 1)
                CMP     0, R10
                RBRA    _CS_FAIL, !Z
                RSUB    PASS, 1
                RBRA    _CS_RET, 1
_CS_FAIL        RSUB    FAIL, 1
                MOVE    STR_GOT, R8
                SYSCALL(puts, 1)
                MOVE    R1, R8
                SYSCALL(puts, 1)
                MOVE    STR_QUOTE, R8
                SYSCALL(puts, 1)
                SYSCALL(crlf, 1)
_CS_RET         SYSCALL(leave, 1)
                RET

; R8: actual value, R9: expected value, R10: test name
CHECK_EQ        SYSCALL(enter, 1)
                MOVE    R10, R0
                MOVE    R8, R1
                CMP     R8, R9
                RBRA    _CE_FAIL, !Z
                RSUB    PASS, 1
                RBRA    _CE_RET, 1
_CE_FAIL        RSUB    FAIL, 1
                MOVE    STR_GOTV, R8
                SYSCALL(puts, 1)
                MOVE    R1, R8
                SYSCALL(puthex, 1)
                SYSCALL(crlf, 1)
_CE_RET         SYSCALL(leave, 1)
                RET

; FB_PATH has to be R9, test name in R10
CHECK_FBP       MOVE    FB_PATH, R8
                RBRA    CHECK_STR, 1

PASS            MOVE    STR_PASS, R8            ; R0: test name
                SYSCALL(puts, 1)
                MOVE    R0, R8
                SYSCALL(puts, 1)
                SYSCALL(crlf, 1)
                RET

FAIL            MOVE    STR_FAILT, R8           ; R0: test name
                SYSCALL(puts, 1)
                MOVE    R0, R8
                SYSCALL(puts, 1)
                MOVE    FAILS, R8
                ADD     1, @R8
                RET

CLEAR_LOG       INCRB
                MOVE    LOADS, R0
                MOVE    0, @R0
                MOVE    STROBES, R0
                MOVE    0, @R0
                DECRB
                RET

; LONGBUF = "/" + 299 x "a"
MAKE_LONG       SYSCALL(enter, 1)
                MOVE    LONGBUF, R8
                MOVE    0x002F, @R8++
                MOVE    299, R9
                MOVE    0x0061, R10
                SYSCALL(memset, 1)
                ADD     299, R8
                MOVE    0, @R8
                SYSCALL(leave, 1)
                RET

; ----------------------------------------------------------------------------
; Stubs for the parts of the shell that mntmem.asm uses
; ----------------------------------------------------------------------------

; Logs the call and opens the file like the real LOAD_IMAGE; fails for BAD.ST
LOAD_IMAGE      SYSCALL(enter, 1)
                MOVE    R8, R0                  ; R0: id
                MOVE    R9, R1                  ; R1: path
                MOVE    R10, R2                 ; R2: mode
                MOVE    LOADS, R3
                MOVE    @R3, R4                 ; R4: log index
                ADD     1, @R3
                MOVE    LOG_ID, R3
                ADD     R4, R3
                MOVE    R0, @R3
                MOVE    LOG_MODE, R3
                ADD     R4, R3
                MOVE    R2, @R3
                MOVE    LOG_PATHS, R9           ; copy the path to the log
                MOVE    R4, R5
_LI_1           CMP     0, R5
                RBRA    _LI_2, Z
                ADD     LOG_PATH_SZ, R9
                SUB     1, R5
                RBRA    _LI_1, 1
_LI_2           MOVE    R1, R8
                SYSCALL(strcpy, 1)

                MOVE    R0, R3                  ; file handle: vdrives 0..3,
                CMP     0, R2                   ; CRTs/ROMs 4..5
                RBRA    _LI_3, Z
                ADD     4, R3
_LI_3           MOVE    FH_IMG, R9
_LI_4           CMP     0, R3
                RBRA    _LI_5, Z
                ADD     FAT32$FDH_STRUCT_SIZE, R9
                SUB     1, R3
                RBRA    _LI_4, 1
_LI_5           MOVE    HANDLE_DEV, R8
                MOVE    R1, R10
                XOR     R11, R11
                SYSCALL(f32_fopen, 1)
                MOVE    R10, R6                 ; R6: result
                CMP     0, R6
                RBRA    _LI_RET, !Z             ; (cannot happen: checked)

                MOVE    R1, R8                  ; BAD.ST: "not a disk image"
                MOVE    F_BAD, R9
                SYSCALL(strcmp, 1)
                XOR     R6, R6
                CMP     0, R10
                RBRA    _LI_RET, !Z
                MOVE    0x00EE, R6

_LI_RET         MOVE    R6, @--SP
                SYSCALL(leave, 1)
                MOVE    @SP++, R8               ; R8: error code
                XOR     R9, R9                  ; R9: image type
                RET

VD_STROBE_IM    INCRB
                MOVE    STROBES, R0
                MOVE    @R0, R1
                ADD     1, @R0
                MOVE    STROBE_ID, R0
                ADD     R1, R0
                MOVE    R8, @R0
                MOVE    STROBE_LO, R0
                ADD     R1, R0
                MOVE    R9, @R0
                DECRB
                RET

VD_MENGRP       ADD     10, R8                  ; menu index = 10 + id
                MOVE    R8, R9
                OR      0x0004, SR              ; Carry: found
                RET

CRTROM_M_GI     ADD     20, R8                  ; menu index = 20 + id
                MOVE    R8, R9
                OR      0x0004, SR
                RET

VD_ACTIVE       XOR     R8, R8                  ; no vdrive caches to check
                AND     0xFFFB, SR
                RET

VD_DRV_READ     XOR     R8, R8
                RET

SCR$PRINTSTR    SYSCALL(puts, 1)
                RET

VD_MNT_ST_SET   RET
WAIT_FOR_SD     RET
SCR$OSM_OFF     RET
SCR$OSM_M_ON    RET
SCR$CLRINNER    RET
SCR$GOTOXY      RET
FRAME_FULLSCR   RET

FATAL           MOVE    R8, R0
                MOVE    STR_FATAL, R8
                SYSCALL(puts, 1)
                MOVE    R0, R8
                SYSCALL(puts, 1)
                HALT

HNDL_VD_FILES   .DW     FH_IMG                  ; like shell_fh_ptrs.asm
                .DW     FH_IMG1
                .DW     FH_IMG2
                .DW     FH_IMG3

FN_UPDIR        .ASCII_W ".."                   ; like strings.asm
FN_ROOT_DIR     .ASCII_W "/"
ERR_FATAL_INST  .ASCII_W "Instable system state.\n"
ERR_FATAL_INST7 .EQU     7

STR_START       .ASCII_W "mntmem test\n"
STR_OK          .ASCII_W "OK\n"
STR_FAIL        .ASCII_W "FAIL: failed checks: "
STR_PASS        .ASCII_W "  pass: "
STR_FAILT       .ASCII_W "  FAIL: "
STR_GOT         .ASCII_W ": got \""
STR_QUOTE       .ASCII_W "\""
STR_GOTV        .ASCII_W ": got "
STR_FATAL       .ASCII_W "FATAL: "
STR_CFGFILE     .ASCII_W "/atarist/stmount"

P_ATARIST       .ASCII_W "/atarist"
P_GAMES_REL     .ASCII_W "games"
P_GAMES         .ASCII_W "/atarist/games"
P_ROOT_GAMES    .ASCII_W "/games"
P_TOS           .ASCII_W "/atarist/tos"
P_LONG          .ASCII_W "/My Long Directory Name"
P_NOPE          .ASCII_W "/nope"
P_TEN           .ASCII_W "0123456789"
P_THREE         .ASCII_W "012"
N_DISK1         .ASCII_W "DISK1.ST"
N_TOS           .ASCII_W "TOS104.IMG"
N_LONG          .ASCII_W "Some Long Disk Image Name.st"
N_LONG19        .ASCII_W "Some Long Disk Imag"
N_BAD           .ASCII_W "BAD.ST"
N_X             .ASCII_W "X.ST"
F_DISK1         .ASCII_W "/atarist/games/DISK1.ST"
F_TOS           .ASCII_W "/atarist/tos/TOS104.IMG"
F_LONG          .ASCII_W "/My Long Directory Name/Some Long Disk Image Name.st"
F_BAD           .ASCII_W "/atarist/BAD.ST"
F_NOPE          .ASCII_W "/nope/X.ST"

T_CD_DOWN       .ASCII_W "cd games"
T_CD_UP         .ASCII_W "cd .."
T_CD_UP_ROOT    .ASCII_W "cd .. to the root"
T_CD_ROOT_DOWN  .ASCII_W "cd games in the root"
T_CD_DOT        .ASCII_W "cd ."
T_CD_UP_IN_ROOT .ASCII_W "cd .. in the root"
T_TOO_LONG      .ASCII_W "start path too long: unknown"
T_UNKNOWN_CD    .ASCII_W "unknown path stays unknown"
T_CD_TOO_LONG   .ASCII_W "cd makes the path too long: unknown"
T_ON            .ASCII_W "MNT_ON after the start"
T_NOTHING       .ASCII_W "nothing restored at the start"
T_OFF_CLEAN     .ASCII_W "off: nothing remembered"
T_REM_PATH      .ASCII_W "remember vdrive 0"
T_REM_ROM       .ASCII_W "remember CRT/ROM 1 behind the vdrives"
T_DIRTY         .ASCII_W "dirty after remembering"
T_SAVED         .ASCII_W "clean after saving"
T_LOADS4        .ASCII_W "restore: 4 images"
T_LOAD0         .ASCII_W "restore: TOS first"
T_LOAD0_MODE    .ASCII_W "restore: TOS in CRT/ROM mode"
T_LOAD0_ID      .ASCII_W "restore: TOS id"
T_LOAD1         .ASCII_W "restore: vdrive 0"
T_LOAD2         .ASCII_W "restore: vdrive 2 (long names)"
T_STROBES       .ASCII_W "restore: 2 vdrives notified"
T_STROBE0_ID    .ASCII_W "restore: notified vdrive 0"
T_STROBE0_SZ    .ASCII_W "restore: size of vdrive 0"
T_STROBE1_ID    .ASCII_W "restore: notified vdrive 2"
T_STROBE1_SZ    .ASCII_W "restore: size of vdrive 2"
T_BAD_GONE      .ASCII_W "restore: unusable image forgotten"
T_BAD_DIRTY     .ASCII_W "restore: dirty after forgetting"
T_CTX           .ASCII_W "restore: SF_CONTEXT reset"
T_OSM0          .ASCII_W "menu name of vdrive 0"
T_OSM2          .ASCII_W "menu name of vdrive 2 (shortened)"
T_OSM_ROM       .ASCII_W "menu name of CRT/ROM 1"
T_OSM_FLAG      .ASCII_W "menu: %s replaced flag"
T_OSM_EMPTY     .ASCII_W "menu: no name for vdrive 1"
T_OSM_ONCE      .ASCII_W "menu names written only once"
T_LOADS2        .ASCII_W "restore after unmount: 2 images"
T_MISSING_KEPT  .ASCII_W "missing image kept"
T_FORGOTTEN     .ASCII_W "unmounted image forgotten"
T_UNKNOWN_REM   .ASCII_W "unknown browser path: entry empty"
T_REM_TOO_LONG  .ASCII_W "path + name too long: entry empty"

#include "../../../M2M/rom/mntmem.asm"

; ----------------------------------------------------------------------------
; Variables
; ----------------------------------------------------------------------------

                .ORG    0x8000

#include "../../../M2M/rom/mntmem_vars.asm"

HANDLE_DEV      .BLOCK  FAT32$DEV_STRUCT_SIZE   ; like shell_vars.asm
INITIAL_SD      .BLOCK  1
VDRIVES_NUM     .BLOCK  1
CRTROM_MAN_NUM  .BLOCK  1
OPTM_SCOUNT     .BLOCK  1
OPTM_HEAP       .BLOCK  1
SCR$OSM_O_DX    .BLOCK  1
SF_CONTEXT      .BLOCK  1

FH_IMG          .BLOCK  FAT32$FDH_STRUCT_SIZE
FH_IMG1         .BLOCK  FAT32$FDH_STRUCT_SIZE
FH_IMG2         .BLOCK  FAT32$FDH_STRUCT_SIZE
FH_IMG3         .BLOCK  FAT32$FDH_STRUCT_SIZE
FH_IMG4         .BLOCK  FAT32$FDH_STRUCT_SIZE
FH_IMG5         .BLOCK  FAT32$FDH_STRUCT_SIZE

FAILS           .BLOCK  1
LOADS           .BLOCK  1
LOG_ID          .BLOCK  8
LOG_MODE        .BLOCK  8
LOG_PATHS       .BLOCK  512                     ; 8 x LOG_PATH_SZ
STROBES         .BLOCK  1
STROBE_ID       .BLOCK  8
STROBE_LO       .BLOCK  8
OSM_BUF         .BLOCK  200
LONGBUF         .BLOCK  301

                .ORG    0xFEE0
#include "../../../M2M/rom/main_vars.asm"
