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
; stays in reset until the menu closes. FC_SWITCH (main loop, CORE_LOOP) then loads
; the TOS again for the new machine: the manually loaded TOS when there is
; one (its path is kept by mntmem.asm), else the auto-load TOS
; (/atarist/tos.img), and a loaded cartridge. Then the new machine starts.
;
; This machine is based on AtariST_MiSTer
; Powered by MiSTer2MEGA65
; MEGA65 port done by Chris Freeman in 2026 and licensed under GPL v3
; ****************************************************************************

FC_CRT_TOS      .EQU    0                       ; C_CRTROMS_MAN (globals.vhd)

LOG_FC_SWITCH   .ASCII_W "Machine: ST <-> Falcon, loading TOS again\n"
LOG_FC_AUTO     .ASCII_W "Machine: no manual TOS to reload, auto-load TOS\n"

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

                ; the manual TOS, if one is loaded and its path is known
                MOVE    CRTROM_MAN_LDF, R0
                ADD     FC_CRT_TOS, R0
                CMP     0, @R0
                RBRA    _FCS_AUTO, Z
                MOVE    FC_CRT_TOS, R8
                MOVE    1, R9
                RSUB    _MNT_ENTRY, 1
                CMP     0, @R8
                RBRA    _FCS_MAN, !Z
                MOVE    LOG_FC_AUTO, R8
                SYSCALL(puts, 1)
_FCS_AUTO       RSUB    CRTROM_AUTOLOAD, 1
                RBRA    _FCS_CART, 1
_FCS_MAN        MOVE    FC_CRT_TOS, R8
                MOVE    1, R9
                RSUB    _MNT_LOAD, 1

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
                RBRA    _FCS_START, Z
                MOVE    0, @R0
                RSUB    SCR$OSM_OFF, 1
_FCS_START      MOVE    M2M$CSR, R0
                AND     M2M$CSR_UN_RESET, @R0

_FCS_RET        SYSCALL(leave, 1)
                RET
