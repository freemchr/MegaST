; ****************************************************************************
; MegaST: test of the switch between the ST and the Falcon
; (CORE/m2m-rom/fcswitch.asm) in the QNICE emulator, see run.sh. The menu bit,
; the loaders and the window are stubs that count their calls.
;
; 1. FC_INIT with the ST: FC_MACH = 0
; 2. FC_CHECK, still the ST: no hold; FC_SWITCH: nothing loaded
; 3. Falcon chosen: hold; back to the ST before the menu closes: no hold
; 4. Falcon, FC_SWITCH without any manual TOS: auto-load TOS, FC_MACH = 1,
;    the remembered images are saved
; 5. A manual TOS for the Falcon is loaded and remembered ("/F"), the ST has
;    one remembered ("/S"), a cartridge is loaded. ST: the Falcon TOS is
;    unloaded, "/S" and the cartridge are loaded, no auto-load, the entries
;    are swapped, FC_MACH = 0
; 6. Falcon again: "/F" is loaded, "/S" goes back behind the CRTs/ROMs
; 7. The ST has no manual TOS any more: ST: the Falcon TOS is unloaded and the
;    ST gets its auto-load TOS
; 8. Without the file of the remembered images (MNT_ON = 0) nothing is
;    swapped: Falcon: auto-load TOS
;    The menu is closed: the TOS line is unmarked with M2M$SET_SETTING, not
;    with M2M$FORCE_MENU (OPTM_SET goes fatal)
; 9. FC_AUT_NAME keeps the name of other auto-load ROMs and the TOS of the ST
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
                RSUB    CLR_CALLS, 1
                MOVE    CRTROM_MAN_LDF, R0
                MOVE    0, @R0++
                MOVE    0, @R0
                MOVE    MNT_PATHS, R8           ; all entries empty
                MOVE    1792, R9
                XOR     R10, R10
                SYSCALL(memset, 1)
                MOVE    MNT_ON, R0
                MOVE    0, @R0

                ; 1.
                MOVE    MENU_BIT, R0
                MOVE    0, @R0
                RSUB    FC_INIT, 1
                MOVE    FC_MACH, R8
                MOVE    0, R9
                RSUB    CHECK_EQ, 1

                ; 2.
                RSUB    FC_CHECK, 1
                MOVE    FC_HOLD, R8
                MOVE    0, R9
                RSUB    CHECK_EQ, 1
                RSUB    FC_SWITCH, 1
                MOVE    N_AUTO, R8
                MOVE    0, R9
                RSUB    CHECK_EQ, 1

                ; 3.
                MOVE    MENU_BIT, R0
                MOVE    1, @R0
                RSUB    FC_CHECK, 1
                MOVE    FC_HOLD, R8
                MOVE    1, R9
                RSUB    CHECK_EQ, 1
                MOVE    MENU_BIT, R0
                MOVE    0, @R0
                RSUB    FC_CHECK, 1
                MOVE    FC_HOLD, R8
                MOVE    0, R9
                RSUB    CHECK_EQ, 1
                RSUB    FC_SWITCH, 1
                MOVE    N_AUTO, R8
                MOVE    0, R9
                RSUB    CHECK_EQ, 1

                ; 4.
                MOVE    MNT_ON, R0
                MOVE    1, @R0
                MOVE    MENU_BIT, R0
                MOVE    1, @R0
                RSUB    FC_CHECK, 1
                RSUB    FC_SWITCH, 1
                MOVE    N_AUTO, R8
                MOVE    1, R9
                RSUB    CHECK_EQ, 1
                MOVE    N_LOAD0, R8
                MOVE    0, R9
                RSUB    CHECK_EQ, 1
                MOVE    N_UNLOAD, R8
                MOVE    0, R9
                RSUB    CHECK_EQ, 1
                MOVE    N_SAVE, R8
                MOVE    1, R9
                RSUB    CHECK_EQ, 1
                MOVE    FC_MACH, R8
                MOVE    1, R9
                RSUB    CHECK_EQ, 1
                MOVE    FC_HOLD, R8
                MOVE    0, R9
                RSUB    CHECK_EQ, 1

                ; 5.
                RSUB    CLR_CALLS, 1
                MOVE    CRTROM_MAN_LDF, R0
                MOVE    1, @R0++
                MOVE    1, @R0
                MOVE    ENTRY_TOS, R0
                MOVE    0x0046, @R0             ; "F"
                MOVE    ENTRY_OTHER, R0
                MOVE    0x0053, @R0             ; "S"
                MOVE    ENTRY_CART, R0
                MOVE    0x0043, @R0             ; "C"
                MOVE    MENU_BIT, R0
                MOVE    0, @R0
                RSUB    FC_CHECK, 1
                RSUB    FC_SWITCH, 1
                MOVE    N_AUTO, R8
                MOVE    0, R9
                RSUB    CHECK_EQ, 1
                MOVE    N_UNLOAD, R8
                MOVE    1, R9
                RSUB    CHECK_EQ, 1
                MOVE    N_LOAD0, R8
                MOVE    1, R9
                RSUB    CHECK_EQ, 1
                MOVE    N_LOAD1, R8
                MOVE    1, R9
                RSUB    CHECK_EQ, 1
                MOVE    N_OSMOFF, R8
                MOVE    1, R9
                RSUB    CHECK_EQ, 1
                MOVE    ENTRY_TOS, R8
                MOVE    0x0053, R9
                RSUB    CHECK_EQ, 1
                MOVE    ENTRY_OTHER, R8
                MOVE    0x0046, R9
                RSUB    CHECK_EQ, 1
                MOVE    MNT_DIRTY, R8
                MOVE    1, R9
                RSUB    CHECK_EQ, 1
                MOVE    FC_MACH, R8
                MOVE    0, R9
                RSUB    CHECK_EQ, 1
                MOVE    N_SETOFF, R8
                MOVE    1, R9
                RSUB    CHECK_EQ, 1

                ; 6.
                RSUB    CLR_CALLS, 1
                MOVE    MENU_BIT, R0
                MOVE    1, @R0
                RSUB    FC_CHECK, 1
                RSUB    FC_SWITCH, 1
                MOVE    N_AUTO, R8
                MOVE    0, R9
                RSUB    CHECK_EQ, 1
                MOVE    N_UNLOAD, R8
                MOVE    1, R9
                RSUB    CHECK_EQ, 1
                MOVE    N_LOAD0, R8
                MOVE    1, R9
                RSUB    CHECK_EQ, 1
                MOVE    ENTRY_TOS, R8
                MOVE    0x0046, R9
                RSUB    CHECK_EQ, 1
                MOVE    ENTRY_OTHER, R8
                MOVE    0x0053, R9
                RSUB    CHECK_EQ, 1

                ; 7.
                RSUB    CLR_CALLS, 1
                MOVE    ENTRY_OTHER, R0
                MOVE    0, @R0
                MOVE    MENU_BIT, R0
                MOVE    0, @R0
                RSUB    FC_CHECK, 1
                RSUB    FC_SWITCH, 1
                MOVE    N_UNLOAD, R8
                MOVE    1, R9
                RSUB    CHECK_EQ, 1
                MOVE    N_LOAD0, R8
                MOVE    0, R9
                RSUB    CHECK_EQ, 1
                MOVE    N_AUTO, R8
                MOVE    1, R9
                RSUB    CHECK_EQ, 1
                MOVE    CRTROM_MAN_LDF, R8
                MOVE    0, R9
                RSUB    CHECK_EQ, 1
                MOVE    ENTRY_OTHER, R8
                MOVE    0x0046, R9
                RSUB    CHECK_EQ, 1

                ; 8.
                RSUB    CLR_CALLS, 1
                MOVE    MNT_ON, R0
                MOVE    0, @R0
                MOVE    MENU_BIT, R0
                MOVE    1, @R0
                RSUB    FC_CHECK, 1
                RSUB    FC_SWITCH, 1
                MOVE    N_AUTO, R8
                MOVE    1, R9
                RSUB    CHECK_EQ, 1
                MOVE    N_LOAD0, R8
                MOVE    0, R9
                RSUB    CHECK_EQ, 1
                MOVE    ENTRY_OTHER, R8
                MOVE    0x0046, R9
                RSUB    CHECK_EQ, 1
                MOVE    FC_MACH, R8
                MOVE    1, R9
                RSUB    CHECK_EQ, 1

                ; 9.
                MOVE    MENU_BIT, R0
                MOVE    1, @R0
                MOVE    1, R8                   ; another auto-load ROM
                MOVE    0x1234, R9
                RSUB    FC_AUT_NAME, 1
                MOVE    SCRATCH, R8
                MOVE    R9, @R8
                MOVE    0x1234, R9
                RSUB    CHECK_EQ, 1
                MOVE    MENU_BIT, R0
                MOVE    0, @R0
                XOR     R8, R8                  ; the TOS of the ST
                MOVE    0x1234, R9
                RSUB    FC_AUT_NAME, 1
                MOVE    SCRATCH, R8
                MOVE    R9, @R8
                MOVE    0x1234, R9
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

CLR_CALLS       MOVE    N_AUTO, R8
                MOVE    0, @R8++
                MOVE    0, @R8++
                MOVE    0, @R8++
                MOVE    0, @R8++
                MOVE    0, @R8++
                MOVE    0, @R8
                MOVE    N_SETOFF, R8
                MOVE    0, @R8
                MOVE    MNT_DIRTY, R8
                MOVE    0, @R8
                RET

; R8 = address of the value, R9 = expected: count and log a mismatch
CHECK_EQ        SYSCALL(enter, 1)
                MOVE    R8, R1                  ; R1: address (logged)
                MOVE    @R8, R8
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
                MOVE    STR_AT, R8
                SYSCALL(puts, 1)
                MOVE    R1, R8
                SYSCALL(puthex, 1)
                SYSCALL(crlf, 1)
_CE_RET         SYSCALL(leave, 1)
                RET

; stubs for the parts of the shell and of mntmem.asm that fcswitch.asm uses
MENU_FALCON     .EQU    16
CRT_ID_CART     .EQU    1
CRTROM_MAN_MAX  .EQU    2
MNT_ENTRY_SZ    .EQU    256
ENTRY_TOS       .EQU    0x8C00                  ; MNT_PATHS + 4 * 256
ENTRY_CART      .EQU    0x8D00                  ; MNT_PATHS + 5 * 256
ENTRY_OTHER     .EQU    0x8E00                  ; MNT_PATHS + 6 * 256
_MNT_CFM_GET    MOVE    MENU_BIT, R8            ; the Falcon menu bit
                MOVE    @R8, R8
                RET
_MNT_ENTRY      CMP     0, R9                   ; R8: entry (vdrives first)
                RBRA    _ME_1, Z
                ADD     4, R8
_ME_1           AND     0xFFFD, SR
                SHL     8, R8
                ADD     MNT_PATHS, R8
                RET
_MNT_LOAD       INCRB                           ; loads a remembered entry
                MOVE    R8, R1
                RSUB    _MNT_ENTRY, 1
                CMP     0, @R8
                RBRA    _ML_RET, Z
                MOVE    N_LOAD0, R0
                ADD     R1, R0
                ADD     1, @R0
                MOVE    CRTROM_MAN_LDF, R0
                ADD     R1, R0
                MOVE    1, @R0
                MOVE    MNT_SHOWN, R0           ; it opened its window
                MOVE    1, @R0
_ML_RET         DECRB
                RET
MNT_SAVE        INCRB
                MOVE    N_SAVE, R0
                ADD     1, @R0
                DECRB
                RET
CRTROM_AUTOLOAD INCRB
                MOVE    N_AUTO, R0
                ADD     1, @R0
                DECRB
                RET
SCR$OSM_OFF     INCRB
                MOVE    N_OSMOFF, R0
                ADD     1, @R0
                DECRB
                RET
SAVE_DEVSEL     RET
RESTORE_DEVSEL  RET
CRTROM_CSR_W    INCRB
                MOVE    N_UNLOAD, R0
                ADD     1, @R0
                DECRB
                RET
CRTROM_M_GI     MOVE    5, R9                   ; menu index of the TOS line
                OR      0x0004, SR
                RET
M2M$SET_SETTING INCRB                           ; counts "item 5 off"
                CMP     5, R8
                RBRA    _SS_RET, !Z
                CMP     0, R9
                RBRA    _SS_RET, !Z
                MOVE    N_SETOFF, R0
                ADD     1, @R0
_SS_RET         DECRB
                RET
M2M$FORCE_MENU  INCRB                           ; must not be called
                MOVE    FAILS, R0
                ADD     1, @R0
                DECRB
                RET

#include "../../m2m-rom/fcswitch.asm"

STR_START       .ASCII_W "fcswitch test\n"
STR_OK          .ASCII_W "OK\n"
STR_FAIL        .ASCII_W "FAIL: failed checks: "
STR_FAILT       .ASCII_W "  FAIL: got "
STR_EXP         .ASCII_W " expected "
STR_AT          .ASCII_W " at "

                .ORG    0x8000
MENU_BIT        .BLOCK  1
N_AUTO          .BLOCK  1
N_LOAD0         .BLOCK  1
N_LOAD1         .BLOCK  1
N_OSMOFF        .BLOCK  1
N_UNLOAD        .BLOCK  1
N_SAVE          .BLOCK  1
FC_MACH         .BLOCK  1
FC_HOLD         .BLOCK  1
MNT_SHOWN       .BLOCK  1
CRTROM_MAN_LDF  .BLOCK  2
MNT_ON          .BLOCK  1
MNT_DIRTY       .BLOCK  1
SCRATCH_HEX     .BLOCK  5
CRTROM_MAN_DEV  .BLOCK  2
CONFIG_DEVH     .BLOCK  1
CRTROM_AUT_FILE .BLOCK  1
SCRATCH         .BLOCK  1
FAILS           .BLOCK  1
N_SETOFF        .BLOCK  1
                .ORG    0x8800
MNT_PATHS       .BLOCK  1792

                .ORG    0xFEE0
#include "../../../M2M/rom/main_vars.asm"
