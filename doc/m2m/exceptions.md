How to update MegaST
====================

The following changes have been made to MiSTer (AtariST_MiSTer), MiSTer2MEGA65 and QNICE.
When you update one of these, re-apply the changes described here. Changes in the source code are
marked with `MegaST`, `MEGA65` or `Atari ST for MEGA65` comments, so `grep` finds them.

MiSTer core AtariST_MiSTer
--------------------------

`CORE/AtariST_MiSTer/` is a copy of https://github.com/MiSTer-devel/AtariST_MiSTer at commit `426ef87`
(June 2026), not a submodule. The MiSTer framework parts (`sys/`, `AtariST.sv` with `hps_io`) are not
used: `CORE/verilog/atarist_m65.sv` is the Atari ST machine of `AtariST.sv` without the MiSTer
framework. When updating, compare the new `AtariST.sv` with `atarist_m65.sv` and carry over the changes.

Changes to files in `CORE/AtariST_MiSTer/rtl/` (all marked with `MEGA65` comments):

* `ikbd/ikbd.sv`: additional input `matrix_ext` for the MEGA65 keyboard matrix
* `ikbd/rom/MCU_BIROM.v`: loads `ikbd.mem` (a copy of `ikbd.hex`), which is part of the Vivado project
* `stBlitter.sv`: wrapper `stBlitter_m65` with plain ports (Vivado: no struct type across files)
* `gstmcu/hdegen.v`: `de` is a `reg` (it is assigned in an `always` block)
* `fdc1772/fdc1772.sv`: complete sensitivity list of the floppy demultiplexer
* `ikbd/hd63701/HD63701.v`: removed a stray carriage return inside a comment
* `mfp/usart_top.vhd`: `entity` keyword for the direct entity instantiation
* `dma.v`: outputs `dio_fifo_used` (DMA FIFO fill level), `dio_cmd_start` and `dio_fifo_reset`
  (new ACSI command, DMA direction toggle), all for the ACSI controller
* `acsi.v`: output `cmd_start`; the first byte of a new command clears `busy`, so the late ack of a
  cancelled command (the driver timed out and retries) is not taken as the answer to the new one
* `ym2149.sv`: output `IOB_dir` (port B direction, for the printer port); fixed a typo when port B
  is read in output mode
* `gstmcu/gstshifter.v`: output `PIX_ACTIVE` (graphics area, for cropping the border)

Replaced, not modified (the MiSTer file is not in the Vivado project):

* `sdram.v` -> `CORE/verilog/sdram_m65.v`: Xilinx version (ODDR clock, IOB registers, DQM pins)
* `CEGen.vhd` -> `CORE/verilog/cegen_m65.v`: integer ports are not allowed on Vivado's language boundary
* The ACSI commands, executed by the ARM on MiSTer (`Main_MiSTer/support/st/st_tos.cpp`), are executed
  in hardware by `CORE/verilog/acsi_ctrl.sv`

MiSTer2MEGA65
-------------

MegaST is based on MiSTer2MEGA65 V2.0.1. Changes to the `M2M/` folder:

### SDRAM and PMOD pins for the core (board tops)

`M2M/vhdl/top_mega65-r4.vhd`, `-r5.vhd`, `-r6.vhd`: the framework ties the SDRAM and the PMOD headers off.
Instead, these pins are passed to the core (new ports `sdram_*`, `p1lo_io`, `p1hi_io`, `p2lo_io`,
`p2hi_io`, `pmod1_en_o`, `pmod2_en_o` of `MEGA65_Core`, at the end of the `CORE` port map); the tie-offs
are removed. `top_mega65-r3.vhd` (no SDRAM) leaves the SDRAM ports open and passes the PMOD pins to the core
(`pmod_en` open: the PMOD power of the R3 is not switchable). For the R3, ST RAM, TOS and the cartridge
are in block RAM (`CORE/verilog/bram_m65.v`, selected by `G_BOARD` in `CORE/vhdl/mega65.vhd`), see
`doc/DEVELOPMENT.md`.

### R3 top brought in line with the R4-R6 tops

`M2M/vhdl/top_mega65-r3.vhd`: the paddle drain, the scanlines and the PMOD pins are wired like in
`top_mega65-r6.vhd` (see the sections below).

### Paddle drain only for the 1351 mouse (board tops)

`M2M/vhdl/top_mega65-r*.vhd`: the paddle discharge pulses (pins 5 and 9, about 2 kHz) upset optical
Amiga mice, so `paddle_drain_o` is gated with the menu bit of the 1351 mouse (`main_osm_control_m(48)`,
`C_MENU_MOUSE1351` in `CORE/vhdl/mega65.vhd`; update the number if the menu changes). The framework's
output goes to the new signal `fw_paddle_drain`.

### VGA scanlines

`M2M/vhdl/av_pipeline/analog_pipeline.vhd`: new input `video_scanlines_i` (0 = off, 1..3 = 25/50/75%)
darkens every second line of the scandoubled VGA picture. It comes from the new core output
`qnice_scanlines_o` and is passed through the board tops, `framework.vhd` (`qnice_scanlines_i`) and
`av_pipeline.vhd` (CDC: `i_qnice2video` is 2 bits wider). All new inputs default to `"00"`.

### No C64 zoom crop

`M2M/vhdl/av_pipeline/av_pipeline.vhd`: `crop.vhd` is made for the C64 picture (320x200), so
`video_crop_mode_i` is `'0'`. The core blanks the border itself for "zoom-in" (`PIX_ACTIVE`), and ascal
scales only the graphics area.

### No joystick debouncing

`M2M/vhdl/debouncer.vhd`: `stable_time => 0` for all joystick lines (only the two synchronizer
flip-flops remain). Mice in the joystick ports (Atari ST, Amiga) send quadrature steps that are much
shorter than 1 ms, and ST software does not need debounced joysticks.

### Unbuffered virtual drives and fast seek (Shell firmware)

* `M2M/rom/sysdef.asm`: `VD_NOBUFFER` (`0xAAAA`), a RAM buffer ID for "unbuffered" virtual drives.
* `M2M/rom/shell.asm`: an unbuffered drive is not loaded into a RAM buffer. The read and write requests of
  the core are served directly from/to the image file on the SD card (written through, nothing to
  flush). This is used for the hard disk images. See "Unbuffered virtual drives" in `shell.asm`.
* `M2M/rom/vd_fastseek.asm` (new, included by `shell.asm`): fast seek for unbuffered drives.
  `FAT32$FILE_SEEK` follows the cluster chain from the start of the file, which takes minutes for large
  images; the chain is scanned once at mount time instead (checkpoints, or a plain calculation for
  contiguous files). Tested with `CORE/sim/fastseek/run.sh` (QNICE emulator).
* `M2M/rom/shell_vars.asm`: checkpoint tables `VD_UB_CP*` for the fast seek.
* `M2M/rom/strings.asm`: `STR_VD_SCAN` ("Scanning disk image...").

### Bug fix: saving the settings with more than one virtual drive

`M2M/rom/options.asm` (`ROSM_SAVE`): the vdrive id of the "any cache dirty?" loop was kept in `R8`, but
`VD_DRV_READ` returns the dirty flag in `R8`, so with more than one virtual drive the loop never ended.
The id is now kept in `R1`. This is a framework bug (candidate for upstream).

### JTAG probe of the QNICE CPU bus

`M2M/vhdl/QNICE/qnice.vhd`: a `BSCANE2` (USER1) returns a 64 bit snapshot of the QNICE CPU bus, for
debugging firmware hangs on the real hardware without a logic analyser (see `tools/JTAG.md`).
Debugging aid; it can be removed without any effect on the core.

QNICE
-----

No changes (`M2M/QNICE` is the submodule of the M2M V2.0.1 template).
