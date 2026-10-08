# Blueprint: the MEGA65's internal floppy drive in M2M cores

Status: plan, nothing implemented yet (2026-10-08). Feature request: issue #15.

The goal is two things: drive A: of MegaST on the MEGA65's internal 3.5" drive, and a set of building blocks
that other MiSTer2MEGA65 cores (C64 1581, Amiga, Amstrad CPC, Spectrum +3, BBC Master, SAM Coupé, MSX, PC)
can reuse.

## 1. Hardware facts (checked)

* The drive is a standard PC 3.5" drive (720 KB DD / 1.44 MB HD) on the usual 34-pin cable. DD disks at
  300 rpm and 250 kbit/s MFM are exactly the Atari ST format.
* **All drive signals go straight to FPGA pins.** The top files declare them and tie them off:
  `M2M/vhdl/top_mega65-r*.vhd` (`f_* <= '1'`). The pins are the same on **R3, R4, R5 and R6**
  (`M2M/MEGA65-R*.xdc`: P6 F_REDWC, R1 F_DSCKCHG, M2 F_INDEX, M5 F_MOTEA, H15 F_MOTEB, P1 F_RDATA1, N5 F_DRVSA,
  G17 F_DRVSB, M1 F_SIDE1, P5 F_DIR, M3 F_STEP, N2 F_TRCK0, N4 F_WDATE, N3 F_WGATE, P2 F_WPT).
  So the R3/R3A does *not* need a different connection (issue #15 says otherwise; correct it there).
* All signals are **active low at the pin**. The MEGA65 core (`mega65-core/src/vhdl/sdcardio.vhdl`) drives
  the internal drive with `f_motora`/`f_selecta` (drive 0) and keeps `f_density` at `'1'` by default.
* Inputs: `f_rdata_i` (one short low pulse per flux transition, 4/6/8 µs apart for DD MFM), `f_index_i`
  (5 Hz), `f_track0_i`, `f_writeprotect_i`, `f_diskchanged_i` (PC pin 34 = DSKCHG, not READY: it goes active
  when the disk is removed and clears only on a step pulse while the drive is selected).

Still to check on the hardware (phase 0): pulse widths and glitches on RDATA, the WPT level with no disk inserted
(TOS detects a disk change from the write-protect line), whether `f_density` matters for DD disks, the minimum
step pulse width the drive accepts, and the drive's power-up behaviour.

## 2. Building blocks we can reuse (checked)

| Block | Source | Licence | Use |
|-------|--------|---------|-----|
| **WF1772IP**: a complete WD1772-02 (digital PLL, address mark detector, CRC, step/index/motor timing, MFM write with precompensation, HD mode) | Wolfgang Förster, Suska Atari clone; on GitHub e.g. `MelkhiorVintageComputing/Suska_Configware/FDC1772`, `Torlus/firebee-fpga` (used in the Firebee) | LGPL 2.1+ | ST, C64 1581 (the 1581 *is* a 6502 plus a WD1772), BBC Master and SAM Coupé (WD1770/1772); adaptable to the WD279x of the MSX |
| **MEGA65 MFM pipeline**: `mfm_gaps`, `mfm_quantise_gaps`, `mfm_bits_to_bytes`, `mfm_decoder` (finds track/sector, reports the start of the data gap for writes), `crc1581`, `mfm_bits_to_gaps` (write) | `MEGA65/mega65-core` `src/vhdl/` | LGPL 3 | sector-level access for image-based controllers (section 3, layer 2b) and for firmware disk dumping |

Both are compatible with our GPL v3. Copy them into the repo with their headers intact, and record the origin
and any changes in `doc/m2m/exceptions.md` style notes.

WF1772IP details that matter for the port (from the source, 9 files, about 3800 lines):
* It expects a **16 MHz clock**. The PLL counters (`TOP`=152, `BOTTOM`=104, `PHASE_CORR`=75, nominal 128) are
  tuned to it, and the author warns that they are critical. We have `clk_32` at 32.08 MHz: a clock enable at
  half rate gives 16.04 MHz (+0.25 %, far inside the PLL's ±18 % range).
* It samples `RDn` on the **falling** clock edge (one process in `wf1772ip_digital_pll.vhd`). Replace that with a
  two-flip-flop synchroniser in `clk_32`. Every other process uses `wait until CLK = '1'`. Turn those into
  clocked processes with an `if ce = '1'` guard (a mechanical change, checked by simulating before and after).
* Its ports use the `bit` type. Keep them inside a wrapper and present `std_logic` outwards.
* Remember the Vivado rule from `AGENTS.md`: no procedures that write process variables implicitly. Grep the IP
  for them before synthesis.

## 3. Architecture: three layers

```
 FPGA pins ──► [1] m65_floppy_port ──┬──► [2a] WD177x controller (WF1772IP) ──► ST / 1581 / BBC / SAM
 (top files)   generic, every core   ├──► [2b] sector bridge (MEGA65 MFM)   ──► image-based MiSTer FDCs
                                     ├──► [2c] raw bit cells                ──► Amiga Paula
                                     └──► [2d] QNICE firmware access        ──► dump a real disk to .st/.d81/.adf
```

### Layer 1: `m65_floppy_port` (generic, every core)

One VHDL entity that owns the 15 pins. Cores never touch the pins directly.

* Default: every output inactive (`'1'`), exactly like today's tie-offs. A core that does not instantiate it
  behaves as before.
* Inputs: two-flip-flop synchronisers, a glitch filter on RDATA (like `mfm_deglitch`), and a one-cycle
  `flux_pulse` on the falling edge of RDATA, in the core's clock domain.
* Outputs: `select`, `motor`, `side`, `dir`, `step`, `wdata`, `wgate`, `density`, for drive A (internal) and
  B (spare, F_DRVSB/F_MOTEB).
* Safety in hardware, not in the core:
  * a step pulse stretcher (minimum width, direction setup time before the step);
  * **write interlock:** `wgate` only goes low when a generic `G_WRITE_ENABLE` is true *and* the menu
    allows writing *and* the drive is selected *and* the motor runs *and* WPT is not active. The read-only builds
    tie `G_WRITE_ENABLE` to false, so a bug cannot damage a tester's original disks;
  * a motor watchdog: motor off after N seconds without a select (in case the core hangs or is reset while the
    motor runs);
  * motor and select off on `reset_hard_i`.
* Owner multiplexer: `core` or `firmware` (layer 2d), switched by a QNICE register.
* Debug: counters for index pulses, flux pulses and steps, readable through a JTAG USER probe (`tools/JTAG.md`).

Where it lives: `CORE/vhdl/floppy/` as a self-contained directory (entity, testbench, README), so other cores can
copy the directory. The only `M2M/` change is to route the `f_*` pins from `top_mega65-r*.vhd` into the core
(through `mega65.vhd`), with a `MegaST` comment and an entry in `doc/m2m/exceptions.md`. It is a candidate for
upstream M2M because every board revision has the same pins.

### Layer 2a: WD177x controller (WF1772IP wrapper)

`wd1772_real.vhd`: WF1772IP behind the same CPU-side interface as MiSTer's `fdc1772.sv`
(`cpu_addr/sel/rw/din/dout`, `irq`, `drq`, `clk8m_en`), with drive-side ports for layer 1. It contains the
clock-enable conversion and the synchroniser. The ST, C64 (1581) and BBC/SAM cores can use it unchanged.

### Layer 2b: sector bridge (for later, other cores)

Many MiSTer floppy controllers work on images through the `sd_lba/sd_rd/sd_wr/sd_ack/sd_buff_*` interface.
The bridge looks like that image interface to the controller. Behind it, it reads and writes real sectors: it seeks,
uses `mfm_decoder` to find the ID, and moves the 512 byte data field into the buffer. It finds the geometry
(sectors per track, sides) from the boot sector or a read-address scan. It handles only standard formats and
no copy protection, but it fits any image-based controller with IBM MFM sectors (uPD765 cores for CPC, +3 and
PC, after a check of their image formats). The ST does not need it.

### Layer 2c: raw bit cells (Amiga)

Paula reads raw MFM. A simple data separator turns `flux_pulse` into 2 µs bit cells for the Paula disk DMA.
Only DD disks: the drive spins at 300 rpm, and Amiga HD needs 150 rpm.

### Layer 2d: firmware access (for later)

QNICE takes over the port and reads a real disk track by track through `mfm_decoder`, then writes an `.st`
(or `.d81`) to the SD card. This is "make an image of my original disk", it is useful in every core and it needs no
core-side controller.

**Not possible with this drive:** the Mac 400K/800K (variable speed GCR), C64 1541 and Apple II (5.25" GCR).

## 4. MegaST integration

`CORE/verilog/atarist_m65.sv` today: `fdc1772` at lines ~1111-1145, `floppy_side = port_a_out[0]` and
`floppy_sel = port_a_out[2:1]` (PSG port A, both active low, which matches the pin polarity directly:
`f_selecta_o = floppy_sel[0]`, `f_side1_o = port_a_out[0]`). `dma.v` talks to the FDC through
`fdc_sel/addr/rw/din/dout/drq`, and `fdc_irq` goes to MFP GPIO 5. The ST has one WD1772 for both drives. Its MO
output drives the motor line of both drives.

* **Stage 1:** a menu item "Drive A: Image / Real drive". With "Real drive", *all* FDC traffic goes to
  `wd1772_real` (mux on `fdc_dout`, `fdc_irq`, `fdc_drq`). Drive A is the internal drive and drive B is absent,
  so commands to B time out as on an ST with one drive. The image drives are idle. This is the smallest change and
  gives a real WD1772 with real timing.
* **Stage 2:** A: real, B: image. Route the register accesses by `floppy_sel`, and write the track and sector
  registers into both controllers so that they agree when TOS switches drives. Read status, data, IRQ and DRQ from
  the selected one.
* Menu ripple (`AGENTS.md`): a new line shifts the `C_MENU_*` constants, it may move `main_osm_control_m(48)` in
  the top files, and it changes `OPTM_SIZE`, so we ship a new `stcfg`. The main menu shows at most 23 lines,
  so the item may have to go into a submenu. Check `MENU_HEAP_SIZE` too (the 0.4.8 crash).
* The block RAM cost of WF1772IP is small (registers and a CRC, no sector buffer), so the R3 build should fit.

## 5. Simulation first

The simulators cannot see a real drive, so we need a **flux-level drive model**. It is reusable for every core:

* **C++ for Verilator** (`CORE/sim/tb.cpp`, enabled with e.g. `RFLOPPY=disk.st`): builds the MFM bit stream of
  each track from an `.st` file (standard ST layout: gap, 3 × A1* sync, IDAM FE, ID, CRC, gap, DAM FB, 512
  bytes, CRC, 9-11 sectors), turns it into RDATA pulses at 250 kbit/s, gives index once per revolution
  (200 ms = 6.4 M `clk_32` cycles), keeps a head position from STEP/DIR, reports TRK00 and WPT, and decodes WDATA
  back into the image for write tests.
* **The same model in VHDL for GHDL** (`CORE/sim/real_floppy/run.sh`): WF1772IP alone, with fast unit tests
  (restore, seek, step rates, read sector, read address, read track, force interrupt, index timeouts, and later
  write sector compared byte by byte). Add a flux jitter and speed error setting (±3 %) to check the PLL margin.
* Full system: boot TOS 1.04 and EmuTOS from the model drive in Verilator (a few revolutions plus seeks: a
  long run at about 16 frames per minute, so run it in the background), and diff a file copied from the
  real-drive model against the image drive.

## 6. Phases

| Phase | Content | Verification | Hardware session |
|-------|---------|--------------|------------------|
| 0 | Bring-up probe: `m65_floppy_port` with a JTAG probe only. A menu or probe bit spins the motor and steps the head, and the probe reads counters for index, flux pulses, TRK00, WPT and DSKCHG, with and without a disk, DD and HD | GHDL test of the port | yes: answers the open questions in section 1 |
| 1 | Layer 1 complete (stretchers, interlock, watchdog) | GHDL | no |
| 2 | WF1772IP imported, clock enable conversion, wrapper `wd1772_real` | GHDL against the VHDL drive model; output identical before and after the conversion | no |
| 3 | MegaST stage 1, **read only** (`G_WRITE_ENABLE` false), menu item | Verilator boot from the flux model, regression of the normal image boot, Vivado timing | no |
| 4 | Read standard DD disks on the hardware, tune the PLL if needed | probe counters, CRC error count in the probe | yes, several |
| 5 | Writing (interlock on, menu "allow writes"), precompensation as WF1772IP does it | GHDL write and read back, Verilator copy test | yes, on scratch disks only |
| 6 | Stage 2 (A real, B image), copy-protected originals, firmware disk dump (2d) | sim and testers | yes |

Phases 0 to 3 can be done mostly in simulation. Phase 4 is the first point where we learn whether the PLL
reads the drive's signal cleanly.

## 7. Risks

* **PLL tuning** on the real signal (the author warns about it). The probe counters and a CRC error counter make
  this measurable without a logic analyser.
* **The clock enable conversion** of WF1772IP could introduce subtle bugs. Mitigation: GHDL runs with the
  original 16 MHz clock and the converted version must give identical register and flux traces.
* **Media change detection** in TOS relies on the WPT line behaving like an ST drive when the disk is removed.
  Check in phase 0. If not, synthesise the WP toggle from DSKCHG.
* **Writes can destroy disks.** Interlock in layer 1, read-only builds until phase 5, and testers use scratch disks
  only.
* **Copy protection** needs exact WD1772 behaviour. WF1772IP aims for that, but only real originals tested on
  the hardware will show how close it is.
