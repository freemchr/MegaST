| Starts C:\MARS_DSP.PRG (EKO Mars DSP) so that memory is left for EmuTOS's Dsp_LoadProg: the demo
| takes the whole TPA (no Mshrink) and EmuTOS needs a Malloc block for the .LOD file. This program
| shrinks itself, splits the free memory into two blocks (a 256 KB hole, a 16 byte block that stays,
| then the rest) and runs the
| demo, which gets the larger block; the hole serves the Malloc.
|    ./run_prg.sh /tmp/mars tests/dspwrap.s ~/falcon_sw/nf4/tree/DEMOS/EKO/MARSDSP/MARSDSP.95 -- --monitor 1
| MEGA65 port done by Chris Freeman in 2026, licensed under GPL v3
	.text
	move.l	4(sp),a0		| basepage
	lea	stack(pc),sp
	lea	endp(pc),a1
	sub.l	a0,a1
	move.l	a1,-(sp)
	move.l	a0,-(sp)
	clr.w	-(sp)
	move.w	#0x4A,-(sp)		| Mshrink
	trap	#1
	lea	12(sp),sp
	move.l	#0x40000,-(sp)
	move.w	#0x48,-(sp)		| Malloc(256 KB): the hole
	trap	#1
	addq.l	#6,sp
	move.l	d0,d7
	move.l	#16,-(sp)
	move.w	#0x48,-(sp)		| Malloc(16): stays, so the hole and the rest do not merge
	trap	#1
	addq.l	#6,sp
	move.l	d7,-(sp)
	move.w	#0x49,-(sp)		| Mfree(the hole)
	trap	#1
	addq.l	#6,sp
	clr.l	-(sp)			| environment
	pea	cmd(pc)
	pea	name(pc)
	clr.w	-(sp)
	move.w	#0x4B,-(sp)		| Pexec(0)
	trap	#1
	lea	16(sp),sp
	clr.w	-(sp)
	trap	#1
name:	.asciz	"C:\\MARS_DSP.PRG"
cmd:	.byte	0, 0
	.even
	.space	2048
stack:
endp:
