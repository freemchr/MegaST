# MegaST: guide for AI coding agents

MegaST is the **Atari ST/STe core for the MEGA65**: a port of the MiSTer core
[AtariST_MiSTer](https://github.com/MiSTer-devel/AtariST_MiSTer) to the MEGA65, made with the
[MiSTer2MEGA65](https://github.com/sy2002/MiSTer2MEGA65) (M2M) framework V2.0.1.
Maintainer: Chris Freeman (https://github.com/freemchr/MegaST). License: GPL v3.

This file is about **this core**. It is not the M2M framework's own `AGENTS.md`. That file describes
the framework internals, and so does the
[Ultimate MiSTer2MEGA65 Porting Guide](https://github.com/sy2002/MiSTer2MEGA65/wiki/The-Ultimate-MiSTer2MEGA65-Porting-Guide).
Both are the reference for anything inside `M2M/`.

## Read first

| Document | Content |
|----------|---------|
| `README.md` | User manual: installation, keys, menu, what has been tested |
| `doc/DEVELOPMENT.md` | How the port works (file table), memory map, tests, building |
| `doc/m2m/exceptions.md` | Every change to the MiSTer core and to `M2M/` (re-apply when updating) |
| `tools/JTAG.md` | JTAG probes for debugging on the real hardware (no ILA) |
| `VERSIONS.md` | User-facing changelog |

## Layout in one paragraph

`CORE/AtariST_MiSTer/` is a copy of the MiSTer core (not a submodule). `CORE/verilog/atarist_m65.sv`
is the ST machine of the MiSTer `AtariST.sv` without the MiSTer framework. `CORE/vhdl/` is the M2M core
side: `main.vhd` (core clock domain), `mega65.vhd` (framework contract, menu bits, devices), `config.vhd`
(menu and help texts), `globals.vhd`, `keyboard.vhd`, `clk.vhd`. `M2M/` is the framework, with a few
documented changes. `CORE/sim/` holds the simulations.

## Boards

| Board | Memory | Status |
|-------|--------|--------|
| R6 | SDRAM | Main target, tested on hardware by the maintainer (`CORE/CORE-R6.xpr`) |
| R4, R5 | SDRAM | Same design (`CORE-R4.xpr`, `CORE-R5.xpr`); not tested on hardware |
| R3, R3A | no SDRAM | Block RAM build (`CORE-R3.xpr`): 512 KB ST RAM, no Viking, no STEroids; R3A confirmed by a tester (issue #2) |

The maintainer only has an R6. Never call a build for another board "working" before a tester has
reported it.

## Rules

* **Never commit TOS images.** Real Atari TOS ROMs are copyrighted. Local copies live in `TOS/`
  (ignored). The release zip ships EmuTOS only.
* **`M2M/` is the framework.** Change it only when unavoidable. Give new ports a default that keeps the
  old behaviour, mark the change with a `MegaST` comment and add it to `doc/m2m/exceptions.md`.
  Generic fixes are candidates for upstream.
* **Menu changes ripple.** The menu line index is the OSM bit, so after inserting or removing a line in
  `OPTM_ITEMS` / `OPTM_GROUPS` (`config.vhd`), every `C_MENU_*` in `mega65.vhd` below it shifts.
  `top_mega65-r*.vhd` also hard-code `main_osm_control_m(48)` (`C_MENU_MOUSE1351`). `OPTM_SIZE` is the
  size of the settings file `/atarist/stcfg`. If it changes, ship a new `stcfg` (all `0xFF`) and say so
  in `VERSIONS.md` and the README. Likewise `/atarist/stmount` (remembered images) has
  `(C_VDNUM + C_CRTROMS_MAN_NUM) * 256` bytes (`globals.vhd`, currently 1536): ship a new one if that changes.
* **ST memory must stay fast.** The ST bus needs RAM read data within about 175 ns. In the simulator,
  TOS 1.04 survives 10 extra 96 MHz cycles and crashes at 11. Video, DMA and the blitter cannot wait.
  That rules out HyperRAM (about 90 ns average, much more while ascal bursts) for ST RAM.
  ST RAM, TOS and the cartridge are in SDRAM (`sdram_m65.v`), or in block RAM on the R3 (`bram_m65.v`,
  the same 12-state bus cycle). The floppy images are buffered in HyperRAM (not timing critical).
* **Vivado synthesis bugs are real.** Vivado 2026.1 turned the first call of a VHDL procedure that
  writes a process variable implicitly into a constant (`keyboard.vhd`, the A key, issue #1). GHDL and
  Verilator simulated it correctly. So pass variables to procedures as explicit `inout` parameters,
  and don't write through `alias`es (see the porting guide, 3.D.3).
* **Vivado rewrites `.xpr` files** when it opens them (format and absolute paths). Commit only
  intended file-list changes, never a format rewrite. Keep the file lists of `CORE-R3..R6.xpr` in
  sync (R3 differs: `MEGA65-R3.xdc`, `top_mega65-r3.vhd`, `max10.vhdl` and `pcm_to_pdm.vhdl` instead of
  `audio.vhd`, no `CORE-SDRAM.xdc`).
* **File headers** follow the M2M template (`-- This machine is based on AtariST_MiSTer`,
  `-- Powered by MiSTer2MEGA65`, `-- MEGA65 port done by Chris Freeman in 2026 ...`).
  Changes inside MiSTer files are marked with `MEGA65` comments.

## Verify before hardware

Simulate first. Every hardware round trip costs the maintainer time.

* `CORE/sim/build.sh`: Verilator simulation of the whole ST (`cd obj_dir && ./simst <tos.img>
  <frames> [prefix] [ste] [hd.img]`). It writes every 10th frame as PPM. `VFLAGS=-DBRAM_MEM` builds
  the R3 memory variant. `KEY=<col*8+row> KEY_AT=<frame>` presses a key, `MEM=0..5` sets
  the ST RAM (512 KB to 14 MB, default 1 MB).
* `CORE/sim/{keyboard,tos_loader,floppy_swap,fdc_bridge,rmb_guard}/run.sh`: GHDL unit tests.
* `CORE/sim/fastseek/run.sh`: firmware fast seek in the QNICE emulator.
* `CORE/sim/mntmem/run.sh`: remembering the mounted images (`/atarist/stmount`) in the QNICE emulator.
* `CORE/sim/acsi_write/run.sh <emutos tos.img> [delay]`: hard disk writes (64 KB, every sector checked).
* After a Vivado build check: timing met (WNS/WHS >= 0), no new critical warnings, no block RAM
  demoted to LUTRAM (Synth 8-5835).

## Releases

The version is in `config.vhd` (welcome and help texts), `VERSIONS.md` and the README. The `.cor`
comes from `bit2core mega65r6 <bit> "Atari ST" <version> <file>` (`mega65r3`/`r4`/`r5` for the other
boards). The release zip holds the `.cor`, `README.txt` and `atarist/` (EmuTOS `tos.img` plus its
license files, `stcfg`). Posting releases or issue comments needs the maintainer's OK.
