; ****************************************************************************
; MegaST: test of the switch between the ST and the Falcon
; (CORE/m2m-rom/fcswitch.asm) in the QNICE emulator, see run.sh. The menu bit,
; the loaders and the window are stubs that count their calls.
;
; 1. FC_INIT with the ST: FC_MACH = 0
; 2. FC_CHECK, still the ST: no hold; FC_SWITCH: nothing loaded
; 3. Falcon chosen: hold; back to the ST before the menu closes: no hold
; 4. Falcon, FC_SWITCH without a manual TOS: auto-load TOS, FC_MACH = 1
; 5. ST, FC_SWITCH with a manual TOS (path known) and a cartridge: both
;    reloaded, no auto-load, FC_MACH = 0
; 6. Falcon, FC_SWITCH with a manual TOS whose path is unknown: auto-load TOS
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
                MOVE    MNT_PATHS, R0
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
                MOVE    MNT_PATHS, R0           ; entry of CRT/ROM 0
                ADD     MNT_ENTRY_SZ, R0
                ADD     MNT_ENTRY_SZ, R0
                ADD     MNT_ENTRY_SZ, R0
                ADD     MNT_ENTRY_SZ, R0
                MOVE    0x002F, @R0
                MOVE    MENU_BIT, R0
                MOVE    0, @R0
                RSUB    FC_CHECK, 1
                RSUB    FC_SWITCH, 1
                MOVE    N_AUTO, R8
                MOVE    0, R9
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
                MOVE    FC_MACH, R8
                MOVE    0, R9
                RSUB    CHECK_EQ, 1

                ; 6.
                RSUB    CLR_CALLS, 1
                MOVE    CRTROM_MAN_LDF, R0
                ADD     1, R0
                MOVE    0, @R0
                MOVE    MNT_PATHS, R0
                ADD     MNT_ENTRY_SZ, R0
                ADD     MNT_ENTRY_SZ, R0
                ADD     MNT_ENTRY_SZ, R0
                ADD     MNT_ENTRY_SZ, R0
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
                MOVE    N_LOAD1, R8
                MOVE    0, R9
                RSUB    CHECK_EQ, 1
                MOVE    FC_MACH, R8
                MOVE    1, R9
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
                MOVE    0, @R8
                RET

; R8 = address of the value, R9 = expected: count and log a mismatch
CHECK_EQ        SYSCALL(enter, 1)
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
                SYSCALL(crlf, 1)
_CE_RET         SYSCALL(leave, 1)
                RET

; stubs for the parts of the shell and of mntmem.asm that fcswitch.asm uses
MENU_FALCON     .EQU    16
CRT_ID_CART     .EQU    1
MNT_ENTRY_SZ    .EQU    256
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
_MNT_LOAD       INCRB
                MOVE    N_LOAD0, R0
                ADD     R8, R0
                ADD     1, @R0
                MOVE    MNT_SHOWN, R0           ; it opened its window
                MOVE    1, @R0
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

#include "../../m2m-rom/fcswitch.asm"

STR_START       .ASCII_W "fcswitch test\n"
STR_OK          .ASCII_W "OK\n"
STR_FAIL        .ASCII_W "FAIL: failed checks: "
STR_FAILT       .ASCII_W "  FAIL: got "
STR_EXP         .ASCII_W " expected "

                .ORG    0x8000
MENU_BIT        .BLOCK  1
N_AUTO          .BLOCK  1
N_LOAD0         .BLOCK  1
N_LOAD1         .BLOCK  1
N_OSMOFF        .BLOCK  1
FC_MACH         .BLOCK  1
FC_HOLD         .BLOCK  1
MNT_SHOWN       .BLOCK  1
CRTROM_MAN_LDF  .BLOCK  2
MNT_PATHS       .BLOCK  1536
FAILS           .BLOCK  1

                .ORG    0xFEE0
#include "../../../M2M/rom/main_vars.asm"
