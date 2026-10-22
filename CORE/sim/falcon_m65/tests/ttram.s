| TT-RAM (Fast RAM) test: $100000 = Mxalloc(-1, 1) (largest free TT-RAM block), $100004 = the
| address of a 1 MB TT-RAM block (Mxalloc(1 MB, 1): TT-RAM only), $100008 = the number of longs
| that did not read back after writing address-dependent patterns (two passes), $10000C = _p_cookies
| ($5A0), $100010 = ramtop ($5A4). Then the done marker $D0E0600D at $FFFF0.
|    ./run_prg.sh /tmp/tt tests/ttram.s -- --ms 6000 --done FFFF0 --dump 100000:20 --fastram
| MEGA65 port done by Chris Freeman in 2026, licensed under GPL v3
	.text
	move.l	#0x100000,a5
	move.w	#1,-(sp)		| mode 1: TT-RAM only
	move.l	#-1,-(sp)
	move.w	#0x44,-(sp)		| Mxalloc
	trap	#1
	addq.l	#8,sp
	move.l	d0,(a5)
	move.w	#1,-(sp)
	move.l	#0x100000,-(sp)
	move.w	#0x44,-(sp)
	trap	#1
	addq.l	#8,sp
	move.l	d0,4(a5)
	moveq	#0,d7			| errors
	tst.l	d0
	beq.s	fin
	move.l	d0,a0
	move.l	#0x40000-1,d1		| 256 K longs
	move.l	a0,a1
wr1:	move.l	a1,d2
	eor.l	#0x5A5AA5A5,d2
	move.l	d2,(a1)+
	subq.l	#1,d1
	bpl.s	wr1
	move.l	#0x40000-1,d1
	move.l	a0,a1
rd1:	move.l	a1,d2
	eor.l	#0x5A5AA5A5,d2
	cmp.l	(a1)+,d2
	beq.s	ok1
	addq.l	#1,d7
ok1:	subq.l	#1,d1
	bpl.s	rd1
	move.l	#0x40000-1,d1		| second pass: inverted
	move.l	a0,a1
wr2:	move.l	a1,d2
	not.l	d2
	move.l	d2,(a1)+
	subq.l	#1,d1
	bpl.s	wr2
	move.l	#0x40000-1,d1
	move.l	a0,a1
rd2:	move.l	a1,d2
	not.l	d2
	cmp.l	(a1)+,d2
	beq.s	ok2
	addq.l	#1,d7
ok2:	subq.l	#1,d1
	bpl.s	rd2
fin:	move.l	d7,8(a5)
	clr.l	-(sp)
	move.w	#0x20,-(sp)
	trap	#1			| Super
	addq.l	#6,sp
	move.l	0x5a0.w,12(a5)
	move.l	0x5a4.w,16(a5)
	move.l	#0xD0E0600D,0xFFFF0
	clr.w	-(sp)
	trap	#1
