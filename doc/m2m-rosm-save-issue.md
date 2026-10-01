**Title:** ROSM_SAVE hangs forever when a core has more than one virtual drive

**Framework version:** V2.0.1; the code is unchanged on `develop`/default branch (`M2M/rom/options.asm`, lines 690-697, as of 7096eea)

### Summary

When "remember settings" is active (the config file exists and has the right size) and the core has two or more virtual drives, closing the on-screen menu hangs the QNICE firmware in an endless loop inside `ROSM_SAVE`. The menu cannot be opened again, and anything served by the firmware (virtual drive reads/writes) stops. No FATAL message is shown.

### Cause

The loop that checks the write caches of all virtual drives keeps the drive number in R8, but `VD_DRV_READ` returns the register value in R8:

```
                RSUB    VD_ACTIVE, 1            ; any vdrives at all?
                RBRA    _ROSMS_1, !C            ; no, so no danger of corruptn
                MOVE    R8, R0                  ; R0: amount of vdrives
                XOR     R8, R8                  ; vdrive id
_ROSMS_0        MOVE    VD_CACHE_DIRTY, R9
                RSUB    VD_DRV_READ, 1          ; get dirty flag for curr. drv  <-- R8 := dirty flag
                CMP     0, R8                   ; dirty?
                RBRA    _ROSMS_NOWR, !Z         ; yes: do not save
                ADD     1, R8                   ; no: check next vdrive         <-- R8 = 0 + 1 = 1, always
                CMP     R0, R8                  ; done?
                RBRA    _ROSMS_0, !Z            ; no: next iteration
```

After the first iteration R8 is always "dirty flag + 1" = 1. With exactly one virtual drive the loop ends by coincidence (R0 = 1); with two or more it never ends. It also never checks drives other than drive 1.

### How to reproduce

1. A core with `VDNUM` >= 2 (for example two floppy drives) and `SAVE_SETTINGS = true`.
2. A valid config file on the SD card (exactly `OPTM_SIZE` bytes, e.g. filled with 0xFF).
3. Open the menu with Help and close it again.

Result: the firmware loops in `_ROSMS_0`. Found on a MEGA65 R6 by sampling the QNICE address bus over JTAG while hung; the samples only ever showed `_ROSMS_0` and `VD_DRV_READ`.

With a config file of the wrong size ("Corrupt config file", settings are not saved), the hang does not occur, which makes this easy to miss during development.

### Fix

Keep the drive number in a register that `VD_DRV_READ` does not overwrite (R1 is free at this point; it is set again before its next use in `ROSM_SAVE`):

```
                MOVE    R8, R0                  ; R0: amount of vdrives
                XOR     R1, R1                  ; R1: vdrive id
_ROSMS_0        MOVE    R1, R8                  ; R8: vdrive id
                MOVE    VD_CACHE_DIRTY, R9
                RSUB    VD_DRV_READ, 1          ; get dirty flag for curr. drv
                CMP     0, R8                   ; dirty?
                RBRA    _ROSMS_NOWR, !Z         ; yes: do not save
                ADD     1, R1                   ; no: check next vdrive
                CMP     R0, R1                  ; done?
                RBRA    _ROSMS_0, !Z            ; no: next iteration
```

Found in a MEGA65 R6 port of the MiSTer Atari ST core (3 virtual drives: 2 floppies, 1 hard disk). [TODO before posting: confirm the fix on hardware]
