| CPU speed: $100000 = how many times a loop of 1000 dbra ran in 40 ticks of the 200 Hz timer (_hz_200, 200 ms),
| measured once from the cache and once with the caches off; $100004 = the first count, $100008 the second,
| $10000C = $FF8007 (bus control, bit 0: 16 MHz), $100010 = CACR. Done marker $D0E0600D at $FFFF0.
|    ./run_prg.sh /tmp/sp tests/cpuspeed.s -- --ms 4000 --done FFFF0 --dump 100000:14 --start FFFF4 [--turbo]
| MEGA65 port done by Chris Freeman in 2026, licensed under GPL v3
	.text
	move.l	#0x57A27000,0xFFFF4	| start marker (sim_main --start FFFF4)
	clr.l	-(sp)
	move.w	#0x20,-(sp)
	trap	#1			| Super(0)
	addq.l	#6,sp
	move.l	#0x100000,a5
	bsr.s	measure
	move.l	d7,4(a5)
	movec	cacr,d0
	move.l	d0,16(a5)
	moveq	#0,d1
	movec	d1,cacr			| caches off
	bsr.s	measure
	move.l	d7,8(a5)
	movec	d0,cacr
	move.l	4(a5),(a5)
	moveq	#0,d0
	move.b	0xFFFF8007.w,d0
	move.l	d0,12(a5)
	move.l	#0xD0E0600D,0xFFFF0
	clr.w	-(sp)
	trap	#1

measure:
	move.l	0x4BA.w,d1
w0:	cmp.l	0x4BA.w,d1		| start on a tick
	beq.s	w0
	move.l	0x4BA.w,d2
	add.l	#40,d2
	moveq	#0,d7
outer:	move.w	#999,d0
inner:	dbra	d0,inner
	addq.l	#1,d7
	cmp.l	0x4BA.w,d2
	bhi.s	outer
	rts
