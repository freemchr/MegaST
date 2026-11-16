/* fpe_fastcheck.c - fpe_fast.c against Hatari's softfloat on the host, bit for bit: the result,
 * the exception flags and the internal result softfloat keeps for exceptions
 * (saveFloatx80Internal()), for floatx80_add, floatx80_sub and floatx80_mul.
 *   HOST_ONLY=1 ./build.sh
 *   cc -O2 -I. -Ishim -I$H/cpu -I$H/cpu/softfloat -I$H/includes -I$H/debug fpe_fastcheck.c \
 *      fpe_fast.c build/host/libfpe.a -lm -D__real_floatx80_add=floatx80_add \
 *      -D__real_floatx80_sub=floatx80_sub -D__real_floatx80_mul=floatx80_mul -o build/fpe_fastcheck
 *   build/fpe_fastcheck <millions> <seed>
 * (fpe_fast.c's fallback then calls softfloat directly; the libfpe.a here is not wrapped.)
 * Operands: random, and classes aimed at the kernel's edges: every exponent difference from 0 to
 * 140, cancellation (equal exponents and significands that differ in a few low bits, or an
 * exponent apart with the top bits complementary), rounding ties and near ties, all-ones
 * significands, the ends of the exponent range, and now and then a rounding mode, precision or
 * operand the kernel leaves to softfloat (it must then return exactly what softfloat returns).
 * MEGA65 port done by Chris Freeman in 2026, licensed under GPL v3 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include "softfloat.h"

floatx80 __wrap_floatx80_add(floatx80 a, floatx80 b, float_status *s);
floatx80 __wrap_floatx80_sub(floatx80 a, floatx80 b, float_status *s);
floatx80 __wrap_floatx80_mul(floatx80 a, floatx80 b, float_status *s);

static uint64_t st;
static uint64_t r64(void)               /* xorshift64* */
{
	st ^= st >> 12; st ^= st << 25; st ^= st >> 27;
	return st * 0x2545F4914F6CDD1DULL;
}
static unsigned rn(unsigned n) { return (unsigned)(r64() % n); }

static uint64_t sig(void)
{
	switch (rn(8)) {
	case 0: return 0xffffffffffffffffULL;
	case 1: return 0x8000000000000000ULL | rn(4);
	case 2: return 0xffffffffffffffffULL << rn(64);                 /* ones on top */
	case 3: return 0x8000000000000000ULL | (r64() & ((1ULL << rn(64)) - 1));
	default: return r64() | 0x8000000000000000ULL;
	}
}

static floatx80 mk(unsigned s, unsigned e, uint64_t m)
{
	floatx80 z;
	z.high = (uint16_t)(s << 15 | (e & 0x7fff));
	z.low = m;
	return z;
}

static unsigned rexp(void)
{
	switch (rn(6)) {
	case 0: return 1 + rn(80);                      /* bottom of the range */
	case 1: return 0x7ffe - rn(80);                 /* top */
	case 2: return 0x3fff - 40 + rn(80);
	default: return 1 + rn(0x7ffe);
	}
}

/* the operands of one test */
static void pair(floatx80 *a, floatx80 *b)
{
	unsigned c = rn(16);
	unsigned ea = rexp();
	unsigned sa = rn(2), sb = rn(2);
	uint64_t ma = sig(), mb = sig();
	unsigned eb;
	switch (c) {
	case 0: case 1: case 2: {                       /* every exponent difference to 140 */
		int d = (int)rn(141) * (rn(2) ? 1 : -1);
		eb = (unsigned)((int)ea + d);
		if (eb < 1 || eb > 0x7ffe) eb = ea;
		break;
	}
	case 3: case 4:                                 /* cancellation: a few low bits apart */
		eb = ea;
		mb = ma ^ (r64() & ((1ULL << rn(64)) - 1));
		mb |= 0x8000000000000000ULL;
		break;
	case 5:                                         /* one exponent apart, the top bits complementary */
		eb = ea > 1 ? ea - 1 : ea + 1;
		mb = ~ma | 0x8000000000000000ULL;
		break;
	case 6: {                                       /* rounding ties after the alignment */
		int d = 1 + (int)rn(63);
		eb = ea > (unsigned)d ? ea - d : ea + d;
		mb = (r64() | 0x8000000000000000ULL) & ~((1ULL << (d - 1)) - 1);
		if (rn(2)) mb |= 1ULL << (d - 1);
		break;
	}
	case 7:                                         /* products near a tie: few significant bits */
		eb = rexp();
		ma = 0x8000000000000000ULL | (r64() & 0xffffffff00000000ULL);
		mb = 0x8000000000000000ULL | (r64() & 0xffffffff00000000ULL);
		break;
	case 8:                                         /* now and then something not taken */
		eb = rexp();
		switch (rn(6)) {
		case 0: ma = 0; ea = rn(2) ? 0 : ea; break;     /* zero or unnormal */
		case 1: ea = 0; ma >>= 1 + rn(63); break;        /* denormal */
		case 2: ea = 0x7fff; ma = rn(2) ? 0x8000000000000000ULL : ma; break;  /* inf, NaN */
		case 3: ma &= 0x7fffffffffffffffULL; break;      /* unnormal */
		default: eb = ea; mb = ma; break;               /* equal magnitudes */
		}
		break;
	default:
		eb = rexp();
		break;
	}
	*a = mk(sa, ea, ma);
	*b = mk(sb, eb, mb);
}

static long fails;

static void check(int op, floatx80 a, floatx80 b, float_status st0)
{
	static const char *nm[] = { "add", "sub", "mul" };
	float_status s1 = st0, s2 = st0;
	/* the internal result: set to a marker before each, compared after */
	floatx80_internal_sign = 1; floatx80_internal_exp = 0x1234;
	floatx80_internal_sig0 = 0x1111; floatx80_internal_sig1 = 0x2222;
	floatx80_internal_precision = 7; floatx80_internal_mode = 9;
	floatx80 r1 = op == 0 ? floatx80_add(a, b, &s1) : op == 1 ? floatx80_sub(a, b, &s1) : floatx80_mul(a, b, &s1);
	flag i_s = floatx80_internal_sign; int32_t i_e = floatx80_internal_exp;
	uint64_t i_0 = floatx80_internal_sig0, i_1 = floatx80_internal_sig1;
	int8_t i_p = floatx80_internal_precision, i_m = floatx80_internal_mode;
	floatx80_internal_sign = 1; floatx80_internal_exp = 0x1234;
	floatx80_internal_sig0 = 0x1111; floatx80_internal_sig1 = 0x2222;
	floatx80_internal_precision = 7; floatx80_internal_mode = 9;
	floatx80 r2 = op == 0 ? __wrap_floatx80_add(a, b, &s2) : op == 1 ? __wrap_floatx80_sub(a, b, &s2) : __wrap_floatx80_mul(a, b, &s2);
	if (r1.high != r2.high || r1.low != r2.low || memcmp(&s1, &s2, sizeof s1) ||
	    i_s != floatx80_internal_sign || i_e != floatx80_internal_exp || i_0 != floatx80_internal_sig0 ||
	    i_1 != floatx80_internal_sig1 || i_p != floatx80_internal_precision || i_m != floatx80_internal_mode) {
		if (fails++ < 20)
			printf("FAIL %s %04x:%016llx %04x:%016llx mode %d prec %d: softfloat %04x:%016llx f%02x, fast %04x:%016llx f%02x\n",
			       nm[op], a.high, (unsigned long long)a.low, b.high, (unsigned long long)b.low,
			       st0.float_rounding_mode, st0.floatx80_rounding_precision,
			       r1.high, (unsigned long long)r1.low, s1.float_exception_flags,
			       r2.high, (unsigned long long)r2.low, s2.float_exception_flags);
	}
}

int main(int argc, char **argv)
{
	long n = (argc > 1 ? atol(argv[1]) : 10) * 1000000L;
	st = (argc > 2 ? strtoull(argv[2], 0, 0) : 1) * 0x9E3779B97F4A7C15ULL | 1;
	float_status s0;
	memset(&s0, 0, sizeof s0);
	for (long i = 0; i < n; i++) {
		floatx80 a, b;
		pair(&a, &b);
		float_status s = s0;
		s.float_rounding_mode = rn(16) ? float_round_nearest_even : (int8_t)rn(4);
		s.floatx80_rounding_precision = rn(16) ? 80 : (rn(2) ? 64 : 32);
		s.float_exception_flags = rn(4) ? 0 : (uint8_t)r64();
		s.floatx80_special_flags = rn(8) ? 0 : (flag)rn(4);
		check((int)rn(3), a, b, s);
	}
	printf("%s: %ld million cases, %ld failures\n", fails ? "FAIL" : "PASS", n / 1000000, fails);
	return fails != 0;
}
