/* falcon_fpu on the RISC-V in the FPGA: the MC68882 service of the Falcon core's FPU bridge.
 *
 * On MiSTer, falcon_fpu (../falcon_fpu.c) runs on the ARM and reaches the mailbox in DDR3
 * through /dev/mem. The MEGA65 has no ARM: a PicoRV32 next to the Falcon (fpu_rv.v) runs this
 * program, and the mailbox is a dual-port block RAM that the bridge reaches through its d3
 * port (falcon_system.sv, FALCON_FPU_LOCAL). Same mailbox layout and protocol (VERSION 4),
 * same request execution (fpu_request.h, Hatari's fpp.c + softfloat in engine/), same
 * serve() as falcon_fpu.c without the statistics; there is nothing else to run on this
 * processor, so it polls all the time.
 *
 * Based on falcon_fpu.c of Falcon_MiSTer
 * MEGA65 port done by Chris Freeman in 2026, licensed under GPL v3
 */
#include <stdint.h>
#include <string.h>

#include "fpu_rv.h"
#include "../fpu_request.h"

#define FPU_MAGIC    0x4650u        /* "FP" */
#define FPU_VERSION  4u
#define HB_CYCLES    (RV_CLK_HZ / 100)  /* heartbeat every 10 ms */

enum { O_MAGIC = 0x000, O_HB = 0x002, O_VERSION = 0x004,
       O_RSEQ = 0x100, O_CMD = 0x104, O_RNBYTES = 0x108, O_IADDRL = 0x10C, O_RDATA = 0x110,
       O_STATUS = 0x200, O_ADATA = 0x210 };

static volatile uint8_t *const mb = RV_MAILBOX;

/* aligned 32-bit mailbox access: bytes off..off+3 in memory order (little-endian RISC-V) */
static inline uint32_t rd32(unsigned off) { return *(volatile uint32_t *)(mb + off); }
static inline void wr32(unsigned off, uint32_t v) { *(volatile uint32_t *)(mb + off) = v; }
/* the big-endian 16-bit field at off (lo) or off + 2 (hi) of such a word */
static inline uint16_t f_lo(uint32_t w) { return __builtin_bswap16((uint16_t)w); }
static inline uint16_t f_hi(uint32_t w) { return __builtin_bswap16((uint16_t)(w >> 16)); }
static inline uint32_t fields(uint16_t lo, uint16_t hi)
{
	return (uint32_t)__builtin_bswap16(lo) | (uint32_t)__builtin_bswap16(hi) << 16;
}
static inline uint16_t rd16(unsigned off)
{
	return __builtin_bswap16(*(volatile uint16_t *)(mb + off));
}
static inline void wr16(unsigned off, uint16_t v)
{
	*(volatile uint16_t *)(mb + off) = __builtin_bswap16(v);
}

static void serve(uint32_t w0)
{
	uint8_t in[FPU_REQ_MAX + 4], out[FPE_MAXIO + 4];
	uint16_t seq = f_lo(w0), kind = f_hi(w0), cmd = 0, aux = 0;
	int n = 0, out_len = 0;
	uint32_t iaddr = 0;

	if (kind == FPU_KIND_EXEC || kind == FPU_KIND_COND || kind == FPU_KIND_RESTORE) {
		uint32_t w1 = rd32(O_CMD);                      /* CMD, AUX */
		cmd = f_lo(w1);
		aux = f_hi(w1);
	}
	unsigned cls = cmd >> 13;
	int need_n = kind == FPU_KIND_RESTORE || (kind == FPU_KIND_EXEC && (cls == 2 || cls == 4 || cls == 6));
	int need_ia = kind == FPU_KIND_EXEC && (fpe_fpcr() & 0x7f00);
	if (need_n || need_ia) {
		uint32_t w2 = rd32(O_RNBYTES);                  /* NBYTES, IADDR[31:16] */
		if (need_n) n = f_lo(w2);
		if (n > FPU_REQ_MAX) n = FPU_REQ_MAX;
		if (need_ia) iaddr = (uint32_t)f_hi(w2) << 16 | f_lo(rd32(O_IADDRL));
		for (int i = 0; i < n; i += 4) {
			uint32_t v = rd32(O_RDATA + i);
			memcpy(in + i, &v, 4);
		}
	}

	uint16_t flags = fpu_request(kind, cmd, aux, iaddr, in, n, out, &out_len);
	uint32_t fpsr = fpe_fpsr();

	if (out_len & 3) memset(out + out_len, 0, 4 - (out_len & 3));
	for (int i = 0; i < out_len; i += 4) {
		uint32_t v;
		memcpy(&v, out + i, 4);
		wr32(O_ADATA + i, v);
	}
	/* no barrier needed: the RISC-V writes the mailbox in program order (no cache, no buffer) */
	wr32(O_STATUS, fields(fpu_status(seq, flags, fpsr), flags));
}

int main(void)
{
	fpe_reset();
	/* answer nothing that was posted before we ran: catch up with RSEQ */
	uint16_t seen = rd16(O_RSEQ);
	wr32(O_STATUS, fields(fpu_status(seen, 0, 0), 0));
	uint16_t hb = rd16(O_HB);
	wr16(O_VERSION, FPU_VERSION);
	wr16(O_MAGIC, FPU_MAGIC);

	uint32_t next_hb = rv_cycles();
	for (;;) {
		uint32_t w0 = rd32(O_RSEQ);                     /* RSEQ, KIND */
		if (f_lo(w0) != seen) {
			seen = f_lo(w0);
			serve(w0);
		}
		if ((int32_t)(rv_cycles() - next_hb) >= 0) {
			wr16(O_HB, ++hb);
			next_hb += HB_CYCLES;
			if ((int32_t)(rv_cycles() - next_hb) >= 0) next_hb = rv_cycles() + HB_CYCLES;
		}
	}
}
