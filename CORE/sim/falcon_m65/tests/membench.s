| Memory speed: the 200 Hz ticks for 4 passes over a 256 KB block (move.l (a0)+,d1 / add.l d1,d0,
| unrolled 16 times; more than the 68030's caches) in ST-RAM ($100000 = ticks, $100004 = checksum)
| and, if there is TT-RAM (Mxalloc mode 1), in Fast RAM ($100008 = ticks, $10000C = checksum,
| $100010 = the block's address). Then the done marker $D0E0600D at $FFFF0.
|    ./run_prg.sh /tmp/mb tests/membench.s -- --ms 9000 --start FFFF4 --done FFFF0 --dump 100000:14 --fastram 3
| MEGA65 port done by Chris Freeman in 2026, licensed under GPL v3
	.text
	move.l	#0x57A27000,0xFFFF4	| start marker (sim_main --start FFFF4)
	clr.l	-(sp)
	move.w	#0x20,-(sp)
	trap	#1			| Super (for _hz_200)
	addq.l	#6,sp
	move.l	#0x100000,a5
	clr.l	8(a5)
	clr.l	12(a5)
	lea	0x200000,a4		| ST-RAM block (free TPA above the program)
	bsr.s	bench
	move.l	d7,(a5)
	move.l	d0,4(a5)
	move.w	#1,-(sp)
	move.l	#0x40000,-(sp)
	move.w	#0x44,-(sp)		| Mxalloc(256 KB, TT-RAM only)
	trap	#1
	addq.l	#8,sp
	move.l	d0,16(a5)
	tst.l	d0
	beq.s	fin
	move.l	d0,a4
	bsr.s	bench
	move.l	d7,8(a5)
	move.l	d0,12(a5)
fin:	move.l	#0xD0E0600D,0xFFFF0
	clr.w	-(sp)
	trap	#1

| a4 = block; out: d7 = ticks, d0 = sum
bench:	moveq	#0,d0
	moveq	#3,d6			| 4 passes
	move.l	0x4ba.w,d5
pass:	move.l	a4,a0
	move.w	#0x40000/64-1,d2
blk:
	.rept	16
	move.l	(a0)+,d1
	add.l	d1,d0
	.endr
	dbra	d2,blk
	dbra	d6,pass
	move.l	0x4ba.w,d7
	sub.l	d5,d7
	rts
