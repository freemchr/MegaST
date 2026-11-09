/* fpe_shortcheck.c - the engine's short path (fpe_sf_exec(), fpe_sf.c) against Hatari's own path,
 * on the host.  Each case: random FPCR (rounding mode and precision; now and then an enable byte, which
 * the short path must leave to fpp.c), random FPSR, eight random FP registers (zeros, denormals,
 * pseudo-denormals, unnormals, normals around 1 and at both ends of the range, short mantissas for
 * exact results, infinities, quiet and signaling NaNs, pseudo-infinities) and a register-to-register
 * instruction (the short path's opmodes and now and then any opmode).  It runs once through fpp.c
 * (fpe_sf_off = 1) and once through the short path from the same state, and compares the eight
 * registers, FPSR, FPCR, FPIAR, the returned flags and the exception status bit for bit.
 * Then sequences: 40 instructions in a row from a reset FPU (short path instructions, any other
 * register-to-register instruction, FPCR changes that enable exceptions, the CPU taking a pending
 * exception), once through fpp.c and once with the short path, compared after every step.
 *    build.sh (host library), then
 *    cc -O2 -I. fpe_shortcheck.c build/host/libfpe.a -lm -o build/fpe_shortcheck
 *    build/fpe_shortcheck [cases] [seed]
 * MEGA65 port done by Chris Freeman in 2026, licensed under GPL v3 */
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include "falcon_fpu_engine.h"

extern int fpe_sf_off;

static uint64_t rs = 88172645463325252ull;
static uint64_t rnd(void) { rs ^= rs << 13; rs ^= rs >> 7; rs ^= rs << 17; return rs; }
static unsigned rn(unsigned n) { return (unsigned)(rnd() % n); }

static void value(uint16_t *se, uint64_t *m)
{
	uint16_t s = rn(2) ? 0x8000 : 0;
	uint64_t r = rnd();
	switch (rn(14)) {
	case 0:  *se = s; *m = 0; break;                                            /* zero */
	case 1:  *se = s; *m = r >> (1 + rn(63)); break;                            /* denormal */
	case 2:  *se = s; *m = r | 0x8000000000000000ull; break;                    /* pseudo-denormal */
	case 3:  *se = s | (1 + rn(0x7ffe)); *m = r & 0x7fffffffffffffffull; break; /* unnormal */
	case 4:  *se = s | 0x7fff; *m = 0; break;                                   /* infinity */
	case 5:  *se = s | 0x7fff; *m = rn(2) ? 0x8000000000000000ull : 0x0000000000000000ull; break;
	case 6:  *se = s | 0x7fff; *m = r | 0xc000000000000000ull; break;           /* quiet NaN */
	case 7:  *se = s | 0x7fff; *m = (r & 0x3fffffffffffffffull) | 0x8000000000000001ull; break; /* SNaN */
	case 8:  *se = s | 0x7fff; *m = r & 0x7fffffffffffffffull; break;           /* pseudo-NaN/inf */
	case 9:  *se = s | (1 + rn(80)); *m = r | 0x8000000000000000ull; break;     /* tiny */
	case 10: *se = s | (0x7ffe - rn(80)); *m = r | 0x8000000000000000ull; break; /* huge */
	case 11: *se = s | (0x3fff - 40 + rn(80));                                  /* short mantissa */
		 *m = (r | 0x8000000000000000ull) & ~((1ull << (rn(2) ? 40 : 11)) - 1); break;
	default: *se = s | (0x3fff - 64 + rn(128)); *m = r | 0x8000000000000000ull; break;
	}
}

/* a memory operand of format fmt (L S X P W D B), in memory order; returns its size */
static int operand(unsigned fmt, uint8_t *b)
{
	static const int sz[8] = { 4, 4, 12, 12, 2, 8, 1, 0 };
	uint64_t r = rnd(); uint32_t w;
	switch (fmt) {
	case 1: {                                   /* single: specials or random */
		uint32_t sg = rn(2) ? 0x80000000u : 0;
		switch (rn(8)) {
		case 0: w = sg; break;
		case 1: w = sg | ((uint32_t)r & 0x7fffff); break;                  /* denormal */
		case 2: w = sg | 0x7f800000u; break;
		case 3: w = sg | 0x7fc00000u | ((uint32_t)r & 0x3fffff); break;   /* quiet NaN */
		case 4: w = sg | 0x7f800001u | ((uint32_t)r & 0x1fffff); break;   /* SNaN */
		default: w = (uint32_t)r; break;
		}
		b[0] = w >> 24; b[1] = w >> 16; b[2] = w >> 8; b[3] = w; break;
	}
	case 5: {                                   /* double */
		uint64_t sg = rn(2) ? 0x8000000000000000ull : 0, d;
		switch (rn(8)) {
		case 0: d = sg; break;
		case 1: d = sg | (r & 0xfffffffffffffull); break;
		case 2: d = sg | 0x7ff0000000000000ull; break;
		case 3: d = sg | 0x7ff8000000000000ull | (r & 0x7ffffffffffffull); break;
		case 4: d = sg | 0x7ff0000000000001ull | (r & 0x3ffffffffffffull); break;
		case 5: d = sg | ((0x3ff - 30 + rn(60)) * 1ull << 52) | (r & 0xfffffff00000000ull); break;
		default: d = r; break;
		}
		for (int i = 0; i < 8; i++) b[i] = d >> (56 - 8 * i);
		break;
	}
	case 2: case 3: {                           /* extended (and packed: random bits) */
		uint16_t se; uint64_t m; value(&se, &m);
		b[0] = se >> 8; b[1] = se; b[2] = b[3] = 0;
		for (int i = 0; i < 8; i++) b[4 + i] = m >> (56 - 8 * i);
		if (fmt == 3) for (int i = 0; i < 12; i++) b[i] = rnd();
		break;
	}
	default: {                                  /* L W B: limits or random */
		uint32_t v = rn(4) == 0 ? (rn(2) ? 0x80000000u : 0x7fffffffu) >> (fmt == 4 ? 16 : fmt == 6 ? 24 : 0) : (uint32_t)r;
		if (rn(6) == 0) v = rn(3);
		for (int i = 0; i < 4; i++) b[i] = v >> (24 - 8 * i);
		if (fmt == 4) { b[0] = v >> 8; b[1] = v; }
		if (fmt == 6) b[0] = v;
		break;
	}
	}
	return sz[fmt];
}

static const uint16_t ops[] = { 0x00, 0x04, 0x05, 0x18, 0x1a, 0x20, 0x22, 0x23, 0x28,
                                0x38, 0x39, 0x3c, 0x3d, 0x3a, 0x3b, 0x3e, 0x3f };

typedef struct { uint16_t se[8]; uint64_t m[8]; uint32_t fpsr, fpcr, fpiar; int flags, st; uint32_t vec; uint8_t out[12]; } St;

static uint8_t lastout[FPE_MAXIO];
static void get(St *s, int flags)
{
	int ol = flags >> 8;
	for (int i = 0; i < 12; i++) s->out[i] = i < ol ? lastout[i] : 0;
	for (int i = 0; i < 8; i++) fpe_get_fp(i, &s->se[i], &s->m[i]);
	s->fpsr = fpe_fpsr(); s->fpcr = fpe_fpcr(); s->fpiar = fpe_fpiar();
	s->flags = flags; s->st = fpe_status(); s->vec = fpe_pending_vector();
}

static void put(const St *s)
{
	fpe_clear_exception();
	for (int i = 0; i < 8; i++) fpe_set_fp(i, s->se[i], s->m[i]);
	fpe_set_fpcr(s->fpcr); fpe_set_fpsr(s->fpsr); fpe_set_fpiar(s->fpiar);
}

static int same(const St *a, const St *b)
{
	for (int i = 0; i < 8; i++) if (a->se[i] != b->se[i] || a->m[i] != b->m[i]) return 0;
	for (int i = 0; i < 12; i++) if (a->out[i] != b->out[i]) return 0;
	return a->fpsr == b->fpsr && a->fpcr == b->fpcr && a->fpiar == b->fpiar && a->flags == b->flags &&
	       a->st == b->st && a->vec == b->vec;
}

int main(int argc, char **argv)
{
	long n = argc > 1 ? atol(argv[1]) : 1000000;
	if (argc > 2) rs ^= strtoull(argv[2], 0, 0) * 0x9E3779B97F4A7C15ull;
	long fail = 0, shortcases = 0;
	fpe_reset();
	for (long k = 0; k < n; k++) {
		St st0, ref, got;
		for (int i = 0; i < 8; i++) value(&st0.se[i], &st0.m[i]);
		st0.fpcr = (rn(4) << 4) | (rn(4) << 6);                /* rounding mode, precision */
		if (rn(16) == 0) st0.fpcr |= (rnd() & 0xff) << 8;       /* an enable byte now and then */
		st0.fpsr = (uint32_t)rnd() & 0x0ffffff8;
		st0.fpiar = (uint32_t)rnd();
		uint16_t op = rn(8) ? ops[rn(sizeof ops / sizeof ops[0])] : rn(0x40);
		unsigned cls = rn(3) == 0 ? 0 : rn(2) ? 2 : 3, fmt = rn(16) == 0 ? 3 : rn(7);
		if (fmt == 3 && rn(2)) fmt = 7;
		uint8_t in[16] = { 0 }; int inl = 0;
		uint16_t cmd;
		if (cls == 0) cmd = (uint16_t)(rn(8) << 10 | rn(8) << 7 | op);
		else if (cls == 2) { if (fmt == 7) fmt = 6; inl = operand(fmt, in); cmd = (uint16_t)(0x4000 | fmt << 10 | rn(8) << 7 | op); }
		else cmd = (uint16_t)(0x6000 | fmt << 10 | rn(8) << 7 | (fmt == 3 || fmt == 7 ? (rnd() & 0x7f) : 0));
		int ol;

		put(&st0);
		fpe_sf_off = 1;
		int f = fpe_exec(cmd, inl ? in : 0, inl, 0, 0x1000, lastout, &ol);
		get(&ref, f | ol << 8);

		put(&st0);
		fpe_sf_off = 0;
		f = fpe_exec(cmd, inl ? in : 0, inl, 0, 0x1000, lastout, &ol);
		get(&got, f | ol << 8);
		if (!(st0.fpcr & 0xff00)) shortcases++;

		if (!same(&ref, &got)) {
			if (fail++ < 10) {
				printf("DIFF case %ld cmd %04x fpcr %08x fpsr %08x\n", k, cmd, st0.fpcr, st0.fpsr);
				int s = (cmd >> 10) & 7, d = (cmd >> 7) & 7;
				printf("  src FP%d %04x %016llx  dst FP%d %04x %016llx\n", s, st0.se[s],
				       (unsigned long long)st0.m[s], d, st0.se[d], (unsigned long long)st0.m[d]);
				printf("  in");
				for (int i = 0; i < inl; i++) printf(" %02x", in[i]);
				printf("\n  ref FP%d %04x %016llx fpsr %08x flags %x st %x out", d, ref.se[d],
				       (unsigned long long)ref.m[d], ref.fpsr, ref.flags, ref.st);
				for (int i = 0; i < 12; i++) printf(" %02x", ref.out[i]);
				printf("\n  got FP%d %04x %016llx fpsr %08x flags %x st %x out", d, got.se[d],
				       (unsigned long long)got.m[d], got.fpsr, got.flags, got.st);
				for (int i = 0; i < 12; i++) printf(" %02x", got.out[i]);
				printf("\n");
			}
		}
	}
	printf("%ld cases (%ld with no exception enabled), %ld differ: %s\n", n, shortcases, fail,
	       fail ? "FAIL" : "PASS");

	/* sequences */
	enum { L = 40 };
	long nseq = n / 20, sfail = 0;
	for (long k = 0; k < nseq; k++) {
		St st0, log[2][L];
		uint64_t seed = rnd();
		for (int i = 0; i < 8; i++) value(&st0.se[i], &st0.m[i]);
		st0.fpcr = (rn(4) << 4) | (rn(4) << 6); st0.fpsr = 0; st0.fpiar = 0;
		for (int pass = 0; pass < 2; pass++) {
			uint64_t save = rs; rs = seed;
			fpe_reset(); put(&st0);
			fpe_sf_off = pass == 0;
			for (int j = 0; j < L; j++) {
				int ol = 0, f = 0;
				unsigned what = rn(16);
				if (what == 0)                                   /* FPCR, now and then enables */
					fpe_set_fpcr((rn(4) << 4) | (rn(4) << 6) | (rn(3) == 0 ? (rnd() & 0xff) << 8 : 0));
				else if (what == 1 && (fpe_status() & 1))        /* the CPU takes the exception */
					fpe_clear_exception();
				else if (what == 2) {                            /* a new value into a register */
					uint16_t se; uint64_t m; value(&se, &m); fpe_set_fp(rn(8), se, m);
				} else {
					uint16_t op = rn(4) ? ops[rn(sizeof ops / sizeof ops[0])] : rn(0x40);
					unsigned c = rn(3), fm = rn(7);
					uint8_t in[16]; int inl = 0; uint16_t cmd;
					if (c == 0) cmd = (uint16_t)(rn(8) << 10 | rn(8) << 7 | op);
					else if (c == 1) { inl = operand(fm, in); cmd = (uint16_t)(0x4000 | fm << 10 | rn(8) << 7 | op); }
					else cmd = (uint16_t)(0x6000 | fm << 10 | rn(8) << 7 | (fm == 3 ? 0x11 : 0));
					f = fpe_exec(cmd, inl ? in : 0, inl, 0, 0x2000 + 4 * j, lastout, &ol);
				}
				get(&log[pass][j], f | ol << 8);
			}
			rs = save;
		}
		for (int j = 0; j < L; j++)
			if (!same(&log[0][j], &log[1][j])) {
				if (sfail++ < 5)
					printf("SEQ DIFF sequence %ld step %d: ref fpsr %08x st %x vec %x, got fpsr %08x st %x vec %x\n",
					       k, j, log[0][j].fpsr, log[0][j].st, log[0][j].vec,
					       log[1][j].fpsr, log[1][j].st, log[1][j].vec);
				break;
			}
	}
	printf("%ld sequences of %d steps, %ld differ: %s\n", nseq, L, sfail, sfail ? "FAIL" : "PASS");
	return fail != 0 || sfail != 0;
}
