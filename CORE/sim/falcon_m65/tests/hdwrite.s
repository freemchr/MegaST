| Hard disk partitions: writes X:\TEST.TXT (4096 bytes, a pattern per drive) on C:, D:, E: and F:, reads it back
| and compares. $100000 + 4 * n (n = 0..3 for C..F): 0 = good, else the GEMDOS error (negative) or 1 (data differ).
| Then the done marker $D0E0600D at $FFFF0. For blank images of tools/make_falcon_hd.py (from a floppy, see
| tools/fastram for a floppy with \AUTO):
|    Vtb_top tos.img --hda falcon.img --fda auto.st --ms 8000 --done FFFF0 --dump 100000:10
| MEGA65 port done by Chris Freeman in 2026, licensed under GPL v3
	.text
	move.l	#0x57A27000,0xFFFF4	| start marker (sim_main --start FFFF4)
	move.l	#0x100000,a5
	moveq	#0,d6			| drive 0..3
drive:	lea	name(pc),a0
	move.b	d6,d0
	add.b	#'C',d0
	move.b	d0,(a0)
	move.l	#0x180000,a1		| pattern
	move.w	#4095,d1
	move.b	d6,d2
fill:	move.b	d2,(a1)+
	add.b	#7,d2
	dbra	d1,fill
	clr.w	-(sp)
	pea	name(pc)
	move.w	#0x3c,-(sp)
	trap	#1			| Fcreate
	addq.l	#8,sp
	tst.l	d0
	bmi	result
	move.w	d0,d7
	pea	0x180000
	move.l	#4096,-(sp)
	move.w	d7,-(sp)
	move.w	#0x40,-(sp)
	trap	#1			| Fwrite
	lea	12(sp),sp
	move.l	d0,d5
	move.w	d7,-(sp)
	move.w	#0x3e,-(sp)
	trap	#1			| Fclose
	addq.l	#4,sp
	move.l	d5,d0
	bmi	result
	clr.w	-(sp)
	pea	name(pc)
	move.w	#0x3d,-(sp)
	trap	#1			| Fopen
	addq.l	#8,sp
	tst.l	d0
	bmi	result
	move.w	d0,d7
	pea	0x190000
	move.l	#4096,-(sp)
	move.w	d7,-(sp)
	move.w	#0x3f,-(sp)
	trap	#1			| Fread
	lea	12(sp),sp
	move.l	d0,d5
	move.w	d7,-(sp)
	move.w	#0x3e,-(sp)
	trap	#1			| Fclose
	addq.l	#4,sp
	move.l	d5,d0
	bmi	result
	moveq	#1,d0
	cmp.l	#4096,d5
	bne	result
	move.l	#0x180000,a0
	move.l	#0x190000,a1
	move.w	#1023,d1
cmp:	cmpm.l	(a0)+,(a1)+
	bne	result
	dbra	d1,cmp
	moveq	#0,d0
result:	move.l	d0,(a5)+
	addq.w	#1,d6
	cmp.w	#4,d6
	bne	drive
	move.l	#0xD0E0600D,0xFFFF0
	clr.w	-(sp)
	trap	#1

name:	.asciz	"C:\\TEST.TXT"
	.even
