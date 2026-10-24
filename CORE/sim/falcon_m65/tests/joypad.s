| Enhanced joystick ports (falcon_combel.sv): row 0 of joypad A and B selected ($FF9202 = $EE);
| every change of {directions ($FF9202 bits 15..8), buttons ($FF9200 bits 7..0)} is logged at
| $100000 as {_hz_200.l, value.w}, for 4 s. Then the done marker $D0E0600D at $FFFF0.
|    ./run_prg.sh /tmp/jp tests/joypad.s -- --ms 9000 --start FFFF4 --done FFFF0 --dump 100000:60 --pad 300:18:200
| MEGA65 port done by Chris Freeman in 2026, licensed under GPL v3
	.text
	move.l	#0x57A27000,0xFFFF4	| start marker (sim_main --start FFFF4)
	clr.l	-(sp)
	move.w	#0x20,-(sp)
	trap	#1			| Super
	addq.l	#6,sp
	move.l	#0x100000,a2
	move.l	0x4ba.w,d6
	add.l	#800,d6
	moveq	#-1,d5
loop:	move.w	#0xFFEE,0xFFFF9202
	move.w	0xFFFF9202,d0		| directions in bits 15..8
	move.w	0xFFFF9200,d1		| buttons in bits 7..0
	move.b	d1,d0
	cmp.w	d5,d0
	beq.s	same
	move.w	d0,d5
	move.l	0x4ba.w,(a2)+
	move.w	d0,(a2)+
	cmp.l	#0x100F00,a2
	bhs.s	fin
same:	cmp.l	0x4ba.w,d6
	bgt.s	loop
fin:	move.l	#0xD0E0600D,0xFFFF0
	clr.w	-(sp)
	trap	#1
