; ****************************************************************************
; MegaST: the NVRAM of the Falcon on the SD card
;
; The 50 NVRAM bytes of the MC146818 of the Falcon (boot video mode, language,
; keyboard, boot device, ...) live in a 64 byte buffer in the core (device
; C_DEV_FC_NVRAM, globals.vhd; falcon_m65.sv): bytes 0..49 are the NVRAM
; bytes 14..63, byte 62 is a change counter, byte 63 is $A5 when 0..49 are
; valid. The core restores the NVRAM from the buffer when the Falcon starts
; and copies every change of the NVRAM back with the next counter value.
;
; NV_RESTORE (PREP_START, the core is still held in reset) loads the file
; NV_FNAME into the buffer. Like the settings file it has to exist with the
; exact size (64 bytes), otherwise the feature is off; a file of 0xFF bytes
; means "use the defaults" (byte 63 is not $A5) and gets them at the first
; save. NV_POLL (main loop, CORE_LOOP) saves the buffer when the counter
; changed, at most about once per second and not while the write cache of
; a vdrive is dirty (like MNT_SAVE, M2M/rom/mntmem.asm).
;
; This machine is based on AtariST_MiSTer
; Powered by MiSTer2MEGA65
; MEGA65 port done by Chris Freeman in 2026 and licensed under GPL v3
; ****************************************************************************

NV_DEVICE       .EQU    0x0106                  ; C_DEV_FC_NVRAM (globals.vhd)
NV_SIZE         .EQU    64
NV_CNT          .EQU    62                      ; change counter
NV_MARK         .EQU    63                      ; $A5: the image is valid
NV_TICKS        .EQU    20000                   ; main loop runs between checks

NV_FNAME        .ASCII_W "/atarist/fcnvram"
LOG_NV_ON       .ASCII_W "Falcon NVRAM: /atarist/fcnvram loaded\n"
LOG_NV_OFF      .ASCII_W "Falcon NVRAM: no /atarist/fcnvram with 64 bytes, not saved\n"
LOG_NV_SAVED    .ASCII_W "Falcon NVRAM: saved\n"
LOG_NV_EWRITE   .ASCII_W "Falcon NVRAM: write error, not saved any more\n"

; ----------------------------------------------------------------------------
; Load the file into the buffer of the core
; Called by PREP_START, i.e. after MNT_RESTORE (the SD card is mounted then,
; if it is there at all) and while the core is still held in reset.
; ----------------------------------------------------------------------------

NV_RESTORE      SYSCALL(enter, 1)

                MOVE    NV_ON, R0
                MOVE    0, @R0
                MOVE    NV_COUNT, R0
                MOVE    0, @R0

                MOVE    HANDLE_DEV, R8          ; SD card mounted?
                CMP     0, @R8
                RBRA    _NVR_OFF, Z             ; no: feature off

                MOVE    NV_FDH, R9              ; open the file
                MOVE    NV_FNAME, R10
                XOR     R11, R11
                SYSCALL(f32_fopen, 1)
                CMP     0, R10
                RBRA    _NVR_OFF, !Z

                MOVE    R9, R8                  ; R8: file handle
                MOVE    R9, R0
                ADD     FAT32$FDH_SIZE_HI, R0
                CMP     0, @R0
                RBRA    _NVR_OFF, !Z
                MOVE    R9, R0
                ADD     FAT32$FDH_SIZE_LO, R0
                CMP     NV_SIZE, @R0
                RBRA    _NVR_OFF, !Z

                ; the bytes of the file into the buffer
                MOVE    M2M$RAMROM_DEV, R0
                MOVE    NV_DEVICE, @R0
                MOVE    M2M$RAMROM_4KWIN, R0
                MOVE    0, @R0
                MOVE    M2M$RAMROM_DATA, R0     ; R0: buffer
                MOVE    NV_SIZE, R1             ; R1: bytes to go
_NVR_1          SYSCALL(f32_fread, 1)           ; R9: byte
                CMP     0, R10
                RBRA    _NVR_OFF, !Z
                RSUB    NV_SEL, 1               ; (the file system may use it)
                MOVE    R9, @R0++
                SUB     1, R1
                RBRA    _NVR_1, !Z

                MOVE    M2M$RAMROM_DATA, R0     ; the counter as loaded
                ADD     NV_CNT, R0
                MOVE    @R0, R1
                AND     0x00FF, R1
                MOVE    NV_LAST, R0
                MOVE    R1, @R0
                MOVE    NV_ON, R0
                MOVE    1, @R0
                MOVE    LOG_NV_ON, R8
                RBRA    _NVR_LOG, 1

_NVR_OFF        MOVE    LOG_NV_OFF, R8
_NVR_LOG        SYSCALL(puts, 1)

                SYSCALL(leave, 1)
                RET

; ----------------------------------------------------------------------------
; Save the buffer to the file when the core changed it
; Called from the main loop (CORE_LOOP).
; ----------------------------------------------------------------------------

NV_POLL         SYSCALL(enter, 1)

                MOVE    NV_ON, R0
                CMP     0, @R0
                RBRA    _NVP_RET, Z
                MOVE    NV_COUNT, R0            ; time for a check?
                SUB     1, @R0
                RBRA    _NVP_RET, !N
                MOVE    NV_TICKS, @R0

                MOVE    M2M$RAMROM_DEV, R0
                MOVE    NV_DEVICE, @R0
                MOVE    M2M$RAMROM_4KWIN, R0
                MOVE    0, @R0
                MOVE    M2M$RAMROM_DATA, R0
                ADD     NV_MARK, R0
                MOVE    @R0, R1
                AND     0x00FF, R1
                CMP     0x00A5, R1              ; a valid image?
                RBRA    _NVP_RET, !Z
                MOVE    M2M$RAMROM_DATA, R0
                ADD     NV_CNT, R0
                MOVE    @R0, R2
                AND     0x00FF, R2              ; R2: counter
                MOVE    NV_LAST, R0
                CMP     R2, @R0                 ; changed?
                RBRA    _NVP_RET, Z

                MOVE    HANDLE_DEV, R0          ; SD card not mounted (it is
                CMP     0, @R0                  ; re-mounted after a card
                RBRA    _NVP_RET, Z             ; change): try again later

                ; postpone while the write cache of a vdrive is dirty
                RSUB    VD_ACTIVE, 1
                RBRA    _NVP_2, !C
                MOVE    R8, R3                  ; R3: amount of vdrives
                XOR     R1, R1                  ; R1: vdrive id
_NVP_1          MOVE    R1, R8
                MOVE    VD_CACHE_DIRTY, R9
                RSUB    VD_DRV_READ, 1
                CMP     0, R8                   ; dirty?
                RBRA    _NVP_RET, !Z            ; yes: try again later
                ADD     1, R1
                CMP     R3, R1
                RBRA    _NVP_1, !Z

_NVP_2          MOVE    HANDLE_DEV, R8          ; open the file
                MOVE    NV_FDH, R9
                MOVE    NV_FNAME, R10
                XOR     R11, R11
                SYSCALL(f32_fopen, 1)
                CMP     0, R10
                RBRA    _NVP_EWR, !Z

                MOVE    R9, R8                  ; R8: file handle
                MOVE    M2M$RAMROM_DEV, R0      ; (the file system may have
                MOVE    NV_DEVICE, @R0          ; used the device window)
                MOVE    M2M$RAMROM_4KWIN, R0
                MOVE    0, @R0
                XOR     R1, R1                  ; R1: byte index
_NVP_3          RSUB    NV_SEL, 1
                MOVE    M2M$RAMROM_DATA, R0
                ADD     R1, R0
                MOVE    @R0, R9
                AND     0x00FF, R9
                SYSCALL(f32_fwrite, 1)
                CMP     0, R9
                RBRA    _NVP_EWR, !Z
                ADD     1, R1
                CMP     NV_SIZE, R1
                RBRA    _NVP_3, !Z
                SYSCALL(f32_fflush, 1)
                CMP     0, R9
                RBRA    _NVP_EWR, !Z

                MOVE    NV_LAST, R0             ; saved: the counter of the
                MOVE    R2, @R0                 ; data written (a newer one
                MOVE    LOG_NV_SAVED, R8        ; is saved at the next check)
                SYSCALL(puts, 1)
                RBRA    _NVP_RET, 1

_NVP_EWR        MOVE    LOG_NV_EWRITE, R8       ; stop for this session
                SYSCALL(puts, 1)
                MOVE    NV_ON, R0
                MOVE    0, @R0

_NVP_RET        SYSCALL(leave, 1)
                RET

; Select the buffer in the device window; all registers unchanged
NV_SEL          INCRB
                MOVE    M2M$RAMROM_DEV, R0
                MOVE    NV_DEVICE, @R0
                MOVE    M2M$RAMROM_4KWIN, R0
                MOVE    0, @R0
                DECRB
                RET
