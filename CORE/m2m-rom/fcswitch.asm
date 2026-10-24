; ****************************************************************************
; MegaST: switching between the ST and the Falcon030 in the menu
;
; Both machines keep their TOS in the SDRAM, but each in its own layout (the
; memory arbiter of the Falcon has 64-bit words with other rows, banks and byte
; order than the ST). TOS goes in only through the TOS loader of the machine
; that runs (tos_loader.vhd, main.vhd), so after a switch the new machine
; would start with the RAM contents of the old one instead of a TOS (the
; Falcon hung at its reset vector).
;
; OSM_SEL_PRE puts the core into reset before the framework changes a menu
; bit of the Machine group (the callbacks only come for a new selection).
; FC_CHECK (OSM_SEL_POST) lets it go again unless the Falcon menu bit now
; differs from the machine whose TOS is in the SDRAM (FC_MACH): then the core
; stays in reset until the menu closes. FC_SWITCH (main loop, CORE_LOOP) then
; loads the TOS of the new machine and a loaded cartridge, then the new
; machine starts.
;
; Each machine has its own TOS:
; * the auto-load TOS: /atarist/tos.img for the ST, /atarist/tosfalc.img for
;   the Falcon (FC_AUT_NAME, called by CRTROM_AUTOLOAD, also at power on;
;   without tosfalc.img the Falcon gets tos.img, so the menu still works)
; * a TOS loaded with the menu item "TOS:", remembered per machine: the
;   remembered images (mntmem.asm) have one entry more than the vdrives and
;   CRTs/ROMs, which holds the manual TOS of the machine that does not run.
;   FC_SWITCH swaps it with the entry of the TOS, so at power on MNT_RESTORE
;   loads the manual TOS of the machine in the settings.
;
; This machine is based on AtariST_MiSTer
; Powered by MiSTer2MEGA65
; MEGA65 port done by Chris Freeman in 2026 and licensed under GPL v3
; ****************************************************************************

FC_CRT_TOS      .EQU    0                       ; C_CRTROMS_MAN (globals.vhd)

LOG_FC_SWITCH   .ASCII_W "Machine: ST <-> Falcon, loading its TOS\n"
LOG_FC_AUTO     .ASCII_W "Machine: no manual TOS for it, auto-load TOS\n"
LOG_FC_NOFTOS   .ASCII_W "Machine: /atarist/tosfalc.img not found, using tos.img\n"
FC_FTOS_NAME    .ASCII_W "/atarist/tosfalc.img"

; ----------------------------------------------------------------------------
; Remember the machine of the TOS in the SDRAM
; Called by PREP_START (the TOS has just been loaded, the core is in reset)
; ----------------------------------------------------------------------------

FC_INIT         INCRB
                MOVE    MENU_FALCON, R8
                RSUB    _MNT_CFM_GET, 1
                MOVE    FC_MACH, R0
                MOVE    R8, @R0
                MOVE    FC_HOLD, R0
                MOVE    0, @R0
                DECRB
                RET

; ----------------------------------------------------------------------------
; A menu item of the Machine group was selected (OSM_SEL_POST, the core is in
; reset since OSM_SEL_PRE): keep it in reset if the other machine type was
; chosen
; ----------------------------------------------------------------------------

FC_CHECK        INCRB
                MOVE    MENU_FALCON, R8
                RSUB    _MNT_CFM_GET, 1
                MOVE    M2M$CSR, R0
                MOVE    FC_HOLD, R1
                MOVE    FC_MACH, R2
                CMP     R8, @R2
                RBRA    _FCC_SAME, Z
                OR      M2M$CSR_RESET, @R0      ; other machine: reset until
                MOVE    1, @R1                  ; its TOS is loaded
                RBRA    _FCC_RET, 1
_FCC_SAME       MOVE    0, @R1                  ; the machine of the TOS: it
                AND     M2M$CSR_UN_RESET, @R0   ; may start (again)
_FCC_RET        DECRB
                RET

; ----------------------------------------------------------------------------
; File name of an auto-load ROM (called by CRTROM_AUTOLOAD, crts-and-roms.asm)
; Input:  R8: number of the auto-load ROM
;         R9: its file name from globals.vhd (in the M2M$SYS_CRTSANDROMS
;             window, which is selected)
; Output: R9: the file name to load; the window is selected again
; ----------------------------------------------------------------------------

FC_AUT_NAME     SYSCALL(enter, 1)
                CMP     0, R8                   ; the TOS?
                RBRA    _FCAN_RET, !Z
                MOVE    R9, R2                  ; R2: default name
                MOVE    MENU_FALCON, R8
                RSUB    _MNT_CFM_GET, 1
                CMP     0, R8                   ; Falcon?
                RBRA    _FCAN_RET, Z            ; no: tos.img
                MOVE    CONFIG_DEVH, R8         ; tosfalc.img there?
                MOVE    CRTROM_AUT_FILE, R9     ; (opened again by the caller)
                MOVE    FC_FTOS_NAME, R10
                XOR     R11, R11
                SYSCALL(f32_fopen, 1)
                MOVE    M2M$RAMROM_DEV, R0      ; the FAT32 routines changed
                MOVE    M2M$SYS_INFO, @R0       ; the device: select the
                MOVE    M2M$RAMROM_4KWIN, R0    ; window again
                MOVE    M2M$SYS_CRTSANDROMS, @R0
                MOVE    FC_FTOS_NAME, R9
                CMP     0, R10
                RBRA    _FCAN_RET, Z            ; found
                MOVE    LOG_FC_NOFTOS, R8
                SYSCALL(puts, 1)
                MOVE    R2, R9
_FCAN_RET       MOVE    R9, @--SP               ; lift R9 over the leave hump
                SYSCALL(leave, 1)
                MOVE    @SP++, R9
                RET

; ----------------------------------------------------------------------------
; Main loop (CORE_LOOP), i.e. the menu is closed: load the TOS for the new
; machine, then let it start
; ----------------------------------------------------------------------------

FC_SWITCH       SYSCALL(enter, 1)
                MOVE    FC_HOLD, R0
                CMP     0, @R0
                RBRA    _FCS_RET, Z
                MOVE    0, @R0
                MOVE    MENU_FALCON, R8
                RSUB    _MNT_CFM_GET, 1
                MOVE    FC_MACH, R0
                MOVE    R8, @R0

                MOVE    LOG_FC_SWITCH, R8
                SYSCALL(puts, 1)
                MOVE    MNT_SHOWN, R0           ; _MNT_LOAD opens its window
                MOVE    0, @R0

                ; swap the remembered manual TOS of both machines
                MOVE    MNT_ON, R0
                CMP     0, @R0
                RBRA    _FCS_UNLD, Z
                MOVE    FC_CRT_TOS, R8
                MOVE    1, R9
                RSUB    _MNT_ENTRY, 1
                MOVE    R8, R1                  ; R1: entry of the TOS
                MOVE    CRTROM_MAN_MAX, R8      ; the entry behind the
                RSUB    _MNT_ENTRY, 1           ; CRTs/ROMs
                MOVE    R8, R2                  ; R2: TOS of the other machine
                MOVE    MNT_ENTRY_SZ, R3
_FCS_SWAP       MOVE    @R1, R4
                MOVE    @R2, @R1++
                MOVE    R4, @R2++
                SUB     1, R3
                RBRA    _FCS_SWAP, !Z
                MOVE    MNT_DIRTY, R0
                MOVE    1, @R0

                ; the manual TOS of the old machine is no longer loaded
_FCS_UNLD       MOVE    CRTROM_MAN_LDF, R0
                ADD     FC_CRT_TOS, R0
                CMP     0, @R0
                RBRA    _FCS_MAN, Z
                RSUB    FC_TOS_UNLOAD, 1

                ; the manual TOS of the new machine, if one is remembered
_FCS_MAN        MOVE    FC_CRT_TOS, R8
                MOVE    1, R9
                RSUB    _MNT_ENTRY, 1
                CMP     0, @R8
                RBRA    _FCS_AUTO, Z
                MOVE    FC_CRT_TOS, R8
                MOVE    1, R9
                RSUB    _MNT_LOAD, 1
                MOVE    CRTROM_MAN_LDF, R0      ; loaded?
                ADD     FC_CRT_TOS, R0
                CMP     0, @R0
                RBRA    _FCS_CART, !Z

                ; else the auto-load TOS of the new machine
_FCS_AUTO       MOVE    LOG_FC_AUTO, R8
                SYSCALL(puts, 1)
                RSUB    CRTROM_AUTOLOAD, 1

                ; the cartridge, if one is loaded
_FCS_CART       MOVE    CRTROM_MAN_LDF, R0
                ADD     CRT_ID_CART, R0
                CMP     0, @R0
                RBRA    _FCS_DONE, Z
                MOVE    CRT_ID_CART, R8
                MOVE    1, R9
                RSUB    _MNT_LOAD, 1

_FCS_DONE       MOVE    MNT_SHOWN, R0           ; hide the window, if shown
                CMP     0, @R0
                RBRA    _FCS_SAVE, Z
                MOVE    0, @R0
                RSUB    SCR$OSM_OFF, 1
_FCS_SAVE       RSUB    MNT_SAVE, 1             ; the swapped entries
_FCS_START      MOVE    M2M$CSR, R0
                AND     M2M$CSR_UN_RESET, @R0

_FCS_RET        SYSCALL(leave, 1)
                RET

; ----------------------------------------------------------------------------
; The manual TOS is no longer loaded (it was for the other machine): status
; of its device idle (the TOS loader ignores that), not marked in the menu,
; the menu shows its default text again
; ----------------------------------------------------------------------------

FC_TOS_UNLOAD   SYSCALL(enter, 1)
                MOVE    CRTROM_MAN_LDF, R0
                ADD     FC_CRT_TOS, R0
                MOVE    0, @R0
                MOVE    SCRATCH_HEX, R8
                RSUB    SAVE_DEVSEL, 1
                MOVE    CRTROM_MAN_DEV, R8
                ADD     FC_CRT_TOS, R8
                MOVE    @R8, R8                 ; R8: device id
                MOVE    CRTROM_CSR_STATUS, R9
                MOVE    CRTROM_CSR_ST_IDLE, R10
                RSUB    CRTROM_CSR_W, 1
                MOVE    SCRATCH_HEX, R8
                RSUB    RESTORE_DEVSEL, 1
                MOVE    FC_CRT_TOS, R8          ; menu index of the item
                RSUB    CRTROM_M_GI, 1
                RBRA    _FCTU_RET, !C
                MOVE    R9, R8                  ; R8: menu index
                XOR     R9, R9                  ; unmark it: the menu takes
                RSUB    M2M$SET_SETTING, 1      ; its marks from these bits
                                                ; when it opens (not
                                                ; M2M$FORCE_MENU: the menu is
                                                ; closed, OPTM_SET goes fatal)
_FCTU_RET       SYSCALL(leave, 1)
                RET
