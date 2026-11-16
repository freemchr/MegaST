/* Engine speed on the RISC-V (simulation, CORE/sim/fpu_rv): RISC-V cycles per 68882 instruction
 * as the service (fpu_rv.c quick(), serve()) executes them: fpe_quick(), else fpu_request(); without
 * the mailbox.
 * BENCHF="-DBENCH_ONLY=1 -DBENCH_N=1000" ./build.sh: only FADD, 1000 times; -DBENCH_MEM_ONLY=n: only
 * the n-th of the second list (memory operands and the special operands of FPUBENCH's loops).
 * MEGA65 port done by Chris Freeman in 2026, licensed under GPL v3 */
#include <stdio.h>
#include "fpu_rv.h"
#include "../fpu_request.h"
#include "../engine/fpe_quick.h"

static inline void run(uint16_t cmd, const uint8_t *in, int n, uint8_t *out, int *on)  /* as serve() */
{
	if (!fpe_quick_cmd(cmd) || (fpe_quick(cmd, in, n, out, on) < 0 && (fpe_quick_tried = 1)))
		fpu_request(FPU_KIND_EXEC, cmd, 0, 0, in, n, out, on);
}

#ifndef BENCH_N
#define BENCH_N 20
#endif

static void load(int reg, const uint8_t d[8])   /* FMOVE.D #d,FPn */
{
	uint8_t out[FPE_MAXIO + 4]; int n;
	fpu_request(FPU_KIND_EXEC, 0x5400 | reg << 7, 0, 0, d, 8, out, &n);
}

#ifdef FPE_HWMUL
/* the multiplier of fpu_rv_h3.v ($30000000) against the product in C, random and edge values */
static void hwmul_check(void)
{
	volatile uint32_t *m = (volatile uint32_t *)0x30000000;
	static const uint64_t edge[] = { 0, 1, 0xffffffffull, 0x100000000ull, 0x8000000000000000ull,
	                                 0xffffffffffffffffull, 0xffffffff00000000ull, 0x80000000ffffffffull };
	uint64_t x = 0x9E3779B97F4A7C15ull;
	unsigned bad = 0;
	for (int i = 0; i < 20000; i++) {
		x ^= x << 13; x ^= x >> 7; x ^= x << 17;
		uint64_t a = i < 64 ? edge[i & 7] : x;
		x ^= x << 13; x ^= x >> 7; x ^= x << 17;
		uint64_t b = i < 64 ? edge[i >> 3] : x;
		m[0] = (uint32_t)a; m[1] = (uint32_t)(a >> 32); m[2] = (uint32_t)b; m[3] = (uint32_t)(b >> 32);
		uint32_t p0 = m[0], p1 = m[1], p2 = m[2], p3 = m[3];
		uint32_t a0 = (uint32_t)a, a1 = (uint32_t)(a >> 32), b0 = (uint32_t)b, b1 = (uint32_t)(b >> 32);
		uint64_t ll = (uint64_t)a0 * b0, lh = (uint64_t)a0 * b1, hl = (uint64_t)a1 * b0, hh = (uint64_t)a1 * b1;
		uint64_t mid = (ll >> 32) + (uint32_t)lh + (uint32_t)hl;
		uint64_t lo = mid << 32 | (uint32_t)ll, hi = hh + (lh >> 32) + (hl >> 32) + (mid >> 32);
		if (p0 != (uint32_t)lo || p1 != (uint32_t)(lo >> 32) || p2 != (uint32_t)hi || p3 != (uint32_t)(hi >> 32))
			bad++;
	}
	printf("hardware multiplier: 20000 products, %u wrong\n", bad);
}
#endif

int main(void)
{
#ifdef FPE_HWMUL
	hwmul_check();
#endif
	static const uint8_t pi[8] = { 0x40, 0x09, 0x21, 0xfb, 0x54, 0x44, 0x2d, 0x18 };
	static const uint8_t e[8]  = { 0x40, 0x05, 0xbf, 0x0a, 0x8b, 0x14, 0x57, 0x69 };
	static const struct { const char *name; uint16_t cmd; } t[] = {
		{ "FMOVE FP1,FP0", 0x0400 }, { "FADD FP1,FP0", 0x0422 }, { "FMUL FP1,FP0", 0x0423 },
		{ "FDIV FP1,FP0", 0x0420 }, { "FSQRT FP1,FP0", 0x0404 }, { "FSIN FP1,FP0", 0x040e },
	};
	uint8_t out[FPE_MAXIO + 4]; int n;
	fpe_reset();
#if defined BENCH_ONLY || defined BENCH_MEM_ONLY  /* one instruction, for a profile of it alone */
#ifndef BENCH_ONLY
#define BENCH_ONLY 99
#endif
	for (unsigned i = BENCH_ONLY; i == BENCH_ONLY && i < sizeof t / sizeof t[0]; i++) {
#else
	for (unsigned i = 0; i < sizeof t / sizeof t[0]; i++) {
#endif
		load(0, pi); load(1, e);
		uint32_t c0 = rv_cycles();
		for (int k = 0; k < BENCH_N; k++) run(t[i].cmd, 0, 0, out, &n);
		uint32_t c = (rv_cycles() - c0) / BENCH_N;
		printf("%-14s %6lu cycles  %3lu.%02lu us at 96 MHz\n", t[i].name, (unsigned long)c,
		       (unsigned long)(c / 96), (unsigned long)(c % 96 * 100 / 96));
	}
#if !defined BENCH_ONLY || defined BENCH_MEM_ONLY
	{       /* memory operands: FMOVE.D <ea>,FP0 (8 bytes in) and FMOVE.D FP0,<ea> (8 bytes out) */
		static const struct { const char *name; uint16_t cmd; int in; } m[] = {
			{ "FMOVE.D in", 0x5400, 8 }, { "FMOVE.D out", 0x7400, 0 },
			{ "FADD.D in", 0x5422, 8 }, { "FMUL.D in", 0x5423, 8 },
			/* the special operands of FPUBENCH's loops: FMUL of infinity, zero to and from memory */
			{ "FMUL inf", 0x0423, 0 }, { "FMOVE.X 0 out", 0x6800, 0 },
			{ "FMOVE.D 0 in", 0x5400, -8 }, { "FMUL.D 0 in", 0x5423, -8 },
		};
		static const uint8_t inf[8] = { 0x7f, 0xf0 }, zero[8] = { 0 };
#ifdef BENCH_MEM_ONLY
		for (unsigned i = BENCH_MEM_ONLY; i == BENCH_MEM_ONLY; i++) {
#else
		for (unsigned i = 0; i < sizeof m / sizeof m[0]; i++) {
#endif
			load(0, i == 4 ? inf : i >= 5 ? zero : pi);
			load(1, e);
			uint32_t c0 = rv_cycles();
			for (int k = 0; k < BENCH_N; k++)
				run(m[i].cmd, m[i].in > 0 ? pi : m[i].in ? zero : 0, m[i].in < 0 ? -m[i].in : m[i].in, out, &n);
			uint32_t c = (rv_cycles() - c0) / BENCH_N;
			printf("%-14s %6lu cycles  %3lu.%02lu us at 96 MHz\n", m[i].name, (unsigned long)c,
			       (unsigned long)(c / 96), (unsigned long)(c % 96 * 100 / 96));
		}
	}
#endif
	return 0;
}
