| Large hard disk transfers (one Fwrite / Fread of 128 KB, like an installer copying a file): writes C:\BIG1.DAT
| from a buffer in ST-RAM ($200000), reads it back into $240000 and compares; then, if TT-RAM is there
| ($5A8 = $1357BD13), C:\BIG2.DAT from a buffer in TT-RAM ($01200000), read back into $01240000.
| $100000 / $100004: 0 = good, else the GEMDOS error (negative), 1 (length) or 2 (data differ); $100004 = -1 without
| TT-RAM. Then the done marker $D0E0600D at $FFFF0. With the SD card latency of the bench:
|    HD_RD_US=2000 HD_WR_US=20000 ./run_prg.sh OUT tests/bigfile.s -- --scsi --turbo --fastram 3 --start FFFF4 \
|        --done FFFF0 --dump 100000:8 --ms 30000
| MEGA65 port done by Chris Freeman in 2026, licensed under GPL v3
	.text
	clr.l	-(sp)
	move.w	#0x20,-(sp)
	trap	#1			| Super: $5A8 is protected
	addq.l	#6,sp
	move.l	#0x57A27000,0xFFFF4	| start marker (sim_main --start FFFF4)
	move.l	#0x100000,a5
	move.l	#-1,4(a5)
	lea	name1(pc),a4
	move.l	#0x200000,a3
	bsr	test
	move.l	d0,(a5)
	cmp.l	#0x1357BD13,0x5A8
	bne	done
	lea	name2(pc),a4
	move.l	#0x01200000,a3
	bsr	test
	move.l	d0,4(a5)
done:	move.l	#0xD0E0600D,0xFFFF0
	clr.w	-(sp)
	trap	#1

| a4 = name, a3 = write buffer (read back into a3 + $40000); d0 = result
test:	move.l	a3,a1			| pattern
	move.l	#0x7FFF,d1		| 32768 longs
	move.l	#0x12345678,d2
fill:	move.l	d2,(a1)+
	add.l	#0x01030507,d2
	rol.l	#3,d2
	subq.l	#1,d1
	bpl	fill
	clr.w	-(sp)
	move.l	a4,-(sp)
	move.w	#0x3c,-(sp)
	trap	#1			| Fcreate
	addq.l	#8,sp
	tst.l	d0
	bmi	res
	move.w	d0,d7
	move.l	a3,-(sp)
	move.l	#0x20000,-(sp)
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
	bmi	res
	moveq	#1,d0
	cmp.l	#0x20000,d5
	bne	res
	clr.w	-(sp)
	move.l	a4,-(sp)
	move.w	#0x3d,-(sp)
	trap	#1			| Fopen
	addq.l	#8,sp
	tst.l	d0
	bmi	res
	move.w	d0,d7
	lea	0x40000(a3),a0
	move.l	a0,-(sp)
	move.l	#0x20000,-(sp)
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
	bmi	res
	moveq	#1,d0
	cmp.l	#0x20000,d5
	bne	res
	move.l	a3,a0
	lea	0x40000(a3),a1
	move.l	#0x7FFF,d1
cmp:	cmpm.l	(a0)+,(a1)+
	bne	bad
	subq.l	#1,d1
	bpl	cmp
	moveq	#0,d0
res:	rts
bad:	moveq	#2,d0
	rts

name1:	.asciz	"C:\\BIG1.DAT"
name2:	.asciz	"C:\\BIG2.DAT"
	.even
