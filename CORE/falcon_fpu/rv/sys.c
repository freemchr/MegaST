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
