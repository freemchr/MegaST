/* fpe_quick.h - the engine's quick path (fpe_sf.c) for a caller that knows the request is an
 * execute request: fpe_quick_cmd() is the opcode check of fpe_quick(), inline, so that the
 * commands it never takes do not pay for the call. fpe_quick() returns -1 for what it does not
 * take; when it returns 0 there is no exception enabled, pending or raised (fpu_request()'s flags
 * would all be 0).
 * MEGA65 port done by Chris Freeman in 2026, licensed under GPL v3 */
#ifndef FPE_QUICK_H
#define FPE_QUICK_H
#include <stdint.h>

int fpe_quick(uint16_t extra, const uint8_t *in, int in_len, uint8_t *out, int *out_len);
extern uint32_t fpe_quick_fpsr;     /* the FPSR after fpe_quick() returned 0 */
/* set by a caller that already called fpe_quick() for this request and got -1: the next
 * fpe_exec() does not call it again (and clears it) */
extern uint8_t fpe_quick_tried;

/* FMOVE FADD FMUL FSUB <register, .L .S .X .W .D .B>,FPn; FMOVE FPn,<.L .S .X .D> */
static inline int fpe_quick_cmd(uint16_t cmd)
{
	unsigned cls = cmd >> 13, fmt = (cmd >> 10) & 7, op = cmd & 0x7f;
	if (cls == 3)
		return (0x27u >> fmt) & 1;
	return (cls == 0 || cls == 2) && (op == 0x00 || op == 0x22 || op == 0x23 || op == 0x28);
}
#endif
