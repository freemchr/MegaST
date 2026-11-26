| 640x400 in 16 colours, interlaced on an RGB monitor (Falcon mode $12A: VERTFLAG | PAL | COL80 | BPS4),
| issue #38. Line y of the picture is drawn in colour 1 + (y mod 15), so in the frames of the bench
| (one per field) the colour of each line tells which picture row it shows; colour 0 is the border.
|    python3 simrom.py tosfalc.img /tmp/tosfalc_sim.img
|    TOS=/tmp/tosfalc_sim.img ./run_prg.sh /tmp/ilace tests/ilace.s -- --monitor 1 --ms 4500 --frame-every 1
|    ./ilace_check.py /tmp/ilace.log /tmp/ilace 216 6      (WEAVE OK; a model built after 2026-11-26)
| Result (1.6-test8): the field with the odd rows has one more visible line above the picture (40 vs 39);
| ilace_fl now puts the even rows down and the woven pairs give rows 0..399 in order (test6/7: swapped).
| Also checked: $10A (NTSC) and $16A (overscan 768x480: Malloc 184320, 48 groups, 480 lines, ROWS=480).
| MEGA65 port done by Chris Freeman in 2026, licensed under GPL v3
	.text
	move.l	4(sp),a0		| basepage
	move.l	#0x10000,-(sp)		| keep 64 KB (the TPA has all the memory)
	move.l	a0,-(sp)
	clr.w	-(sp)
	move.w	#74,-(sp)
	trap	#1			| Mshrink
	lea	12(sp),sp
	move.l	#128000+256,-(sp)
	move.w	#72,-(sp)
	trap	#1			| Malloc
	addq.l	#6,sp
	add.l	#255,d0
	and.l	#0xFFFFFF00,d0
	move.l	d0,a0
	move.l	d0,a5
	move.w	#0x12A,-(sp)		| mode
	move.w	#3,-(sp)		| rez 3: use the mode
	move.l	a5,-(sp)		| physbase
	move.l	a5,-(sp)		| logbase
	move.w	#5,-(sp)
	trap	#14			| Setscreen (VsetScreen)
	lea	14(sp),sp		| (clears the screen: draw afterwards)
	move.l	a5,a0
	moveq	#0,d1			| y
line:	move.l	d1,d5
	divu	#15,d5
	swap	d5			| y mod 15
	addq.w	#1,d5			| colour 1..15
	moveq	#0,d3			| plane 0/1 words
	moveq	#0,d6			| plane 2/3 words
	btst	#0,d5
	beq.s	1f
	or.l	#0xFFFF0000,d3
1:	btst	#1,d5
	beq.s	2f
	or.l	#0x0000FFFF,d3
2:	btst	#2,d5
	beq.s	3f
	or.l	#0xFFFF0000,d6
3:	btst	#3,d5
	beq.s	4f
	or.l	#0x0000FFFF,d6
4:	moveq	#39,d4			| 40 x 16 pixels
grp:	move.l	d3,(a0)+
	move.l	d6,(a0)+
	dbra	d4,grp
	addq.w	#1,d1
	cmp.w	#400,d1
	bne.s	line
	move.l	#0x57A27000,0xFFFF4	| start marker
wait:	bra.s	wait
