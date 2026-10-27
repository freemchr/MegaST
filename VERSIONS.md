Version 1.2 - October 27, 2026
==============================

* **New menu look**: the on-screen menu and the welcome screen in the style of the Atari GEM desktop
  (black on white, green headlines, black selection bar) with the MegaST logo.
* **Falcon: "Hard disks on SCSI (ICD)"** (Falcon030 settings, off by default): the hard disks are
  SCSI ID 0 and 1 on the Falcon's SCSI port instead of IDE master and slave. For hard disk drivers
  that do not know IDE, such as ICD: then the same image works on the ST (ACSI) and the Falcon.
  Takes effect with a reset (issue #25).
* **Falcon: Fast RAM under Atari TOS 4.04**: `extras/FASTRAM.PRG` in the zip adds the 48 MB Fast
  RAM to TOS 4.04 (in the AUTO folder), as the driver of an accelerator card does on a real Falcon.
  EmuTOS finds the Fast RAM by itself (issue #29).
* **Falcon: a ready IDE hard disk image**: `extras/falcon128.img`, 128 MB with four empty FAT16
  partitions (C: to F:). EmuTOS mounts it without a driver; TOS 4.04 needs an IDE driver such as
  HDDRIVER. `tools/make_falcon_hd.py` makes other sizes (issue #25).
* README: what the 32 MHz turbo speeds up (programs with the 68030's caches on) and why tools still
  show 16 MHz (issue #28).
* The settings files are unchanged: `fccfg` and `fcmount` of 1.1.6 still work.

Version 1.1.6 - October 25, 2026
================================

* **Atari Falcon030 (test, R6 only)**: choose "Machine: Falcon030" in the menu. 68030 (16 or
  32 MHz), 68882 FPU, VIDEL, DSP56001, DMA sound, 14 MB ST-RAM and 48 MB Fast RAM, IDE hard disks,
  enhanced joystick ports, NVRAM saved on the SD card (`/atarist/fcnvram`). Engineered for
  MegaST (SDRAM controller, FPU on a RISC-V in the FPGA, MEGA65 integration, menu, machine
  switching, TOS handling, fixes); CPU and chipset from the open-source Falcon_MiSTer and AP68030
  projects. It runs EmuTOS (`tosfalc.img`, in the zip) and
  Atari's TOS 4.04, Falcon demos and programs, and boots FreeMiNT from a hard disk image (its
  XaAES/NVDI desktop does not start yet with the tested image). See the README.
* **Each machine has its own TOS**: at power on and after a switch the core loads `tos.img` for the
  ST and `tosfalc.img` for the Falcon. A TOS chosen with "TOS:" is remembered per machine. A TOS
  the machine cannot run (a 512 KB TOS on the ST, an ST TOS on the Falcon) is refused with a
  message.
* **Switching the machine closes the menu** and starts the new machine with its TOS. Before,
  switching with a TOS chosen by hand could stop the core ("menu.asm: OPTM_RUN is not running").
* **The menu is split per machine**: "ST/STe settings" (memory, blitter, mono monitor, borders,
  Viking, stereo YM), "Falcon030 settings" and "Drives & images" (floppy options, remembering the
  images). "Reset Atari ST" is now "Reset".
* **New settings files: copy `atarist/fccfg` (119 bytes) and `atarist/fcmount` (1792 bytes) from
  the zip.** The menu is larger, so the settings and remembered images are kept in these files;
  without `fccfg` the settings are not saved. `stcfg` and `stmount` are no longer read, but stay on
  the card, so going back to 1.1.5 keeps its settings.

Version 1.1.5 - October 24, 2026
================================

* **The Viking 1280x1024 card works** (with the MiST driver `mist_vhi.prg` in the AUTO folder, see
  the README). Before, its picture was scrambled: the 2:1 downscaler never reset its pixel counter
  at the start of a line.
* **Sharp Viking picture on HDMI**: while the Viking desktop is on screen, HDMI switches to
  1280x1024 @ 60 Hz and shows every pixel of the card 1:1, without scaling. When the card is
  switched off, HDMI goes back to the mode chosen in the menu. 1280x1024 is a PC monitor mode;
  many TVs do not show it. VGA shows the picture downscaled to 640x512 in grey, as before.
* **Switching the Viking card on or off in the menu resets the ST.** Without the reset, the driver
  went on drawing into the card's memory after switching off and the ST crashed.
* The menu item "Viking" is respected on every machine: the STEroids mode no longer switches the
  card on by itself.
* The HDMI scaler no longer has the bilinear and bicubic filters, which MegaST never used (needed
  for the timing of the 1280x1024 mode).

The settings file stays the same: the 104 byte `/atarist/stcfg` of 1.1 is still valid.

Version 1.1.4 - October 22, 2026
================================

* **Bombs after a reset** (tester report: about 5 out of 10 resets, mostly STEroids, only a power
  cycle helped): a reset could hit the ST while it was reading TOS. During a reset the memory
  controller saw a write request, and the TOS read in progress became a write: one word of the
  TOS in memory was overwritten (TOS 2.06 reported "BAD ROM CRC", then bombs). The TOS stayed
  damaged until it was loaded again at power on. TOS reads can no longer write. Reproduced and
  fixed in simulation (TOS 2.06, STEroids, reset during the memory test).
* **A cartridge could not be removed** (tester report): Space on the "Cartridge:" line now removes
  the cartridge, and the ST restarts without it.
* **"config.vhd: No selected menu group item" when opening the menu**: a settings file that does not
  match the menu (written by another build, or damaged) stopped the core. Now a setting without a
  valid choice in the file goes back to its default, and all other settings are kept.
* **Coloured stripes behind the welcome screen** (tester report): the ST is held in reset until the
  welcome screen is closed, and sends no picture then. The HDMI scaler kept showing its memory,
  which holds random data after power on. While the ST sends no picture, the core now sends a
  black one, so the welcome screen is shown on black (also on VGA).
* The menu firmware wrote to a random memory address at start (framework bug); fixed.

The settings file stays the same: the 104 byte `/atarist/stcfg` of 1.1 is still valid.

Version 1.1.3 - October 21, 2026
================================

* **The monochrome mode flickered on HDMI at 720p** (tester report and videos): small columns of the
  desktop pattern flickered at 720p 50 and 60 Hz, while 576p was stable. The scaler that converts
  the ST picture to the HDMI resolution keeps its frame buffer in the HyperRAM, and with 24 bits
  per pixel the HyperRAM could not deliver the lines in time. The frame buffer now uses 16 bits
  per pixel (the ST has at most 4096 colours, so nothing is lost) and three buffers, so the
  scaler never reads a frame that is half old and half new. Confirmed fixed by the tester.
* **STEroids: the picture was cut off on the left** (tester report): in the monochrome mode the
  first pixels of every line were missing (half of the first letter). In the STEroids mode, and
  in the Mega STe mode with the cache on, the video data comes out a few pixels earlier; the
  colour modes were shifted too. The picture is now in its place, in simulation exactly as in
  the STe mode.

The settings file stays the same: the 104 byte `/atarist/stcfg` of 1.1 is still valid.

Version 1.1.2 - October 19, 2026
================================

* **Reset took 5 to 10 seconds longer with "Real floppy drive as A:"** (tester report). Drive B:
  is not connected while the real drive is on. At every reset TOS checks whether drive B: is
  there (TOS 2.06: 7 commands that move the head to track 0). On a drive that is not there, the
  floppy controller steps for up to 1.5 seconds per command looking for track 0, and TOS waited
  for each one until its timeout. The controller now answers these commands for drive B: at
  once, with the result of a missing drive. TOS still sees no drive B: (as before), just without
  the wait. With an empty drive A: TOS still waits a moment for drive A:, as on a real ST.
* Tested on an R6 and in simulation (TOS 1.04, TOS 2.06 and EmuTOS boot from the real drive and
  find no drive B:).

The settings file stays the same: the 104 byte `/atarist/stcfg` of 1.1 is still valid.

Version 1.1.1 - October 18, 2026
================================

* **EmuTOS found no floppy drive with "Real floppy drive as A:" (issue #24):** the desktop showed
  no drive icons. EmuTOS checks at start-up whether a drive is connected: it stops the floppy
  controller ("force interrupt") and moves the head to track 0. The controller (WF1772IP) had a
  bug: a "force interrupt" while it was idle restarted its previous command, which then waited
  for the disk to spin up, and it ignored the next command. So EmuTOS saw no drive. Atari TOS
  showed the icons anyway, because its desktop always shows A: and B:. Fixed in the controller.
  Drive B: stays absent while the real drive is on (as before).
* Tested on an R6 (EmuTOS 1.4 shows DISK A on the desktop) and in simulation (TOS 2.06 boots as
  before).

The settings file stays the same: the 104 byte `/atarist/stcfg` of 1.1 is still valid.

Version 1.1 - October 16, 2026
==============================

* **The MEGA65's internal floppy drive as the ST's drive A: (issue #15).** "Real floppy drive
  as A:" in "System settings" (off by default), then "Reset Atari ST". The core has a complete
  WD1772 floppy controller (WF1772IP by Wolfgang Förster), so original ST disks are read as on a
  real ST, including copy protections and formats with 10 sectors and 82 tracks. Drive B: and the
  floppy images are not used while it is on. **Read only:** the core never writes to the disk.
  DD disks only.
* **"Floppy read assist"** in "System settings" (on by default): the MEGA65 drive's speed varies
  by up to 8 % within each turn of the disk, and the WD1772's data separator then misreads a
  sector now and then; some loaders keep the wrong bytes and hang. A data separator in front of
  the controller re-times the drive's pulses, and a sector read that fails its checksum is
  repeated (up to 15 more turns) before the ST gets the data.
* Tested on an R6 with an original-format Jim Power disk (82 tracks, 10 sectors): boots and loads
  the game with no read errors. A weak spot on an older copy needed up to 26 turns: a disk that
  reads in a PC drive can still be marginal.

**The menu has two new lines:** copy the new 104 byte `/atarist/stcfg` from the zip to the SD
card. The 102 byte file of 1.0 is reported as corrupt and the settings are not saved. The 1536
byte `/atarist/stmount` stays valid.

Known limitations: the real floppy drive is read only and DD only, and it is not tested on the
R3/R3A, R4 and R5 yet; the right button of an Atari mouse is a short click only (issue #17); a
tester saw some programs crash with 8 MB of ST RAM on an STe (4 MB works); the R4 and R5 builds
are not tested on hardware yet.

Version 1.0 - October 12, 2026
==============================

The first stable version. Since the first beta (0.4.6) the floppy and hard disk images, the
keyboard, the mice, the joysticks and the settings have been tested by the developer and by
testers on R6 and R3A boards. New in 1.0:

* **HDMI picture centred:** in 576p (4:3 and 5:4), 720x480 and 640x480 the right side of the
  picture was cut off and the picture looked shifted to the right, because the ST line (744
  pixels, 840 with full borders) is wider than the 4:3 area of these modes and the scaler could
  only cut it. The scaler now shrinks the line to fit, so both borders are equal.
* **"Remember floppies" and "Remember TOS/cartridge"** in "System settings" (both on by default):
  switch one off to start without the last floppies or without the last TOS/cartridge (then
  `tos.img` is used). Hard disks are always remembered.
* **MEGA + F1..F9 gives Shift+F1..F10** (F11..F20 in GFA-Basic and STOS, issue #18):
  MEGA + F1/F3/F5/F7/F9 for Shift+F1/F3/F5/F7/F9, MEGA + Shift + F1..F9 for Shift+F2..F10.
* **Right button of the Atari mouse (issue #17):** after a right click GEM saw the button held
  for 10 seconds and ignored left clicks meanwhile. Measured on an R6: the Atari mouse only grounds
  pin 9, and without the ST's pull-up the line takes 10-13 seconds to float back up after a release.
  With Mouse type = Atari a right click now counts as a short click (200 ms). Right-click menus work;
  holding the right button does not, and a second right click only counts about 10 seconds later.

**The menu has three new lines:** copy the new 102 byte `/atarist/stcfg` from the zip to the SD
card. The old 99 byte file is reported as corrupt and the settings are not saved. The 1536 byte
`/atarist/stmount` of 0.4.12 to 0.4.14 stays valid.

A mouSTer (firmware 3.23.5313 or newer) works with the right button in Amiga mode with
`activepotlines=true` or in 1351 mode (tester report, issue #17); the README has the INI settings.

Known limitations: the right button of an Atari mouse is a short click only and works about once
every 10 seconds (pin 9 has no pull-up on the MEGA65, issue #17); a tester saw some programs crash
with 8 MB of ST RAM on an STe (4 MB works); the R4 and R5 builds are not tested on hardware yet.

Version 0.4.14 beta - October 10, 2026
======================================

* **Hard disk images restored at power-on were not seen by TOS (issues #11, #12).** Since 0.4.12
  the core brings back the remembered images at power-on and after a long press of the reset
  button, but it ejected them again at once inside the core, while the menu still listed them.
  The eject at a restart of the firmware (0.4.10, issue #10) reacted to the firmware holding the ST
  in reset, which it does exactly while it restores the images. "Reset Atari ST" in the menu
  ejected the images, too. Images mounted in the menu while the ST was running were not affected.
* **Right mouse button stuck with a mouSTer (issue #17):** pin 9 of the mouse port has no pull-up
  on the MEGA65, so a mouSTer that leaves it open (or a joystick in the mouse port) looked like a
  held right button, and GEM ignored left clicks on window controls. The core now ignores the
  right button until it has seen pin 9 released. An Atari or Amiga mouse is not affected; a
  mouSTer in Atari mode has no right button.

The menu is unchanged: the 99 byte `/atarist/stcfg` of 0.4.8 to 0.4.13 stays valid, and so does the
1536 byte `/atarist/stmount` of 0.4.12.

Version 0.4.13 beta - October 9, 2026
=====================================

* **Function keys (issue #16):** F6, F8 and F10 (Shift+F5/F7/F9 on the MEGA65) sometimes arrived as
  Shift+F6/F8/F10, so programs like GFA Basic reacted wrongly. The core hid Shift in the same moment
  in which the F key appeared, and the ST's keyboard processor sometimes still saw Shift. The F key
  now follows 20 ms after Shift is hidden.
* **Right mouse button (issue #17):** the right button of an Atari mouse (or a mouSTer adapter) on
  the mouse port did nothing. It now works like the right button of the Amiga mouse (pin 9).
* More timing margin for the HyperRAM clock on all boards (the R4/R5 builds of 0.4.12 only met
  timing after extra implementation runs).
* README: how to unmount (eject) a drive: select its line in the menu and press Space.

Known problem under investigation: some users report that a hard disk image is mounted but not
seen by TOS with 0.4.12 (issues #11, #12). This version contains the same firmware.

The menu is unchanged: the 99 byte `/atarist/stcfg` of 0.4.8 to 0.4.12 stays valid, and so does the
1536 byte `/atarist/stmount` of 0.4.12.

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
