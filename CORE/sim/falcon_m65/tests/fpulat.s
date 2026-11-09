| FPU latency as the 68030 sees it (bridge + mailbox + RISC-V service): 200 Hz ticks for N
| instructions each, stored as longs at $100000: FNOP, FMOVE FP1,FP0, FADD, FMUL, FDIV, FSQRT,
| FMOVE.D mem,FP0, FMOVE.D FP0,mem (N = 2000 each), FSIN (N = 500). Done marker $D0E0600D at $FFFF0.
| us per instruction = ticks * 5000 / N.
|    ./run_prg.sh /tmp/fl tests/fpulat.s -- --ms 6000 --done FFFF0 --dump 100000:24 --start FFFF4 [--turbo]
| MEGA65 port done by Chris Freeman in 2026, licensed under GPL v3
	.text
	move.l	#0x57A27000,0xFFFF4	| start marker (sim_main --start FFFF4)
	clr.l	-(sp)
	move.w	#0x20,-(sp)
	trap	#1			| Super(0)
	addq.l	#6,sp
	move.l	#0x100000,a5
	lea	0x100100,a4		| scratch for the memory operands
	move.l	#0x400921FB,(a4)	| pi as a double
	move.l	#0x54442D18,4(a4)
	fmove.l	#0,fpcr
	fmove.l	#3,fp1
	fmove.l	#7,fp0

	lea	l_nop(pc),a0
	bsr	run2000
	lea	l_mov(pc),a0
	bsr	run2000
	lea	l_add(pc),a0
	bsr	run2000
	lea	l_mul(pc),a0
	bsr	run2000
	lea	l_div(pc),a0
	bsr	run2000
	lea	l_sqrt(pc),a0
	bsr	run2000
	lea	l_ldd(pc),a0
	bsr	run2000
	lea	l_std(pc),a0
	bsr	run2000
	lea	l_sin(pc),a0
	move.w	#49,d7			| 50 x 10
	bsr	timed
	move.l	#0xD0E0600D,0xFFFF0
	clr.w	-(sp)
	trap	#1

run2000:
	move.w	#199,d7			| 200 x 10
timed:	move.l	0x4BA.w,d6
1:	cmp.l	0x4BA.w,d6		| start on a tick edge
	beq.s	1b
	move.l	0x4BA.w,d6
	jsr	(a0)
	move.l	0x4BA.w,d0
	sub.l	d6,d0
	move.l	d0,(a5)+
	rts

l_nop:	.rept	10
	fnop
	.endr
	dbra	d7,l_nop
	rts
l_mov:	.rept	10
	fmove.x	fp1,fp0
	.endr
	dbra	d7,l_mov
	rts
l_add:	.rept	10
	fadd.x	fp1,fp0
	.endr
	dbra	d7,l_add
	rts
l_mul:	.rept	10
	fmul.x	fp1,fp0
	.endr
	dbra	d7,l_mul
	rts
l_div:	.rept	10
	fdiv.x	fp1,fp0
	.endr
	dbra	d7,l_div
	rts
l_sqrt:	.rept	10
	fsqrt.x	fp1,fp0
	.endr
	dbra	d7,l_sqrt
	rts
l_ldd:	.rept	10
	fmove.d	(a4),fp0
	.endr
	dbra	d7,l_ldd
	rts
l_std:	.rept	10
	fmove.d	fp0,8(a4)
	.endr
	dbra	d7,l_std
	rts
l_sin:	.rept	10
	fsin.x	fp1,fp0
	.endr
	dbra	d7,l_sin
	rts
