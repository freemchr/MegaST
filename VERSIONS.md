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
