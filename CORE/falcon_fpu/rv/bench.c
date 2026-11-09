/* Engine speed on the RISC-V (simulation, CORE/sim/fpu_rv): RISC-V cycles per 68882 instruction
 * through fpu_request(), as the service executes them, without the mailbox.
 * BENCHF="-DBENCH_ONLY=1 -DBENCH_N=1000" ./build.sh: only FADD, 1000 times.
 * MEGA65 port done by Chris Freeman in 2026, licensed under GPL v3 */
#include <stdio.h>
#include "fpu_rv.h"
#include "../fpu_request.h"

#ifndef BENCH_N
#define BENCH_N 20
#endif

static void load(int reg, const uint8_t d[8])   /* FMOVE.D #d,FPn */
{
	uint8_t out[FPE_MAXIO + 4]; int n;
	fpu_request(FPU_KIND_EXEC, 0x5400 | reg << 7, 0, 0, d, 8, out, &n);
}

int main(void)
{
	static const uint8_t pi[8] = { 0x40, 0x09, 0x21, 0xfb, 0x54, 0x44, 0x2d, 0x18 };
	static const uint8_t e[8]  = { 0x40, 0x05, 0xbf, 0x0a, 0x8b, 0x14, 0x57, 0x69 };
	static const struct { const char *name; uint16_t cmd; } t[] = {
		{ "FMOVE FP1,FP0", 0x0400 }, { "FADD FP1,FP0", 0x0422 }, { "FMUL FP1,FP0", 0x0423 },
		{ "FDIV FP1,FP0", 0x0420 }, { "FSQRT FP1,FP0", 0x0404 }, { "FSIN FP1,FP0", 0x040e },
	};
	uint8_t out[FPE_MAXIO + 4]; int n;
	fpe_reset();
#ifdef BENCH_ONLY                               /* one instruction, for a profile of it alone */
	for (unsigned i = BENCH_ONLY; i == BENCH_ONLY; i++) {
#else
	for (unsigned i = 0; i < sizeof t / sizeof t[0]; i++) {
#endif
		load(0, pi); load(1, e);
		uint32_t c0 = rv_cycles();
		for (int k = 0; k < BENCH_N; k++) fpu_request(FPU_KIND_EXEC, t[i].cmd, 0, 0, 0, 0, out, &n);
		uint32_t c = (rv_cycles() - c0) / BENCH_N;
		printf("%-14s %6lu cycles  %3lu.%02lu us at 96 MHz\n", t[i].name, (unsigned long)c,
		       (unsigned long)(c / 96), (unsigned long)(c % 96 * 100 / 96));
	}
#ifndef BENCH_ONLY
	{       /* memory operands: FMOVE.D <ea>,FP0 (8 bytes in) and FMOVE.D FP0,<ea> (8 bytes out) */
		static const struct { const char *name; uint16_t cmd; int in; } m[] = {
			{ "FMOVE.D in", 0x5400, 8 }, { "FMOVE.D out", 0x7400, 0 },
			{ "FADD.D in", 0x5422, 8 }, { "FMUL.D in", 0x5423, 8 },
		};
		for (unsigned i = 0; i < sizeof m / sizeof m[0]; i++) {
			load(0, pi);
			uint32_t c0 = rv_cycles();
			for (int k = 0; k < BENCH_N; k++)
				fpu_request(FPU_KIND_EXEC, m[i].cmd, 0, 0, m[i].in ? pi : 0, m[i].in, out, &n);
			uint32_t c = (rv_cycles() - c0) / BENCH_N;
			printf("%-14s %6lu cycles  %3lu.%02lu us at 96 MHz\n", m[i].name, (unsigned long)c,
			       (unsigned long)(c / 96), (unsigned long)(c % 96 * 100 / 96));
		}
	}
#endif
	return 0;
}
