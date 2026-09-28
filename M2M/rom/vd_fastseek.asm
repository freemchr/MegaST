; ****************************************************************************
; MegaST (Atari ST/STe for MEGA65): fast seek for unbuffered virtual drives
;
; Included by shell.asm. Needs the variables VD_UB_CP* (shell_vars.asm).
; Test: CORE/sim/fastseek (QNICE emulator, FAT32 image with fragmented files)
;
; Atari ST port 2026, licensed under GPL v3
; ****************************************************************************

; ----------------------------------------------------------------------------
; MegaST: fast seek for unbuffered virtual drives (large hard disk images)
;
; FAT32$FILE_SEEK (f32_fseek) always starts at the beginning of the file and
; follows the cluster chain sector by sector, i.e. it reads the FAT at every
; cluster boundary: seeking far into a large image takes seconds. The fast
; seek starts at the current position of the file (if the target is behind
; it) or at a checkpoint: the cluster of every 2^shift sectors of the file,
; which is recorded whenever a seek passes it. The shift is chosen when the
; image is mounted: VD_UB_CP_SHIFT (12: 2 MB) or more, so that the 512
; checkpoints cover the whole image (up to 4 GB: 8 MB). Everything else works
; like FAT32$FILE_SEEK. The image files never change their size, so the
; cluster chain and the checkpoints stay valid while a file is mounted.
;
; There are VD_UB_CP_SLOTS tables: word 0 = drive number that owns the table
; (0xFFFF = none), word 1 = shift, then VD_UB_CP_ENTRIES (512) times cluster
; lo, cluster hi (cluster 0 = no checkpoint, yet; the first data cluster of
; FAT32 is 2).
; ----------------------------------------------------------------------------

#ifndef VD_UB_CP_SHIFT
#define VD_UB_CP_SHIFT 12
#endif

; Claim the checkpoint table for the drive in R8 (called after a mount, R9:
; file handle of the image): reuse the table of this drive or a free one,
; otherwise take the first one, then choose the shift and delete all
; checkpoints
VD_UB_CP_CLAIM  INCRB
                MOVE    VD_UB_CP, R0            ; R0: table of this drive?
                MOVE    VD_UB_CP_SLOTS, R1
_VDUBCC_1       CMP     @R0, R8
                RBRA    _VDUBCC_CLR, Z
                ADD     VD_UB_CP_SLOTSZ, R0
                SUB     1, R1
                RBRA    _VDUBCC_1, !Z
                MOVE    VD_UB_CP, R0            ; R0: free table?
                MOVE    VD_UB_CP_SLOTS, R1
_VDUBCC_2       CMP     0xFFFF, @R0
                RBRA    _VDUBCC_CLR, Z
                ADD     VD_UB_CP_SLOTSZ, R0
                SUB     1, R1
                RBRA    _VDUBCC_2, !Z
                MOVE    VD_UB_CP, R0            ; take the first table

_VDUBCC_CLR     MOVE    R8, @R0++               ; owner

                ; shift: the 512 checkpoints have to cover the file:
                ; file size < 512 * 512 * 2^shift = 2^(18 + shift), i.e.
                ; (file size high word >> (shift + 2)) = 0
                MOVE    R9, R2
                ADD     FAT32$FDH_SIZE_HI, R2
                MOVE    @R2, R2                 ; R2: file size high word
                MOVE    VD_UB_CP_SHIFT, R1      ; R1: shift
_VDUBCC_S       MOVE    R1, R3
                ADD     2, R3
                MOVE    R2, R4
                AND     0xFFFB, SR              ; clear C (SHR fills with C)
                SHR     R3, R4
                RBRA    _VDUBCC_S2, Z
                ADD     1, R1
                RBRA    _VDUBCC_S, 1
_VDUBCC_S2      MOVE    R1, @R0++               ; shift

                MOVE    VD_UB_CP_ENTRIES, R1
_VDUBCC_3       MOVE    0, @R0++                ; no checkpoint
                MOVE    0, @R0++
                SUB     1, R1
                RBRA    _VDUBCC_3, !Z

                DECRB
                RET

; Seek like FAT32$FILE_SEEK, but fast (see above)
; Input:   R8: file handle
;          R9: position low word, R10: position high word
;          R11: drive number (checkpoint table)
; Output:  R8: file handle
;          R9: 0=OK, otherwise error code
;          R10, R11 may be changed
VD_UB_FSEEK     INCRB

                MOVE    R8, R0                  ; R0: file handle
                MOVE    R9, R1                  ; R2|R1: target position
                MOVE    R10, R2

                ; R3: checkpoint table of the drive (0: none)
                MOVE    VD_UB_CP, R3
                MOVE    VD_UB_CP_SLOTS, R4
_VDUBF_T1       CMP     @R3, R11
                RBRA    _VDUBF_T2, Z
                ADD     VD_UB_CP_SLOTSZ, R3
                SUB     1, R4
                RBRA    _VDUBF_T1, !Z
                SYSCALL(f32_fseek, 1)           ; no table: standard seek
                RBRA    _VDUBF_RET, 1
_VDUBF_T2       ADD     2, R3                   ; R3: first checkpoint

                ; target behind the end of the file?
                MOVE    R0, R4
                ADD     FAT32$FDH_SIZE_LO, R4
                MOVE    @R4, R4
                MOVE    R0, R5
                ADD     FAT32$FDH_SIZE_HI, R5
                MOVE    @R5, R5
                SUB     R1, R4
                SUBC    R2, R5
                RBRA    _VDUBF_1, !C            ; target <= file size
                MOVE    FAT23$ERR_SEEKTOOLARGE, R9
                RBRA    _VDUBF_RET, 1

                ; flush the sector buffer (using the handle of its owner)
                ; before the position of any file changes
_VDUBF_1        MOVE    R0, R8
                ADD     FAT32$FDH_DEVICE, R8
                MOVE    @R8, R8
                ADD     FAT32$DEV_BUFFERED_FDH, R8
                MOVE    @R8, R8
                RSUB    FAT32$FLUSH, 1
                CMP     0, R9
                RBRA    _VDUBF_RET, !Z

                ; R5|R4: target sector = target position / 512
                MOVE    R1, R4
                AND     0xFFFB, SR              ; clear C (SHR fills with C)
                SHR     9, R4
                MOVE    R2, R6
                AND     0x01FF, R6
                AND     0xFFFD, SR              ; clear X (SHL fills with X)
                SHL     7, R6
                OR      R6, R4
                MOVE    R2, R5
                AND     0xFFFB, SR              ; clear C (SHR fills with C)
                SHR     9, R5

                ; R7|R6: current sector = (access position - index) / 512
                MOVE    R0, R8
                ADD     FAT32$FDH_ACCESS_LO, R8
                MOVE    @R8, R6
                MOVE    R0, R8
                ADD     FAT32$FDH_ACCESS_HI, R8
                MOVE    @R8, R7
                MOVE    R0, R8
                ADD     FAT32$FDH_INDEX, R8
                SUB     @R8, R6
                SUBC    0, R7
                MOVE    R6, R8
                AND     0xFFFB, SR              ; clear C (SHR fills with C)
                SHR     9, R8
                MOVE    R7, R9
                AND     0x01FF, R9
                AND     0xFFFD, SR              ; clear X (SHL fills with X)
                SHL     7, R9
                OR      R9, R8
                MOVE    R8, R6
                AND     0xFFFB, SR              ; clear C (SHR fills with C)
                SHR     9, R7

                ; R10|R9: sector of the best checkpoint <= target sector:
                ; checkpoint k = target sector >> shift, k < VD_UB_CP_ENTRIES,
                ; go back to the next valid one, k = 0: start of the file
                MOVE    R4, R8                  ; R8: k = R5|R4 >> shift
                MOVE    R5, R9
                RSUB    _VDUBF_K, 1
                CMP     VD_UB_CP_ENTRIES, R8
                RBRA    _VDUBF_2B, N            ; k < entries: OK
                MOVE    VD_UB_CP_ENTRIES, R8
                SUB     1, R8
_VDUBF_2B       CMP     0, R8                   ; k = 0: start of the file
                RBRA    _VDUBF_2D, Z
                MOVE    R8, R11                 ; valid checkpoint?
                ADD     R11, R11
                ADD     R3, R11
                CMP     0, @R11++
                RBRA    _VDUBF_2D, !Z
                CMP     0, @R11
                RBRA    _VDUBF_2D, !Z
                SUB     1, R8                   ; no: previous one
                RBRA    _VDUBF_2B, 1
_VDUBF_2D       RSUB    _VDUBF_KSEC, 1          ; R10|R9 = k << shift

                ; start at the current sector if it is between the
                ; checkpoint and the target (R10|R9 <= R7|R6 <= R5|R4)
                MOVE    R4, R11                 ; target - current >= 0?
                MOVE    R5, R12
                SUB     R6, R11
                SUBC    R7, R12
                RBRA    _VDUBF_3, C             ; no: use the checkpoint
                MOVE    R6, R11                 ; current - checkpoint >= 0?
                MOVE    R7, R12
                SUB     R9, R11
                SUBC    R10, R12
                RBRA    _VDUBF_4, !C            ; yes: use the current sector

                ; start at the checkpoint (sector 0 of its cluster)
_VDUBF_3        MOVE    R9, R6                  ; R7|R6: current sector
                MOVE    R10, R7
                MOVE    R8, R11                 ; R12|R11: cluster
                CMP     0, R11
                RBRA    _VDUBF_3A, !Z
                MOVE    R0, R11                 ; k = 0: first cluster
                ADD     FAT32$FDH_START_CLUS_LO, R11
                MOVE    @R11, R11
                MOVE    R0, R12
                ADD     FAT32$FDH_START_CLUS_HI, R12
                MOVE    @R12, R12
                RBRA    _VDUBF_3B, 1
_VDUBF_3A       ADD     R11, R11                ; checkpoint k
                ADD     R3, R11
                MOVE    @R11++, R12             ; (swapped below)
                MOVE    @R11, R11
                MOVE    R12, R8
                MOVE    R11, R12
                MOVE    R8, R11
_VDUBF_3B       MOVE    R0, R8
                ADD     FAT32$FDH_CLUSTER_LO, R8
                MOVE    R11, @R8
                MOVE    R0, R8
                ADD     FAT32$FDH_CLUSTER_HI, R8
                MOVE    R12, @R8
                MOVE    R0, R8
                ADD     FAT32$FDH_SECTOR, R8
                MOVE    0, @R8
                MOVE    R0, R8
                ADD     FAT32$FDH_INDEX, R8
                MOVE    0, @R8

                ; push the file handle sector by sector to the target sector
                ; (seek mode: the data is not read), record the checkpoints
_VDUBF_4        CMP     R6, R4                  ; current = target?
                RBRA    _VDUBF_5, !Z
                CMP     R7, R5
                RBRA    _VDUBF_6, Z             ; yes: done
_VDUBF_5        MOVE    R0, R8
                ADD     FAT32$FDH_INDEX, R8
                MOVE    FAT32$SECTOR_SIZE, @R8  ; next sector
                MOVE    R0, R8
                MOVE    1, R9                   ; seek mode
                RSUB    FAT32$READ_FDH, 1
                CMP     0, R9
                RBRA    _VDUBF_RET, !Z          ; error
                ADD     1, R6                   ; current sector + 1
                ADDC    0, R7

                MOVE    R3, R8                  ; checkpoint (every 2^shift)?
                MOVE    @--R8, R8               ; R8: shift
                MOVE    1, R9
                AND     0xFFFD, SR              ; clear X (SHL fills with X)
                SHL     R8, R9
                SUB     1, R9                   ; R9: 2^shift - 1
                AND     R6, R9
                RBRA    _VDUBF_4, !Z
                MOVE    R0, R8                  ; sector 0 of the cluster?
                ADD     FAT32$FDH_SECTOR, R8
                CMP     0, @R8
                RBRA    _VDUBF_4, !Z
                MOVE    R6, R8                  ; R8: k = R7|R6 >> shift
                MOVE    R7, R9
                RSUB    _VDUBF_K, 1
                CMP     VD_UB_CP_ENTRIES, R8
                RBRA    _VDUBF_4, !N            ; k >= entries: no room
                ADD     R8, R8
                ADD     R3, R8
                MOVE    R0, R9
                ADD     FAT32$FDH_CLUSTER_LO, R9
                MOVE    @R9, @R8++
                MOVE    R0, R9
                ADD     FAT32$FDH_CLUSTER_HI, R9
                MOVE    @R9, @R8
                RBRA    _VDUBF_4, 1

                ; set the index and the access position to the target
_VDUBF_6        MOVE    R0, R8
                ADD     FAT32$FDH_INDEX, R8
                MOVE    R1, @R8
                AND     0x01FF, @R8
                MOVE    R0, R8
                ADD     FAT32$FDH_ACCESS_LO, R8
                MOVE    R1, @R8
                MOVE    R0, R8
                ADD     FAT32$FDH_ACCESS_HI, R8
                MOVE    R2, @R8

                ; read the target sector and become the owner of the buffer
                MOVE    R0, R8
                ADD     FAT32$FDH_DEVICE, R8
                MOVE    @R8, R8                 ; R8: device handle
                MOVE    R0, R9
                ADD     FAT32$FDH_CLUSTER_LO, R9
                MOVE    @R9, R9
                MOVE    R0, R10
                ADD     FAT32$FDH_CLUSTER_HI, R10
                MOVE    @R10, R10
                MOVE    R0, R11
                ADD     FAT32$FDH_SECTOR, R11
                MOVE    @R11, R11
                XOR     R12, R12                ; read
                RSUB    FAT32$RW_SIC, 1
                CMP     0, R9
                RBRA    _VDUBF_RET, !Z
                ADD     FAT32$DEV_BUFFERED_FDH, R8
                MOVE    R0, @R8
                XOR     R9, R9

_VDUBF_RET      MOVE    R0, R8
                DECRB
                RET

; k = sector R9|R8 >> shift (R3 of VD_UB_FSEEK: first checkpoint, the shift
; is the word in front of it); output: R8, R9, R11 and R12 are changed
; (k < 512, so the bits of the high word that are shifted out are 0)
_VDUBF_K        MOVE    R3, R11
                MOVE    @--R11, R11             ; R11: shift
                AND     0xFFFB, SR              ; clear C (SHR fills with C)
                SHR     R11, R8                 ; low word >> shift
                MOVE    16, R12
                SUB     R11, R12                ; R12: 16 - shift
                AND     0xFFFD, SR              ; clear X (SHL fills with X)
                SHL     R12, R9                 ; high word << (16 - shift)
                OR      R9, R8
                RET

; sector R10|R9 = k (R8) << shift (see _VDUBF_K); R11, R12 are changed
_VDUBF_KSEC     MOVE    R3, R11
                MOVE    @--R11, R11             ; R11: shift
                MOVE    R8, R9
                AND     0xFFFD, SR              ; clear X (SHL fills with X)
                SHL     R11, R9                 ; low word: k << shift
                MOVE    16, R12
                SUB     R11, R12                ; R12: 16 - shift
                MOVE    R8, R10
                AND     0xFFFB, SR              ; clear C (SHR fills with C)
                SHR     R12, R10                ; high word: k >> (16 - shift)
                RET
