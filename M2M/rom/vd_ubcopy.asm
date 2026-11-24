; ****************************************************************************
; MiSTer2MEGA65 (M2M) QNICE ROM
;
; MegaST: sector-wise data transfer for unbuffered virtual drives
;
; VD_UB_READ and VD_UB_WRITE (shell.asm) used to move every byte of a request
; through f32_fread/f32_fwrite: each byte went through FILE_RWB, READ_FDH,
; READ_B/WRITE_B, the device callback and SD$READ_BYTE/SD$WRITE_BYTE, plus
; four calls into the vdrives device. That is about 33 KB/s on the MEGA65
; (measured on hardware, issue #34).
;
; Now only one byte per sector goes through the FAT32 library. That byte
; makes the library do everything it has to do at a sector boundary: flush
; the old sector, follow the cluster chain, read the new sector into the
; 512-byte buffer of the SD controller and mark this file handle as the owner
; of the buffer (and, for writes, as dirty). The rest of the sector is then
; copied directly between the buffer of the SD controller and the sector
; buffer of the drive, and the index and access position in the file handle
; are advanced by the same amount, as FILE_RWB does it byte by byte. So the
; next byte through the library continues at the right place, and the
; sector, cluster and flush logic stay in the FAT32 library.
;
; VD_UBC_SIM defined: the drive buffer is VD_UBC_SIMBUF in RAM instead of the
; vdrives device (test in the QNICE emulator, CORE/sim/ubcopy)
;
; This machine is based on AtariST_MiSTer
; Powered by MiSTer2MEGA65
; MEGA65 port done by Chris Freeman in 2026 and licensed under GPL v3
; ****************************************************************************

; Read R9 bytes from the current position of the file R8 into the drive
; buffer (positions 0 .. R9 - 1); bytes behind the end of the file are zeros
; Input:   R8: file handle, R9: amount of bytes
; Output:  none, R8..R12 are changed
VD_UB_RDATA     INCRB

                MOVE    R8, R1                  ; R1: file handle
                MOVE    R9, R2                  ; R2: amount of bytes
                XOR     R3, R3                  ; R3: transmitted bytes

_VDUBRD_LOOP    CMP     R3, R2                  ; done?
                RBRA    _VDUBRD_RET, Z

                ; one byte through the FAT32 library
                MOVE    R1, R8
                SYSCALL(f32_fread, 1)
                CMP     0, R10                  ; EOF or error: send zeros
                RBRA    _VDUBRD_1, Z
                XOR     R9, R9
_VDUBRD_1       MOVE    R9, R4                  ; R4: byte
#ifdef VD_UBC_SIM
                MOVE    VD_UBC_SIMBUF, R8
                ADD     R3, R8
                MOVE    R4, @R8
#else
                MOVE    VD_B_ADDR, R8           ; write buffer: address
                MOVE    R3, R9
                RSUB    VD_CAD_WRITE, 1
                MOVE    VD_B_DOUT, R8           ; write buffer: data out
                MOVE    R4, R9
                RSUB    VD_CAD_WRITE, 1
                MOVE    VD_B_WREN, R8           ; strobe write enable
                MOVE    1, R9
                RSUB    VD_CAD_WRITE, 1
                XOR     R9, R9
                RSUB    VD_CAD_WRITE, 1
#endif
                ADD     1, R3

                ; the rest of the sector directly from the SD controller
                MOVE    R1, R8
                MOVE    R2, R9
                SUB     R3, R9
                RSUB    VD_UB_RUN, 1            ; R9: amount, R10: index
                CMP     0, R9
                RBRA    _VDUBRD_LOOP, Z
                MOVE    R9, R5                  ; R5: bytes of this run
                MOVE    R10, R6                 ; R6: index in the SD buffer
                MOVE    R1, R8
                RSUB    VD_UB_ADV, 1

#ifdef VD_UBC_SIM
                MOVE    IO$SD_DATA_POS, R8
                MOVE    IO$SD_DATA, R9
                MOVE    VD_UBC_SIMBUF, R10
                ADD     R3, R10
                ADD     R5, R3
_VDUBRD_FAST    MOVE    R6, @R8                 ; SD buffer position
                MOVE    @R9, @R10++             ; SD buffer -> drive buffer
                ADD     1, R6
                SUB     1, R5
                RBRA    _VDUBRD_FAST, !Z
#else
                MOVE    M2M$RAMROM_DEV, R8      ; select the vdrives device
                MOVE    VDRIVES_DEVICE, R9      ; and its control and data
                MOVE    @R9, @R8                ; window once for the run
                MOVE    M2M$RAMROM_4KWIN, R8
                MOVE    VD_WIN_CAD, @R8
                MOVE    IO$SD_DATA_POS, R8
                MOVE    IO$SD_DATA, R9
                MOVE    VD_B_ADDR, R10
                MOVE    VD_B_DOUT, R11
                MOVE    VD_B_WREN, R12
                ; fdc_bridge.vhd hands every second byte to the core clock
                ; domain without a handshake towards QNICE: it needs about
                ; 3 QNICE + 4 core clock cycles per word, this loop takes
                ; far longer for two bytes
_VDUBRD_FAST    MOVE    R6, @R8                 ; SD buffer position
                MOVE    R3, @R10                ; drive buffer address
                MOVE    @R9, @R11               ; SD buffer -> drive buffer
                MOVE    1, @R12                 ; strobe write enable
                MOVE    0, @R12
                ADD     1, R6
                ADD     1, R3
                SUB     1, R5
                RBRA    _VDUBRD_FAST, !Z
#endif
                RBRA    _VDUBRD_LOOP, 1

_VDUBRD_RET     DECRB
                RET

; Write R9 bytes of the drive buffer (positions 0 .. R9 - 1) of the drive R10
; to the current position of the file R8 (no flush)
; Input:   R8: file handle, R9: amount of bytes, R10: virtual drive number
; Output:  R9: 0 = OK, otherwise error code of f32_fwrite
;          R8, R10..R12 are changed
VD_UB_WDATA     INCRB

                MOVE    R8, R1                  ; R1: file handle
                MOVE    R9, R2                  ; R2: amount of bytes
                MOVE    R10, R0                 ; R0: drive number
                XOR     R3, R3                  ; R3: written bytes

_VDUBWD_LOOP    XOR     R9, R9                  ; R9 = 0: OK
                CMP     R3, R2                  ; done?
                RBRA    _VDUBWD_RET, Z

                ; one byte through the FAT32 library
#ifdef VD_UBC_SIM
                MOVE    VD_UBC_SIMBUF, R8
                ADD     R3, R8
                MOVE    @R8, R9
#else
                MOVE    VD_B_ADDR, R8           ; read buffer: address
                MOVE    R3, R9
                RSUB    VD_CAD_WRITE, 1
                MOVE    R0, R8                  ; read byte from the drive
                MOVE    VD_B_DIN, R9
                RSUB    VD_DRV_READ, 1
                MOVE    R8, R9
#endif
                MOVE    R1, R8                  ; write byte to the file
                SYSCALL(f32_fwrite, 1)
                CMP     0, R9                   ; write successful?
                RBRA    _VDUBWD_RET, !Z         ; no: return the error
                ADD     1, R3

                ; the rest of the sector directly into the SD controller
                ; (the byte above has set the dirty flag of the sector)
                MOVE    R1, R8
                MOVE    R2, R9
                SUB     R3, R9
                RSUB    VD_UB_RUN, 1            ; R9: amount, R10: index
                CMP     0, R9
                RBRA    _VDUBWD_LOOP, Z
                MOVE    R9, R5                  ; R5: bytes of this run
                MOVE    R10, R6                 ; R6: index in the SD buffer
                MOVE    R1, R8
                RSUB    VD_UB_ADV, 1

#ifdef VD_UBC_SIM
                MOVE    IO$SD_DATA_POS, R8
                MOVE    IO$SD_DATA, R9
                MOVE    VD_UBC_SIMBUF, R10
                ADD     R3, R10
                ADD     R5, R3
_VDUBWD_FAST    MOVE    R6, @R8                 ; SD buffer position
                MOVE    @R10++, @R9             ; drive buffer -> SD buffer
                ADD     1, R6
                SUB     1, R5
                RBRA    _VDUBWD_FAST, !Z
#else
                MOVE    M2M$RAMROM_DEV, R8      ; select the vdrives device
                MOVE    VDRIVES_DEVICE, R9
                MOVE    @R9, @R8
                MOVE    M2M$RAMROM_4KWIN, R8    ; R8: window register
                MOVE    VD_WIN_DRV, R7          ; R7: window of the drive
                ADD     R0, R7
                MOVE    IO$SD_DATA_POS, R9
                MOVE    IO$SD_DATA, R10
                MOVE    VD_B_ADDR, R11
                MOVE    VD_B_DIN, R12
                ; reading VD_B_DIN stalls QNICE until the byte has come back
                ; from the core clock domain (C_VD_DIN_WAIT in mega65.vhd)
_VDUBWD_FAST    MOVE    VD_WIN_CAD, @R8
                MOVE    R3, @R11                ; drive buffer address
                MOVE    R7, @R8
                MOVE    R6, @R9                 ; SD buffer position
                MOVE    @R12, @R10              ; drive buffer -> SD buffer
                ADD     1, R6
                ADD     1, R3
                SUB     1, R5
                RBRA    _VDUBWD_FAST, !Z
#endif
                RBRA    _VDUBWD_LOOP, 1

_VDUBWD_RET     DECRB
                RET

; How many bytes behind the current position of the file can be copied
; directly between the buffer of the SD controller and the drive buffer: if
; the file handle owns the SD buffer, at most to the end of the sector, to the
; end of the file and R9 bytes
; Input:   R8: file handle, R9: bytes still wanted
; Output:  R9: amount (0 .. 511), R10: index in the SD buffer
;          R8 unchanged
VD_UB_RUN       INCRB

                MOVE    R9, R2                  ; R2: bytes wanted
                XOR     R9, R9                  ; R9: amount = 0

                MOVE    R8, R0                  ; does the file handle own
                ADD     FAT32$FDH_DEVICE, R0    ; the SD buffer?
                MOVE    @R0, R0
                ADD     FAT32$DEV_BUFFERED_FDH, R0
                CMP     @R0, R8
                RBRA    _VDUBRUN_RET, !Z        ; no

                MOVE    R8, R0                  ; R10: index
                ADD     FAT32$FDH_INDEX, R0
                MOVE    @R0, R10
                MOVE    FAT32$SECTOR_SIZE, R1   ; R1: rest of the sector
                CMP     R10, R1                 ; index > 512?
                RBRA    _VDUBRUN_RET, N         ; yes: nothing (never happens)
                SUB     R10, R1
                CMP     R1, R2                  ; more than wanted?
                RBRA    _VDUBRUN_1, !N          ; no
                MOVE    R2, R1                  ; yes: as many as wanted

_VDUBRUN_1      MOVE    R8, R0                  ; R4|R3: rest of the file
                ADD     FAT32$FDH_SIZE_LO, R0   ; (size - access position)
                MOVE    @R0, R3
                MOVE    R8, R0
                ADD     FAT32$FDH_SIZE_HI, R0
                MOVE    @R0, R4
                MOVE    R8, R0
                ADD     FAT32$FDH_ACCESS_LO, R0
                SUB     @R0, R3
                MOVE    R8, R0
                ADD     FAT32$FDH_ACCESS_HI, R0
                SUBC    @R0, R4
                CMP     0, R4                   ; 64 KB or more: no limit
                RBRA    _VDUBRUN_2, !Z
                CMP     R1, R3                  ; more than the rest?
                RBRA    _VDUBRUN_2, !N          ; no
                MOVE    R3, R1                  ; yes: only the rest

_VDUBRUN_2      MOVE    R1, R9

_VDUBRUN_RET    DECRB
                RET

; Advance the index and the access position of the file R8 by R9 bytes, as
; FAT32$FILE_RWB does after each byte
; Input:   R8: file handle, R9: amount
; Output:  none, R8, R9 unchanged
VD_UB_ADV       INCRB

                MOVE    R8, R0
                ADD     FAT32$FDH_INDEX, R0
                ADD     R9, @R0
                MOVE    R8, R0
                ADD     FAT32$FDH_ACCESS_LO, R0
                MOVE    R8, R1
                ADD     FAT32$FDH_ACCESS_HI, R1
                ADD     R9, @R0
                ADDC    0, @R1

                DECRB
                RET
