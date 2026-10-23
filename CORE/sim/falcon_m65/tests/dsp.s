| DSP host port test: reset the DSP (PSG port A bit 4), bootstrap an echo program
|    P:0 jclr #0,x:$FFE9,0 / move x:$FFEB,x0 / jclr #1,x:$FFE9,4 / move x0,x:$FFEB / jmp 0
| and send 256 words with handshake (TXDE before each write, RXDF before each read). Results:
| $100000 = words that came back wrong, $100004 = the first wrong word, $100008 = timeouts
| (no RXDF within about 1 s), $10000C = the number of words done. Then the done marker at $FFFF0.
|    ./run_prg.sh /tmp/dsp tests/dsp.s -- --ms 6000 --start FFFF4 --done FFFF0 --dump 100000:10 --pc 100
| MEGA65 port done by Chris Freeman in 2026, licensed under GPL v3
	.text
	move.l	#0x57A27000,0xFFFF4	| start marker (sim_main --start FFFF4)
	clr.l	-(sp)
	move.w	#0x20,-(sp)
	trap	#1			| Super
	addq.l	#6,sp
	move.w	#0x2700,sr
	move.l	#0x100000,a5
	clr.l	(a5)
	clr.l	4(a5)
	clr.l	8(a5)
	clr.l	12(a5)
	lea	0xFFFF8800,a0		| PSG
	lea	0xFFFFA200,a1		| DSP host interface
	move.b	#14,(a0)		| port A
	move.b	(a0),d0
	bset	#4,d0
	move.b	d0,2(a0)		| DSP reset
	move.w	#2000,d1
dly:	dbra	d1,dly
	bclr	#4,d0
	move.b	d0,2(a0)		| bootstrap starts
	lea	prog(pc),a2
	lea	progend(pc),a3
	move.w	#512-1,d1
boot:	btst	#1,2(a1)		| TXDE
	beq.s	boot
	move.l	(a2)+,4(a1)		| TXH/TXM/TXL (the long's high byte is unused)
	cmpa.l	a3,a2			| the program first, then zeros
	blo.s	bnext
	lea	zero(pc),a2
bnext:	dbra	d1,boot
	moveq	#0,d6			| word index
loop:	move.l	d6,d2
	mulu.w	#0x0101,d2
	eor.l	#0x5AA55A,d2
	and.l	#0xFFFFFF,d2
	move.l	#200000,d3
w1:	btst	#1,2(a1)		| TXDE
	bne.s	s1
	subq.l	#1,d3
	bne.s	w1
	addq.l	#1,8(a5)
	bra.s	fin
s1:	move.l	d2,4(a1)
	move.l	#200000,d3
w2:	btst	#0,2(a1)		| RXDF
	bne.s	r1
	subq.l	#1,d3
	bne.s	w2
	addq.l	#1,8(a5)
	bra.s	fin
r1:	move.l	4(a1),d4
	and.l	#0xFFFFFF,d4
	cmp.l	d2,d4
	beq.s	ok
	tst.l	(a5)
	bne.s	not1
	move.l	d4,4(a5)
not1:	addq.l	#1,(a5)
ok:	addq.l	#1,d6
	move.l	d6,12(a5)
	cmp.w	#256,d6
	blo.s	loop
fin:	move.w	#0x2300,sr
	move.l	#0xD0E0600D,0xFFFF0
	clr.w	-(sp)
	trap	#1
	.even
prog:	.long	0x0AA980, 0x000000, 0x44F000, 0x00FFEB, 0x0AA981, 0x000004, 0x447000, 0x00FFEB, 0x0C0000
progend:
zero:	.long	0
