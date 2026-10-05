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

`redboot.st` (repo root, not committed): a 360 KB test disk whose boot sector turns the background red.
