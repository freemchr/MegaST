# JTAG tools (TE0790 adapter, Vivado hw_server)

Development helpers for debugging MegaST on real hardware without an ILA (the free Vivado
licence refuses debug-core insertion). Run them with
`vivado -mode batch -nojournal -nolog -source <script>` (on this machine with
`LD_LIBRARY_PATH=~/.local/lib/vivado-compat`). In WSL the adapter has to be attached first:
`usbipd attach --wsl --busid <busid>` in an admin PowerShell.

| Script | Purpose |
|---|---|
| `prog.tcl` | Load a bitstream into the FPGA (volatile): `$BIT` or `CORE/CORE-R6.runs/impl_1/mega65_r6.bit` |
| `probe.tcl` + `decode.py` | Sample the QNICE CPU bus `$N` times (USER1, 64 bits, `M2M/vhdl/QNICE/qnice.vhd`); `decode.py samples.txt CORE/m2m-rom/m2m-rom.lis` maps addresses to firmware labels |
| `probe2.tcl` + `decode2.py` | Joystick ports, mouse menu settings, pots and edge counters (USER2, 96 bits, `CORE/vhdl/mega65.vhd`) |
| `probe3.tcl` + `decode3.py` | Keyboard: the ST keyboard matrix from `keyboard.vhd`, the last 4 bytes the CPU read from the keyboard ACIA and press counters for the MEGA65 keys A/S and the ST key A (USER3, 176 bits, `CORE/vhdl/mega65.vhd`) |
| `probe5.tcl` + `decode5.py` | Falcon: the last 68030 program space bus address and device access, DSP PC, R6, R7, LC, SSISR, host port ISR/HSR and a count of the DSP's SSI TX writes (USER2 bits 255..96, `CORE/vhdl/mega65.vhd`; `N` samples `MS` ms apart) |
| `probe4.tcl` + `decode4.py` | Internal floppy drive (USER4, 224 bits, `CORE/vhdl/floppy/floppy_probe.vhd`): sends an optional command `$CMD`, then reads index period (rpm), flux transitions per revolution, a histogram of the flux intervals, TRK00/WPT/DSKCHG and step counters |

Floppy probe commands (`CMD`, hex): bits 15..8 must be `A5`. Bit 0 motor, 1 select A, 2 side 1,
3 direction in, 4 clear the counters, 5 density pin low, 6 select B; bits 23..16 = number of step pulses
(6 ms apart). Examples: `00A503` motor on and drive A selected, `05A50B` 5 steps in, `05A503` 5 steps out,
`00A507` side 1, `00A500` everything off. The write lines are never driven (`G_WRITE_ENABLE` false), and
the motor stops by itself after 30 s without a step. Example:
`CMD=00A513 N=8 vivado -mode batch -nojournal -nolog -source tools/probe4.tcl | tee f.txt; tools/decode4.py f.txt`

Command log of the real floppy controller ("Real floppy drive as A:" on): per command the track, side,
sector, data register, bytes moved by DMA and the status the ST read afterwards (CRC error, record not
found, lost data). Shows where a loader gives up:
`LOG=1 vivado -mode batch -nojournal -nolog -source tools/probe4.tcl | tee l.txt; tools/decode4.py --log l.txt`

Raw flux capture: `FLUX=arm` records 128 KB of flux from the drive (about 3 revolutions of whatever track
the core or the probe has selected; the capture only listens), `FLUX=dump` reads it out (check that the
snapshot says `done` first). `tools/flux2scp.py` turns the dump into an SCP file, which
`CORE/sim/real_floppy/scp_mfm.py` decodes and `CORE/sim/real_floppy/run_flux_replay.sh` replays into the
floppy controller in simulation:
`FLUX=arm vivado ... -source tools/probe4.tcl`, then
`FLUX=dump vivado ... -source tools/probe4.tcl > d.txt; tools/flux2scp.py d.txt t.scp <cyl> <head>`

`redboot.st` (repo root, not committed): a 360 KB test disk whose boot sector turns the background red.
