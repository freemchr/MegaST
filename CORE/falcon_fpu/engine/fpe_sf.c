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
 * the two).  Returns 0 when it does not take the command.
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

int fpe_sf_off;
extern bool *const fpe_mmu_fixup;       /* fpe_fpp.c: fpp.c's fpu_mmu_fixup */

static const uint8_t fsize[8] = { 4, 4, 12, 0, 2, 8, 1, 0 };   /* L S X P W D B -, 0: not here */

static inline uae_u32 be32(const uint8_t *p) { return (uae_u32)p[0] << 24 | p[1] << 16 | p[2] << 8 | p[3]; }
static inline void put32(uint8_t *p, uae_u32 v) { p[0] = v >> 24; p[1] = v >> 16; p[2] = v >> 8; p[3] = v; }
static inline floatx80 norm(floatx80 a)
{
	return (floatx80_is_unnormal(a) || floatx80_is_denormal(a)) ? floatx80_normalize(a) : a;
}

/* fpsr_make_status(): fp_get_status(), then the accrued exception byte */
static uae_u32 make_status(uae_u32 fpsr)
{
	unsigned f = fs.float_exception_flags;
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

int fpe_sf_exec(uae_u16 extra, const uint8_t *in, int in_len, uint8_t *out, int *out_len)
{
	unsigned cls = extra >> 13, fmt = (extra >> 10) & 7, op = extra & 0x7f;
	if (regs.fp_exp_pend || regs.fp_unimp_pend || (regs.fpcr & 0xff00) ||
	    currprefs.fpu_model != 68882 || currprefs.cpu_model != 68030 || fpe_sf_off)
		return 0;
	if (cls == 3) {                                         /* FMOVE FPn,<ea> */
		if (!fsize[fmt] || in_len != 0)
			return 0;
	} else {
		if (cls == 0) {
			if (in_len != 0) return 0;
		} else if (cls == 2) {
			if (!fsize[fmt] || in_len != fsize[fmt]) return 0;
		} else
			return 0;
		switch (op) {
		case 0x00: case 0x04: case 0x05: case 0x18: case 0x1a: case 0x20: case 0x22: case 0x23:
		case 0x28: case 0x38: case 0x39: case 0x3c: case 0x3d: case 0x3a: case 0x3b: case 0x3e: case 0x3f:
			break;
		default:
			return 0;
		}
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
		*out_len = fsize[fmt];
		return 1;
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
	floatx80 dst = regs.fp[reg].fpx, r;
	if ((op & 0x30) == 0x20 || op == 0x38)
		dst = norm(dst);

	int write = 1;
	switch (op) {
	case 0x00: r = floatx80_move(src, &fs); break;
	case 0x04: case 0x05: r = floatx80_sqrt(src, &fs); break;
	case 0x18: r = floatx80_abs(src, &fs); break;
	case 0x1a: r = floatx80_neg(src, &fs); break;
	case 0x20: r = floatx80_div(dst, src, &fs); break;
	case 0x22: r = floatx80_add(dst, src, &fs); break;
	case 0x23: r = floatx80_mul(dst, src, &fs); break;
	case 0x28: r = floatx80_sub(dst, src, &fs); break;
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
	*out_len = 0;
	return 1;
}
