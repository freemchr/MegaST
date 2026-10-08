Version 0.4.12 beta - October 8, 2026
=====================================

* **The core remembers the mounted images (issue #13).** With the new file `/atarist/stmount`
  (1536 bytes, included in the zip), the floppy and hard disk images and the TOS and cartridge
  chosen in the menu are loaded again at the next start, before the ST boots. Unmounting a drive
  in the menu forgets it. A long press of the reset button now brings the remembered images back
  (like a power cycle) instead of leaving the drives empty.

The menu is unchanged: the 99 byte `/atarist/stcfg` of 0.4.8 to 0.4.11 stays valid. Hard disk writes
are unchanged since 0.4.11.

Version 0.4.11 beta - October 8, 2026
=====================================

* **Hard disk writes were still broken in 0.4.10 (issue #11).** The core's ACSI controller took
  each word from the ST's DMA one clock cycle too early and got old data, so only the first 16
  bytes of every written sector were correct. TOS kept showing the files from its cache until it
  read the disk again (e.g. after a power cycle), then files, folders and the FAT were damaged.
  **Hard disk images that were written to with 0.4.10 or older may be damaged: restore them from
  a backup or check them.** Floppy disks were not affected.
* When a hard disk driver times out during a long write and retries, the controller now cancels
  the old command. Before, the data of the retry could be written to the wrong sectors.
* New simulation test of hard disk writes (`CORE/sim/acsi_write`): 64 KB written in one go and
  checked sector by sector, also with slow SD card timing.

The menu is unchanged: the 99 byte `/atarist/stcfg` of 0.4.8 to 0.4.10 stays valid.

Version 0.4.10 beta - October 7, 2026
=====================================

* **Hard disk writes were broken in all versions up to 0.4.9 (issue #11).** Every sector the ST
  wrote to a hard disk image was filled with the floppy controller's sector buffer instead of the
  ST's data, so new files, directories and the FAT were overwritten with wrong data. TOS kept
  showing the files from its cache until it read the disk again, then they were gone.
  `fdc_bridge.vhd` returned the sector buffer of the drive with an active sd_ack, but the firmware
  reads the data of a write request before it sends the ack. **Hard disk images that were written
  to with an older version may be damaged: restore them from a backup or check them.**
* A long press of the MEGA65 reset button (restarts the menu firmware, which forgets the mounted
  images) now also ejects the floppies and hard disks in the ST. Before, the ST could still read
  the old floppy while the menu showed no disk (issue #10).

The menu is unchanged: the 99 byte `/atarist/stcfg` of 0.4.8 and 0.4.9 stays valid.

Version 0.4.9 beta - October 6, 2026
====================================

* Opening the menu with the Help key stopped 0.4.8 with "Heap corruption: Hint: OPTM_HEAP_SIZE"
  (error code 002B, reported in issue #6). The larger menu of 0.4.8 needed more than the 2048
  words the firmware reserves for it; the menu buffer now has 2560 words.

The menu is unchanged: the 99 byte `/atarist/stcfg` of 0.4.8 stays valid.

Version 0.4.8 beta - October 6, 2026
====================================

* Changing the machine type or the memory size in the menu crashed the ST until a TOS was
  loaded again (issue #7). TOS keeps the memory layout in RAM and trusts it at the next reset.
  The core now clears it and restarts the ST with a cold boot automatically.
* New option "Keyboard" in "Controllers & ports" (issue #6): "As printed, US TOS" / "As printed,
  UK TOS" give the character printed on the MEGA65 key instead of the ST key at the same position
  ("ST keys (positional)" stays the default).
* MEGA65 R3/R3A support: its own core file with the ST RAM in block RAM (512 KB, no Viking, no
  STEroids). Confirmed working on an R3A by a tester (issue #2). Builds for the R4 and R5 are
  included too (not tested on hardware yet).

**Important:** the menu has five more items, so `/atarist/stcfg` must be the new 99 byte file
from the release zip (the old 94 byte file is reported as corrupt and settings are not saved).

Version 0.4.7 beta - October 5, 2026
====================================

Bug fixes and one new option, based on the first tester reports.

* The A key did not work (issue #1). A Vivado synthesis bug turned the first key mapping in
  `keyboard.vhd` into a constant, so the ST always saw A as held down. Fixed and confirmed on
  a MEGA65 R6.
* New option "DVI mode (no sound)" in the HDMI settings for DVI monitors on an HDMI-to-DVI
  cable, which show a garbled picture with the HDMI audio and info packets (issue #4).
* README: the Amiga and 1351 mice have to be selected in the menu ("Mouse type", issue #5);
  how the 71 Hz mono mode is shown on VGA and HDMI (issue #3).

**Important:** the menu has two more items, so `/atarist/stcfg` must be the new 94 byte file
from the release zip (the old 92 byte file is reported as corrupt and settings are not saved).

Version 0.4.6 beta - October 3, 2026
====================================

First public release. Tested on a MEGA65 R6; see the README for what has been tested.

Features
--------

* Atari ST, STe, Mega STe and "STEroids" modes, 512 KB to 14 MB of ST RAM, blitter
* TOS 1.00 - 2.06 and EmuTOS; `tos.img` at power on, other TOS images from the menu
* Two floppy drives (`.st`, read/write, swappable), blank disk images with `tools/make_st_disk.py`
* Two ACSI hard disks (`.hd`/`.img`/`.vhd` images up to 4 GB, directly on the SD card, fast seek)
* Atari ST, Amiga and Commodore 1351 mice in port 1 or port 2, joystick in the other port
* Joystick debouncing that also copes with worn switches that chatter while held
* HDMI and VGA (scanlines, 15 kHz RGB with composite sync), colour and mono monitors,
  full borders, zoom-in
* Mega ST real time clock from the MEGA65's clock, cartridges, Cubase dongles, Viking card,
  serial, MIDI and printer ports on the PMOD headers
* Menu settings are saved on the SD card (`/atarist/stcfg`)

Fixed during testing
--------------------

* Closing the menu or "Reset Atari ST" froze the whole machine when settings saving was active
  (a bug in the MiSTer2MEGA65 V2.0.1 firmware, fixed the same way upstream in the develop branch)
* Virtual drives stayed mounted in the menu but were lost by the ST after a reset
* Seeking in large hard disk images took minutes; 4 GB images now seek at once

Earlier versions
================

Versions 0.1 to 0.4.5 (September 27 - October 2, 2026) were internal test builds.

MiSTer2MEGA65 framework
=======================

MegaST is based on MiSTer2MEGA65 V2.0.1 (February 22, 2025):
https://github.com/sy2002/MiSTer2MEGA65/blob/master/VERSIONS.md
