/* falcon_fpu on the RISC-V in the FPGA: reset entry. The RAM is loaded with the whole image
 * (.data included) at configuration, so only .bss is cleared here.
 * MEGA65 port done by Chris Freeman in 2026, licensed under GPL v3 */
	.section .text.start
	.globl _start
_start:
	.option push
	.option norelax
	la	gp, __global_pointer$
	.option pop
	la	sp, __stack_top
	la	t0, __bss_start
	la	t1, __bss_end
1:	bgeu	t0, t1, 2f
	sw	zero, 0(t0)
	addi	t0, t0, 4
	j	1b
2:	call	main
	call	exit			/* main's return value (the self-test's result) */
3:	j	3b
