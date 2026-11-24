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
| `CORE/verilog/bram_m65.v` | MEGA65 R3/R3A (no SDRAM): ST RAM, TOS and cartridge in block RAM, same interface and bus timing as `sdram_m65.v` |
| `CORE/verilog/cegen_m65.v` | Verilog replacement of `CEGen.vhd` (integer ports are not allowed on Vivado's language boundary) |
| `CORE/vhdl/clk.vhd` | MMCM: 32.083 MHz system, 96.25 MHz SDRAM and 2.005 MHz IKBD clocks (phase aligned) |
| `CORE/vhdl/main.vhd` | M2M wrapper of the ST machine, joysticks, video/audio formatting |
| `CORE/vhdl/keyboard.vhd` | MEGA65 keyboard to Atari ST keyboard matrix |
| `CORE/vhdl/tos_loader.vhd` | QNICE devices: receive `tos.img`, a TOS image chosen in the menu and cartridges from the M2M ROM loader and write them to SDRAM |
| `CORE/verilog/acsi_ctrl.sv` | ACSI "IO controller" in hardware (on MiSTer, the ARM executes the ACSI commands) |
| `CORE/verilog/viking_scale.sv` | 2:1 downscaler for the Viking card (1280x1024 @ 96 MHz to 640x512 @ 32 MHz) |
| `CORE/verilog/rp5c15_m65.sv` | Mega ST real time clock (RP5C15), fed by the MEGA65 RTC |
| `CORE/vhdl/floppy_swap.vhd` | Swapping the floppy drives A: and B: (the FDC's image geometry is announced again) |
| `CORE/vhdl/floppy/m65_floppy_port.vhd` | Internal 3.5" floppy drive: owns the 15 drive pins, synchronisers, RDATA glitch filter and flux pulse, step pulse stretcher, write interlock (`G_WRITE_ENABLE`), motor watchdog. Reusable by other M2M cores |
| `CORE/vhdl/floppy/floppy_probe.vhd` | Bring-up probe for the floppy drive (phase 0 of `doc/real-floppy.md`): motor/select/step commands and index, flux and step statistics through JTAG USER4 (`tools/probe4.tcl`) |
| `CORE/verilog/wd1772_m65.v` | WD1772 for the internal floppy drive: WF1772IP behind the fdc1772 CPU interface, clock enable at half rate, short DMA selects stretched over two enabled edges. `atarist_m65.sv` routes all FDC accesses to it with the menu item "Real floppy drive as A:" (drive B: is then absent; type I commands to it end at once, so the TOS drive probe does not wait for its timeouts) |
| `CORE/vhdl/floppy/wf1772ip/` | WF1772IP, a complete WD1772 (Suska, LGPL), converted to a clock enable by `tools/wf1772_ce.py`, which also applies the bug fixes (origin, fixes and known differences in its `README.md`); `orig/` is the unmodified source. Used by `wd1772_m65.v`; `CORE/sim/build.sh` converts it to Verilog with `ghdl --synth` for Verilator |
| `CORE/vhdl/rmb_guard.vhd` | Right mouse button on pin 9: ignored until the pin was seen released (no pull-up on the MEGA65, an open pin reads as pressed); click mode for the Atari mouse (a press counts 200 ms, the release is not visible) |
| `CORE/vhdl/mouse1351.vhd` | Commodore 1351 mouse to the IKBD's PS/2 mouse emulation |
| `CORE/vhdl/fdc_bridge.vhd` | Connects the M2M virtual drives (8 bit) to the ST's FDC and ACSI controller (16 bit MiSTer "WIDE" interface) |
| `CORE/vhdl/mega65.vhd` | Glue: clocks, menu settings, TOS loader, floppy buffers in HyperRAM, virtual drives |
| `CORE/vhdl/config.vhd`, `globals.vhd` | M2M configuration: menu, welcome/help screens, TOS auto-load, drives; the OSD colours (`OSM_PALETTE`: GEM look) |
| `CORE/font/MegaST-16x16.rom`, `tools/osd_logo.py` | The OSD font with the MegaST logo (from `doc/logo/megast-logo.png`) and the logo block `SCR_LOGO` in `config.vhd`, both written by `osd_logo.py` (needs Pillow and numpy); run it again after changing the logo |

* **Memory:** ST RAM and the TOS ROM live in the SDRAM (like on MiSTer). The TOS image is
  always stored at $E00000; 192k TOS images (header `os_beg` = $FC0000) are detected by the
  loader and mapped to $FC0000.
* **R3/R3A (no SDRAM):** `bram_m65.v` replaces the SDRAM controller (`G_BOARD = "MEGA65_R3"`,
  parameter `BRAM_MEM` of `atarist_m65.sv`): 512 KB ST RAM, 256 KB TOS and 128 KB cartridge in
  224 RAMB36, with the same 12-state bus cycle (read data at t = 6). The memory size is forced to
  512 KB, Viking and STEroids are off. HyperRAM is not an option for ST RAM: the ST bus needs the
  data within about 175 ns (video, DMA and blitter cannot wait). The SDRAM pin constraints are in
  `CORE/CORE-SDRAM.xdc`, which only the R4-R6 projects include.
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
* `rtl/dma.v`: outputs `dio_fifo_used` (DMA FIFO fill level), `dio_cmd_start` and `dio_fifo_reset`
  for the ACSI controller
* `rtl/acsi.v`: output `cmd_start`; a new command clears `busy` (a retry cancels the old command)
* `rtl/ym2149.sv`: output `IOB_dir` (port B direction for the printer port), fixed a typo when
  reading port B in output mode
* `rtl/gstmcu/gstshifter.v`: output `PIX_ACTIVE` (graphics area, for cropping the border)

Tests
-----

These tests run with the OSS CAD Suite (Verilator, GHDL), gcc and python3 (there is no Vivado
simulation):

* `CORE/sim/build.sh`: Verilator simulation of the whole Atari ST machine (`atarist_m65.sv`) with
  an SDRAM model; boots TOS 1.04, 2.06 and EmuTOS, ACSI hard disk, `CROP=1` for zoom-in,
  `VFLAGS=-DRTC_TRACE` traces the real time clock, `RFLOPPY=<.st>` boots from a flux level model of the
  internal floppy drive through `wd1772_m65.v` (`VFLAGS=-DFDC_TRACE` logs every FDC access),
  `FLOPPY=<.st>` mounts an image (`FLOPPY_DRIVE=B`: as drive B:, e.g. next to `RFLOPPY` for issue #33;
  `FLOPPY_OUT=<file>` saves the image with the sectors the ST wrote)
* `CORE/sim/tos_loader/run.sh`, `CORE/sim/keyboard/run.sh`, `CORE/sim/floppy_swap/run.sh`,
  `CORE/sim/fdc_bridge/run.sh`, `CORE/sim/rmb_guard/run.sh`, `CORE/sim/real_floppy/run.sh`: GHDL tests of the TOS/cartridge loader,
  the keyboard (numeric keypad, "Keyboard as printed"), the floppy swap (and eject at a firmware
  restart), the sector buffer read-back of `fdc_bridge.vhd` (every drive returns its own buffer; the
  Verilator simulation bypasses it), the right mouse button guard and the internal floppy drive port
  and probe (with a simple drive model: step timing, index period, flux histogram, glitch filter, write
  interlock, motor watchdog)
* `CORE/sim/real_floppy/run_wf1772.sh`: the WF1772IP clock enable conversion: the original IP (with the bug fixes) on 16 MHz
  and the converted one on 32 MHz side by side on a flux level drive model (`floppy_model.vhd`, ST MFM
  tracks with CRCs); every output identical at every 16 MHz edge, restore, seek, read sector (every byte),
  read address, step, side 1, force interrupt (also with no command running, issue #24) (about 4 minutes)
* `CORE/sim/ascal_reset/run.sh [trials] [seed]`: the HDMI scaler (ascal, avm_decrease, arbiter, HyperRAM model)
  with resets at random moments, reset button and Help-menu reset (issue #26); `BUG=1` puts the old ascal
  line back (froze 4 of 48), with the fix none of 64
* `CORE/sim/ascal_ilace/run.sh`: the HDMI scaler with the Falcon's interlaced fields (issue #38): fields like
  the Videl's (odd rows, even rows, `ilace_fl`) on the HyperRAM model; every output line must show its own
  source row, interlaced (woven) and progressive
* `CORE/sim/fastseek/run.sh`: the fast seek of the firmware in the QNICE emulator (FAT32 image
  with fragmented files, compared with the FAT32 library)
* `CORE/sim/ubcopy/run.sh`: the sector-wise transfer of the hard disk images (`M2M/rom/vd_ubcopy.asm`)
  in the QNICE emulator: random reads and writes of 1 to 1536 bytes (aligned, unaligned, sequential,
  across the end of the file, another file taking the SD buffer in between) on fragmented and contiguous
  FAT32 images, checked against the file content; then the QNICE instructions for 256 KB read and
  written, new code against the old byte loop (the drive buffer is a RAM array, `VD_UBC_SIM`)
* `CORE/sim/mntmem/run.sh`: remembering the mounted images (`M2M/rom/mntmem.asm`) in the QNICE
  emulator: path tracking of the file browser, saving to and restoring from `/atarist/stmount` on a
  FAT32 image, with stubs for the rest of the shell
* `CORE/sim/rosmfix/run.sh [stcfg ...]`: the check of the settings loaded from `/atarist/stcfg`
  (`M2M/rom/rosmfix.asm`) in the QNICE emulator: the menu of `config.vhd` with valid settings and with
  files where a group of options has no or several items selected (that group gets its defaults)
* `CORE/sim/acsi_write/run.sh <emutos tos.img> [delay]`: hard disk writes in the Verilator
  simulation (run `build.sh` first). A floppy boot sector writes 64 KB with one `Rwabs` call, and
  `check.py` verifies every sector of the image. A delay (641666 = 20 ms per sector) makes the
  writes as slow as the firmware's SD path; very long delays make the driver time out and retry
* `CORE/sim/falcon_m65/` (Falcon030 bench, `Vtb_top`): `HD_RD_US` / `HD_WR_US` make every hard disk
  sector read/write take that many microseconds, like the firmware's SD path (2000 / 20000 is an
  estimate of the unbuffered drives, not measured on the hardware); `HD_SPIKE_EVERY=N HD_SPIKE_US=T`
  makes every Nth request take T instead (SD card busy). With 2000 / 20000, the EmuTOS 1.3 release
  image failed to copy 68 KB files on a SCSI disk (EUNDEV, its transfer time limit assumes 200 KB/s);
  IDE passed. **Only models built from `sim_main.cpp` of 2026-11-02 or later know these variables**
  (`obj_v13`); older ones (`obj_fpu` of 10-28 and others) ignore them silently, so check that a slow
  run really takes longer (520 sectors at 20 ms: about 10 s more). `tests/bigfile.s` writes and reads
  back 128 KB in one call, from ST-RAM and (with `--fastram 1..3`) from TT-RAM through EmuTOS's FRB.

### Falcon FPU: the 68882 on the RISC-V

The Falcon's 68882 is the FPU bridge of Falcon_MiSTer (`falcon_system.sv`, `FALCON_FPU_LOCAL`) and a
RISC-V that runs Hatari's 68882 emulation (`CORE/falcon_fpu`: `engine/` = Hatari's `fpp.c` and
softfloat, unmodified, plus the shim; `rv/` = the service, built by `rv/build.sh`, `HATARI=` the
Hatari 2.6.1 source tree, xPack `riscv-none-elf-gcc`). The 68030 waits for each instruction; the
hand-over from the 68030 to the RISC-V and back costs about 3 to 5 us (`tests/fpulat.s`).

The RISC-V of the core is Hazard3 (Luke Wren, Apache 2.0, `CORE/hazard3`, copied unmodified;
`CORE/verilog/fpu_rv_h3.v`, image `rv/fpu_rv_h3.mem` from `H3=1 rv/build.sh`) on its own clock,
80.2 MHz (`clk.vhd` CLKOUT2 = VCO/12; 1.6-test3 and earlier: PicoRV32 at 96 MHz,
`fpu_rv.v` + `picorv32.v`, image `rv/fpu_rv.mem`, still built by `rv/build.sh` and used by the
simulations without `H3=1`). PicoRV32 needs about 4.5 clocks per instruction, Hazard3 about 1.2.
Hazard3 does not reach 96 MHz in the whole design (WNS -1.2 ns, register file to the RAM address;
out of context it just met), so: RV32IM without the bit manipulation extensions and without
`MULH_FAST` (-2.6 ns), the register file in LUT RAM (`HAZARD3_REGFILE_RAM_STYLE_DISTRIBUTED`, a Verilog
define of the R4..R6 projects), 80.2 MHz. The bridge's mailbox accesses (clk_32) are sampled in the
RISC-V's clock first; the nearest clk_32 and 80 MHz edges are 6.2 ns apart (same MMCM), Vivado times
the crossings. The Falcon bench models the three clocks with that phase (`H3=1`: `sim_main.cpp`
`FPU80`).

Most of an instruction used to be Hatari's general code (function pointers for every check, copies
of the FPU state, a full set-up per request) rather than the arithmetic. Changes:

* `rv/sys.c`: `memset`/`memcpy` a word at a time (newlib-nano's go byte by byte: 4600 cycles to clear
  the 256 byte operand buffer of every request with operands) (2026-11-09)
* `engine/fpe_sf.c` (`fpe_sf_exec()`): a short path for FMOVE, FADD, FSUB, FMUL, FDIV, FSQRT, FABS,
  FNEG, FCMP, FTST with a register or a memory operand (.L .S .X .W .D .B) and for FMOVE FPn to
  memory (same formats), when no exception is enabled or pending. It does Hatari's steps in Hatari's
  order with the same softfloat calls (the comment lists them); everything else (packed decimal,
  FSIN and the other transcendental functions, FMOVEM, control registers, exceptions) takes
  Hatari's own path. `fpe_sf_off = 1` turns it off. (2026-11-09)
* `fpe_sf_exec()` is called first (`fpe_shim.c`) and hands everything else to the full path; values
  that are exact at the rounding precision skip `roundAndPackFloatx80` (FMOVE, FABS, FNEG);
  `norm()` returns at once for a normalized value; the status only when it changed (2026-11-15)
* 1.6-test5 (2026-11-16):
  * `engine/fpe_fastk.h`: floatx80 add, subtract and multiply for the common case (normalized
    operands, rounding to nearest, precision 80, no overflow, underflow or exact zero), softfloat's
    steps and intermediate values without the general code; anything else goes to softfloat.
    The short path calls it directly; `engine/fpe_fast.c` puts it in front of softfloat's
    `floatx80_add/sub/mul` for every other caller with `-Wl,--wrap` (`rv/build.sh`, `FAST=0`:
    without), so the FPSP functions (FSIN, FETOX, ...) use it too. 64-bit shifts and the leading
    zero count are written with 32-bit operations (RV32IM has no instructions for them; GCC would
    call libgcc).
  * `fpe_quick()` (`engine/fpe_sf.c`, `fpe_quick.h`): before `fpe_sf_exec()`, a small function for
    FMOVE/FADD/FMUL/FSUB from a register or .L .W .B .S .D .X into FPn and FMOVE FPn to .L .S .X .D
    with normalized operands (the conversions inline). The RISC-V's main loop (`rv/fpu_rv.c`
    `quick()`) reads only the mailbox words these use and writes STATUS from the FPSR `fpe_quick()`
    leaves; `serve()`'s set-up cost about as much as the operation.
  * `fpu_rv_h3.v`: a 64 x 64 bit multiplier at `$30000000` (four 32 x 32 products in DSPs, 5 clocks)
    for `fk_mul64()` (`FPE_HWMUL`, Hazard3 build only): Hazard3's MULHU takes 18 clocks without
    `MULH_FAST`, which does not reach 80 MHz, and was half of every multiplication.
    `rv/bench.c` checks it against the product in C.
  * The bridge polls STATUS every clock or so instead of every 4 (`GAP_WAIT`, `GAP_BG`,
    `doc/m2m/exceptions.md`).
  * Special operands (found with FPUBENCH on the R6: FMUL of an infinity, FMOVE of a zero to and
    from memory were 1.3 to 1.5 times slower than in 1.6-test4): `fpe_quick()` declined them only
    after its whole set-up, then `fpe_exec()` called it a second time, and FMUL went through the
    kernel three times before softfloat. Now `fpe_quick()` checks the operand classes first (a
    decline is about 20 cycles), takes FMOVE of a zero in and out itself (`q_zero()`), a caller
    that already tried it sets `fpe_quick_tried` so `fpe_exec()` goes straight to
    `fpe_sf_exec()`, which calls softfloat's own `floatx80_add/sub/mul` (`FPE_WRAP`); FSUB is
    the kernel's add of the negated operand (one copy of the code: the self-test image is tight).
  * Tried and dropped: a faster `__udivdi3` (Hacker's Delight `divlu`) was slower than libgcc's on
    Hazard3 (DIVU 19 clocks, and GCC turned the remainders into REMU); `MULDIV_UNROLL` 8 (-10 ns)
    and `MULH_FAST` (-7.9 ns with it) at 80 MHz.

RISC-V cycles per instruction (`rv/bench.c` in `CORE/sim/fpu_rv`, `./build.sh ../../falcon_fpu/rv/bench.mem`,
`H3=1 ./build.sh` for Hazard3):

| | before | short path (1.6-test3) | trimmed, PicoRV32 | Hazard3 (1.6-test4) | 1.6-test5 |
|---|---|---|---|---|---|
| FMOVE FP1,FP0 | 2413 | 1277 | 879 | 260 | 160 |
| FADD / FMUL FP1,FP0 | 3066 / 3024 | 1771 / 1741 | 1545 / 1588 | 445 / 531 | 244 / 293 |
| FDIV / FSQRT | 4915 / 4876 | 3622 / 3763 | 3479 / 3615 | 1266 / 1336 | 1284 / 1353 |
| FMOVE.D <ea>,FP0 / FMOVE.D FP0,<ea> | 8204 / 7063 | 1548 / 1166 | 1147 / 977 | 334 / 290 | 238 / 198 |
| FSIN | 17898 | 18280 (Hatari's path) | 18200 | 5950 | 4596 |
| FMUL of an infinity / FMOVE.X of a zero out / FMOVE.D of a zero in | | | | 378 / 269 / 376 | 422 / 156 / 174 |

As the 68030 sees it (`tests/fpulat.s`, us per instruction, 200 Hz ticks: +-2.5 us): 1.6-test3
FMOVE 17.5, FADD/FMUL 22.5, FDIV/FSQRT 42.5, FMOVE.D in/out 22.5, FSIN 190; Hazard3 at 80 MHz:
5, 7.5, 17.5, 7.5/10, 70. 1.6-test5 (`fpulat.s` with 10 times as many instructions, +-0.25 us, in the
Falcon bench): FMOVE 3.5, FADD 4.25, FSQRT 19.75, FMOVE.D in/out 6.75/8.25, FSIN 59, FMUL (the operand
an infinity after a few hundred) 6.25 (1.6-test4 in the same bench: 5.75, 8.0, 19.25, 9.5/10.75, 76, 8.0;
the first 1.6-test5 build before the special operand fix: 3.0, 4.0, 20, 6.25/7.75, 58, 8.0). FDIV and FSQRT are a little slower than in 1.6-test4: they
go through `fpe_quick_cmd()` first, and most of their time is softfloat's 128/64 bit division
(`estimateDiv128To64()`, libgcc's `__udivdi3`).

Checks (all must pass after a change in `engine/` or `rv/`):

* `engine/fpe_shortcheck.c`: the short path against Hatari's path on the host, bit for bit (the eight
  registers, FPSR, FPCR, FPIAR, the bytes stored, the returned flags and the exception status):
  random single instructions (zeros, denormals, unnormals, infinities, NaNs, signaling NaNs, values at
  the edges of the exponent range of each rounding precision, every rounding mode and precision,
  sometimes an enable byte) and sequences of 40 instructions (with Hatari-path instructions,
  exceptions and the CPU taking them). `HOST_ONLY=1 engine/build.sh`, then
  `cc -O2 -I. fpe_shortcheck.c build/host/libfpe.a -lm -o build/fpe_shortcheck` and
  `build/fpe_shortcheck 25000000 <seed>` (several seeds in parallel; a deliberately broken short path
  must make it fail, which was checked for the status bits, the events, .S loads, .D stores, the
  exponent limits of the exact test, the conversions and rounding ties of `fpe_quick()` and its zero
  test (denormals with half of the mantissa zero); it runs
  `fpe_exec()`, so it covers `fpe_quick()`)
* `engine/fpe_fastcheck.c`: the kernel of `fpe_fastk.h` against softfloat's `floatx80_add/sub/mul`
  on the host, bit for bit (result, exception flags and the internal result softfloat keeps for
  exceptions), with random operands and classes aimed at its edges (every exponent difference to
  140, cancellation, rounding ties, the ends of the exponent range, modes it leaves alone); the
  build line is in its header (16 billion cases per change; mutants of the shifts, rounding,
  jamming and limits all fail)
* `engine/fpe_selftest.c` on the host and `rv/selftest.mem` / `rv/selftest_h3.mem` on the RISC-V
  (`CORE/sim/fpu_rv`, `H3=1 ./build.sh` for Hazard3; about 40 / 15 minutes): 24546 checks of the
  engine against `fpp.c` driven with real effective addresses. The self-test image is close to the
  256 KB RAM: with the 1.6-test5 code its stack ran into the data and the CPU restarted after the
  second check, so `fpe_selftest.c` itself is built with `-Os` and `rv/build.sh` now stops if less
  than 8 KB is left above `.bss` (self-test 10 KB, the core's image 45 KB)
* `falcon_fpu/fputest` (FPUTEST.TOS) in the Falcon bench (`FPU=1 H3=1 build.sh`): every operation,
  format, rounding mode, condition and the exception round trips through the bridge, against results
  of the host engine
* `tests/fscc_irq.s` in the Falcon bench: FScc (A1)+ / -(A1) while the FPU is busy and Timer A
  interrupts at 30 kHz (the AP68030 fix of 2026-11-15, `doc/m2m/exceptions.md`): A1 must move by
  exactly one byte per FScc

### EmuTOS in the release zip

`atarist/tosfalc.img` is the Falcon EmuTOS with one change, made by `tools/emutos_scsi_timeout.py`
(it checks the original bytes): `do_scsi_rw` (`bios/scsi.c`) gives a SCSI transfer
max(1 s, length / 1024) ticks, i.e. 200 KB/s. The patch makes that max(10 s, length / 8): at least
1.6 KB/s, 320 ms per sector (`asr.l #10` -> `#3`; `cmpi.l #200` -> `#2000`; `moveq #$37,d6; not.b d6`,
which makes 200, -> `move.w #2000,d6`). 1.4 had length / 64 (12.8 KB/s) with the 1 s minimum, which
was still too little on a tester's SD card (Signum install; 1.5 has the new values, confirmed on
the tester's R6, issue #34). His stopwatch: copying 1 MB takes about 31 s on SCSI, IDE and with
TOS 4.04 + ICD alike (about 33 KB/s each way), so single transfers must stall for more than 1 s
now and then. Upstream
EmuTOS uses length / 64 since emutos#81. Apply the patch to every new EmuTOS image before a release
(the offset depends on the build: find `moveq #10,d0; asr.l d0,d6; cmpi.l #200,d6` in a disassembly).
`tos.img` (ST, ACSI) is unchanged. The real cure is a faster SD path: up to 1.6-test6 the firmware
moved unbuffered drives with one `f32_fread` / `f32_fwrite` call per byte (`VD_UB_READ` /
`VD_UB_WRITE`, `M2M/rom/shell.asm`); since then it copies sector-wise (`M2M/rom/vd_ubcopy.asm`,
about 8.6 times fewer QNICE instructions; speed on hardware not measured yet).

`tools/JTAG.md` describes the JTAG tools used for debugging on the real hardware (a TE0790 adapter
and Vivado's hardware manager, no ILA needed).

Building
--------

1. `git submodule update --init --recursive`
2. Build the QNICE toolchain: `cd M2M/QNICE/tools && ./make-toolchain.sh`
3. Open `CORE/CORE-R6.xpr` (or R4/R5) in Vivado 2022.2 or newer and generate the bitstream.
   The firmware (`CORE/m2m-rom/m2m-rom.rom`) is built automatically before synthesis.
