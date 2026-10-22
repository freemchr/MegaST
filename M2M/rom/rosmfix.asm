; ****************************************************************************
; MegaST: check of the settings loaded from the config file (CFG_FILE)
;
; In a group of options (OPTM_GROUPS entries in config.vhd with the same group
; id that are neither single select items nor submenus) exactly one item must
; be selected. A settings file that does not match the menu breaks this: one
; written by another build whose menu has the same size but other items, or a
; damaged one. OPTM_CB_SHOW then stopped the firmware (ERR_F_MENUNGRP) as
; soon as the menu was opened. ROSM_FIXGRP is called by
; HELP_MENU_INIT (options.asm) right after the settings were loaded from the
; file: such a group gets its defaults (OPTM_G_STDSEL) instead, all other
; settings stay as they are in the file.
;
; Tested in the QNICE emulator: CORE/sim/rosmfix (defines ROSMFG_STUB, the
; emulator has neither M2M$CFM_DATA nor the config.vhd device).
;
; MEGA65 port done by Chris Freeman in 2026 and licensed under GPL v3
; ****************************************************************************

ROSM_FIXGRP     SYSCALL(enter, 1)

                MOVE    OPTM_ICOUNT, R7
                MOVE    @R7, R7                 ; R7: amount of menu items
                XOR     R0, R0                  ; R0: current item

_ROSMFG_ITEM    CMP     R0, R7                  ; all items done?
                RBRA    _ROSMFG_RET, Z
                MOVE    R0, R8
                RSUB    _ROSMFG_GID, 1          ; R8: group id or 0
                MOVE    R8, R1                  ; R1: group id of this item
                RBRA    _ROSMFG_NEXT, Z         ; not in a group of options

                ; only check each group once: at its first item
                XOR     R2, R2
_ROSMFG_FIRST   CMP     R2, R0                  ; no earlier item of group?
                RBRA    _ROSMFG_CNT, Z          ; yes: check the group
                MOVE    R2, R8
                RSUB    _ROSMFG_GID, 1
                CMP     R8, R1                  ; earlier item of this group?
                RBRA    _ROSMFG_NEXT, Z         ; yes: already checked
                ADD     1, R2
                RBRA    _ROSMFG_FIRST, 1

                ; count the selected items of the group
_ROSMFG_CNT     XOR     R3, R3                  ; R3: selected items
                MOVE    R0, R2
_ROSMFG_CNT1    MOVE    R2, R8
                RSUB    _ROSMFG_GID, 1
                CMP     R8, R1
                RBRA    _ROSMFG_CNT2, !Z        ; other group
                MOVE    R2, R8
                RSUB    _ROSMFG_GET, 1          ; R9: selected?
                ADD     R9, R3
_ROSMFG_CNT2    ADD     1, R2
                CMP     R2, R7
                RBRA    _ROSMFG_CNT1, !Z
                CMP     1, R3                   ; exactly one selected?
                RBRA    _ROSMFG_NEXT, Z         ; yes: fine

                MOVE    LOG_STR_CFG_GRP, R8     ; no: log and use defaults
                SYSCALL(puts, 1)
                MOVE    R0, R8
                SYSCALL(puthex, 1)
                SYSCALL(crlf, 1)
                MOVE    R0, R2
_ROSMFG_DEF1    MOVE    R2, R8
                RSUB    _ROSMFG_GID, 1
                CMP     R8, R1
                RBRA    _ROSMFG_DEF2, !Z        ; other group
                MOVE    R2, R8
                RSUB    _ROSMFG_STD, 1          ; R9: default of this item
                RSUB    _ROSMFG_SET, 1
_ROSMFG_DEF2    ADD     1, R2
                CMP     R2, R7
                RBRA    _ROSMFG_DEF1, !Z

_ROSMFG_NEXT    ADD     1, R0
                RBRA    _ROSMFG_ITEM, 1

_ROSMFG_RET     SYSCALL(leave, 1)
                RET

; Input: R8: OPTM_GROUPS index; output: R8: its group id if the item belongs
; to a group of options, else 0
_ROSMFG_GID     INCRB
                RSUB    _ROSMFG_GRP, 1          ; R8: OPTM_GROUPS entry
                MOVE    R8, R1
                AND     OPTM_SINGLESEL, R1      ; single select item, mount,
                RBRA    _ROSMFG_GID0, !Z        ; load, help: not a group
                MOVE    R8, R1
                AND     OPTM_SUBMENU, R1        ; submenu: not a group
                RBRA    _ROSMFG_GID0, !Z
                AND     0x00FF, R8              ; R8: group id
                CMP     OPTM_CLOSE, R8          ; close item: not a group
                RBRA    _ROSMFG_GIDR, !Z
_ROSMFG_GID0    XOR     R8, R8
_ROSMFG_GIDR    DECRB
                RET

; The accesses to config.vhd and to M2M$CFM_DATA
;   _ROSMFG_GRP: R8: index -> R8: OPTM_GROUPS entry
;   _ROSMFG_STD: R8: index -> R9: default (OPTM_G_STDSEL), R8 unchanged
;   _ROSMFG_GET: R8: index -> R9: setting, R8 unchanged
;   _ROSMFG_SET: R8: index, R9: setting
#ifndef ROSMFG_STUB
_ROSMFG_GRP     INCRB
                MOVE    R9, R0
                MOVE    M2M$CFG_OPTM_GROUPS, R9
                RSUB    _ROSMFG_CFG, 1
                MOVE    R0, R9
                DECRB
                RET

_ROSMFG_STD     INCRB
                MOVE    R8, R0
                MOVE    M2M$CFG_OPTM_STDSEL, R9
                RSUB    _ROSMFG_CFG, 1
                MOVE    R8, R9
                MOVE    R0, R8
                DECRB
                RET

; R8: index, R9: config.vhd selector -> R8: word
_ROSMFG_CFG     INCRB
                MOVE    M2M$RAMROM_DEV, R0
                MOVE    M2M$CONFIG, @R0
                MOVE    M2M$RAMROM_4KWIN, R0
                MOVE    R9, @R0
                MOVE    M2M$RAMROM_DATA, R0
                ADD     R8, R0
                MOVE    @R0, R8
                DECRB
                RET

_ROSMFG_GET     RBRA    M2M$GET_SETTING, 1
_ROSMFG_SET     RBRA    M2M$SET_SETTING, 1
#endif
