/* fpe_fastk.h - the kernel of fpe_fast.c: floatx80 add, subtract and multiply for the common case,
 * bit for bit what Hatari's softfloat (SOFTFLOAT_68K) returns and records. Included by fpe_fast.c
 * (the --wrap functions) and fpe_sf.c (the short path calls it directly, without passing 80-bit
 * values through memory as the RISC-V calling convention does for every softfloat call).
 *
 * fk_add()/fk_mul() return 1 and store the result for the case taken (a subtraction is
 * fk_add() of the negated operand: softfloat picks the same function with the same signs):
 *   both operands normalized (integer bit set, exponent $0001-$7FFE: no zero, denormal,
 *   unnormal, infinity or NaN), rounding to nearest, rounding precision 80 (any value other than
 *   32 and 64, as roundAndPackFloatx80() reads it), a result exponent before rounding of
 *   $0001-$7FFD (no overflow, no underflow) and not an exact zero (subtraction);
 * otherwise they return 0 and change nothing (the caller then calls softfloat).
 * The steps and intermediate values are softfloat's: addFloatx80Sigs(), subFloatx80Sigs() +
 * normalizeRoundAndPackFloatx80(), floatx80_mul(), then the precision80 part of
 * roundAndPackFloatx80() (the inexact flag and saveFloatx80Internal() when bits are lost).
 * 64-bit shifts by a variable count and the leading zero count are written with 32-bit
 * operations: RV32IM has no instructions for them and GCC would call libgcc.
 * fpe_fastcheck.c compares them with softfloat on the host.
 * MEGA65 port done by Chris Freeman in 2026, licensed under GPL v3 */
#ifndef FPE_FASTK_H
#define FPE_FASTK_H
#include <stdint.h>
#include "softfloat.h"

#define FK_TOP 0x8000000000000000ULL

static inline uint64_t fk_shr(uint64_t a, unsigned n)   /* a >> n, 0 <= n < 64 */
{
	uint32_t hi = (uint32_t)(a >> 32), lo = (uint32_t)a;
	if (n >= 32) return hi >> (n - 32);
	if (n == 0) return a;
	return (uint64_t)(hi >> n) << 32 | lo >> n | hi << (32 - n);
}

static inline uint64_t fk_shl(uint64_t a, unsigned n)   /* a << n, 0 <= n < 64 */
{
	uint32_t hi = (uint32_t)(a >> 32), lo = (uint32_t)a;
	if (n >= 32) return (uint64_t)(lo << (n - 32)) << 32;
	if (n == 0) return a;
	return (uint64_t)(hi << n | lo >> (32 - n)) << 32 | (uint32_t)(lo << n);
}

static inline unsigned fk_clz64(uint64_t a)            /* a != 0 */
{
	uint32_t x = (uint32_t)(a >> 32);
	unsigned n = 0;
	if (!x) { x = (uint32_t)a; n = 32; }
	if (!(x & 0xffff0000u)) { x <<= 16; n += 16; }
	if (!(x & 0xff000000u)) { x <<= 8; n += 8; }
	if (!(x & 0xf0000000u)) { x <<= 4; n += 4; }
	if (!(x & 0xc0000000u)) { x <<= 2; n += 2; }
	if (!(x & 0x80000000u)) n += 1;
	return n;
}

static inline int fk_normal(const floatx80 *a)
{
	unsigned e = a->high & 0x7fff;
	return (uint32_t)(a->low >> 32) >> 31 && e != 0 && e != 0x7fff;
}

static inline int fk_mode_ok(const float_status *s)
{
	return s->float_rounding_mode == float_round_nearest_even &&
	       s->floatx80_rounding_precision != 32 && s->floatx80_rounding_precision != 64;
}

/* the precision80 part of roundAndPackFloatx80() with rounding to nearest, for
 * 1 <= zExp <= $7FFD and a normalized zSig0 */
static inline void fk_round80(int sign, int32_t zExp, uint64_t zSig0, uint64_t zSig1,
                              float_status *s, floatx80 *z)
{
	if (zSig1) {
		s->float_exception_flags |= float_flag_inexact;
		/* saveFloatx80Internal() */
		floatx80_internal_sign = sign;
		floatx80_internal_exp = zExp;
		floatx80_internal_sig0 = zSig0;
		floatx80_internal_sig1 = zSig1;
		floatx80_internal_precision = s->floatx80_rounding_precision;
		floatx80_internal_mode = s->float_rounding_mode;
		if ((int64_t)zSig1 < 0) {
			++zSig0;
			if (zSig0 == 0) {
				++zExp;
				zSig0 = FK_TOP;
			} else if ((uint64_t)(zSig1 << 1) == 0)
				zSig0 &= ~1ULL;
		}
	}
	z->low = zSig0;
	z->high = (uint16_t)(sign << 15 | zExp);
}

/* shift64ExtraRightJamming(a, 0, n), n > 0 (addFloatx80Sigs()) */
static inline uint64_t fk_shr64x_jam(uint64_t a, int n, uint64_t *lo)
{
	if (n < 64) {
		*lo = fk_shl(a, 64 - n);
		return fk_shr(a, n);
	}
	*lo = n == 64 ? a : (a != 0);
	return 0;
}

/* shift128RightJamming(a, 0, n), n > 0 (subFloatx80Sigs()) */
static inline uint64_t fk_shr128_jam(uint64_t a, int n, uint64_t *lo)
{
	if (n < 64) {
		*lo = fk_shl(a, 64 - n);
		return fk_shr(a, n);
	}
	if (n == 64)
		*lo = a;
	else if (n < 128)
		*lo = fk_shr(a, n - 64) | (fk_shl(a, 128 - n) != 0);
	else
		*lo = a != 0;
	return 0;
}

/* |a| + |b|, both normalized: addFloatx80Sigs() */
static inline __attribute__((always_inline)) int fk_add_sigs(const floatx80 *a, const floatx80 *b, int sign, float_status *s, floatx80 *z)
{
	int32_t aExp = a->high & 0x7fff, bExp = b->high & 0x7fff, zExp;
	uint64_t aSig = a->low, bSig = b->low, zSig0, zSig1;
	int32_t d = aExp - bExp;
	if (d > 0) {
		bSig = fk_shr64x_jam(bSig, d, &zSig1);
		zExp = aExp;
	} else if (d < 0) {
		aSig = fk_shr64x_jam(aSig, -d, &zSig1);
		zExp = bExp;
	} else {
		zSig1 = 0;
		zExp = aExp;
	}
	zSig0 = aSig + bSig;
	if (d == 0 || (int64_t)zSig0 >= 0) {    /* a carry (always when d == 0): shiftRight1 */
		zSig1 = zSig0 << 63 | (zSig1 != 0);
		zSig0 = zSig0 >> 1 | FK_TOP;
		++zExp;
	}
	if (zExp > 0x7ffd)
		return 0;
	fk_round80(sign, zExp, zSig0, zSig1, s, z);
	return 1;
}

/* |a| - |b|, both normalized: subFloatx80Sigs() + normalizeRoundAndPackFloatx80() */
static inline __attribute__((always_inline)) int fk_sub_sigs(const floatx80 *a, const floatx80 *b, int sign, float_status *s, floatx80 *z)
{
	int32_t aExp = a->high & 0x7fff, bExp = b->high & 0x7fff, zExp;
	uint64_t aSig = a->low, bSig = b->low, zSig0, zSig1;
	int32_t d = aExp - bExp;
	if (d > 0) {
		bSig = fk_shr128_jam(bSig, d, &zSig1);
		zSig0 = aSig - bSig - (zSig1 != 0);     /* sub128(aSig, 0, bSig, zSig1) */
		zSig1 = -zSig1;
		zExp = aExp;
	} else if (d < 0) {
		aSig = fk_shr128_jam(aSig, -d, &zSig1);
		zSig0 = bSig - aSig - (zSig1 != 0);     /* sub128(bSig, 0, aSig, zSig1) */
		zSig1 = -zSig1;
		zExp = bExp;
		sign ^= 1;
	} else {
		zSig1 = 0;
		if (bSig < aSig)
			zSig0 = aSig - bSig;
		else if (aSig < bSig) {
			zSig0 = bSig - aSig;
			sign ^= 1;
		} else
			return 0;               /* an exact zero: the rounding mode decides its sign */
		zExp = aExp;
	}
	/* normalizeRoundAndPackFloatx80() */
	if (zSig0 == 0) {
		zSig0 = zSig1;
		zSig1 = 0;
		zExp -= 64;
	}
	unsigned n = fk_clz64(zSig0);
	if (n) {
		zSig0 = fk_shl(zSig0, n) | fk_shr(zSig1, 64 - n);
		zSig1 = fk_shl(zSig1, n);
	}
	zExp -= n;
	if (zExp < 1 || zExp > 0x7ffd)
		return 0;
	fk_round80(sign, zExp, zSig0, zSig1, s, z);
	return 1;
}

/* fk_add_n(), fk_mul_n(): for a caller that checked fk_normal() of both operands itself */
static inline int fk_add_n(const floatx80 *a, const floatx80 *b, float_status *s, floatx80 *z)
{
	if (!fk_mode_ok(s))
		return 0;
	int as = a->high >> 15;
	return as == b->high >> 15 ? fk_add_sigs(a, b, as, s, z) : fk_sub_sigs(a, b, as, s, z);
}

static inline int fk_add(const floatx80 *a, const floatx80 *b, float_status *s, floatx80 *z)
{
	if (!fk_normal(a) || !fk_normal(b) || !fk_mode_ok(s))
		return 0;
	int as = a->high >> 15;
	return as == b->high >> 15 ? fk_add_sigs(a, b, as, s, z) : fk_sub_sigs(a, b, as, s, z);
}

/* the 128-bit product of two 64-bit numbers (mul64To128()); FPE_HWMUL (the Hazard3 build,
 * rv/build.sh): the multiplier of fpu_rv_h3.v at $30000000 */
static inline void fk_mul64(uint64_t a, uint64_t b, uint64_t *hi, uint64_t *lo)
{
#ifdef FPE_HWMUL
	volatile uint32_t *m = (volatile uint32_t *)0x30000000;
	m[0] = (uint32_t)a; m[1] = (uint32_t)(a >> 32);
	m[2] = (uint32_t)b; m[3] = (uint32_t)(b >> 32);
	uint32_t p0 = m[0], p1 = m[1], p2 = m[2], p3 = m[3];
	*lo = (uint64_t)p1 << 32 | p0;
	*hi = (uint64_t)p3 << 32 | p2;
	return;
#endif
	uint32_t a0 = (uint32_t)a, a1 = (uint32_t)(a >> 32), b0 = (uint32_t)b, b1 = (uint32_t)(b >> 32);
	uint64_t p00 = (uint64_t)a0 * b0, p01 = (uint64_t)a0 * b1;
	uint64_t p10 = (uint64_t)a1 * b0, p11 = (uint64_t)a1 * b1;
	uint64_t mid = (p00 >> 32) + (uint32_t)p01 + (uint32_t)p10;
	*lo = mid << 32 | (uint32_t)p00;
	*hi = p11 + (p01 >> 32) + (p10 >> 32) + (mid >> 32);
}

static inline int fk_mul_n(const floatx80 *a, const floatx80 *b, float_status *s, floatx80 *z);

static inline int fk_mul(const floatx80 *a, const floatx80 *b, float_status *s, floatx80 *z)
{
	if (!fk_normal(a) || !fk_normal(b))
		return 0;
	return fk_mul_n(a, b, s, z);
}

static inline int fk_mul_n(const floatx80 *a, const floatx80 *b, float_status *s, floatx80 *z)
{
	if (!fk_mode_ok(s))
		return 0;
	int32_t zExp = (a->high & 0x7fff) + (b->high & 0x7fff) - 0x3ffe;
	uint64_t zSig0, zSig1;
	fk_mul64(a->low, b->low, &zSig0, &zSig1);
	if ((int64_t)zSig0 > 0) {                       /* 0 < (int64_t)zSig0: shortShift128Left 1 */
		zSig0 = zSig0 << 1 | zSig1 >> 63;
		zSig1 <<= 1;
		--zExp;
	}
	if (zExp < 1 || zExp > 0x7ffd)
		return 0;
	fk_round80((a->high ^ b->high) >> 15 & 1, zExp, zSig0, zSig1, s, z);
	return 1;
}

#endif
