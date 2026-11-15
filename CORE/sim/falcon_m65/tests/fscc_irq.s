| FScc (An)+ while the FPU is busy and interrupts arrive: the condition CIR answers come-again
| with IA, the 68030 takes the interrupt with a mid-instruction frame and resumes the dialogue
| after the RTE. MFP Timer A interrupts about every 33 us; N times FSIN (busy for tens of us)
| then FSNE (A1)+. Results as longs at $100000: bytes A1 moved (expect N), Timer A interrupts,
| A1 moved by FSNE -(A1) (expect -N), then the same with FMOVE FP1,FP0 before the FScc.
| Done marker $D0E0600D at $FFFF0.
|    ./run_prg.sh /tmp/fs tests/fscc_irq.s -- --ms 3000 --done FFFF0 --dump 100000:32 --start FFFF4
| MEGA65 port done by Chris Freeman in 2026, licensed under GPL v3
	.equ	N, 300			| interrupt counter at $1000F0 (no relocations)
	.text
	move.l	#0x57A27000,0xFFFF4	| start marker (sim_main --start FFFF4)
	clr.l	-(sp)
	move.w	#0x20,-(sp)
	trap	#1			| Super(0)
	addq.l	#6,sp
	move.l	#0x100000,a5
	clr.l	0x1000F0
	fmove.l	#0,fpcr
	fmove.l	#3,fp1

	move.w	#0x2700,sr
	lea	timer_a(pc),a0
	move.l	a0,0x134.w		| MFP Timer A vector
	clr.b	0xFFFFFA19.w		| TACR: stop
	move.b	#20,0xFFFFFA1F.w	| TADR
	move.b	#1,0xFFFFFA19.w		| delay mode, /4: 2.4576 MHz / 4 / 20 = 30.7 kHz
	bset	#5,0xFFFFFA07.w		| IERA
	bset	#5,0xFFFFFA13.w		| IMRA
	move.w	#0x2300,sr

	lea	0x101000,a1		| (A1)+ with FSIN
	move.l	a1,a3
	move.w	#N-1,d7
1:	fsin.x	fp1,fp0
	.word	0xF259,0x000E		| FSNE (A1)+
	dbra	d7,1b
	sub.l	a3,a1
	move.l	a1,(a5)+
	move.l	0x1000F0,(a5)+

	lea	0x103000,a1		| -(A1) with FSIN
	move.l	a1,a3
	move.w	#N-1,d7
2:	fsin.x	fp1,fp0
	.word	0xF261,0x000E		| FSNE -(A1)
	dbra	d7,2b
	sub.l	a3,a1
	move.l	a1,(a5)+
	move.l	0x1000F0,(a5)+

	lea	0x104000,a1		| (A1)+ with FMOVE
	move.l	a1,a3
	move.w	#N*4-1,d7
3:	fmove.x	fp1,fp0
	.word	0xF259,0x000E		| FSNE (A1)+
	dbra	d7,3b
	sub.l	a3,a1
	move.l	a1,(a5)+
	move.l	0x1000F0,(a5)+

	move.w	#0x2700,sr
	bclr	#5,0xFFFFFA07.w
	bclr	#5,0xFFFFFA13.w
	clr.b	0xFFFFFA19.w
	move.w	#0x2300,sr
	move.l	#0xD0E0600D,0xFFFF0
	clr.w	-(sp)
	trap	#1

timer_a:
	addq.l	#1,0x1000F0
	move.b	#0xDF,0xFFFFFA0F.w	| ISRA: end of interrupt (software EOI)
	rte

