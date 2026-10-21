// Driver for the falcon_m65.sv test bench (tb_top.sv): plays the parts of MegaST around the
// Falcon machine.
//
//   ./obj_dir/Vtb_top TOS.img [options]
//     --ms N              simulated milliseconds (default 6000)
//     --frames DIR        write frames as DIR/frame_NNNN.ppm   --frame-every N (default 50)
//     --monitor M         0 mono, 1 RGB, 2 VGA (default), 3 TV     --ram MB (4 or 14, default 14)
//     --fda FILE          floppy A (.st), served like fdc_bridge.vhd (16-bit words, even byte low)
//     --hda FILE          hard disk on drive 2 (IDE master), served the same way
//     --key IDX:T[:D]     ST matrix position IDX (col*8+row) pressed at T ms for D ms (default 100)
//     --turbo             CPU at 32 MHz
//     --mouse T:DX:DY:B   at T ms a PS/2 mouse packet (B: bit 0 left, bit 1 right)
//     --reset T:US        at T ms a reset pulse of US microseconds (the menu item "Reset Atari ST")
//     --pc MS             print the CPU's PC every MS milliseconds (and the CPU's reset edges)
//     --text ADDR         at the end print the NUL-terminated text at ADDR (hex; FPUTEST's simrom.s: 100000)
//     --done ADDR         stop when the long at ADDR is $D0E0600D (simrom.s: FFFF0)
//     --joyflicker T      from T ms on joystick 0 changes every ms (mouse pins seen as a joystick)
//
// TOS goes in like tos_loader.vhd sends it (68000 word address from $E00000, even byte in bits
// 15..8, a toggle per word, acknowledged by the machine) and is compared with the image in the
// SDRAM model afterwards. The bytes the CPU reads from the IKBD ACIA are logged.
//
// MEGA65 port done by Chris Freeman in 2026, licensed under GPL v3
#include "Vtb_top.h"
#include "Vtb_top__Dpi.h"
#include "verilated.h"
#include "svdpi.h"
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <cstdint>
#include <string>
#include <vector>
#include <sys/stat.h>

static const double CLK_HZ = 32083333.0;
static Vtb_top *top;
static uint64_t cyc = 0;

static void tick() {
    // clk_96: three rising edges per clk_32, one of them with the rising edge of clk_32
    top->clk_32 = 0; top->clk_96 = 1; top->eval();
    top->clk_96 = 0; top->eval();
    top->clk_32 = 1; top->clk_96 = 1; top->eval();
    top->clk_96 = 0; top->eval();
    top->clk_96 = 1; top->eval();
    top->clk_96 = 0; top->eval();
    cyc++;
}

struct Key { int idx; double t, d; };

int main(int argc, char **argv) {
    Verilated::commandArgs(argc, argv);
    setvbuf(stdout, nullptr, _IOLBF, 0);   // line buffered: progress is visible in a log file
    if (argc < 2) { fprintf(stderr, "usage: %s TOS.img [options]\n", argv[0]); return 1; }
    std::string tos_name = argv[1], frames_dir, img_name[4];
    double run_ms = 6000;
    int frame_every = 50, monitor = 2, ram = 14;
    bool turbo = false;
    std::vector<Key> keys;
    struct Mouse { double t; int dx, dy, b; };
    std::vector<Mouse> mice;
    double joyflicker = -1, pc_every = 0, pc_next = 0;
    uint32_t text_addr = 0, done_addr = 0;
    bool prev_cpu_rst = true;
    struct Rst { double t, us; };
    std::vector<Rst> resets;
    for (int i = 2; i < argc; i++) {
        std::string a = argv[i];
        auto next = [&]() { return std::string(i + 1 < argc ? argv[++i] : ""); };
        if (a == "--ms") run_ms = atof(next().c_str());
        else if (a == "--frames") frames_dir = next();
        else if (a == "--frame-every") frame_every = atoi(next().c_str());
        else if (a == "--monitor") monitor = atoi(next().c_str());
        else if (a == "--ram") ram = atoi(next().c_str());
        else if (a == "--fda") img_name[0] = next();
        else if (a == "--hda") img_name[2] = next();
        else if (a == "--turbo") turbo = true;
        else if (a == "--mouse") { Mouse m{0, 0, 0, 0}; sscanf(next().c_str(), "%lf:%d:%d:%d", &m.t, &m.dx, &m.dy, &m.b); mice.push_back(m); }
        else if (a == "--reset") { Rst r{0, 30}; sscanf(next().c_str(), "%lf:%lf", &r.t, &r.us); resets.push_back(r); }
        else if (a == "--text") text_addr = (uint32_t)strtoul(next().c_str(), nullptr, 16);
        else if (a == "--done") done_addr = (uint32_t)strtoul(next().c_str(), nullptr, 16);
        else if (a == "--pc") pc_every = atof(next().c_str());
        else if (a == "--joyflicker") joyflicker = atof(next().c_str());
        else if (a == "--key") { Key k{0, 0, 100}; sscanf(next().c_str(), "%d:%lf:%lf", &k.idx, &k.t, &k.d); keys.push_back(k); }
    }
    std::vector<uint8_t> tos, img[4];
    {
        FILE *f = fopen(tos_name.c_str(), "rb");
        if (!f) { perror(tos_name.c_str()); return 1; }
        uint8_t buf[65536]; size_t n;
        while ((n = fread(buf, 1, sizeof buf, f)) > 0) tos.insert(tos.end(), buf, buf + n);
        fclose(f);
    }
    for (int d = 0; d < 4; d++) if (!img_name[d].empty()) {
        FILE *f = fopen(img_name[d].c_str(), "rb");
        if (!f) { perror(img_name[d].c_str()); return 1; }
        uint8_t buf[65536]; size_t n;
        while ((n = fread(buf, 1, sizeof buf, f)) > 0) img[d].insert(img[d].end(), buf, buf + n);
        fclose(f);
    }
    if (!frames_dir.empty()) mkdir(frames_dir.c_str(), 0755);

    top = new Vtb_top;
    svSetScope(svGetScopeFromName("TOP.tb_top"));
    top->ram_mb = ram; top->monitor = monitor; top->cpu_turbo = turbo;
    for (int i = 0; i < 4; i++) top->kbd_matrix_n[i] = 0xFFFFFFFF;
    top->ps2_mouse = 0; top->joy0 = 0; top->img_mounted = 0; top->img_size = 0; top->sd_ack = 0;
    top->sd_buff_wr = 0; top->sd_buff_addr = 0; top->sd_buff_dout = 0;
    top->dio_strobe = 0;

    // power on: init, por, then TOS through the loader while the machine is in reset
    top->init = 1; top->por = 1; top->cold_reset = 1; top->reset = 1;
    for (int i = 0; i < 10; i++) tick();
    top->init = 0;
    for (int i = 0; i < 300; i++) tick();
    top->por = 0;
    uint64_t t0 = cyc;
    for (size_t w = 0; w < tos.size() / 2; w++) {
        top->dio_addr = 0x700000 + w;            // word address of $E00000 + 2w
        top->dio_data = tos[2 * w] << 8 | tos[2 * w + 1];
        top->dio_strobe = !top->dio_strobe;
        int timeout = 0;
        do { tick(); } while (top->dio_strobe_ack != top->dio_strobe && ++timeout < 100000);
        if (timeout >= 100000) { printf("ERROR: TOS loader timeout at word %zu\n", w); return 1; }
    }
    printf("TOS loaded: %zu bytes in %.3f ms\n", tos.size(), (cyc - t0) / CLK_HZ * 1e3);
    for (int i = 0; i < 200; i++) tick();        // the last byte reaches the SDRAM
    int bad = 0;
    for (size_t a = 0; a < tos.size(); a++)
        if (guest_peek8(0xE00000 + a) != tos[a] && bad++ < 5)
            printf("ERROR: TOS byte %06zx in the SDRAM: %02x, expected %02x\n", a, guest_peek8(0xE00000 + a), tos[a]);
    printf("TOS in the SDRAM: %s (%d bytes differ)\n", bad ? "WRONG" : "verified", bad);

    top->cold_reset = 0;
    for (int i = 0; i < 200; i++) tick();
    top->reset = 0;

    // mount the images (one clock pulse each, like the firmware)
    for (int d = 0; d < 4; d++) if (!img[d].empty()) {
        top->img_size = img[d].size(); top->img_mounted = 1 << d; tick(); top->img_mounted = 0;
    }

    // drive emulation state (fdc_bridge.vhd core side), one request at a time
    int fd_phase = 0;           // 0 idle, 1 delay, 2 read words, 3 write bytes, 4 finish
    int fd_delay = 0, fd_idx = 0, fd_wait = 0, fd_drv = 0;
    uint32_t fd_lba = 0;
    int sectors_rd[4] = {0}, sectors_wr[4] = {0};

    // video capture
    std::vector<uint8_t> fb(2048 * 1200 * 3);
    int fx = 0, fy = 0, maxx = 0, frame_no = 0;
    bool prev_hb = true, prev_vb = true, prev_kbd_rd = false;

    const uint64_t total = cyc + (uint64_t)(run_ms * 1e-3 * CLK_HZ);
    while (cyc < total && !Verilated::gotFinish()) {
        double now_ms = cyc / CLK_HZ * 1e3;

        // keys in the ST matrix (low active)
        for (auto &k : keys) {
            bool down = now_ms >= k.t && now_ms < k.t + k.d;
            uint32_t &wd = top->kbd_matrix_n[k.idx / 32];
            uint32_t bit = 1u << (k.idx % 32);
            if (down) wd &= ~bit; else wd |= bit;
        }

        // mouse packets (toggle bit 24 like hps_io) and the joystick 0 flicker
        for (auto &m : mice) if (m.t >= 0 && now_ms >= m.t) {
            int st = (m.b & 3) | 8 | (m.dx < 0 ? 0x10 : 0) | (m.dy < 0 ? 0x20 : 0);
            top->ps2_mouse = ((~top->ps2_mouse >> 24 & 1) << 24) | ((m.dy & 0xFF) << 16) | ((m.dx & 0xFF) << 8) | st;
            printf("[%9.3f ms] mouse packet dx %d dy %d buttons %d\n", now_ms, m.dx, m.dy, m.b);
            m.t = -1;
        }
        if (joyflicker >= 0 && now_ms >= joyflicker) top->joy0 = ((uint64_t)(now_ms) & 3) == 0 ? 1 : ((uint64_t)(now_ms) & 3) == 1 ? 2 : 0;

        {
            bool r = false;
            for (auto &x : resets) if (now_ms >= x.t && now_ms < x.t + x.us * 1e-3) r = true;
            if (r != (bool)top->reset) printf("[%9.3f ms] reset %d\n", now_ms, r);
            top->reset = r;
        }

        // drive A
        top->sd_buff_wr = 0;
        switch (fd_phase) {
        case 0:
            for (int d = 0; d < 4 && fd_phase == 0; d++) {
                bool rd = top->sd_rd >> d & 1, wr = top->sd_wr >> d & 1;
                if (rd || wr) { fd_drv = d; fd_lba = top->sd_lba[d]; fd_phase = 1; fd_delay = 2000; fd_idx = rd ? 0 : -1; }
            }
            break;
        case 1:
            if (--fd_delay == 0) { top->sd_ack = 1 << fd_drv; fd_phase = fd_idx == 0 ? 2 : 3; fd_idx = 0; fd_wait = 0; }
            break;
        case 2:   // a word every 8 clocks, one clock write strobe (the CDC handshake of fdc_bridge)
            if (++fd_wait == 8) {
                fd_wait = 0;
                size_t o = (size_t)fd_lba * 512 + 2 * fd_idx;
                std::vector<uint8_t> &m = img[fd_drv];
                uint8_t lo = o < m.size() ? m[o] : 0, hi = o + 1 < m.size() ? m[o + 1] : 0;
                top->sd_buff_addr = fd_idx; top->sd_buff_dout = lo | hi << 8; top->sd_buff_wr = 1;
                if (++fd_idx == 256) { fd_phase = 4; fd_delay = 20; sectors_rd[fd_drv]++; }
            }
            break;
        case 3:   // a byte by its word address; the word is taken 12 clocks later (C_VD_DIN_WAIT: ~15)
            top->sd_buff_addr = fd_idx >> 1;
            if (++fd_wait == 12) {
                fd_wait = 0;
                uint16_t w = top->sd_buff_din >> (16 * fd_drv) & 0xFFFF;
                size_t o = (size_t)fd_lba * 512 + fd_idx;
                std::vector<uint8_t> &m = img[fd_drv];
                if (o < m.size()) m[o] = (fd_idx & 1) ? w >> 8 : w & 0xFF;
                if (++fd_idx == 512) { fd_phase = 4; fd_delay = 20; sectors_wr[fd_drv]++; }
            }
            break;
        case 4:
            if (--fd_delay == 0) { top->sd_ack = 0; fd_phase = 5; fd_delay = 20; }
            break;
        case 5:
            if (--fd_delay == 0) fd_phase = 0;
            break;
        }

        tick();

        if (done_addr && (cyc & 32767) == 0 &&
            (guest_peek8(done_addr) << 24 | guest_peek8(done_addr + 1) << 16 | guest_peek8(done_addr + 2) << 8 | guest_peek8(done_addr + 3)) == (int)0xD0E0600D) {
            printf("[%9.3f ms] done marker at %06x\n", now_ms, done_addr);
            break;
        }
        if (pc_every > 0 && now_ms >= pc_next) { printf("[%9.3f ms] PC %08X\n", now_ms, top->dbg_pc); pc_next = now_ms + pc_every; }
        if (top->dbg_cpu_rst != prev_cpu_rst) { printf("[%9.3f ms] CPU reset %d, PC %08X\n", now_ms, top->dbg_cpu_rst, top->dbg_pc); prev_cpu_rst = top->dbg_cpu_rst; }
        if (top->dbg_kbd_rd && !prev_kbd_rd) printf("[%9.3f ms] IKBD byte %02X\n", now_ms, top->dbg_kbd_byte);
        prev_kbd_rd = top->dbg_kbd_rd;

        if (top->ce_pix) {
            bool hb = top->hblank, vb = top->vblank;
            if (!hb && !vb) {
                if (fx < 2048 && fy < 1200) {
                    uint8_t *p = &fb[(fy * 2048 + fx) * 3];
                    p[0] = top->r; p[1] = top->g; p[2] = top->b;
                }
                fx++;
            }
            if (hb && !prev_hb) { if (fx > 0) { if (fx > maxx) maxx = fx; fy++; } fx = 0; }
            if (vb && !prev_vb) {
                if (fy > 0) {
                    if (!frames_dir.empty() && (frame_no % frame_every) == 0) {
                        char fn[512]; snprintf(fn, sizeof fn, "%s/frame_%04d.ppm", frames_dir.c_str(), frame_no);
                        FILE *o = fopen(fn, "wb");
                        fprintf(o, "P6\n%d %d\n255\n", maxx, fy);
                        for (int y = 0; y < fy; y++) fwrite(&fb[y * 2048 * 3], 1, maxx * 3, o);
                        fclose(o);
                        printf("[%9.3f ms] frame %d: %dx%d\n", now_ms, frame_no, maxx, fy);
                    }
                    frame_no++;
                }
                fx = 0; fy = 0; maxx = 0;
            }
            prev_hb = hb; prev_vb = vb;
        }
    }
    printf("simulated %.0f ms; SDRAM errors: %s\n", cyc / CLK_HZ * 1e3, top->dbg_sdram_err ? "YES" : "none");
    for (int d = 0; d < 4; d++) if (!img[d].empty()) {
        printf("drive %d: %d sectors read, %d written\n", d, sectors_rd[d], sectors_wr[d]);
        if (sectors_wr[d]) {
            std::string out = img_name[d] + ".out";
            FILE *f = fopen(out.c_str(), "wb"); fwrite(img[d].data(), 1, img[d].size(), f); fclose(f);
            printf("drive %d written back to %s\n", d, out.c_str());
        }
    }
    if (text_addr) {
        printf("text at %06x:\n", text_addr);
        for (uint32_t i = 0; i < 65536; i++) {
            uint8_t c = guest_peek8(text_addr + i);
            if (!c) break;
            if (c != 13) putchar(c >= 32 || c == 10 ? c : '?');
        }
        printf("\n");
    }
    // the cookie jar (_p_cookies at $5A0): which CPU and FPU TOS found
    {
        auto rd32 = [](uint32_t x) { return (uint32_t)guest_peek8(x) << 24 | guest_peek8(x + 1) << 16 | guest_peek8(x + 2) << 8 | guest_peek8(x + 3); };
        uint32_t jar = rd32(0x5A0);
        if (jar && jar < 0xE00000) {
            for (int i = 0; i < 64; i++) {
                uint32_t id = rd32(jar + 8 * i), v = rd32(jar + 8 * i + 4);
                if (!id) break;
                if (id == 0x5F435055 || id == 0x5F465055)   // _CPU, _FPU
                    printf("cookie %c%c%c%c = %08X\n", id >> 24, id >> 16 & 255, id >> 8 & 255, id & 255, v);
            }
        } else printf("no cookie jar\n");
    }
    top->final();
    delete top;
    return 0;
}
