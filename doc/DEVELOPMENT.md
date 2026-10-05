MegaST: development notes
=========================

How the MiSTer AtariST core was ported to the MEGA65, how it is tested and how to build it.
For using the core see the [README](../README.md).

How the port works
------------------

| File | Purpose |
|------|---------|
| `CORE/AtariST_MiSTer/` | Copy of the MiSTer core (commit `426ef87`, June 2026), see "Changes to the MiSTer sources" below |
| `CORE/verilog/atarist_m65.sv` | The Atari ST machine: `AtariST.sv` without the MiSTer framework (hps_io etc.) |
| `CORE/verilog/sdram_m65.v` | Xilinx version of the MiSTer SDRAM controller (ODDR clock, IOB registers, DQM pins) |
| `CORE/verilog/cegen_m65.v` | Verilog replacement of `CEGen.vhd` (integer ports are not allowed on Vivado's language boundary) |
| `CORE/vhdl/clk.vhd` | MMCM: 32.083 MHz system, 96.25 MHz SDRAM and 2.005 MHz IKBD clocks (phase aligned) |
| `CORE/vhdl/main.vhd` | M2M wrapper of the ST machine, joysticks, video/audio formatting |
| `CORE/vhdl/keyboard.vhd` | MEGA65 keyboard to Atari ST keyboard matrix |
| `CORE/vhdl/tos_loader.vhd` | QNICE devices: receive `tos.img`, a TOS image chosen in the menu and cartridges from the M2M ROM loader and write them to SDRAM |
| `CORE/verilog/acsi_ctrl.sv` | ACSI "IO controller" in hardware (on MiSTer, the ARM executes the ACSI commands) |
| `CORE/verilog/viking_scale.sv` | 2:1 downscaler for the Viking card (1280x1024 @ 96 MHz to 640x512 @ 32 MHz) |
| `CORE/verilog/rp5c15_m65.sv` | Mega ST real time clock (RP5C15), fed by the MEGA65 RTC |
| `CORE/vhdl/floppy_swap.vhd` | Swapping the floppy drives A: and B: (the FDC's image geometry is announced again) |
| `CORE/vhdl/mouse1351.vhd` | Commodore 1351 mouse to the IKBD's PS/2 mouse emulation |
| `CORE/vhdl/fdc_bridge.vhd` | Connects the M2M virtual drives (8 bit) to the ST's FDC and ACSI controller (16 bit MiSTer "WIDE" interface) |
| `CORE/vhdl/mega65.vhd` | Glue: clocks, menu settings, TOS loader, floppy buffers in HyperRAM, virtual drives |
| `CORE/vhdl/config.vhd`, `globals.vhd` | M2M configuration: menu, welcome/help screens, TOS auto-load, drives |

* **Memory:** ST RAM and the TOS ROM live in the SDRAM (like on MiSTer). The TOS image is
  always stored at $E00000; 192k TOS images (header `os_beg` = $FC0000) are detected by the
  loader and mapped to $FC0000.
* **Floppies:** the M2M firmware buffers the whole disk image in HyperRAM (2 MB per drive
  at $400000/$600000, the lower 4 MB belong to the framework) and serves sector requests
  of the FDC through `vdrives.vhd` and `fdc_bridge.vhd`.
* **Video:** the core outputs its native 15 kHz signal (16 MHz pixel clock enable, 32 MHz in
  the monochrome mode). The M2M scandoubler creates 31 kHz for VGA (switched off in the
  71 Hz monochrome mode and in the 15 kHz VGA modes) and `ascal` scales the image for HDMI.
  For "zoom-in", the core blanks everything but the graphics area (`PIX_ACTIVE` of the
  shifter, the lines with DE of the previous frame), so `ascal` scales only the graphics.
* **Framework changes** (all of them, with how to re-apply them: [m2m/exceptions.md](m2m/exceptions.md)): `M2M/vhdl/top_mega65-r*.vhd` pass the SDRAM and PMOD pins to the core.
  `M2M/rom/shell.asm` supports "unbuffered" virtual drives (buffer ID `0xAAAA`, `VD_NOBUFFER`)
  that are read and written directly on the SD card; this is used for the hard disks, with
  the fast seek of `M2M/rom/vd_fastseek.asm`. `M2M/vhdl/av_pipeline/analog_pipeline.vhd` has
  VGA scanlines (`qnice_scanlines_o` of the core, passed through `framework.vhd` and
  `av_pipeline.vhd`). The C64 specific `crop.vhd` is not used (`av_pipeline.vhd`).

### Changes to the MiSTer sources

All changes are marked with `MEGA65` comments:

* `rtl/ikbd/ikbd.sv`: additional input `matrix_ext` for the MEGA65 keyboard matrix
* `rtl/ikbd/rom/MCU_BIROM.v`: loads `ikbd.mem` (copy of `ikbd.hex`) which is part of the Vivado project
* `rtl/stBlitter.sv`: wrapper `stBlitter_m65` with plain ports (no struct type across files)
* `rtl/gstmcu/hdegen.v`: `de` is a `reg` (assigned in an `always` block)
* `rtl/fdc1772/fdc1772.sv`: sensitivity list for the floppy demultiplexer
* `rtl/ikbd/hd63701/HD63701.v`: removed a stray carriage return inside a comment
* `rtl/mfp/usart_top.vhd`: `entity` keyword for direct entity instantiation
* `rtl/dma.v`: output `dio_fifo_used` (DMA FIFO fill level for the ACSI controller)
* `rtl/ym2149.sv`: output `IOB_dir` (port B direction for the printer port), fixed a typo when
  reading port B in output mode
* `rtl/gstmcu/gstshifter.v`: output `PIX_ACTIVE` (graphics area, for cropping the border)

Tests
-----

These tests run with the OSS CAD Suite (Verilator, GHDL), gcc and python3 (there is no Vivado
simulation):

* `CORE/sim/build.sh`: Verilator simulation of the whole Atari ST machine (`atarist_m65.sv`) with
  an SDRAM model; boots TOS 1.04, 2.06 and EmuTOS, ACSI hard disk, `CROP=1` for zoom-in,
  `VFLAGS=-DRTC_TRACE` traces the real time clock
* `CORE/sim/tos_loader/run.sh`, `CORE/sim/keyboard/run.sh`, `CORE/sim/floppy_swap/run.sh`:
  GHDL tests of the TOS/cartridge loader, the keyboard (numeric keypad) and the floppy swap
* `CORE/sim/fastseek/run.sh`: the fast seek of the firmware in the QNICE emulator (FAT32 image
  with fragmented files, compared with the FAT32 library)

`tools/JTAG.md` describes the JTAG tools used for debugging on the real hardware (a TE0790 adapter
and Vivado's hardware manager, no ILA needed).

Building
--------

1. `git submodule update --init --recursive`
2. Build the QNICE toolchain: `cd M2M/QNICE/tools && ./make-toolchain.sh`
3. Open `CORE/CORE-R6.xpr` (or R4/R5) in Vivado 2022.2 or newer and generate the bitstream.
   The firmware (`CORE/m2m-rom/m2m-rom.rom`) is built automatically before synthesis.
