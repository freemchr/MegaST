Falcon_MiSTer in MegaST
=======================

This folder is a copy (not a submodule) of the Atari Falcon030 core for MiSTer, used for the
"Falcon030" machine of MegaST:

| Part | Source | Commit | Licence |
|------|--------|--------|---------|
| `rtl/falcon`, `docs`, `README-upstream.md` | https://github.com/apolkosnik/Falcon_MiSTer | `09c1844` (2026-10-20) | no licence file upstream; used with the author's permission (see below) |
| `rtl/AP68030` | https://github.com/apolkosnik/AP68030 | `4772ea4` | GPL v2 or later (`rtl/AP68030/LICENSE`) |

Not copied: the MiSTer framework (`sys/`), the Quartus project, the HPS (ARM) parts (FPU service,
Main_MiSTer patches) and the upstream test benches. MegaST has no ARM CPU, so the 68882 FPU is
not available (`FALCON_NO_FPU`).

Licence: Falcon_MiSTer has no LICENSE file. The maintainer was told by the author that the
core may be used in MegaST. Before a release with the Falcon, the permission must be on record
(ideally a LICENSE file upstream, GPL v2-or-later or v3 to match MegaST's GPL v3).

Changes to these files are marked with `MEGA65` comments and listed in `doc/m2m/exceptions.md`
(none yet). When updating, copy the new upstream files and re-apply the changes.
