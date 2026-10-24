Falcon_MiSTer in MegaST
=======================

This folder is a copy (not a submodule) of the Atari Falcon030 core for MiSTer, used for the
"Falcon030" machine of MegaST:

| Part | Source | Commit | Licence |
|------|--------|--------|---------|
| `rtl/falcon`, `docs`, `README-upstream.md` | https://github.com/apolkosnik/Falcon_MiSTer | `09c1844` (2026-10-20) | no licence file upstream |
| `rtl/AP68030` | https://github.com/apolkosnik/AP68030 | `4772ea4` | GPL v2 or later (`rtl/AP68030/LICENSE`) |

Not copied: the MiSTer framework (`sys/`), the Quartus project, the HPS (ARM) parts (FPU service,
Main_MiSTer patches) and the upstream test benches. MegaST has no ARM CPU: the FPU service runs on
a RISC-V in the FPGA instead (`CORE/verilog/fpu_rv.v`, `CORE/falcon_fpu`, `FALCON_FPU_LOCAL`).

Changes to these files are marked with `MEGA65` comments and listed in `doc/m2m/exceptions.md`. When updating, copy the new upstream files and re-apply the changes.
