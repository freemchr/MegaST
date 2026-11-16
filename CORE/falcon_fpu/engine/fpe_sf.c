/* fpe_sf.c - Hatari's softfloat back-end (src/cpu/fpp_softfloat.c, included unmodified) and the
 * arithmetic part of the engine's short path for the common register-to-register instructions.
 *
 * fpe_sf_exec() does what fpuop_arithmetic() (fpp.c), fp_arithmetic() and the back-end functions
 * they call do for
 *   FMOVE $00, FSQRT $04/$05, FABS $18, FNEG $1A, FDIV $20, FADD $22, FMUL $23, FSUB $28,
 *   FCMP $38/$39/$3C/$3D and FTST $3A/$3B/$3E/$3F (the FPCR rounding precision), with the source
 *   a register (opclass 000) or a memory operand .L .S .X .W .D .B (opclass 010, not packed),
 * and for FMOVE FPn,<ea> .L .S .X .W .D .B (opclass 011, not packed),
 * from fpsr_clear_status() on, in the same order and with the same softfloat functions:
 *   fpsr_clear_status()       FPSR &= $0FFF00F8, softfloat exception flags = 0
 *   source                    a copy of FPm, or the operand converted as get_fp_value() does:
 *                             .L .W .B int32_to_floatx80 (fpset()), .S/.D to_single()/to_double()
 *                             (float32/64_to_floatx80_allowunnormal), .X the bits (to_exten())
 *   normalization             an unnormal or denormal source is normalized (not after .L .W .B),
 *                             the destination only when fp_is_dyadic() says so (FCMP: only
 *                             opmode $38) (normalize_or_fault_if_no_denormal_support[_dst]() on
 *                             a 68882: support_denormals is set by this back-end)
 *   the operation             floatx80_*(dst, src, &fs) as fp_add() etc. with PREC_NORMAL
 *   fpsr_set_result_always()  FPSR &= $00FFFFF8, N if the result is negative
 *   fpsr_set_result()         NAN, else Z, else I
 *   fpsr_make_status()        fp_get_status() and the accrued byte (updateaccrued())
 *   the register write        FPn = result, not for FCMP and FTST (fp_arithmetic() returns
 *                             false for them, and for an enabled exception, which is excluded
 *                             here: FPCR enable byte 0)
 * FMOVE out (fpuop_arithmetic2() case 3, put_fp_value2()): fpsr_clear_status(), a copy of FPn
 * normalized as above, converted (to_int() floatx80_to_int32/16/8, from_single(), from_double(),
 * from_exten() floatx80_to_floatx80), fpsr_make_status(); the condition codes stay.  The result
 * goes to out[] in memory order, as fpe_exec() returns it from its buffer at (A0) = 0.
 * under the conditions of fpe_fast_arith() (fpe_fpp.c: no exception pending or enabled, 68030 +
 * 68882, opmode below $40), which it checks itself, and with fpe_exec()'s start (the event flags
 * cleared) and fpuop_arithmetic()'s (fpu_state, fp_exception, fpu_mmu_fixup).  fpe_exec() calls
 * it first, before its own set-up.  Without it, every step goes through fpp.c's function pointers
 * and copies of fpdata, and fpe_exec() saves and sets up far more than this needs: on the FPGA's
 * RISC-V that cost more than the operation itself.
 * fpe_sf_off = 1 turns it off (the engine then runs fpp.c's own path; fpe_shortcheck.c compares
 * the two).  A command it does not take goes on to fpe_exec_full(); returns what fpe_exec() does.
 * MEGA65 port done by Chris Freeman in 2026, licensed under GPL v3 */
#include "fpp_softfloat.c"

/* the FPSR condition code and accrued exception bits, as fpp.c defines them (not in fpp.h) */
#define FPSR_CC_N       0x08000000
#define FPSR_CC_Z       0x04000000
#define FPSR_CC_I       0x02000000
#define FPSR_CC_NAN     0x01000000
#define FPSR_AE_IOP     0x00000080
#define FPSR_AE_OVFL    0x00000040
#define FPSR_AE_UNFL    0x00000020
#define FPSR_AE_DZ      0x00000010
#define FPSR_AE_INEX    0x00000008

#include "fpe_internal.h"
#include "fpe_fastk.h"
#ifdef FPE_WRAP                 /* fpe_fast.c is in front of floatx80_add/sub/mul (rv/build.sh) */
floatx80 __real_floatx80_add(floatx80 a, floatx80 b, float_status *status);
floatx80 __real_floatx80_sub(floatx80 a, floatx80 b, float_status *status);
floatx80 __real_floatx80_mul(floatx80 a, floatx80 b, float_status *status);
#define SF_ADD __real_floatx80_add
#define SF_SUB __real_floatx80_sub
#define SF_MUL __real_floatx80_mul
#else
#define SF_ADD floatx80_add
#define SF_SUB floatx80_sub
#define SF_MUL floatx80_mul
#endif

int fpe_sf_off;
extern bool *const fpe_mmu_fixup;       /* fpe_fpp.c: fpp.c's fpu_mmu_fixup */

static const uint8_t fsize[8] = { 4, 4, 12, 0, 2, 8, 1, 0 };   /* L S X P W D B -, 0: not here */

static inline uae_u32 be32(const uint8_t *p) { return (uae_u32)p[0] << 24 | p[1] << 16 | p[2] << 8 | p[3]; }
static inline void put32(uint8_t *p, uae_u32 v) { p[0] = v >> 24; p[1] = v >> 16; p[2] = v >> 8; p[3] = v; }
static inline floatx80 norm(floatx80 a)
{
	if ((uae_u32)(a.low >> 32) & 0x80000000u)       /* integer bit set: neither unnormal nor denormal */
		return a;
	return (floatx80_is_unnormal(a) || floatx80_is_denormal(a)) ? floatx80_normalize(a) : a;
}

/* roundAndPackFloatx80(prec, sign, exp, sig, 0, &fs), as floatx80_move/abs/neg call it for a
 * number with 0 < exp < $7FFF, returns packFloatx80(sign, exp, sig) and raises nothing when sig
 * is normalized, the bits below the rounding precision are zero (nothing to round, no carry) and
 * exp is inside the range of the precision (no overflow, no underflow):
 *   80 (and any other value: precision80)  exp $0001-$7FFE
 *   64  sig & $7FF = 0,        exp $3C01-$43FE (expOffset $3C00)
 *   32  sig & $FF_FFFFFFFF = 0, exp $3F81-$407E (expOffset $3F80) */
static inline int exact(floatx80 a)
{
	unsigned e = a.high & 0x7fff;
	if (!((uae_u32)(a.low >> 32) & 0x80000000u))
		return 0;
	switch (fs.floatx80_rounding_precision) {
	case 64: return ((uae_u32)a.low & 0x7ff) == 0 && e >= 0x3c01 && e <= 0x43fe;
	case 32: return (a.low & 0xffffffffffULL) == 0 && e >= 0x3f81 && e <= 0x407e;
	default: return e >= 1 && e <= 0x7ffe;
	}
}

/* fpsr_make_status(): fp_get_status(), then the accrued exception byte */
static uae_u32 make_status(uae_u32 fpsr)
{
	unsigned f = fs.float_exception_flags;
	if (!f)         /* the exception byte is clear (fpsr_clear_status()): nothing to accrue */
		return fpsr;
	if (f & float_flag_signaling) fpsr |= FPSR_SNAN;
	if (f & float_flag_invalid)   fpsr |= FPSR_OPERR;
	if (f & float_flag_divbyzero) fpsr |= FPSR_DZ;
	if (f & float_flag_overflow)  fpsr |= FPSR_OVFL;
	if (f & float_flag_underflow) fpsr |= FPSR_UNFL;
	if (f & float_flag_inexact)   fpsr |= FPSR_INEX2;
	if (f & float_flag_decimal)   fpsr |= FPSR_INEX1;
	if (fpsr & FPSR_OVFL) fpsr |= FPSR_AE_OVFL;
	if (fpsr & (FPSR_OVFL | FPSR_INEX2 | FPSR_INEX1)) fpsr |= FPSR_AE_INEX;
	if (fpsr & (FPSR_BSUN | FPSR_SNAN | FPSR_OPERR)) fpsr |= FPSR_AE_IOP;
	if ((fpsr & FPSR_UNFL) && (fpsr & FPSR_INEX2)) fpsr |= FPSR_AE_UNFL;
	if (fpsr & FPSR_DZ) fpsr |= FPSR_AE_DZ;
	return fpsr;
}

int fpe_exec_full(uae_u16 cmd, const uint8_t *in, int in_len, uae_u16 aux, uae_u32 iaddr,
                  uint8_t *out, int *out_len);         /* fpe_shim.c */

/* the opmodes taken, bit n = opmode n: $00 $04 $05 $18 $1A | $20 $22 $23 $28 $38-$3F */
#define SF_OPS ((uint64_t)0xff00010du << 32 | 0x05000031u)

/* called by fpe_exec() with all its arguments; what it does not take goes on to fpe_exec_full()
 * (a tail call: nothing to save around it) */
int fpe_sf_exec(uae_u16 extra, const uint8_t *in, int in_len, uae_u16 aux, uae_u32 iaddr,
                uint8_t *out, int *out_len)
{
	unsigned cls = extra >> 13, fmt = (extra >> 10) & 7, op = extra & 0x7f;
	if (regs.fp_exp_pend || regs.fp_unimp_pend || (regs.fpcr & 0xff00) ||
	    currprefs.fpu_model != 68882 || currprefs.cpu_model != 68030 || fpe_sf_off)
		goto full;
	if (cls == 3) {                                         /* FMOVE FPn,<ea> */
		if (!fsize[fmt] || in_len != 0)
			goto full;
	} else {
		if (cls == 0) {
			if (in_len != 0) goto full;
		} else if (cls == 2) {
			if (!fsize[fmt] || in_len != fsize[fmt]) goto full;
		} else
			goto full;
		if (op >= 0x40 || !((SF_OPS >> op) & 1))
			goto full;
	}

	/* fpe_exec(): fpe_shim_clear_events() (no event can happen here) */
	fpe_ev_unimpl = fpe_ev_exc = fpe_ev_fmt = fpe_ev_pre = 0;
	fpe_ev_vector = fpe_ev_opcode = 0;
	/* fpuop_arithmetic() */
	regs.fpu_state = 1;
	regs.fp_exception = false;
	*fpe_mmu_fixup = false;

	int reg = (extra >> 7) & 7;
	uae_u32 fpsr = regs.fpsr & 0x0fff00f8;          /* fpsr_clear_status() */
	fs.float_exception_flags = 0;

	if (cls == 3) {
		floatx80 v = norm(regs.fp[reg].fpx);
		switch (fmt) {
		case 0: put32(out, (uae_u32)floatx80_to_int32(v, &fs)); break;
		case 1: put32(out, floatx80_to_float32(v, &fs)); break;
		case 2: {
			floatx80 x = floatx80_to_floatx80(v, &fs);
			put32(out, (uae_u32)(x.high << 16)); put32(out + 4, x.low >> 32); put32(out + 8, (uae_u32)x.low);
			break;
		}
		case 4: { uae_s16 w = (uae_s16)floatx80_to_int16(v, &fs); out[0] = w >> 8; out[1] = w; break; }
		case 5: { float64 d = floatx80_to_float64(v, &fs); put32(out, d >> 32); put32(out + 4, (uae_u32)d); break; }
		default: out[0] = (uae_u8)(uae_s8)floatx80_to_int8(v, &fs); break;
		}
		regs.fpsr = make_status(fpsr);
		if (out_len) *out_len = fsize[fmt];
		return 0;
	}

	floatx80 src;
	if (cls == 0)
		src = norm(regs.fp[fmt].fpx);
	else switch (fmt) {
	case 0: src = int32_to_floatx80((uae_s32)be32(in)); break;
	case 1: src = norm(float32_to_floatx80_allowunnormal(be32(in), &fs)); break;
	case 2: src.high = (uae_u16)(be32(in) >> 16); src.low = (uint64_t)be32(in + 4) << 32 | be32(in + 8);
		src = norm(src); break;
	case 4: src = int32_to_floatx80((uae_s16)(in[0] << 8 | in[1])); break;
	case 5: src = norm(float64_to_floatx80_allowunnormal((uint64_t)be32(in) << 32 | be32(in + 4), &fs)); break;
	default: src = int32_to_floatx80((uae_s8)in[0]); break;
	}
	/* fp_is_dyadic() (fpp.c): of the FCMP opmodes only $38 counts, so the destination of the
	 * aliases $39, $3C and $3D is not normalized */
	floatx80 dst, r;
	if (op & 0x20) {                                /* dyadic: FDIV FADD FMUL FSUB FCMP */
		dst = regs.fp[reg].fpx;
		if ((op & 0x30) == 0x20 || op == 0x38)
			dst = norm(dst);
	}

	int write = 1;
	switch (op) {
	/* FMOVE, FABS, FNEG of a normalized number that the precision holds: what their
	 * roundAndPackFloatx80() returns (exact()) */
	case 0x00: r = exact(src) ? src : floatx80_move(src, &fs); break;
	case 0x04: case 0x05: r = floatx80_sqrt(src, &fs); break;
	case 0x18: if (exact(src)) { r = src; r.high &= 0x7fff; } else r = floatx80_abs(src, &fs); break;
	case 0x1a: if (exact(src)) { r = src; r.high ^= 0x8000; } else r = floatx80_neg(src, &fs); break;
	case 0x20: r = floatx80_div(dst, src, &fs); break;
	/* fpe_quick() came first and left these to softfloat (operands or modes the kernel does not
	 * take): with -Wl,--wrap (FPE_WRAP, rv/build.sh) straight to softfloat, past fpe_fast.c */
	case 0x22: r = SF_ADD(dst, src, &fs); break;
	case 0x23: r = SF_MUL(dst, src, &fs); break;
	case 0x28: r = SF_SUB(dst, src, &fs); break;
	case 0x38: case 0x39: case 0x3c: case 0x3d:
		r = floatx80_cmp(dst, src, &fs); write = 0; break;
	default:   /* FTST */
		r = floatx80_tst(src, &fs); write = 0; break;
	}

	/* fpsr_set_result_always(), fpsr_set_result() */
	fpsr &= 0x00fffff8;
	if (floatx80_is_negative(r)) fpsr |= FPSR_CC_N;
	if (floatx80_is_any_nan(r)) fpsr |= FPSR_CC_NAN;
	else if (floatx80_is_zero(r)) fpsr |= FPSR_CC_Z;
	else if (floatx80_is_infinity(r)) fpsr |= FPSR_CC_I;
	regs.fpsr = make_status(fpsr);

	if (write)
		regs.fp[reg].fpx = r;
	if (out_len) *out_len = 0;
	return 0;
full:
	return fpe_exec_full(extra, in, in_len, aux, iaddr, out, out_len);
}

/* fpe_quick(): before fpe_sf_exec(), a small function for the most common forms, so that they do
 * not pay for the set-up of the big one (its frame, the copies of 80-bit values the calling
 * convention passes through memory):
 *   FMOVE, FADD, FMUL, FSUB with the source a register (opclass 000) or a memory operand
 *   .L .W .B (not 0), .S .D (normalized numbers) or .X (opclass 010), into FPn, and
 *   FMOVE FPn,<ea> .L .S .X .D (opclass 011, q_out()),
 * when the source and for FADD/FMUL/FSUB the destination are normalized (norm() leaves them as
 * they are), FMOVE's source is exact() and the kernel of fpe_fastk.h takes the operation. It
 * does what fpe_sf_exec() does for them: the conversions are those of int32_to_floatx80() and
 * float32/64_to_floatx80_allowunnormal() for these values; the results are finite, nonzero and
 * not NaN, so of the condition codes only N can be set. Returns -1 for anything else; what it
 * may have changed by then (the event flags, fpu_state, fp_exception, fpu_mmu_fixup, the
 * softfloat flags) fpe_sf_exec() sets again to the same values. */
uint32_t fpe_quick_fpsr;                         /* the FPSR after fpe_quick() took a command */
uint8_t fpe_quick_tried;                         /* fpe_quick.h */

static inline floatx80 q_int(int32_t a)                 /* int32_to_floatx80(), a != 0 */
{
	floatx80 z;
	uint32_t m = a < 0 ? -(uint32_t)a : (uint32_t)a;
	unsigned n = fk_clz64(m);                       /* countLeadingZeros32() + 32 */
	z.low = fk_shl(m, n);
	z.high = (uint16_t)((a < 0) << 15 | (0x403e - n));
	return z;
}

/* FMOVE FPn,<ea> .L .S .X .D of a normalized FPn with rounding to nearest and a value the
 * format holds without overflow or underflow: what fpe_sf_exec() does through
 * floatx80_to_int32() (shift64RightJamming() + roundAndPackInt32()), floatx80_to_float32/64()
 * (shift64RightJamming() + the normal case of roundAndPackFloat32/64(): only the inexact flag) and
 * floatx80_to_floatx80() (the value itself); the condition codes stay */
static int q_out(uae_u16 extra, unsigned fmt, int in_len, uint8_t *out, int *out_len)
{
	const floatx80 *v = &regs.fp[(extra >> 7) & 7].fpx;
	uint64_t m = v->low;
	unsigned e = v->high & 0x7fff, sign = v->high >> 15;
	unsigned inexact = 0;
	if (in_len != 0 || !((uint32_t)(m >> 32) >> 31) || e == 0 || e == 0x7fff)
		return -1;
	if (fmt != 2 && fs.float_rounding_mode != float_round_nearest_even)
		return -1;
	switch (fmt) {
	case 0: {                                       /* .L, |v| < 2^31 */
		if (e > 0x401d) return -1;
		int n = 0x4037 - (int)e;                /* >= 26 */
		uint64_t a = n < 64 ? fk_shr(m, n) | (fk_shl(m, 64 - n) != 0) : (m != 0);
		unsigned rb = (unsigned)a & 0x7f;
		a = (a + 0x40) >> 7;
		if (rb == 0x40) a &= ~1ULL;
		int32_t z = (int32_t)(uint32_t)a;
		if (sign) z = (int32_t)(0u - (uint32_t)z);
		if ((a >> 32) || (z && ((z < 0) ^ sign)))
			return -1;                      /* the invalid case */
		inexact = rb;
		put32(out, (uae_u32)z);
		break;
	}
	case 1: {                                       /* .S, exponent $3F81-$407B */
		if (e < 0x3f81 || e > 0x407b) return -1;
		uint32_t a = (uint32_t)fk_shr(m, 33) | ((m & 0x1ffffffffULL) != 0);
		unsigned rb = a & 0x7f;
		a = (a + 0x40) >> 7;
		if (rb == 0x40) a &= ~1u;
		inexact = rb;
		put32(out, (sign << 31) + ((e - 0x3f81) << 23) + a);
		break;
	}
	case 5: {                                       /* .D, exponent $3C01-$43FC */
		if (e < 0x3c01 || e > 0x43fc) return -1;
		uint64_t a = m >> 1 | (m & 1);
		unsigned rb = (unsigned)a & 0x3ff;
		a = (a + 0x200) >> 10;
		if (rb == 0x200) a &= ~1ULL;
		inexact = rb;
		uint64_t d = ((uint64_t)sign << 63) + ((uint64_t)(e - 0x3c01) << 52) + a;
		put32(out, (uae_u32)(d >> 32));
		put32(out + 4, (uae_u32)d);
		break;
	}
	default:                                        /* .X */
		put32(out, (uae_u32)v->high << 16);
		put32(out + 4, (uae_u32)(m >> 32));
		put32(out + 8, (uae_u32)m);
		break;
	}
	/* fpe_exec(), fpuop_arithmetic(), fpsr_clear_status(), fpsr_make_status() */
	fpe_ev_unimpl = fpe_ev_exc = fpe_ev_fmt = fpe_ev_pre = 0;
	fpe_ev_vector = fpe_ev_opcode = 0;
	regs.fpu_state = 1;
	regs.fp_exception = false;
	*fpe_mmu_fixup = false;
	fs.float_exception_flags = inexact ? float_flag_inexact : 0;
	fpe_quick_fpsr = regs.fpsr = make_status(regs.fpsr & 0x0fff00f8);
	if (out_len) *out_len = fsize[fmt];
	return 0;
}

static inline __attribute__((always_inline)) int q_work(uae_u16 extra, const uint8_t *in, int in_len, uint8_t *out, int *out_len, unsigned zs);

static inline const floatx80 *neg(const floatx80 *a, floatx80 *t)   /* -a, in t */
{
	t->low = a->low;
	t->high = a->high ^ 0x8000;
	return t;
}

/* FMOVE of a zero (sign sg): into FPn from a register or memory (FPSR: the condition codes Z and
 * N for -0, as fpsr_set_result() sets them), or FPn to .L .S .X .D: 0, the signed zero, the
 * register itself (floatx80_to_int32/float32/float64() of a zero: no flags; the condition codes
 * stay) */
static int q_zero(uae_u16 extra, unsigned cls, unsigned fmt, unsigned sg, int in_len, uint8_t *out, int *out_len)
{
	floatx80 *d = &regs.fp[(extra >> 7) & 7].fpx;
	if (cls == 3) {
		if (in_len != 0)
			return -1;
		switch (fmt) {
		case 0: put32(out, 0); break;
		case 1: put32(out, (uae_u32)sg << 31); break;
		case 5: put32(out, (uae_u32)sg << 31); put32(out + 4, 0); break;
		default: put32(out, (uae_u32)d->high << 16); put32(out + 4, 0); put32(out + 8, 0); break;
		}
	} else if (cls == 0 && in_len != 0)
		return -1;
	/* fpe_exec(), fpuop_arithmetic(), fpsr_clear_status(), fpsr_set_result(), fpsr_make_status() */
	fpe_ev_unimpl = fpe_ev_exc = fpe_ev_fmt = fpe_ev_pre = 0;
	fpe_ev_vector = fpe_ev_opcode = 0;
	regs.fpu_state = 1;
	regs.fp_exception = false;
	*fpe_mmu_fixup = false;
	fs.float_exception_flags = 0;
	if (cls == 3) {
		fpe_quick_fpsr = regs.fpsr = make_status(regs.fpsr & 0x0fff00f8);
		if (out_len) *out_len = fsize[fmt];
		return 0;
	}
	d->low = 0;
	d->high = (uint16_t)(sg << 15);
	fpe_quick_fpsr = regs.fpsr = make_status((regs.fpsr & 0x00ff00f8) | FPSR_CC_Z | (sg ? FPSR_CC_N : 0));
	if (out_len) *out_len = 0;
	return 0;
}

/* the operand classes first, with nothing else set up: an infinity, NaN, denormal or unnormal
 * operand, or a zero in FADD/FMUL/FSUB (all go to fpe_sf_exec()), costs only these loads and
 * compares here. q_work() relies on them: the kernel without its own checks (fk_add_n(),
 * fk_mul_n()). FMOVE of a zero is taken (zs: 1 = +0, 2 = -0). */
static inline int q_zero_x(const floatx80 *v)          /* 1 = +0, 2 = -0, else 0 */
{
	return !(v->high & 0x7fff) && !v->low ? 1 + (v->high >> 15) : 0;
}

int fpe_quick(uae_u16 extra, const uint8_t *in, int in_len, uint8_t *out, int *out_len)
{
	unsigned cls = extra >> 13, fmt = (extra >> 10) & 7, op = extra & 0x7f;
	unsigned zs = 0;
	const floatx80 *r = &regs.fp[(extra >> 7) & 7].fpx;
	if (cls == 3) {                                 /* FMOVE out: the source */
		if (!fk_normal(r) && !(zs = q_zero_x(r)))
			return -1;
	} else if (op != 0x00 && !fk_normal(r))         /* the destination */
		return -1;
	if (cls == 0) {
		const floatx80 *v = &regs.fp[fmt].fpx;
		if (!fk_normal(v) && (op != 0x00 || !(zs = q_zero_x(v))))
			return -1;
	} else if (cls == 2) {
		if (in_len != fsize[fmt])
			return -1;
		unsigned e;
		switch (fmt) {
		case 0: if (!be32(in)) zs = 1; break;
		case 4: if (!(in[0] | in[1])) zs = 1; break;
		case 6: if (!in[0]) zs = 1; break;
		case 1:
			e = (in[0] << 1 | in[1] >> 7) & 0xff;
			if (e == 0 && !((in[1] & 0x7f) | in[2] | in[3])) zs = 1 + (in[0] >> 7);
			else if (e == 0 || e == 0xff) return -1;
			break;
		case 5:
			e = (in[0] << 4 | in[1] >> 4) & 0x7ff;
			if (e == 0 && !((in[1] & 0xf) | in[2] | in[3] | be32(in + 4))) zs = 1 + (in[0] >> 7);
			else if (e == 0 || e == 0x7ff) return -1;
			break;
		case 2:
			e = (in[0] << 8 | in[1]) & 0x7fff;
			if (e == 0 && !(be32(in + 4) | be32(in + 8))) zs = 1 + (in[0] >> 7);
			else if (e == 0 || e == 0x7fff || !(in[4] & 0x80)) return -1;
			break;
		default: return -1;
		}
		if (zs && op != 0x00)
			return -1;
	}
	return q_work(extra, in, in_len, out, out_len, zs);
}

static inline __attribute__((always_inline)) int q_work(uae_u16 extra, const uint8_t *in, int in_len, uint8_t *out, int *out_len, unsigned zs)
{
	unsigned cls = extra >> 13, fmt = (extra >> 10) & 7, op = extra & 0x7f;
	floatx80 src, z;
	const floatx80 *s;
	if (cls == 3 ? !((0x27u >> fmt) & 1) :         /* FMOVE FPn,<ea> .L .S .X .D */
	    ((op != 0x00 && op != 0x22 && op != 0x23 && op != 0x28) || (cls != 0 && cls != 2)))
		return -1;
	if (regs.fp_exp_pend || regs.fp_unimp_pend || (regs.fpcr & 0xff00) ||
	    currprefs.fpu_model != 68882 || currprefs.cpu_model != 68030 || fpe_sf_off)
		return -1;
	if (zs)
		return q_zero(extra, cls, fmt, zs - 1, in_len, out, out_len);
	if (cls == 3)
		return q_out(extra, fmt, in_len, out, out_len);
	if (cls == 0) {
		if (in_len != 0) return -1;
		s = &regs.fp[fmt].fpx;
	} else {
		if (!fsize[fmt] || in_len != fsize[fmt]) return -1;
		switch (fmt) {
		case 0: { int32_t v = (int32_t)be32(in); if (!v) return -1; src = q_int(v); break; }
		case 4: { int32_t v = (int16_t)(in[0] << 8 | in[1]); if (!v) return -1; src = q_int(v); break; }
		case 6: { int32_t v = (int8_t)in[0]; if (!v) return -1; src = q_int(v); break; }
		case 1: {
			uae_u32 f = be32(in);
			unsigned e = (f >> 23) & 0xff;
			if (e == 0 || e == 0xff) return -1;
			src.high = (uint16_t)((f >> 31) << 15 | (e + 0x3f80));
			src.low = (uint64_t)((f & 0x7fffff) | 0x800000) << 40;
			break;
		}
		case 5: {
			uae_u32 hi = be32(in), lo = be32(in + 4);
			unsigned e = (hi >> 20) & 0x7ff;
			if (e == 0 || e == 0x7ff) return -1;
			src.high = (uint16_t)((hi >> 31) << 15 | (e + 0x3c00));
			src.low = ((uint64_t)((hi & 0xfffff) | 0x100000) << 32 | lo) << 11;
			break;
		}
		default:        /* .X */
			src.high = (uae_u16)(be32(in) >> 16);
			src.low = (uint64_t)be32(in + 4) << 32 | be32(in + 8);
			break;
		}
		s = &src;
	}
	if (op == 0x00 && !exact(*s))
		return -1;

	/* fpe_exec(), fpuop_arithmetic(), fpsr_clear_status() as in fpe_sf_exec() */
	fpe_ev_unimpl = fpe_ev_exc = fpe_ev_fmt = fpe_ev_pre = 0;
	fpe_ev_vector = fpe_ev_opcode = 0;
	regs.fpu_state = 1;
	regs.fp_exception = false;
	*fpe_mmu_fixup = false;
	fs.float_exception_flags = 0;

	floatx80 *d = &regs.fp[(extra >> 7) & 7].fpx;
	uint64_t zl;
	unsigned zh;
	if (op == 0x00) {
		zl = s->low;
		zh = s->high;
	} else if (op == 0x23 ? fk_mul_n(d, s, &fs, &z) : fk_add_n(d, op == 0x22 ? s : neg(s, &src), &fs, &z)) {
		/* FSUB as FADD of -source: floatx80_sub() and floatx80_add() pick addFloatx80Sigs() or
		 * subFloatx80Sigs() by the same sign test, with the same signs (one copy of the kernel) */
		zl = z.low;
		zh = z.high;
	} else
		return -1;
	/* fpsr_clear_status(), fpsr_set_result_always(), fpsr_set_result(), fpsr_make_status() */
	uae_u32 fpsr = regs.fpsr & 0x00ff00f8;
	if (zh & 0x8000) fpsr |= FPSR_CC_N;
	fpe_quick_fpsr = regs.fpsr = make_status(fpsr);
	d->low = zl;
	d->high = (uint16_t)zh;
	if (out_len) *out_len = 0;
	return 0;
}
