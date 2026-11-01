| FASTRAM.PRG: tells Atari TOS 4.0x about the Fast RAM (TT-RAM) of the MegaST Falcon030.
| TOS 4.0x does not look for TT-RAM on a Falcon (on real hardware the driver of an accelerator
| card adds it), EmuTOS finds it by itself. Put the program into \AUTO of the boot disk. It
|  - finds the Fast RAM at $01000000 (16, 32 or 48 MB, menu "Fast RAM"): the core answers a bus
|    error above it; without Fast RAM the bus has 24 bits and $01000000 is a mirror of address 0,
|  - adds it to GEMDOS (Maddalt), sets ramtop ($5A4) and ramvalid ($5A8),
|  - puts the _FRB cookie (a 64 KB ST-RAM buffer for DMA into Fast RAM) into the cookie jar,
|  - hooks GEMDOS (XBRA 'MSFR') and clears the TT-RAM bits (1, 2) of Pexec mode 7 called from
|    the ROM: TOS 4.04 makes the process of the AES and desktop that way (flags 7, $E1F44E, again
|    after each resolution change), and a desktop in Fast RAM draws all its icons scrambled
|    (issues #28, #29). Programs are started with other modes and keep their flags,
|  - stays resident for the hook and the buffer.
| After its message it waits 3 seconds (a key ends the wait), so the message can be read.
| It does nothing when TOS already knows Fast RAM (ramvalid set and ramtop above $01000000).
| Position independent, no relocation table (tools/fastram/build.sh).
| MEGA65 port done by Chris Freeman in 2026, licensed under GPL v3
	.text
	move.l	4(sp),a3		| basepage
	pea	probe(pc)
	move.w	#38,-(sp)
	trap	#14			| Supexec(probe): fsize = Fast RAM size, -1: already known
	addq.l	#6,sp
	move.l	fsize(pc),d6
	lea	m_known(pc),a0
	bmi	quit
	lea	m_none(pc),a0
	beq	quit
	move.l	d6,-(sp)
	move.l	#0x01000000,-(sp)
	move.w	#0x14,-(sp)
	trap	#1			| Maddalt($01000000, size)
	lea	10(sp),sp
	lea	m_fail(pc),a0
	tst.l	d0
	bmi	quit
	pea	setvars(pc)
	move.w	#38,-(sp)
	trap	#14			| Supexec(setvars): frbset = 1 with the _FRB cookie, the hook
	addq.l	#6,sp
	lea	m_ok(pc),a0
	move.l	d6,d0
	moveq	#20,d1
	lsr.l	d1,d0			| MB
	divu	#10,d0
	add.b	#'0',d0
	move.b	d0,m_mb-m_ok(a0)
	swap	d0
	add.b	#'0',d0
	move.b	d0,m_mb+1-m_ok(a0)
	bsr	print
	lea	frbbuf(pc),a0		| keep the program (the hook)
	tst.l	frbset(pc)
	beq.s	keep
	add.l	#0x10000,a0		| and the _FRB buffer
keep:	sub.l	a3,a0
	clr.w	-(sp)
	move.l	a0,-(sp)
	move.w	#0x31,-(sp)
	trap	#1			| Ptermres

quit:	bsr	print
term:	clr.w	-(sp)
	trap	#1			| Pterm0

print:	move.l	a0,-(sp)
	move.w	#9,-(sp)
	trap	#1			| Cconws
	addq.l	#6,sp
	move.w	#180,d7			| 3 s at 60 Hz (3.6 s at 50 Hz)
pause:	move.w	#2,-(sp)
	move.w	#1,-(sp)
	trap	#13			| Bconstat(CON)
	addq.l	#4,sp
	tst.w	d0
	bne.s	pa_key
	move.w	#37,-(sp)
	trap	#14			| Vsync
	addq.l	#2,sp
	subq.w	#1,d7
	bne.s	pause
	rts
pa_key:	move.w	#2,-(sp)
	move.w	#2,-(sp)
	trap	#13			| Bconin(CON): take the key
	addq.l	#4,sp
	rts

| supervisor: fsize = the Fast RAM size (0: none), -1 when TOS knows it already
probe:	movem.l	d2-d7/a2-a6,-(sp)
	moveq	#-1,d7
	cmp.l	#0x1357BD13,0x5a8.w
	bne.s	pr_go
	cmp.l	#0x01000000,0x5a4.w
	bhi	pr_end
pr_go:	moveq	#0,d7
	movec	vbr,a5
	move.l	8(a5),a4		| the bus error vector
	lea	berr(pc),a0
	move.l	a0,8(a5)
	lea	savesp(pc),a0
	move.l	sp,(a0)
	movec	cacr,d5
	lea	mark(pc),a1
	move.l	#0x4D454741,(a1)	| 'MEGA' in ST RAM
	move.l	a1,a2
	add.l	#0x01000000,a2
	move.l	#0x46415354,(a2)	| 'FAST' at $01000000 + mark: bus error without a 32-bit bus
	move.l	d5,d0
	or.w	#0x0808,d0		| clear both caches (the mirror would be hidden in the cache)
	movec	d0,cacr
	cmp.l	#0x4D454741,(a1)
	bne	pr_done			| 24 bits: written over the mirror
	cmp.l	#0x46415354,(a2)
	bne	pr_done
	move.l	#0x01000000,d7
	move.l	#0x02000000,a2
pr_blk:	move.l	#0x46415354,(a2)	| the next 16 MB block: bus error above the Fast RAM
	cmp.l	#0x46415354,(a2)
	bne	pr_done
	add.l	#0x01000000,d7
	add.l	#0x01000000,a2
	cmp.l	#0x04000000,a2
	bne.s	pr_blk
pr_done:
	move.l	a4,8(a5)
	movec	d5,cacr
pr_end:	lea	fsize(pc),a0
	move.l	d7,(a0)
	movem.l	(sp)+,d2-d7/a2-a6
	rts
berr:	move.l	savesp(pc),sp		| drop the bus error frame
	bra.s	pr_done

| supervisor: ramtop, ramvalid and the _FRB cookie
setvars:
	movem.l	d2-d3/a2,-(sp)
	move.l	fsize(pc),d0
	add.l	#0x01000000,d0
	move.l	d0,0x5a4.w		| ramtop
	move.l	#0x1357BD13,0x5a8.w	| ramvalid
	lea	old1(pc),a0
	move.l	0x84.w,(a0)		| GEMDOS
	lea	pexhook(pc),a0
	move.l	a0,0x84.w
	move.l	0x5a0.w,d0		| _p_cookies
	beq.s	sv_end
	move.l	d0,a0
	moveq	#0,d2
sv_find:
	move.l	(a0),d0
	beq.s	sv_last
	cmp.l	#0x5F465242,d0		| '_FRB' already there
	beq.s	sv_end
	addq.l	#8,a0
	addq.l	#1,d2
	bra.s	sv_find
sv_last:
	move.l	4(a0),d3		| number of slots
	addq.l	#2,d2			| the entries, ours and the end
	cmp.l	d3,d2
	bhi.s	sv_end			| full
	move.l	#0x5F465242,(a0)
	lea	frbbuf(pc),a2
	move.l	a2,4(a0)
	clr.l	8(a0)
	move.l	d3,12(a0)
	lea	frbset(pc),a2
	move.l	#1,(a2)
sv_end:	movem.l	(sp)+,d2-d3/a2
	rts

| GEMDOS hook: Pexec mode 7 without the TT-RAM bits (load and Malloc in TT-RAM)
	.ascii	"XBRAMSFR"
old1:	.long	0
pexhook:
	move.l	a0,-(sp)
	btst	#5,4(sp)		| called from supervisor mode?
	bne.s	ph_sup
	move.l	usp,a0
	bra.s	ph_go
ph_sup:	lea	12(sp),a0		| a0, SR, PC, format word
ph_go:	cmp.l	#0x004B0007,(a0)	| Pexec mode 7
	bne.s	ph_out
	cmp.l	#0x00E00000,6(sp)	| called from the ROM? (PC at 6(sp))
	bcs.s	ph_out
	cmp.l	#0x00F00000,6(sp)
	bcc.s	ph_out
	and.l	#0xFFFFFFF9,4(a0)
ph_out:	move.l	(sp)+,a0
	move.l	old1(pc),-(sp)
	rts

m_ok:	.ascii	"MegaST: "
m_mb:	.ascii	"00 MB Fast RAM at $01000000 added\r\n\0"
m_known: .asciz	"MegaST: TOS knows the Fast RAM already\r\n"
m_none:	.asciz	"MegaST: no Fast RAM (menu: Fast RAM)\r\n"
m_fail:	.asciz	"MegaST: Maddalt failed, Fast RAM not added\r\n"
	.balign	4
fsize:	.long	0
frbset:	.long	0
savesp:	.long	0
mark:	.long	0
frbbuf:				| 64 KB, behind the program in the TPA (Ptermres keeps it)
