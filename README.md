Atari ST/STe for MEGA65 (MegaST)
================================

This is a port of the [AtariST_MiSTer](https://github.com/MiSTer-devel/AtariST_MiSTer)
core (the "MiSTery" Atari ST/STe core by Till Harbaum, Gyorgy Szombathelyi, Jorge Cwik,
Alexey Melnikov and others) to the [MEGA65](https://mega65.org), using the
[MiSTer2MEGA65](https://github.com/sy2002/MiSTer2MEGA65) framework.

**Status: work in progress, not yet tested on real hardware.** The design has been
linted (slang, GHDL) and the Atari ST machine including the SDRAM controller, the TOS
loader, the ACSI controller and the Viking downscaler has been simulated with Verilator
(see `CORE/sim`), but it has not been synthesized with Vivado nor run on a MEGA65 yet.

Features
--------

* Atari ST, STe, Mega STe (16 MHz) and "STEroids" modes
* 512 KB, 1 MB, 2 MB, 4 MB, 8 MB and 14 MB of ST RAM
* Blitter (always on in STe mode, optional in ST mode)
* All TOS versions: 192k TOS (1.00 - 1.04), 256k TOS (1.06, 1.62, 2.06) and EmuTOS;
  `tos.img` is loaded at power on, another TOS image can be loaded from the menu
* Two floppy drives (`.st` images, read/write)
* Two ACSI hard disks (`.hd`/`.img` images, read/write, directly on the SD card, any size)
* ROM cartridges (raw `.img` or `.stc`, up to 128 kB)
* Viking/SM194 compatible 1280x1024 monochrome card (shown as 640x512 grey scale)
* Serial port (RS232), MIDI and parallel (printer) port on the MEGA65's PMOD headers
* Color (low/medium resolution, 50/60 Hz) and monochrome (SM124, 71 Hz or 60 Hz) monitor,
  normal or full borders (overscan)
* YM2149 and STe DMA sound
* Real IKBD (HD6301) with the MEGA65 keyboard mapped directly into the ST keyboard matrix,
  numeric keypad via the MEGA key
* Mega ST real time clock (RP5C15), set from the MEGA65's real time clock
* Atari ST mouse (or a mouSTer in Atari mode) or a Commodore 1351 mouse in MEGA65 joystick
  port 1, joystick in port 2 (can be swapped), STe enhanced joystick ports (fire button only)
* Cubase 2 and Cubase 3 dongle in the cartridge port
* HDMI (720p/576p/480p/600p) and VGA output

Requirements
------------

* **MEGA65 R4, R5 or R6** board. The Atari ST core needs the SDRAM of these boards
  (the ST RAM is accessed with a fixed, cycle exact timing). The R3/R3A board only has
  HyperRAM and is not supported.
* SD card with a folder `/atarist` containing
  * `tos.img`: your TOS image (mandatory)
  * your floppy disk images (`.st`), hard disk images (`.hd`, `.img`) and cartridges (`.stc`, `.img`)
  * optionally `stcfg`, an empty settings file, if you want the menu settings to be saved:
    `cd M2M/tools && ./make_config.sh stcfg auto`. The file must have exactly as many bytes as
    the menu has lines (`OPTM_SIZE` in `CORE/vhdl/config.vhd`, currently 72). When the menu
    changes, a settings file of the old size is ignored: create a new one.

Usage
-----

* Press <kbd>Help</kbd> to open the on-screen menu: mount floppy disks, choose the machine
  type, memory size, video output and more. "Reset Atari ST" resets the ST (like the reset
  button of the MEGA65, the ST RAM is kept).
* Keyboard mapping (the MEGA65 has a C64 style layout, symbols are mapped by position):

  | MEGA65               | Atari ST             |
  |----------------------|----------------------|
  | F1, F3, F5, F7, F9   | F1, F3, F5, F7, F9   |
  | Shift + F1 .. F9     | F2, F4, F6, F8, F10  |
  | F11, Run/Stop        | Undo                 |
  | F13                  | Help                 |
  | Inst/Del             | Backspace            |
  | Arrow up (↑)         | Delete               |
  | No Scroll            | Insert               |
  | Clr/Home             | Clr/Home             |
  | Ctrl, Alt, Esc, Tab  | Control, Alternate, Esc, Tab |
  | Caps Lock            | Caps Lock            |
  | `+` `-` `£`          | `-` `=` `\`          |
  | `@` `*` `←`          | `[` `]` `` ` ``      |
  | `:` `;` `=`          | `;` `'` ISO key (`<>`) |

* Numeric keypad: hold the <kbd>MEGA</kbd> key. MEGA + `0`..`9`, `+`, `-`, `*`, `/`, `.` and
  <kbd>Return</kbd> are the keypad keys, MEGA + Shift + `8` / `9` are the keypad keys `(` and `)`.

TOS
---

`/atarist/tos.img` is loaded at power on. "TOS" in the menu loads another TOS image (`.img` or
`.rom`) and restarts the ST with it (cold boot). This choice is not saved: after the next power
cycle `tos.img` is used again, so rename your favourite TOS image to `tos.img`. STe and Mega STe
modes need TOS 1.06 or newer (or EmuTOS).

Real time clock
---------------

The ST has the clock chip of the Mega ST (Ricoh RP5C15 at $FFFC21), which TOS 1.02 and newer and
EmuTOS use automatically. It shows the time of the MEGA65's real time clock: set the clock in the
MEGA65 configuration utility. Setting the time on the ST (e.g. in the control panel) does not
change the MEGA65 clock and is overwritten by it.

Hard disks
----------

The hard disks are ACSI targets 0 and 1. The images are raw disk images (as used by Hatari,
MiSTer and MiST), e.g. with a DOS (MBR) or Atari (AHDI) partition table. EmuTOS finds the
partitions automatically; with Atari TOS you need a hard disk driver (AHDI, HDDRIVER, ...),
e.g. on a boot floppy or on the hard disk itself.

The images are **not** loaded into RAM: every sector is read from and written to the SD card
directly (write-through). Sequential access is fast, random access within large images is
slower because the FAT32 library seeks from the start of the file.

Viking/SM194 card
-----------------

Enable "Viking 1280x1024 card" in the system settings and load a Viking driver (memory must be
8 MB or less, the card uses $C00000). As soon as the driver accesses the card, the video
output switches to the card. The MEGA65's video pipeline cannot handle 1280x1024 at 96 MHz, so
2x2 pixels are averaged into one of five grey levels: 640x512 @ 60 Hz, 31 kHz.

PMOD headers (serial port, MIDI, printer)
-----------------------------------------

When "PMOD: RS232/MIDI/printer" is enabled in the "Controllers & ports" menu, the PMOD headers
are powered and used as follows (3.3V TTL levels, all inputs have pull-ups):

| Pin         | Signal                       | Pin         | Signal                     |
|-------------|------------------------------|-------------|----------------------------|
| PMOD1 lo[0] | RS232 CTS (in)               | PMOD1 hi[0] | MIDI OUT (out)             |
| PMOD1 lo[1] | RS232 TXD (out)              | PMOD1 hi[1] | MIDI IN (in)               |
| PMOD1 lo[2] | RS232 RXD (in)               | PMOD1 hi[2] | printer STROBE (out)       |
| PMOD1 lo[3] | RS232 RTS (out)              | PMOD1 hi[3] | printer BUSY (in)          |
| PMOD2 lo[0..3] | printer D0..D3 (in/out)   | PMOD2 hi[0..3] | printer D4..D7 (in/out) |

PMOD1 lo matches the Digilent PMOD UART pinout (e.g. a PmodUSBUART or a MAX3232 module).
MIDI needs the usual opto-coupler (IN) and driver (OUT) circuit. The parallel port pins also
allow "Gauntlet" style joystick adapters.

Not supported (yet)
-------------------

* MT32-pi, Ethernec
* Jaguar pad buttons beyond fire on the STe joystick ports (the MEGA65 joysticks have one button)

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
  71 Hz monochrome mode) and `ascal` scales the image for HDMI.
* **Framework changes:** `M2M/vhdl/top_mega65-r*.vhd` pass the SDRAM and PMOD pins to the core.
  `M2M/rom/shell.asm` supports "unbuffered" virtual drives (buffer ID `0xAAAA`, `VD_NOBUFFER`)
  that are read and written directly on the SD card; this is used for the hard disks.

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

Building
--------

1. `git submodule update --init --recursive`
2. Build the QNICE toolchain: `cd M2M/QNICE/tools && ./make-toolchain.sh`
3. Open `CORE/CORE-R6.xpr` (or R4/R5) in Vivado 2022.2 or newer and generate the bitstream.
   The firmware (`CORE/m2m-rom/m2m-rom.rom`) is built automatically before synthesis.

License
-------

GPL v3, see [LICENSE](LICENSE). The MiSTer core is licensed under GPL v2 or later (FX68K:
GPL v3). TOS is copyrighted by Atari and is not part of this repository.
