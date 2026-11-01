| 640x480 in 4 colours on VGA (Falcon VsetMode $19: VGA | COL80 | BPS2), issue #26. Draws four
| vertical bars (colours 0..3, 160 pixels each) over all 480 lines, then waits.
|    python3 simrom.py tosfalc.img /tmp/tosfalc_sim.img     (EmuTOS boots in time)
|    TOS=/tmp/tosfalc_sim.img SIM=obj_fm/Vtb_top ./run_prg.sh /tmp/vga4c tests/vga4c.s -- --ms 3500 --frame-every 25
| Result (1.3): the four bars are correct; the active line is 672 pixels (640 and a border).
| MEGA65 port done by Chris Freeman in 2026, licensed under GPL v3
	.text
	move.w	#0x19,-(sp)		| VGA | COL80 | BPS2: 640x480, 4 colours
	move.w	#88,-(sp)
	trap	#14			| VsetMode
	addq.l	#4,sp
	move.w	#2,-(sp)
	trap	#14			| Physbase
	addq.l	#2,sp
	move.l	d0,a0
	move.w	#479,d1			| 480 lines
line:	moveq	#3,d2			| 4 bars
	lea	pat(pc),a1
bar:	move.l	(a1)+,d3		| plane 0 and plane 1 word of this colour
	moveq	#9,d4			| 10 x 16 pixels = 160 pixels
grp:	move.l	d3,(a0)+
	dbra	d4,grp
	dbra	d2,bar
	dbra	d1,line
	move.l	#0x57A27000,0xFFFF4	| start marker
wait:	bra.s	wait
pat:	.long	0x00000000, 0xFFFF0000, 0x0000FFFF, 0xFFFFFFFF
