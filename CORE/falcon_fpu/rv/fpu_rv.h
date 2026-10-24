/* falcon_fpu on the RISC-V in the FPGA (fpu_rv.v): memory map.
 * MEGA65 port done by Chris Freeman in 2026, licensed under GPL v3 */
#ifndef FPU_RV_H
#define FPU_RV_H
#include <stdint.h>

#define RV_CLK_HZ   96000000u                           /* fpu_rv.v runs on clk_96 */
#define RV_MAILBOX  ((volatile uint8_t *)0x10000000)    /* 1 KB, shared with the bridge (guest $E90000) */
#define RV_DEBUG    (*(volatile uint32_t *)0x20000000)  /* simulation: a byte to stdout */
#define RV_EXIT     (*(volatile uint32_t *)0x20000004)  /* simulation: end with this code */
#define RV_STACK    8192                                /* bytes kept free for the stack */

static inline uint32_t rv_cycles(void)
{
	uint32_t c;
	__asm__ volatile("rdcycle %0" : "=r"(c));
	return c;
}
#endif
