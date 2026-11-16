/* fpe_fast.c - floatx80_add/sub/mul in front of Hatari's softfloat: the kernel of fpe_fastk.h for
 * the common case, softfloat for everything else, bit for bit the same results and records.
 * Linked with -Wl,--wrap=floatx80_add,--wrap=floatx80_sub,--wrap=floatx80_mul (rv/build.sh), so
 * every caller outside softfloat.c gets them: fpp.c's path and the FPSP functions of
 * softfloat_fpsp.c (FSIN, FETOX, ...: their steps are mostly these). The short path (fpe_sf.c)
 * calls the kernel directly. fpe_fastcheck.c compares them with softfloat on the host.
 * MEGA65 port done by Chris Freeman in 2026, licensed under GPL v3 */
#include "fpe_fastk.h"

floatx80 __real_floatx80_add(floatx80 a, floatx80 b, float_status *status);
floatx80 __real_floatx80_sub(floatx80 a, floatx80 b, float_status *status);
floatx80 __real_floatx80_mul(floatx80 a, floatx80 b, float_status *status);

floatx80 __wrap_floatx80_add(floatx80 a, floatx80 b, float_status *s)
{
	floatx80 z;
	return fk_add(&a, &b, s, &z) ? z : __real_floatx80_add(a, b, s);
}

/* a - b as a + (-b): floatx80_sub() and floatx80_add() choose addFloatx80Sigs() or
 * subFloatx80Sigs() by the same sign test with the same signs (one copy of the kernel's code) */
floatx80 __wrap_floatx80_sub(floatx80 a, floatx80 b, float_status *s)
{
	floatx80 z, nb = b;
	nb.high ^= 0x8000;
	return fk_add(&a, &nb, s, &z) ? z : __real_floatx80_sub(a, b, s);
}

floatx80 __wrap_floatx80_mul(floatx80 a, floatx80 b, float_status *s)
{
	floatx80 z;
	return fk_mul(&a, &b, s, &z) ? z : __real_floatx80_mul(a, b, s);
}
