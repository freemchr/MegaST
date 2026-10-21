// Test bench of fpu_rv.v alone: the RISC-V runs a program (default: the engine self-test,
// CORE/falcon_fpu/rv/selftest.hex) and its stdout is printed; ends when the program exits.
//   ./build.sh && ./obj_dir/Vfpu_rv [--max-mcycles N] [--prof FILE] [--trace N]
// --prof writes the cycles spent per instruction address (fetch address, cycles until the
// next fetch, fetches) as "addr cycles count" lines: tools/rvprof.py turns them into a per-function profile.
// The program's clock is clk_96; the bridge side is idle.
//
// MEGA65 port done by Chris Freeman in 2026, licensed under GPL v3
#include "Vfpu_rv.h"
#include "Vfpu_rv___024root.h"
#include "verilated.h"
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <cstdint>
#include <map>

int main(int argc, char **argv) {
    Verilated::commandArgs(argc, argv);
    setvbuf(stdout, nullptr, _IOLBF, 0);
    uint64_t max_cycles = 20000ull * 1000000ull;
    const char *prof = nullptr;
    uint64_t trace = 0;     // --trace N: print the bus of the first N cycles
    std::map<uint32_t, uint64_t> hist, cnt;
    uint32_t pc = 0; uint64_t pc_t = 0; bool was = false;
    for (int i = 1; i < argc; i++)
        if (!strcmp(argv[i], "--max-mcycles") && i + 1 < argc) max_cycles = strtoull(argv[++i], nullptr, 0) * 1000000ull;
        else if (!strcmp(argv[i], "--prof") && i + 1 < argc) prof = argv[++i];
        else if (!strcmp(argv[i], "--trace") && i + 1 < argc) trace = strtoull(argv[++i], nullptr, 0);
    Vfpu_rv *top = new Vfpu_rv;
    top->d3_req = 0; top->d3_we = 0; top->d3_addr = 0; top->d3_be = 0; top->d3_wdata = 0;
    uint64_t cyc = 0;
    while (!top->dbg_exit && cyc < max_cycles && !Verilated::gotFinish()) {
        // clk_32 every third clk_96
        top->clk_96 = 1; top->clk_32 = (cyc % 3) == 0; top->eval();
        if (top->dbg_out) putchar(top->dbg_byte);
        if (cyc < trace) {
            auto *r = top->rootp;
            printf("%5llu v%d i%d rdy%d a%08x w%x wd%08x rd%08x | la r%d w%d a%08x\n", (unsigned long long)cyc,
                   r->fpu_rv__DOT__mem_valid, r->fpu_rv__DOT__mem_instr, r->fpu_rv__DOT__mem_ready,
                   r->fpu_rv__DOT__mem_addr, r->fpu_rv__DOT__mem_wstrb, r->fpu_rv__DOT__mem_wdata,
                   r->fpu_rv__DOT__mem_rdata, r->fpu_rv__DOT__mem_la_read, r->fpu_rv__DOT__mem_la_write,
                   r->fpu_rv__DOT__mem_la_addr);
            printf("      st%d rinst%d pref%d cpu_la%d\n", r->fpu_rv__DOT__cpu__DOT__mem_state, r->fpu_rv__DOT__cpu__DOT__mem_do_rinst, r->fpu_rv__DOT__cpu__DOT__mem_do_prefetch, r->fpu_rv__DOT__cpu__DOT__mem_la_read);
        }
        if (prof) {
            auto *r = top->rootp;
            bool f = r->fpu_rv__DOT__mem_valid && r->fpu_rv__DOT__mem_instr;
            if (f && !was) { hist[pc] += cyc - pc_t; cnt[pc]++; pc = r->fpu_rv__DOT__mem_addr; pc_t = cyc; }
            was = f;
        }
        top->clk_96 = 0; if ((cyc % 3) == 1) top->clk_32 = 0; top->eval();
        cyc++;
    }
    printf("\n[fpu_rv] %s after %llu cycles (%.3f s at 96 MHz), exit code %d\n",
           top->dbg_exit ? "program ended" : "TIMEOUT", (unsigned long long)cyc, cyc / 96e6, (int)top->dbg_code);
    if (prof) {
        FILE *f = fopen(prof, "w");
        for (auto &h : hist) fprintf(f, "%08x %llu %llu\n", h.first, (unsigned long long)h.second, (unsigned long long)cnt[h.first]);
        fclose(f);
    }
    int rc = top->dbg_exit ? (int)top->dbg_code : 99;
    top->final();
    delete top;
    return rc;
}
