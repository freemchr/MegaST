| Starts C:\DEMO.PRG in 320x240 true colour on VGA (Falcon VsetMode $114), as a user would
| set the mode on the desktop first (needed by the DHS 128-byte demos). For screenshots:
|    ./run_prg.sh /tmp/krawl tests/tcdemo.s DIR -- --ms 8000 --frame-every 25
| with DIR holding DEMO.PRG.
| MEGA65 port done by Chris Freeman in 2026, licensed under GPL v3
	.text
	move.l	4(sp),a0		| basepage
	move.l	#0x1000,-(sp)
	move.l	a0,-(sp)
	clr.w	-(sp)
	move.w	#0x4a,-(sp)
	trap	#1			| Mshrink: leave the TPA to the demo
	lea	12(sp),sp
	move.w	#0x114,-(sp)		| VERTFLAG | VGA | BPS16: 320x240 true colour
	move.w	#88,-(sp)
	trap	#14			| VsetMode
	addq.l	#4,sp
	clr.l	-(sp)			| environment
	pea	cmd(pc)
	pea	name(pc)
	clr.w	-(sp)			| load and go
	move.w	#0x4b,-(sp)
	trap	#1			| Pexec
	lea	16(sp),sp
	clr.w	-(sp)
	trap	#1			| Pterm0
name:	.asciz	"C:\\DEMO.PRG"
cmd:	.byte	0,0
	.even
