; ****************************************************************************
; MegaST: test of ROSM_FIXGRP (M2M/rom/rosmfix.asm) in the QNICE emulator,
; see run.sh
;
; The menu (OPTM_GROUPS, OPTM_G_STDSEL) and the settings files come from
; gen.py (td.asm). The stubs below replace the config.vhd device and
; M2M$CFM_DATA, which the emulator does not have. For each case the settings
; after ROSM_FIXGRP are printed as "CASE n: 0101...", run.sh compares them.
;
; MEGA65 port done by Chris Freeman in 2026 and licensed under GPL v3
; ****************************************************************************

#define RELEASE
#define ROSMFG_STUB
#include "../../../M2M/rom/main.asm"

OPTM_CLOSE      .EQU    0x00FF                  ; like menu.asm
OPTM_SUBMENU    .EQU    0x4000
OPTM_SINGLESEL  .EQU    0x8000

START_FIRMWARE  MOVE    OPTM_ICOUNT, R0
                MOVE    TD_ITEMS, @R0
                XOR     R4, R4                  ; R4: case
                MOVE    TD_CFG, R5              ; R5: its settings

_T_CASE         MOVE    R5, R8                  ; settings of this case
                MOVE    SETTINGS, R9
                MOVE    TD_ITEMS, R10
                SYSCALL(memcpy, 1)
                RSUB    ROSM_FIXGRP, 1

                MOVE    STR_CASE, R8
                SYSCALL(puts, 1)
                MOVE    R4, R8
                ADD     0x30, R8                ; cases 0..9
                SYSCALL(putc, 1)
                MOVE    0x3A, R8                ; ":"
                SYSCALL(putc, 1)
                MOVE    0x20, R8
                SYSCALL(putc, 1)
                MOVE    SETTINGS, R0
                MOVE    TD_ITEMS, R1
_T_OUT          MOVE    @R0++, R8
                ADD     0x30, R8
                SYSCALL(putc, 1)
                SUB     1, R1
                RBRA    _T_OUT, !Z
                SYSCALL(crlf, 1)

                ADD     TD_ITEMS, R5
                ADD     1, R4
                CMP     TD_CASES, R4
                RBRA    _T_CASE, !Z
                MOVE    STR_END, R8
                SYSCALL(puts, 1)
                HALT

STR_CASE        .ASCII_W "CASE "
STR_END         .ASCII_W "END\n"
LOG_STR_CFG_GRP .ASCII_W "Config file: no valid selection, defaults for the group of item 0x"

; Stubs of the accesses to config.vhd and M2M$CFM_DATA (rosmfix.asm)
_ROSMFG_GRP     INCRB
                MOVE    TD_GROUPS, R0
                ADD     R8, R0
                MOVE    @R0, R8
                DECRB
                RET

_ROSMFG_STD     INCRB
                MOVE    TD_STD, R0
                ADD     R8, R0
                MOVE    @R0, R9
                DECRB
                RET

_ROSMFG_GET     INCRB
                MOVE    SETTINGS, R0
                ADD     R8, R0
                MOVE    @R0, R9
                DECRB
                RET

_ROSMFG_SET     INCRB
                MOVE    SETTINGS, R0
                ADD     R8, R0
                MOVE    R9, @R0
                DECRB
                RET

#include "../../../M2M/rom/rosmfix.asm"
#include "td.asm"

                .ORG    0x8000
OPTM_ICOUNT     .BLOCK  1
SETTINGS        .BLOCK  256

                .ORG    0xFEE0
#include "../../../M2M/rom/main_vars.asm"
