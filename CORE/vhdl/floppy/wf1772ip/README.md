# WF1772IP: WD1772 floppy disk controller

A complete WD1772-02 in VHDL (digital PLL, address mark detector, CRC, step/index/motor timing,
MFM/FM read and write with precompensation) by Wolfgang Foerster (Inventronik GmbH), from the Suska
Atari clone. LGPL 2.1 or later (see the file headers), compatible with MegaST's GPL v3.

Source: https://github.com/MelkhiorVintageComputing/Suska_Configware, folder `FDC1772`, commit
`edef821840dc45221cd003caa90d769860a3967c`, revision 2K15B (2015/12/24, `std_logic` ports). The copies in
the Firebee and other repositories are older (`bit` ports) or only reformatted.

* `orig/`: the unmodified source (line endings converted to LF). Used by the equivalence test.
* `*.vhd`: the source converted to a clock enable by `tools/wf1772_ce.py`. The IP expects 16 MHz; the
  converted files take the 32 MHz core clock and `CE` at half rate. Every clocked process only advances when
  `CE = '1'`; the `INPORT` process (RDn on the falling edge) samples on the rising edge without `CE`, because
  `m65_floppy_port.vhd` already synchronises RDATA. The converted lines are marked `MegaST`.
  `wf1772ip_top.vhd` (tri-state data bus) is not used.

Do not edit the converted files by hand: change `tools/wf1772_ce.py` and regenerate
(`tools/wf1772_ce.py CORE/vhdl/floppy/wf1772ip/orig CORE/vhdl/floppy/wf1772ip`).

Bug fixes (`FIXES` in `tools/wf1772_ce.py`, applied before the conversion, marked `MegaST fix`):
* Force interrupt with no command running (issue #24): the IDLE state started a command on the bus write
  (`CMD_WR`, combinational) while the command register still held the previous command. `D0` written
  while idle therefore restarted the last command (after a reset: restore with spin-up, busy until 6 index
  pulses), and the controller ignored the next command. EmuTOS sends `D0` and then a restore to detect
  the drive, so it found no drive A:. IDLE now starts a command on the second clock of the write, when
  the register holds the new value (every CPU access spans at least two enabled edges, see
  `wd1772_m65.v`).

`CORE/sim/real_floppy/run_wf1772.sh` runs the original IP (with the bug fixes, `--fix-only`) on 16 MHz
and the converted IP on 32 MHz with `CE` side by side, on the same CPU accesses and the same drive model (`floppy_model.vhd`). Every output
must be identical at every 16 MHz edge, and the commands must work (restore, seek, read sector with every
byte checked, read address, step in, side 1, force interrupt during and without a command).

Known differences from a real WD1772 (in the original IP):
* Read address transfers 4 bytes (track, side, sector, size). The WD1772 also transfers the 2 CRC bytes.
