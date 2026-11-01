| Blitter and Fast RAM test (the blitter reaches the Fast RAM, falcon_blitter.sv): 64 KB copies
| ST -> Fast, Fast -> Fast and Fast -> ST, each crossing a 64 KB boundary, with the data cache on
| and the destination read by the CPU just before (its old contents in the caches). Then the CPU
| checks every long. $100000 = the Fast RAM block (Mxalloc(256 KB, 1)), $100004 = the ST RAM block
| (Mxalloc(192 KB, 0)), $100008/$10000C/$100010 = the longs that differ after copy 1/2/3 (0 each),
| $100014 = the source address high word read back from the blitter after copy 2 ($01: Fast RAM
| block 1). Then the done marker $D0E0600D at $FFFF0.
|    ./run_prg.sh /tmp/bf tests/blitfast.s -- --ms 8000 --done FFFF0 --dump 100000:18 --fastram 3
| MEGA65 port done by Chris Freeman in 2026, licensed under GPL v3
	.text
	move.l	4(sp),a0		| basepage: give back the TPA (all of the ST RAM)
	move.l	#0x100,d0
	add.l	12(a0),d0		| text
	add.l	20(a0),d0		| data
	add.l	28(a0),d0		| bss
	move.l	d0,-(sp)
	move.l	a0,-(sp)
	clr.w	-(sp)
	move.w	#0x4A,-(sp)		| Mshrink
	trap	#1
	lea	12(sp),sp
	move.l	#0x100000,a5
	move.w	#1,-(sp)		| TT-RAM only
	move.l	#0x40000,-(sp)
	move.w	#0x44,-(sp)		| Mxalloc
	trap	#1
	addq.l	#8,sp
	move.l	d0,(a5)
	clr.w	-(sp)			| ST-RAM only
	move.l	#0x30000,-(sp)
	move.w	#0x44,-(sp)
	trap	#1
	addq.l	#8,sp
	move.l	d0,4(a5)
	tst.l	(a5)
	beq.s	fin
	tst.l	d0
	beq.s	fin
	pea	test(pc)
	move.w	#38,-(sp)
	trap	#14			| Supexec(test)
	addq.l	#6,sp
fin:	move.l	#0xD0E0600D,0xFFFF0
	clr.w	-(sp)
	trap	#1			| Pterm0

| supervisor
test:	movem.l	d2-d7/a2-a6,-(sp)
	move.l	#0x100000,a5
	move.l	#0x2111,d0		| caches on, data cache write allocate
	movec	d0,cacr
	move.l	(a5),a3			| F
	move.l	4(a5),a4		| S
	| the source pattern in S[0, 64 KB)
	move.l	a4,a0
	move.l	#0x4000-1,d1
	move.l	#0x5A5A1234,d2
fill:	move.l	d2,(a0)+
	add.l	#0x01030507,d2
	rol.l	#3,d2
	subq.l	#1,d1
	bpl.s	fill
	| 1: ST -> Fast, F + $8000 (crosses F + $10000)
	lea	0x8000(a3),a1
	bsr	prime
	move.l	a4,a0
	bsr	blit
	move.l	a4,a0
	lea	0x8000(a3),a1
	bsr	check
	move.l	d0,8(a5)
	| 2: Fast -> Fast, F + $8000 -> F + $18000 (crosses F + $20000)
	lea	0x18000(a3),a1
	bsr	prime
	lea	0x8000(a3),a0
	bsr	blit
	move.w	0xFFFF8A24.w,d0
	move.l	d0,0x14(a5)
	move.l	a4,a0
	lea	0x18000(a3),a1
	bsr	check
	move.l	d0,12(a5)
	| 3: Fast -> ST, F + $18000 -> S + $18000 (crosses S + $20000)
	lea	0x18000(a4),a1
	bsr	prime
	lea	0x18000(a3),a0
	bsr	blit
	move.l	a4,a0
	lea	0x18000(a4),a1
	bsr	check
	move.l	d0,16(a5)
	movem.l	(sp)+,d2-d7/a2-a6
	rts

| clear 64 KB at a1 and read it back (the old contents in the caches)
prime:	move.l	a1,a0
	move.l	#0x4000-1,d1
pr_c:	clr.l	(a0)+
	subq.l	#1,d1
	bpl.s	pr_c
	move.l	a1,a0
	move.l	#0x4000-1,d1
	moveq	#0,d0
pr_r:	add.l	(a0)+,d0
	subq.l	#1,d1
	bpl.s	pr_r
	rts

| d0 = the longs of 64 KB at a1 that differ from a0
check:	moveq	#0,d0
	move.l	#0x4000-1,d1
ch_l:	cmpm.l	(a0)+,(a1)+
	beq.s	ch_n
	addq.l	#1,d0
ch_n:	subq.l	#1,d1
	bpl.s	ch_l
	rts

| copy 64 KB from a0 to a1: 128 lines of 256 words, source only, hog mode
blit:	lea	0xFFFF8A00.w,a2
	move.w	#2,0x20(a2)		| src X inc
	move.w	#2,0x22(a2)		| src Y inc
	move.l	a0,0x24(a2)		| src address
	move.w	#-1,0x28(a2)		| endmasks
	move.w	#-1,0x2A(a2)
	move.w	#-1,0x2C(a2)
	move.w	#2,0x2E(a2)		| dst X inc
	move.w	#2,0x30(a2)		| dst Y inc
	move.l	a1,0x32(a2)		| dst address
	move.w	#256,0x36(a2)		| X count
	move.w	#128,0x38(a2)		| Y count
	move.b	#2,0x3A(a2)		| HOP: source
	move.b	#3,0x3B(a2)		| LOP: source
	move.b	#0,0x3D(a2)		| skew
	move.b	#0xC0,0x3C(a2)		| busy + hog: start
bl_w:	btst	#7,0x3C(a2)
	bne.s	bl_w
	rts
