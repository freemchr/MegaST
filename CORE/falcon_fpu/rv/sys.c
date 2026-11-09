/* falcon_fpu on the RISC-V in the FPGA: the few C library hooks it needs.
 * stdout goes to the debug port (simulation only: the FPGA build has no output).
 * MEGA65 port done by Chris Freeman in 2026, licensed under GPL v3 */
#include <errno.h>
#include <stddef.h>
#include <stdint.h>
#include <sys/stat.h>
#include "fpu_rv.h"

int _write(int fd, const char *p, int n)
{
	(void)fd;
	for (int i = 0; i < n; i++) RV_DEBUG = (unsigned char)p[i];
	return n;
}

void *_sbrk(ptrdiff_t inc)
{
	extern char end, __stack_top;
	static char *brk = &end;
	char *old = brk;
	if ((uintptr_t)brk + inc > (uintptr_t)&__stack_top - RV_STACK) { errno = ENOMEM; return (void *)-1; }
	brk += inc;
	return old;
}

void _exit(int code) { RV_EXIT = code; for (;;) ; }
int _close(int fd) { (void)fd; return -1; }
int _fstat(int fd, struct stat *st) { (void)fd; st->st_mode = S_IFCHR; return 0; }
int _isatty(int fd) { (void)fd; return 1; }
int _lseek(int fd, int off, int w) { (void)fd; (void)off; (void)w; return 0; }
int _read(int fd, char *p, int n) { (void)fd; (void)p; (void)n; return 0; }
int _kill(int pid, int sig) { (void)pid; (void)sig; errno = EINVAL; return -1; }
int _getpid(void) { return 1; }

/* memset and memcpy a word at a time: newlib-nano's go a byte at a time (about 18 clocks per
 * byte on the PicoRV32), and fpe_exec clears its 256 byte buffer for every request with
 * operands. Same results. sys.c is compiled with -fno-builtin -fno-tree-loop-distribute-patterns
 * so that GCC does not turn these loops back into calls of themselves. */
void *memset(void *d, int c, size_t n)
{
	uint8_t *p = d;
	uint32_t w = (uint8_t)c * 0x01010101u;
	while (n && ((uintptr_t)p & 3)) { *p++ = (uint8_t)c; n--; }
	for (; n >= 16; n -= 16, p += 16) {
		((uint32_t *)p)[0] = w; ((uint32_t *)p)[1] = w; ((uint32_t *)p)[2] = w; ((uint32_t *)p)[3] = w;
	}
	for (; n >= 4; n -= 4, p += 4) *(uint32_t *)p = w;
	while (n--) *p++ = (uint8_t)c;
	return d;
}

void *memcpy(void *restrict d, const void *restrict s, size_t n)
{
	uint8_t *q = d;
	const uint8_t *p = s;
	if ((((uintptr_t)q ^ (uintptr_t)p) & 3) == 0) {         /* same alignment: words */
		while (n && ((uintptr_t)q & 3)) { *q++ = *p++; n--; }
		for (; n >= 4; n -= 4, q += 4, p += 4) *(uint32_t *)q = *(const uint32_t *)p;
	}
	while (n--) *q++ = *p++;
	return d;
}
