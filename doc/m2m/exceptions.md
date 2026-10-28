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

### Floppy drive pins for the core (board tops)

`M2M/vhdl/top_mega65-r3.vhd` .. `-r6.vhd`: the framework ties the outputs to the internal 3.5" floppy drive
off (`f_* <= '1'`). Instead, all 15 drive pins are passed to the core (new ports `f_*` of `MEGA65_Core`, at
the end of the `CORE` port map, marked `MegaST`); the tie-offs are removed. Inside the core,
`CORE/vhdl/floppy/m65_floppy_port.vhd` owns the pins and keeps every output inactive unless something drives
it (see `doc/real-floppy.md`). The pins are the same on every board revision, so this is a candidate for
upstream M2M.

### R3 top brought in line with the R4-R6 tops

`M2M/vhdl/top_mega65-r3.vhd`: the paddle drain, the scanlines and the PMOD pins are wired like in
`top_mega65-r6.vhd` (see the sections below).

### Paddle drain only for the 1351 mouse (board tops)

`M2M/vhdl/top_mega65-r*.vhd`: the paddle discharge pulses (pins 5 and 9, about 2 kHz) upset optical
Amiga mice, so `paddle_drain_o` is gated with the menu bit of the 1351 mouse (`main_osm_control_m(53)`,
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

### Remembering the mounted images (Shell firmware)

The framework does not remember mounted images (issue #13). Changes:

* `M2M/rom/mntmem.asm` (new, included by `shell.asm`) and `M2M/rom/mntmem_vars.asm` (new, included by
  `shell_vars.asm`): the full path of every mounted vdrive image and manually loaded CRT/ROM is kept in
  `MNT_PATHS` and saved to the file `MNT_FILE` (256 bytes per entry, vdrives first). `MNT_RESTORE` loads
  them again at startup, after `CRTROM_AUTOLOAD` and before `RP_SYSTEM_START` (core still in reset). The
  file is opened through `HANDLE_DEV`, not `CONFIG_DEVH`, so the FAT32 library keeps the shared sector
  buffer consistent with the vdrives. Like the settings file, it must exist with the exact size, else the
  feature is off. Tested with `CORE/sim/mntmem/run.sh` (QNICE emulator).
  A CRT/ROM loaded again by `_MNT_LOAD` (restore, machine switch) gets the context `CTX_LOAD_ROM` with
  the low byte `MNT_CTX_RESTORE` (1), so that `PREP_LOAD_IMAGE` can tell it from one chosen in the
  browser (MegaST: a cartridge is refused on the Falcon only when chosen, issue #27).
* `M2M/rom/selectfile.asm`: the browser tracks its current directory in `FB_PATH` (`FBP_SET`, `FBP_CD`),
  because it only returns the bare file name.
* `M2M/rom/shell.asm`: `HANDLE_MOUNTING` calls `MNT_REMEMBER` after a successful load, `MNT_FORGET` when a
  drive is unmounted and `MNT_SAVE` on exit. The code that puts the file name into the menu
  (`OPTM_HEAP`) moved to `MNT_OSM_NAME` in `mntmem.asm`, so that the restore can use it, too.
* `M2M/rom/rosmfix.asm` (new), `M2M/rom/options.asm` (`HELP_MENU_INIT`), `M2M/rom/shell.asm`
  (include), `M2M/rom/strings.asm` (`LOG_STR_CFG_GRP`): after the settings were loaded from `CFG_FILE`,
  `ROSM_FIXGRP` checks every group of options (same group id, not single select, not submenu): if not
  exactly one item is selected, the group gets its `OPTM_G_STDSEL` defaults. A settings file of another
  menu with the same size (a Falcon test build had written `stcfg` with its fifth Machine item) or a
  damaged one made `OPTM_CB_SHOW` stop the firmware with "No selected menu group item" when the menu was
  opened. Test: `CORE/sim/rosmfix/run.sh` (QNICE emulator). Generic, a candidate for upstream.
* `M2M/rom/shell.asm`: the main loop calls `CORE_LOOP`, a callback of the core (`CORE/m2m-rom/m2m-rom.asm`;
  a core without anything to do there just returns). MegaST saves the Falcon's NVRAM there when it changed
  (`CORE/m2m-rom/nvram.asm`, file `/atarist/fcnvram`, 64 bytes). Generic, a candidate for upstream.
* `M2M/rom/crts-and-roms.asm` (`CRTROM_AUTOLOAD`): before opening an auto-load ROM, it calls
  `FC_AUT_NAME` (`CORE/m2m-rom/fcswitch.asm`), which may return another file name: the TOS of the Falcon
  (`/atarist/tosfalc.img`, if it exists) while the Falcon030 is selected, else the name from `globals.vhd`.
  `CORE/m2m-rom/make_rom.sh` gives the remembered images one entry more (`MNT_ENTRIES`, file `fcmount`
  1792 bytes) for the manual TOS of the machine that does not run; `FC_SWITCH` swaps it with the TOS entry
  on a switch between ST and Falcon. Test: `CORE/sim/fcswitch/run.sh` (QNICE emulator).
* `M2M/rom/shell.asm`: in CRT/ROM mode `HANDLE_MOUNTING` first calls `MNT_CRT_EJECT`
  (`CORE/m2m-rom/m2m-rom.asm`): Space on the line of a loaded cartridge removes it (status "loading",
  then "idle" in the device, so the ST restarts without it) and forgets it, instead of opening the browser.
  Space on the line of a manually loaded TOS forgets it, holds the core in reset and closes the menu;
  `FC_SWITCH` (`fcswitch.asm`, flag `FC_RELOAD`) then loads the auto-load TOS of the same machine.
* `M2M/rom/options.asm` (`HELP_MENU`): `MNT_OSM_NAMES` writes the names of the restored images when the
  menu opens (`OPTM_HEAP` is only valid then); `MNT_SAVE` retries a postponed save when the menu closes.
* `M2M/rom/sysdef.asm`: selector `M2M$CFG_MNT_FILE` (`0x0102`); `CORE/vhdl/config.vhd`: `SEL_MNT_FILE`
  and `MNT_FILE` (empty string = off).
* `CORE/m2m-rom/make_rom.sh` writes `MNT_ENTRIES` and `MNT_BUF_SIZE` to `globals.asm` (qasm cannot
  compute expressions); `CORE/m2m-rom/m2m-rom.asm`: `HEAP_SIZE` 2048 words smaller for the new variables.
* Menu items "Remember floppies" and "Remember TOS/cartridge": `MNT_RESTORE` reads their bits from
  `M2M$CFM_DATA` (`_MNT_CFM_GET`; the settings file is loaded before, by `HELP_MENU_INIT`) and skips the
  first `MNT_FD_NUM` vdrives or all CRTs/ROMs when they are off (the paths stay remembered).
  `make_rom.sh` writes `MNT_OPT_FD`, `MNT_OPT_ROM` (menu line of `OPTM_G_RemFloppy`, `OPTM_G_RemRom` in
  `config.vhd`) and `MNT_FD_NUM` (`C_MNT_FD_NUM` in `globals.vhd`) to `globals.asm`. The QNICE emulator
  test defines `MNT_CFM_STUB` and replaces `_MNT_CFM_GET`.

Generic, a candidate for upstream.

### The menu can be closed by the core (Shell firmware)

`M2M/rom/menu.asm` (`OPTM_RUN`), `M2M/rom/menu_vars.asm`: a select callback may set `OPTM_CLOSE_REQ` to 1,
then the menu closes after the callback as if the close key (Help) was pressed. `OPTM_RUN` clears it when
it starts. MegaST closes the menu when Atari ST and Falcon030 are switched (`FC_CHECK`,
`CORE/m2m-rom/fcswitch.asm`): the TOS of the new machine can only be loaded with the menu closed, and in
between nothing else may be chosen (a TOS, switching back, "Reset Atari ST"). Before, a manual TOS plus a
switch made `M2M$FORCE_MENU` run with the menu closed, and `OPTM_SET` stopped the firmware ("menu.asm:
OPTM_RUN is not running", 0003). Generic, a candidate for upstream.

### Error messages of PREP_LOAD_IMAGE for CRTs/ROMs (Shell firmware)

`M2M/rom/shell.asm` (`HANDLE_MOUNTING`): for a CRT/ROM the error string was always copied from the window
of the CRT/ROM device (where the core puts its own messages). A string below `M2M$RAMROM_DATA` (`0x7000`)
is in the QNICE ROM, like the ones `PREP_LOAD_IMAGE` returns, and is printed directly. MegaST refuses a
TOS the selected machine cannot run (`FC_TOS_CHECK`, `CORE/m2m-rom/fcswitch.asm`: the ST no 512 KB TOS,
the Falcon no 192/256 KB one). Generic, a candidate for upstream.

### Bug fix: saving the settings with more than one virtual drive

`M2M/rom/options.asm` (`ROSM_SAVE`): the vdrive id of the "any cache dirty?" loop was kept in `R8`, but
`VD_DRV_READ` returns the dirty flag in `R8`, so with more than one virtual drive the loop never ended.
The id is now kept in `R1`. This is a framework bug (candidate for upstream).

### Bug fix: reset handling at the start of the firmware

`M2M/rom/gencfg.asm` (`RP_SYSTEM_START`): `R7` was used as the pointer to `M2M$CSR` without being set,
so the keyboard/joystick bits and the release of the reset went to a random address. `R7` is now set.
The release itself is gone: the core stays in reset until `START_CONNECT` (`shell.asm`) releases it after
the welcome screen, as it did in practice before. The virtual drives are only served from the main loop
on, so an ST started behind the welcome screen would miss its floppies. Framework bug (candidate for
upstream; there the missing release would be a behaviour change).

### HDMI: scaler with downscaling

`M2M/vhdl/av_pipeline/digital_pipeline.vhd`: `ascal` is built with `DOWNSCALE => true` (M2M: `false`, "we use
ascal only to upscale"). The ST line is 744 pixels wide with the normal borders (840 with full borders), wider
than the 4:3 area of 576p (720), 720x480 (720) and 640x480 (640). Without downscaling, ascal advances at most one
input pixel per output pixel, so it cut off the right part of the line: the picture looked shifted to the right
(left border wide, right border narrow), only 800x600 and 720p were right. Generic, a candidate for upstream.

### HDMI: 16 bpp scaler frame buffer

`M2M/vhdl/av_pipeline/digital_pipeline.vhd`, `av_pipeline.vhd`, `framework.vhd`: the pixel format of
`ascal`'s frame buffer in HyperRAM is the generic `G_ASCAL_FORMAT` (default `"01"` = 24 bpp, as in M2M);
`framework.vhd` passes `ASCAL_FORMAT` from `globals.vhd`. MegaST uses `"00"` (16 bpp, RGB 565). The ST
monochrome mode writes 640x400 at 71 Hz into the frame buffer (55 MB/s at 24 bpp); at 720p ascal also has
to read every line within a 720p line period. With 24 bpp, the HyperRAM could not keep up: the
desktop flickered in columns at 720p (fewer at 50 Hz), while 576p was stable. 16 bpp needs a third
less bandwidth and loses nothing visible for the ST's colours. Generic, a candidate for upstream.

### HDMI: Viking card picture 1:1 at 1280x1024

The Viking card draws 1280x1024 in black and white. `ascal` takes at most 1024 pixels per line (`IHRES`),
and a 1280x1024 input would need more HyperRAM bandwidth than there is, so the core downscales the picture
to 640x512 grey (`viking_scale.sv`), which made it blurry on HDMI. Instead, HDMI now shows the picture 1:1:

* `M2M/vhdl/av_pipeline/video_modes_pkg.vhd`: new mode `C_SXGA_1280_1024_60` (VESA DMT, 108 MHz, positive
  syncs, no CEA VIC) and `C_VIDEO_SXGA_1280_60` (`"0111"`).
* `M2M/vhdl/controllers/HDMI/video_out_clock.vhd`: clock select `"011"` is 108 MHz instead of 148.5 MHz
  (no M2M mode used 148.5 MHz). The values: VCO 1080 MHz (100 MHz / 5 x 54), lock and filter registers from
  Xilinx's `mmcm_lock_lookup`/`mmcm_filter_lookup` (XAPP888, `OPTIMIZED`). The MMCM's default
  configuration, which static timing analysis uses, is now 108 MHz, the fastest mode (was 74.25 MHz).
* `framework.vhd`, `av_pipeline.vhd`, `digital_pipeline.vhd`: ports `viking_fb_*` (defaults: off). A
  1280x1024 1 bpp frame buffer in block RAM (40 RAMB36) is written by the core in its own clock domain and
  read with the HDMI timing. While `viking_fb_enable_i` is set, every HDMI pixel comes from it instead of
  from `ascal` (before the OSM overlay, so the menu still shows). Both paths go through the same three
  register stages.
* `digital_pipeline.vhd`: `ascal` without the bilinear, sharp bilinear and bicubic filters (`MASK => x"f1"`,
  M2M: `x"ff"`). MegaST only uses nearest neighbour and polyphase; at 108 MHz the bicubic filter missed
  the timing (-0.063 ns).
* `top_mega65-r6.vhd`: connects the ports. The R3-R5 tops leave them open (no Viking on the R3; R4/R5 to
  follow after the R6 test).

The core selects the SXGA mode while the Viking picture is shown (`mega65.vhd`). VGA keeps the downscaled
640x512 picture. MegaST-specific (the 108 MHz entry replaces 148.5 MHz).

### OSM colours: palette of the core and colour escape (GEM look, logo)

* `M2M/vhdl/av_pipeline/vga_osm.vhd`: the 16 colours of the attribute bits {dark, R, G, B} come from the
  generic `G_OSM_PALETTE` (24 bits per colour, colour i in bits 24*i+23..24*i) instead of being computed
  (R, G, B at FF, 7F when dark). The default is that M2M palette, so nothing changes without the generic.
* `video_overlay.vhd`, `analog_pipeline.vhd`, `digital_pipeline.vhd`, `av_pipeline.vhd`, `framework.vhd`:
  pass the generic on; `framework.vhd` takes `OSM_PALETTE` from `globals.vhd`. MegaST: black text on white,
  green headlines, a black selection bar (Atari GEM), and the logo colours in the dark half.
* `M2M/rom/screen.asm`, `SCR$PRINTSTR`: ESC (0x1B) followed by an attribute byte sets the attribute of the
  following characters (written into the attribute VRAM at the same address). Without ESC the attribute
  VRAM is not touched, as before. MegaST uses it for the logo and the headlines of the welcome screen
  (`config.vhd`, `SCR_LOGO` from `tools/osd_logo.py`).

The logo itself is core-side: `CORE/font/MegaST-16x16.rom` is the M2M font with 129 logo characters in
codes the core does not print (`FONT_FILE` in `globals.vhd`). Both framework changes are generic, candidates
for upstream (other cores: `G_OSM_PALETTE` needs a constant `OSM_PALETTE` in their `globals.vhd`).

### JTAG probe of the QNICE CPU bus

`M2M/vhdl/QNICE/qnice.vhd`: a `BSCANE2` (USER1) returns a 64 bit snapshot of the QNICE CPU bus, for
debugging firmware hangs on the real hardware without a logic analyser (see `tools/JTAG.md`).
Debugging aid; it can be removed without any effect on the core.

Falcon core Falcon_MiSTer
-------------------------

`CORE/Falcon_MiSTer` is a copy of Falcon_MiSTer and AP68030 (see its `ORIGIN.md`). Changes, marked
with `MEGA65` comments:

* `rtl/falcon/falcon_psg.sv`, `falcon_pipescan.sv`: the `.mem` tables by file name only (Vivado finds
  project files by name).
* `rtl/falcon/falcon_system.sv`: `FALCON_FPU_LOCAL`: the FPU bridge's mailbox port (d3) goes out of the
  module to the RISC-V that runs the 68882 service (`CORE/verilog/fpu_rv.v`) instead of to
  `falcon_memarb` (no ARM, no DDR3 mailbox).
* `rtl/falcon/falcon_cpubus.sv`: `hold` is never active during a reset. The reset holds the bridge in
  `F_IDLE`; a bus cycle the processor had started then stopped its clock for good, and the AP68030
  (which counts the reset only on `cpu_ce` clocks) never took the reset while the devices did: the
  program ran on with reset video registers (garbage on the screen). Found in simulation (20 of 50
  resets missed the CPU, 0 with the fix). Generic, a candidate for upstream.
* `rtl/falcon/falcon_cpuclk.sv`, `falcon_system.sv`: after a 68030 access to the DSP host port the
  processor runs at the Falcon rate for 512 clocks (`sync`, restarted by every access; the debt is
  kept and caught up afterwards). While the processor caught up at 32 MHz, the code between two host
  port accesses ran in half its Falcon time, and the DSP (real time) lost words the 68030 wrote
  without handshake: ATRIS (bITmASTER DSP Protracker) froze with the DSP and the 68030 waiting for
  each other (found with the JTAG probe below on an R6). Generic, a candidate for upstream.
* `rtl/falcon/falcon_system.sv`: `falcon_scsi` with `CD_ALWAYS = 0`. The core has no SCSI images and
  no ARM to answer the target's window reads, so the always present CD-ROM (ID 2) stayed busy on its
  first command and TOS waited for its timeout.
* `rtl/falcon/falcon_scsi.sv`, `falcon_system.sv`: parameter `BLK_MAX` (default 32, MegaST 1): the
  blocks per HPS request. MegaST's drive bridge (`fdc_bridge.vhd`) moves one 512 byte block per
  request. The hard disks go to SCSI ID 0/1 in `falcon_m65.sv` (menu "Hard disks on SCSI (ICD)"),
  which also answers the targets' window reads (no Main_MiSTer) without data, so that the built-in
  INQUIRY and READ CAPACITY answers are used.
* `rtl/falcon/falcon_system.sv`, `dsp/falcon_dsp.sv`, `dsp/dsp56k_core.sv`, `dsp/dsp_periph.sv`: a
  `dbg` output for the JTAG probe (`tools/probe5.tcl`): the last 68030 program space bus address and
  device access, DSP PC, R6, R7, LC, SSISR, host ISR/HSR and a count of the DSP's SSI TX writes.
  Debugging only, no change in behaviour.
* `rtl/falcon/falcon_system.sv`: inputs `pad0`/`pad1` for the enhanced joystick ports (`falcon_combel`),
  apart from `joy0`/`joy1` for the IKBD's joysticks. On MiSTer both are the same pads; on the MEGA65
  the mouse port must not appear as a joystick (see `main.vhd`), while the joypads come from the
  MEGA65 joystick ports when the menu item "STe joypads" is on. MiSTer: connect `joy0`/`joy1` to both.
* `rtl/falcon/falcon_system.sv`: input `nv_lang`, the language and keyboard of the NVRAM default image
  (`falcon_nvram` `cfg_lang`/`cfg_kbd`, upstream 0 = US): UK with the menu item "As printed, UK TOS".
* `rtl/falcon/falcon_cpubus.sv`, `falcon_l2.sv`, `falcon_memarb.sv`, `falcon_system.sv`: Fast RAM
  (TT-RAM), input `fast_n` (16 MB blocks at `$01000000`, 0 = none: the behaviour of upstream). With
  Fast RAM, A31..A24 are decoded: `$00`/`$FF` the 24-bit space, `$01..fast_n` Fast RAM (a 32-bit port
  without the ST-RAM slot, also in the Falcon mode), the rest a bus error. The CPU's memory port, the
  line cache tags and the arbiter's CPU addresses have two more bits ([25:24]); the Fast RAM is right
  above the 24-bit space in memory (DDRAM_ADDR[22:21]). DMA, video and the blitter stay in the 24-bit
  space. EmuTOS finds the Fast RAM by itself (32-bit bus test, `ttram_detect`). On MiSTer the DDR3
  window would have to grow by 48 MB.
* `rtl/falcon/falcon_system.sv`: the CPU's line cache (`falcon_l2`) is on in the turbo mode too
  (upstream: Falcon mode only). Without it every turbo read was one SDRAM access through the clock
  crossing of `falcon_sdram.v`; reading memory got about 30 % faster (`tests/membench.s`).
* `rtl/falcon/falcon_fdc.sv`, `falcon_system.sv`: input `ext_fd` and the `wd_*` port: the MEGA65's
  internal floppy drive as A: (menu "Real floppy drive as A:"). The WD1772 is then `wd1772_m65.v` (the
  ST's, flux level, at the drive), `falcon_fdc` keeps the DMA chip: register accesses go out (the CPU's
  acknowledge after the access), DRQ moves the data register through the FIFO, INTRQ comes back.
  `fd_sel_n`/`fd_side_n`: PSG port A bits 2..0 for the drive. With `ext_fd = 0` as upstream.

QNICE
-----

No changes (`M2M/QNICE` is the submodule of the M2M V2.0.1 template).
