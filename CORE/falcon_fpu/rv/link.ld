/* falcon_fpu on the RISC-V in the FPGA (fpu_rv.v): code, data, heap and stack in one RAM at 0.
 * MEGA65 port done by Chris Freeman in 2026, licensed under GPL v3 */
MEMORY { RAM (rwx) : ORIGIN = 0x00000000, LENGTH = 256K }
ENTRY(_start)
SECTIONS
{
	.text : { KEEP(*(.text.start)) *(.text .text.*) } > RAM
	.rodata : { *(.rodata .rodata.* .srodata .srodata.*) } > RAM
	.data : { *(.data .data.* .sdata .sdata.*) } > RAM
	.bss (NOLOAD) : { __bss_start = .; *(.bss .bss.* .sbss .sbss.* COMMON) . = ALIGN(4); __bss_end = .; } > RAM
	. = ALIGN(16);
	end = .;                                  /* heap start (sbrk) */
	__stack_top = ORIGIN(RAM) + LENGTH(RAM);
	__global_pointer$ = __bss_start + 0x800;
}
