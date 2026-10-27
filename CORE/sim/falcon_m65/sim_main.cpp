// Driver for the falcon_m65.sv test bench (tb_top.sv): plays the parts of MegaST around the
// Falcon machine.
//
//   ./obj_dir/Vtb_top TOS.img [options]
//     --ms N              simulated milliseconds (default 6000)
//     --frames DIR        write frames as DIR/frame_NNNN.ppm   --frame-every N (default 50)
//     --monitor M         0 mono, 1 RGB, 2 VGA (default), 3 TV     --ram MB (4 or 14, default 14)
//     --fda FILE          floppy A (.st), served like fdc_bridge.vhd (16-bit words, even byte low)
//     --rfloppy FILE      the .st image in the flux level model of the internal drive (realdrive.h),
//                         drive A: is that drive (menu "Real floppy drive as A:")
//     --hda FILE          hard disk on drive 2 (IDE master), served the same way
//     --scsi              the hard disk is SCSI ID 0, not IDE master (menu "Hard disks on SCSI")
//     --key IDX:T[:D]     ST matrix position IDX (col*8+row) pressed at T ms for D ms (default 100)
//     --turbo             CPU at 32 MHz
//     --nvram FILE        the NVRAM buffer (/atarist/fcnvram, 64 bytes) loaded before the start and
//                         written back at the end when byte 62 (the change counter) changed
//     --cart FILE         a cartridge image at $FA0000 (loaded like TOS, cart_loaded = 1)
//     --eject T           at T ms the cartridge is ejected (cart_loaded = 0)
//     --lang N            NVRAM language and keyboard (0 US, 3 UK)
//     --fastram N         Fast RAM (TT-RAM) at $01000000: N blocks of 16 MB (1..3)
//     --mouse T:DX:DY:B   at T ms a PS/2 mouse packet (B: bit 0 left, bit 1 right)
//     --reset T:US        at T ms a reset pulse of US microseconds (the menu item "Reset Atari ST")
//     --pc MS             print the CPU's PC every MS milliseconds (and the CPU's reset edges)
//     --text ADDR         at the end print the NUL-terminated text at ADDR (hex; FPUTEST's simrom.s: 100000)
//     --start ADDR        the times of --key, --joy, --pad and --mouse count from when the long at ADDR
//                         is $57A27000 (a test program's start marker; tests/*.s: FFFF4)
//     --dump ADDR:LEN     at the end print LEN bytes at ADDR (hex) as hex
//     --done ADDR         stop when the long at ADDR is $D0E0600D (simrom.s: FFFF0)
//     --joyflicker T      from T ms on joystick 0 changes every ms (mouse pins seen as a joystick)
//     --joy T:BITS[:D]    joystick port 1 (MiSTer bits, hex: 1 right 2 left 4 down 8 up 10 fire) at T ms for D ms
//     --pad T:BITS[:D]    the same on the enhanced joystick port A (joypad; 80 Pause, 100 Option, ...)
//     --switch            like a switch from the ST to the Falcon in the menu: por, cold_reset and reset
//                         fall in the same cycle (the SDRAM was initialized long before)
//     --reload            like --switch with the TOS loaded again by the firmware (fcswitch.asm):
//                         por and cold_reset fall, the core stays in reset (M2M) while TOS comes
//                         through the loader
//     --junk              no TOS through the loader: $E00000.. holds what the ST left there (pseudo
//                         random bytes), like a switch without reloading TOS
//     --wav FILE          the audio (audio_l/r) as a 16-bit stereo WAV file at 50 kHz
//
// TOS goes in like tos_loader.vhd sends it (68000 word address from $E00000, even byte in bits
// 15..8, a toggle per word, acknowledged by the machine) and is compared with the image in the
// SDRAM model afterwards. The bytes the CPU reads from the IKBD ACIA are logged.
//
// MEGA65 port done by Chris Freeman in 2026, licensed under GPL v3
#include "Vtb_top.h"
#include "Vtb_top__Dpi.h"
#include "../realdrive.h"
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
struct Joy { double t; uint32_t bits; double d; bool pad; };

int main(int argc, char **argv) {
    Verilated::commandArgs(argc, argv);
    setvbuf(stdout, nullptr, _IOLBF, 0);   // line buffered: progress is visible in a log file
    if (argc < 2) { fprintf(stderr, "usage: %s TOS.img [options]\n", argv[0]); return 1; }
    std::string tos_name = argv[1], frames_dir, img_name[4];
    double run_ms = 6000;
    int frame_every = 50, monitor = 2, ram = 14;
    bool turbo = false, scsi = false, sw = false, junk = false, reload = false;
    int lang = 0, fast_n = 0;
    std::vector<Key> keys;
    std::vector<Joy> joys;
    std::string wav_name, rfd_name, cart_name, nvram_name;
    double eject_ms = -1;
    struct Mouse { double t; int dx, dy, b; };
    std::vector<Mouse> mice;
    double joyflicker = -1, pc_every = 0, pc_next = 0;
    uint32_t text_addr = 0, done_addr = 0, dump_addr = 0, dump_len = 0, start_addr = 0;
    double t_start = 0;     // the event times are relative to this (--start)
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
        else if (a == "--scsi") scsi = true;
        else if (a == "--lang") lang = atoi(next().c_str());
        else if (a == "--fastram") fast_n = atoi(next().c_str());
        else if (a == "--mouse") { Mouse m{0, 0, 0, 0}; sscanf(next().c_str(), "%lf:%d:%d:%d", &m.t, &m.dx, &m.dy, &m.b); mice.push_back(m); }
        else if (a == "--reset") { Rst r{0, 30}; sscanf(next().c_str(), "%lf:%lf", &r.t, &r.us); resets.push_back(r); }
        else if (a == "--text") text_addr = (uint32_t)strtoul(next().c_str(), nullptr, 16);
        else if (a == "--start") { start_addr = (uint32_t)strtoul(next().c_str(), nullptr, 16); t_start = 1e30; }
        else if (a == "--dump") sscanf(next().c_str(), "%x:%x", &dump_addr, &dump_len);
        else if (a == "--done") done_addr = (uint32_t)strtoul(next().c_str(), nullptr, 16);
        else if (a == "--pc") pc_every = atof(next().c_str());
        else if (a == "--joyflicker") joyflicker = atof(next().c_str());
        else if (a == "--joy" || a == "--pad") { Joy j{0, 0, 100, a == "--pad"}; sscanf(next().c_str(), "%lf:%x:%lf", &j.t, &j.bits, &j.d); joys.push_back(j); }
        else if (a == "--switch") sw = true;
        else if (a == "--junk") junk = true;
        else if (a == "--reload") reload = true;
        else if (a == "--wav") wav_name = next();
        else if (a == "--rfloppy") rfd_name = next();
        else if (a == "--cart") cart_name = next();
        else if (a == "--nvram") nvram_name = next();
        else if (a == "--eject") eject_ms = atof(next().c_str());
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
    RealDrive rd;
    if (!rfd_name.empty()) {
        FILE *f = fopen(rfd_name.c_str(), "rb");
        if (!f) { perror(rfd_name.c_str()); return 1; }
        std::vector<uint8_t> d; uint8_t buf[65536]; size_t n;
        while ((n = fread(buf, 1, sizeof buf, f)) > 0) d.insert(d.end(), buf, buf + n);
        fclose(f);
        rd.load(d);
    }

    top = new Vtb_top;
    svSetScope(svGetScopeFromName("TOP.tb_top"));
    top->ram_mb = ram; top->monitor = monitor; top->cpu_turbo = turbo; top->hd_scsi = scsi; top->tos_lang = lang; top->fast_n = fast_n;
    for (int i = 0; i < 4; i++) top->kbd_matrix_n[i] = 0xFFFFFFFF;
    top->ps2_mouse = 0; top->joy0 = 0; top->joy1 = 0; top->pad0 = 0; top->pad1 = 0; top->img_mounted = 0; top->img_size = 0; top->sd_ack = 0;
    top->sd_buff_wr = 0; top->sd_buff_addr = 0; top->sd_buff_dout = 0;
    top->dio_strobe = 0;
    top->real_fd = !rfd_name.empty();
    top->rfd_rdata = 0; top->rfd_index = 0; top->rfd_track0 = 0; top->rfd_wprot = 0;

    // power on: init, por, then TOS through the loader while the machine is in reset
    top->init = 1; top->por = 1; top->cold_reset = 1; top->reset = 1;
    for (int i = 0; i < 10; i++) tick();
    top->init = 0;
    // (after the first clocks: the model's initial block has run)
    uint8_t nv_cnt0 = 0xFF;
    if (!nvram_name.empty()) {      // like nvram.asm (NV_RESTORE) before the core starts
        FILE *f = fopen(nvram_name.c_str(), "rb");
        uint8_t b[64]; memset(b, 0xFF, 64);
        if (f) { if (fread(b, 1, 64, f) != 64) printf("NVRAM file: not 64 bytes\n"); fclose(f); }
        for (int i = 0; i < 64; i++) nvb_poke(i, b[i]);
        nv_cnt0 = b[62];
        printf("NVRAM buffer from %s: valid %s, counter %d\n", nvram_name.c_str(), b[63] == 0xA5 ? "yes" : "no", b[62]);
    }
    for (int i = 0; i < 300; i++) tick();
    if (reload) {
        // the ST ran for a while; the Falcon gets por and cold_reset, the firmware holds the reset
        for (int i = 0; i < 20000; i++) tick();
        printf("[%9.3f ms] switch to the Falcon: por and cold_reset fall, TOS through the loader in reset\n",
               cyc / CLK_HZ * 1e3);
        top->por = 0; top->cold_reset = 0;
    }
    if (sw) {
        // the ST ran for a while: the SDRAM is initialized, then the Falcon gets everything in one cycle
        // (its TOS is put into the SDRAM model directly, or the ST's leftovers with --junk)
        for (int i = 0; i < 20000; i++) tick();
        uint32_t x = 12345;
        for (size_t a = 0; a < tos.size(); a++) {
            x = x * 1103515245 + 12345;
            guest_poke8(0xE00000 + a, junk ? x >> 16 : tos[a]);
        }
        printf("[%9.3f ms] switch to the Falcon: por, cold_reset and reset fall%s\n", cyc / CLK_HZ * 1e3,
               junk ? " (no TOS)" : "");
        top->por = 0; top->cold_reset = 0; top->reset = 0;
        tos.clear();
    }
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
    top->cart_loaded = 0;
    if (!cart_name.empty()) {
        FILE *f = fopen(cart_name.c_str(), "rb");
        if (!f) { perror(cart_name.c_str()); return 1; }
        std::vector<uint8_t> c; uint8_t buf[65536]; size_t n;
        while ((n = fread(buf, 1, sizeof buf, f)) > 0) c.insert(c.end(), buf, buf + n);
        fclose(f);
        for (size_t w = 0; w < c.size() / 2; w++) {
            top->dio_addr = 0x7D0000 + w;        // word address of $FA0000 + 2w
            top->dio_data = c[2 * w] << 8 | c[2 * w + 1];
            top->dio_strobe = !top->dio_strobe;
            int timeout = 0;
            do { tick(); } while (top->dio_strobe_ack != top->dio_strobe && ++timeout < 100000);
        }
        top->cart_loaded = 1;
        printf("cartridge loaded: %zu bytes\n", c.size());
    }
    for (int i = 0; i < 200; i++) tick();        // the last byte reaches the SDRAM
    int bad = 0;
    for (size_t a = 0; a < tos.size(); a++)
        if (guest_peek8(0xE00000 + a) != tos[a] && bad++ < 5)
            printf("ERROR: TOS byte %06zx in the SDRAM: %02x, expected %02x\n", a, guest_peek8(0xE00000 + a), tos[a]);
    printf("TOS in the SDRAM: %s (%d bytes differ)\n", bad ? "WRONG" : "verified", bad);

    if (!sw) {
        if (reload) tick();
        top->cold_reset = 0;
        for (int i = 0; i < 200; i++) tick();
        top->reset = 0;
    }

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
    int kbd_last = -1;
    double kbd_last_ms = -1e9;

    FILE *wav = nullptr;
    uint64_t wav_next = 0, wav_samples = 0, wav_c0 = cyc;
    if (!wav_name.empty()) { wav = fopen(wav_name.c_str(), "wb"); fseek(wav, 44, SEEK_SET); wav_next = cyc; }

    const uint64_t total = cyc + (uint64_t)(run_ms * 1e-3 * CLK_HZ);
    while (cyc < total && !Verilated::gotFinish()) {
        double now_ms = cyc / CLK_HZ * 1e3;
        if (start_addr && t_start > 1e29 && (cyc & 32767) == 0 &&
            (guest_peek8(start_addr) << 24 | guest_peek8(start_addr + 1) << 16 | guest_peek8(start_addr + 2) << 8 | guest_peek8(start_addr + 3)) == 0x57A27000) {
            t_start = now_ms;
            printf("[%9.3f ms] start marker at %06x\n", now_ms, start_addr);
        }
        const double ev_ms = now_ms - t_start;    // the time of the input events

        // keys in the ST matrix (low active)
        for (auto &k : keys) {
            bool down = ev_ms >= k.t && ev_ms < k.t + k.d;
            uint32_t &wd = top->kbd_matrix_n[k.idx / 32];
            uint32_t bit = 1u << (k.idx % 32);
            if (down) wd &= ~bit; else wd |= bit;
        }

        // mouse packets (toggle bit 24 like hps_io) and the joystick 0 flicker
        for (auto &m : mice) if (m.t >= 0 && ev_ms >= m.t) {
            int st = (m.b & 3) | 8 | (m.dx < 0 ? 0x10 : 0) | (m.dy < 0 ? 0x20 : 0);
            top->ps2_mouse = ((~top->ps2_mouse >> 24 & 1) << 24) | ((m.dy & 0xFF) << 16) | ((m.dx & 0xFF) << 8) | st;
            printf("[%9.3f ms] mouse packet dx %d dy %d buttons %d\n", now_ms, m.dx, m.dy, m.b);
            m.t = -1;
        }
        {
            uint32_t j1 = 0, p0 = 0;
            for (auto &j : joys) if (ev_ms >= j.t && ev_ms < j.t + j.d) (j.pad ? p0 : j1) |= j.bits;
            if (j1 != top->joy1 || p0 != top->pad0) printf("[%9.3f ms] joystick %X, joypad A %X\n", now_ms, j1, p0);
            top->joy1 = j1; top->pad0 = p0;
        }
        if (wav && cyc >= wav_next) {
            int16_t smp[2] = {(int16_t)top->audio_l, (int16_t)top->audio_r};
            fwrite(smp, 2, 2, wav); wav_samples++;
            wav_next = (uint64_t)((wav_samples + 1) * CLK_HZ / 50000.0) + wav_c0;
        }
        if (joyflicker >= 0 && now_ms >= joyflicker) top->joy0 = ((uint64_t)(now_ms) & 3) == 0 ? 1 : ((uint64_t)(now_ms) & 3) == 1 ? 2 : 0;

        {
            bool r = false;
            for (auto &x : resets) if (now_ms >= x.t && now_ms < x.t + x.us * 1e-3) r = true;
            if (r != (bool)top->reset) printf("[%9.3f ms] reset %d\n", now_ms, r);
            top->reset = r;
        }

        if (eject_ms >= 0 && now_ms >= eject_ms && top->cart_loaded) { top->cart_loaded = 0; printf("[%9.3f ms] cartridge ejected\n", now_ms); }

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

        if (top->real_fd) {
            // the WD1772's commands, interrupts and first status reads after each command
            static int wd_prev = 0, wd_cmds = 0, wd_bytes = 0;
            int w = top->dbg_wd;
            bool sel = w >> 15 & 1, rw = w >> 14 & 1, irq = w >> 11 & 1;
            int ad = w >> 12 & 3, dat = w & 0xFF;
            if (sel && !(wd_prev >> 15 & 1)) {
                if (!rw && ad == 0) { printf("[%9.3f ms] WD1772 command %02X (head %d)\n", now_ms, dat, rd.head); wd_cmds++; }
                else if (!rw) printf("[%9.3f ms] WD1772 reg %d = %02X\n", now_ms, ad, dat);
                else if (ad == 3) wd_bytes++;
            }
            if (irq != (bool)(wd_prev >> 11 & 1)) printf("[%9.3f ms] WD1772 INTRQ %d (%d data bytes so far)\n", now_ms, irq, wd_bytes);
            wd_prev = w;
            bool rdata, index, track0, wprot;
            rd.step(top->rfd_sel_a, top->rfd_motor, top->rfd_side, top->rfd_dir_in, top->rfd_step, frame_no,
                    rdata, index, track0, wprot);
            top->rfd_rdata = rdata; top->rfd_index = index; top->rfd_track0 = track0; top->rfd_wprot = wprot;
        }

        tick();

        if (done_addr && (cyc & 32767) == 0 &&
            (guest_peek8(done_addr) << 24 | guest_peek8(done_addr + 1) << 16 | guest_peek8(done_addr + 2) << 8 | guest_peek8(done_addr + 3)) == (int)0xD0E0600D) {
            printf("[%9.3f ms] done marker at %06x\n", now_ms, done_addr);
            break;
        }
        if (pc_every > 0 && now_ms >= pc_next) {
            // with the DSP (falcon_system dbg): PC, R6, host interface status ISR and HSR, SSI status
            const uint32_t *f = top->dbg_f.data();
            printf("[%9.3f ms] PC %08X  DSP PC %04X R6 %04X R7 %04X LC %04X ISR %02X HSR %02X SSISR %02X\n", now_ms,
                   top->dbg_pc, f[2] & 0xFFFF, f[2] >> 16, f[3] & 0xFFFF, f[3] >> 16,
                   f[4] >> 24, (f[4] >> 16) & 0xFF, (f[4] >> 8) & 0xFF);
            pc_next = now_ms + pc_every;
        }
        if (top->dbg_cpu_rst != prev_cpu_rst) { printf("[%9.3f ms] CPU reset %d, PC %08X\n", now_ms, top->dbg_cpu_rst, top->dbg_pc); prev_cpu_rst = top->dbg_cpu_rst; }
        // the bytes the CPU reads from the IKBD ACIA (a byte read again: at most every 100 ms, programs poll)
        if (top->dbg_kbd_rd && !prev_kbd_rd && (top->dbg_kbd_byte != kbd_last || now_ms - kbd_last_ms > 100)) {
            printf("[%9.3f ms] IKBD byte %02X\n", now_ms, top->dbg_kbd_byte);
            kbd_last = top->dbg_kbd_byte; kbd_last_ms = now_ms;
        }
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
    if (wav) {   // the header, now that the length is known
        uint32_t n = wav_samples * 4, rate = 50000, brate = rate * 4, fmt = 16, n36 = n + 36;
        uint16_t pcm = 1, ch = 2, align = 4, bits = 16;
        fseek(wav, 0, SEEK_SET);
        fwrite("RIFF", 1, 4, wav); fwrite(&n36, 4, 1, wav); fwrite("WAVEfmt ", 1, 8, wav); fwrite(&fmt, 4, 1, wav);
        fwrite(&pcm, 2, 1, wav); fwrite(&ch, 2, 1, wav); fwrite(&rate, 4, 1, wav); fwrite(&brate, 4, 1, wav);
        fwrite(&align, 2, 1, wav); fwrite(&bits, 2, 1, wav); fwrite("data", 1, 4, wav); fwrite(&n, 4, 1, wav);
        fclose(wav);
        printf("audio: %llu samples in %s\n", (unsigned long long)wav_samples, wav_name.c_str());
    }
    if (!nvram_name.empty()) {      // like nvram.asm (NV_POLL): save when the counter changed
        printf("NVRAM buffer: counter %d, valid %s, bytes 14..:", nvb_peek(62), nvb_peek(63) == 0xA5 ? "yes" : "no");
        for (int i = 0; i < 50; i++) printf(" %02x", nvb_peek(i));
        printf("\n");
        if (nvb_peek(62) != nv_cnt0) {
            FILE *f = fopen(nvram_name.c_str(), "wb");
            for (int i = 0; i < 64; i++) fputc(nvb_peek(i), f);
            fclose(f);
            printf("NVRAM buffer saved to %s\n", nvram_name.c_str());
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
    for (uint32_t i = 0; i < dump_len; i++)
        printf("%s%02x%s", i % 16 == 0 ? (i ? "" : "dump:\n") : "", guest_peek8(dump_addr + i), i % 16 == 15 || i + 1 == dump_len ? "\n" : " ");
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
