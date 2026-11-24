| IKBD joysticks (falcon_ikbd.sv) as STOS and most games read them: joystick event mode ($14) sent
| with Ikbdws, the packets caught through joyvec (Kbdvbase). Every packet is logged at $100000 as
| {_hz_200.l, header.b ($FE = port 0, $FF = port 1), byte.b} (EmuTOS's a0 points at the header; the
| state byte is not at 1(a0) there), for 4 s. Then the done marker $D0E0600D at $FFFF0. The stick on
| ST port 1 (the game port, --joy) must arrive with header $FF; the bench log ("IKBD byte") shows the
| header and state bytes as the CPU reads them (issue #37: before the fix FE 09, after it FF 09).
|    ./run_prg.sh /tmp/ij tests/ikbdjoy.s -- --ms 9000 --start FFFF4 --done FFFF0 --dump 100000:60 \
|        --joy 300:9:200 --joy 700:10:200
| MEGA65 port done by Chris Freeman in 2026, licensed under GPL v3
	.text
	move.l	#0x57A27000,0xFFFF4	| start marker (sim_main --start FFFF4)
	clr.l	-(sp)
	move.w	#0x20,-(sp)
	trap	#1			| Super
	addq.l	#6,sp
	move.l	#0x100000,0xFFFE8	| log pointer
	move.w	#34,-(sp)
	trap	#14			| Kbdvbase
	addq.l	#2,sp
	move.l	d0,a3
	lea	handler(pc),a0
	move.l	a0,24(a3)		| joyvec
	pea	cmd(pc)
	clr.w	-(sp)			| 1 byte (count - 1)
	move.w	#25,-(sp)
	trap	#14			| Ikbdws: $14 joystick event mode
	addq.l	#8,sp
	move.l	0x4ba.w,d6
	add.l	#800,d6
wait:	cmp.l	0x4ba.w,d6
	bgt.s	wait
	move.l	#0xD0E0600D,0xFFFF0
	clr.w	-(sp)
	trap	#1

| a0: the joystick packet (header, state)
handler:
	move.l	a1,-(sp)
	move.l	0xFFFE8,a1
	cmp.l	#0x100F00,a1
	bhs.s	h_full
	move.l	0x4ba.w,(a1)+
	move.b	(a0),(a1)+
	move.b	1(a0),(a1)+
	move.l	a1,0xFFFE8
h_full:	move.l	(sp)+,a1
	rts

cmd:	.byte	0x14,0
