// Verilator testbench: load a TOS image through the loader interface, boot the ST and dump frames
#include "Vtb_top.h"
#include "verilated.h"
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <vector>
#include <string>

static Vtb_top* top;

// Flux level model of the MEGA65's internal floppy drive with an .st image (RFLOPPY=<file>):
// builds the MFM bit cells of the track under the head (ST format: gap, 12 x 00, 3 x A1 sync, ID mark FE,
// track, side, sector, size, CRC, gap, 3 x A1, data mark FB, 512 bytes, CRC, gap) and sends one RDATA
// pulse (0.4 us) per flux transition, 2 us per bit cell; 300 rpm, index pulse at the start of the track.
// Call step() once per 32 MHz cycle.
struct RealDrive {
    std::vector<uint8_t> img;
    int spt = 9, sides = 2, tracks = 80;
    int head = 0, trk = -1, sd = -1;
    int bad_t = -1, bad_s = 0, bad_sec = 0, bad_left = 0, bad_data = 0, bad_from = 0; bool bad_on = false;   // RFLOPPY_BAD: weak sector (data CRC error)
    bool wp = false, old_step = false, old_motor = false;
    std::vector<uint8_t> cells;                     // one byte per bit cell
    uint64_t rev = 0;                               // 32 MHz cycles since the index
    int64_t last_cell = -1;
    int pulse = 0;
    uint64_t revs = 0, steps = 0;
    static const int TRACK_BYTES = 6250;            // 200 ms at 250 kbit/s
    static const uint64_t REV = (uint64_t)TRACK_BYTES * 16 * 385 / 6;   // 2 us = 385/6 cycles of 32.083 MHz

    void load(const std::vector<uint8_t>& d) {
        img = d;
        int bspt = d[24] | (d[25] << 8), bsides = d[26] | (d[27] << 8), total = d[19] | (d[20] << 8);
        if (bspt >= 8 && bspt <= 10 && (bsides == 1 || bsides == 2) && total > 0) {
            spt = bspt; sides = bsides; tracks = total / (spt * sides);
        } else {                                    // no BPB: guess from the size
            sides = d.size() > 500000 ? 2 : 1;
            spt = (d.size() / 512 / sides) % 80 == 0 ? (int)(d.size() / 512 / sides / 80) : 9;
            tracks = d.size() / 512 / sides / spt;
        }
        printf("real floppy: %zu bytes, %d tracks, %d sides, %d sectors\n", d.size(), tracks, sides, spt);
    }
    void crc_byte(uint16_t& c, uint8_t b) {
        for (int k = 7; k >= 0; k--) {
            bool x = ((c >> 15) ^ (b >> k)) & 1;
            c <<= 1;
            if (x) c ^= 0x1021;
        }
    }
    void put(uint8_t b, bool& last, uint16_t& c) {
        for (int k = 7; k >= 0; k--) {
            bool d = (b >> k) & 1;
            cells.push_back(!last && !d);
            cells.push_back(d);
            last = d;
        }
        crc_byte(c, b);
    }
    void sync(bool& last, uint16_t& c) {
        for (int k = 15; k >= 0; k--) cells.push_back((0x4489 >> k) & 1);
        last = true;
        crc_byte(c, 0xa1);
    }
    void build(int t, int s) {
        cells.clear();
        bool last = false; uint16_t c = 0xffff;
        if (t < tracks && s < sides) {
            for (int k = 0; k < 60; k++) put(0x4e, last, c);
            for (int sec = 1; sec <= spt; sec++) {
                for (int k = 0; k < 12; k++) put(0x00, last, c);
                c = 0xffff;
                for (int k = 0; k < 3; k++) sync(last, c);
                put(0xfe, last, c); put(t, last, c); put(s, last, c); put(sec, last, c); put(2, last, c);
                uint16_t crc = c; put(crc >> 8, last, c); put(crc & 0xff, last, c);
                for (int k = 0; k < 22; k++) put(0x4e, last, c);
                for (int k = 0; k < 12; k++) put(0x00, last, c);
                c = 0xffff;
                for (int k = 0; k < 3; k++) sync(last, c);
                put(0xfb, last, c);
                size_t o = ((size_t)(t * sides + s) * spt + sec - 1) * 512;
                bool weak = t == bad_t && s == bad_s && sec == bad_sec && bad_left > 0 && bad_on;
                for (int i = 0; i < 512; i++) {
                    uint8_t b = o + i < img.size() ? img[o + i] : 0;
                    put(weak && bad_data && i >= 256 ? b ^ 0xa5 : b, last, c);   // like a real misread: wrong bytes
                }
                crc = c;
                if (weak) crc ^= 1;                         // weak sector
                put(crc >> 8, last, c); put(crc & 0xff, last, c);
                for (int k = 0; k < 40; k++) put(0x4e, last, c);
            }
        }
        while (cells.size() < (size_t)TRACK_BYTES * 16) put(0x4e, last, c);   // unformatted track: gap only
        cells.resize((size_t)TRACK_BYTES * 16);
        trk = t; sd = s;
    }
    // inputs active high; outputs rdata, index, track0, wprot
    void step(bool sel, bool motor, bool side, bool dir_in, bool stp, int frame,
              bool& rdata, bool& index, bool& track0, bool& wprot) {
        if (stp && !old_step && sel) {
            if (dir_in && head < 83) head++;
            else if (!dir_in && head > 0) head--;
            steps++;
        }
        old_step = stp;
        if (motor != old_motor) printf("real floppy: motor %s at frame %d, head %d\n", motor ? "on" : "off", frame, head);
        old_motor = motor;
        int s = side && sides == 2 ? 1 : (side ? 1 : 0);
        if (!bad_on && frame >= bad_from) {
            bad_on = true;
            trk = -1;                                       // rebuild with the weak sector
        }
        if (motor) {
            if (++rev >= REV) {
                rev = 0; revs++; last_cell = -1;
                if (bad_left > 0 && head == bad_t && s == bad_s && --bad_left == 0) {
                    printf("real floppy: weak sector %d.%d/%d reads from now on (frame %d)\n", bad_t, bad_s, bad_sec, frame);
                    trk = -1;                               // rebuild with the right CRC
                }
            }
            if (head != trk || s != sd) build(head, s);
            int64_t cell = (int64_t)(rev * 6 / 385);
            if (cell != last_cell) {
                last_cell = cell;
                if (cell < (int64_t)cells.size() && cells[cell] && sel) pulse = 13;
            }
        }
        if (pulse) pulse--;
        rdata  = pulse > 0;
        index  = motor && sel && rev < 64167;        // 2 ms
        track0 = sel && head == 0;
        wprot  = sel && wp;
    }
};
static uint64_t ticks = 0;   // one tick = half a 96 MHz period

// clk_96: toggles every tick; clk_32: every 3 ticks; clk_2: every 48 ticks (all rise at tick 0)
static void tick() {
    top->clk_96 = (ticks % 2) == 0;
    top->clk_32 = (ticks % 6) < 3;
    top->clk_2  = (ticks % 96) < 48;
    top->eval();
    ticks++;
}
static void cycle32() { for (int i = 0; i < 6; i++) tick(); }

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);
    if (argc < 3) { fprintf(stderr, "usage: %s tos.img frames [out_prefix] [ste]\n", argv[0]); return 1; }
    const char* tos_name = argv[1];
    int frames = atoi(argv[2]);
    std::string prefix = argc > 3 ? argv[3] : "frame";
    int ste = argc > 4 ? atoi(argv[4]) : 0;
    const char* hd_name = argc > 5 ? argv[5] : nullptr;
    std::vector<uint8_t> hd;
    if (hd_name) {
        FILE* h = fopen(hd_name, "rb");
        if (!h) { perror("hd"); return 1; }
        fseek(h, 0, SEEK_END); hd.resize(ftell(h)); fseek(h, 0, SEEK_SET);
        if (fread(hd.data(), 1, hd.size(), h) != hd.size()) return 1;
        fclose(h);
        printf("hard disk image: %zu bytes\n", hd.size());
    }

    // FLOPPY=<.st image>: drive A, mounted at the start or at frame FLOPPY_AT (while TOS runs)
    const char* fd_name = getenv("FLOPPY");
    int fd_at = getenv("FLOPPY_AT") ? atoi(getenv("FLOPPY_AT")) : -1;
    std::vector<uint8_t> fd;
    if (fd_name) {
        FILE* h = fopen(fd_name, "rb");
        if (!h) { perror("floppy"); return 1; }
        fseek(h, 0, SEEK_END); fd.resize(ftell(h)); fseek(h, 0, SEEK_SET);
        if (fread(fd.data(), 1, fd.size(), h) != fd.size()) return 1;
        fclose(h);
        printf("floppy image: %zu bytes\n", fd.size());
    }

    // RFLOPPY=<.st image>: drive A is the internal floppy drive (cfg_real_floppy, flux level drive model);
    // RFLOPPY_WP=1: write protected
    RealDrive rd;
    const char* rf_name = getenv("RFLOPPY");
    if (rf_name) {
        FILE* h = fopen(rf_name, "rb");
        if (!h) { perror("real floppy"); return 1; }
        fseek(h, 0, SEEK_END); std::vector<uint8_t> d(ftell(h)); fseek(h, 0, SEEK_SET);
        if (fread(d.data(), 1, d.size(), h) != d.size()) return 1;
        fclose(h);
        rd.load(d);
        rd.wp = getenv("RFLOPPY_WP") != nullptr;
        // RFLOPPY_BAD=t,s,sec,n[,1[,f]]: the data CRC of that sector is wrong for its first n revolutions under the head
        // (,1: and its second half has wrong bytes, as a real misread delivers; ,f: only from frame f on)
        if (getenv("RFLOPPY_BAD"))
            sscanf(getenv("RFLOPPY_BAD"), "%d,%d,%d,%d,%d,%d", &rd.bad_t, &rd.bad_s, &rd.bad_sec, &rd.bad_left, &rd.bad_data,
                   &rd.bad_from);
    }

    FILE* f = fopen(tos_name, "rb");
    if (!f) { perror("tos"); return 1; }
    std::vector<uint8_t> tos(1024 * 1024);
    size_t tos_len = fread(tos.data(), 1, tos.size(), f);
    fclose(f);
    printf("TOS image: %zu bytes, os_beg = %02x%02x%02x%02x\n", tos_len, tos[8], tos[9], tos[10], tos[11]);

    top = new Vtb_top;
    top->init = 1; top->reset_in = 1; top->cfg_ste = ste;
    top->cfg_mem = getenv("MEM") ? atoi(getenv("MEM")) : 1;   // MEM=0..5: 512K, 1M, 2M, 4M, 8M, 14M
    top->cfg_crop = getenv("CROP") != nullptr;   // CROP=1: only the graphics area is active
    top->cfg_mste = getenv("MSTE") != nullptr;   // MSTE=1: Mega STe; with ste=1: STEroids
    top->cfg_mono = getenv("MONO") != nullptr;   // MONO=1: SM124 monochrome monitor (71 Hz)
    top->cfg_mde60 = getenv("MONO60") != nullptr; // MONO60=1: mono 60 Hz mode
    top->cfg_full_brd = getenv("BORDER") != nullptr; // BORDER=1: full borders
    top->cfg_real_floppy = rf_name != nullptr;
    top->cfg_fdc_retry = getenv("RFLOPPY_RAW") == nullptr;   // RFLOPPY_RAW=1: no read retries in the controller
    int dump_from = getenv("DUMP_FROM") ? atoi(getenv("DUMP_FROM")) : -1;   // write every frame from this one on
    top->dio_download = 1; top->dio_strobe = 0; top->tos192k_in = 0;
    for (int i = 0; i < 4; i++) top->kbd_matrix[i] = 0xffffffff;
    for (int i = 0; i < 100; i++) cycle32();
    top->init = 0;
    // SDRAM init: 2048 * 125 ns
    for (int i = 0; i < 2048 * 4 + 100; i++) cycle32();

    // Load the TOS image, like tos_loader.vhd does
    top->tos192k_in = (tos[8] == 0x00 && tos[9] == 0xfc);
    int strobe = 0;
    for (size_t i = 0; i < tos_len; i += 2) {
        top->dio_addr = 0x700000 + (i >> 1);
        top->dio_data = (tos[i] << 8) | tos[i + 1];
        cycle32(); cycle32();
        strobe ^= 1; top->dio_strobe = strobe;
        int timeout = 0;
        while (top->dio_strobe_ack != strobe) { cycle32(); if (++timeout > 1000) { printf("loader timeout\n"); return 1; } }
        for (int k = 0; k < 8; k++) cycle32();
    }
    printf("TOS loaded at tick %llu\n", (unsigned long long)ticks);
    for (int i = 0; i < 100; i++) cycle32();
    if (fd_name && fd_at < 0) {
        top->img_size = fd.size();
        top->fd_img_mounted = 1; cycle32(); cycle32();
        top->fd_img_mounted = 0;
    }
    // mount the hard disk image (ACSI target 0), like vdrives.vhd does
    if (hd_name) {
        top->img_size = hd.size();
        top->hd_img_mounted = 1; cycle32(); cycle32();
        top->hd_img_mounted = 0;
    }
    top->dio_download = 0;
    top->reset_in = 0;
    int hd_state = 0, hd_idx = 0, hd_wait = 0; uint32_t hd_lba = 0; uint64_t hd_reads = 0, hd_writes = 0;
    // HD_WR_DELAY=<cycles>: each sector write takes this many extra 32 MHz cycles (like the slow
    // firmware path on the MEGA65), HD_TRACE=1: print every sector read/write,
    // HD_OUT=<file>: save the hard disk image at the end
    int hd_wr_delay = getenv("HD_WR_DELAY") ? atoi(getenv("HD_WR_DELAY")) : 0;
    bool hd_trace = getenv("HD_TRACE") != nullptr;
    int fd_state = 0, fd_idx = 0, fd_wait = 0; uint32_t fd_lba = 0; uint64_t fd_reads = 0;

    // Run and dump frames
    int frame = 0, x = 0, y = 0, maxx = 0, maxy = 0;
    int hx = 0, hfirst = 1 << 30, hlast = -1;   // pixels since hsync: first and last active pixel of the frame
    const int W = 1024, H = 640;
    std::vector<uint8_t> img(W * H * 3, 0);
    int old_vs = 0, old_hs = 0, old_as = 1;
    int lines = 0;                  // HSync pulses per frame
    unsigned long long vs_ticks = 0; // ticks at the last VSync
    uint32_t last_a = 0; uint64_t n_bus = 0;
    // RESET_AT=n: reset the ST at frame n like the "Reset Atari ST" menu item
    // (main.vhd: reset_core also drives dio_download)
    int reset_at = getenv("RESET_AT") ? atoi(getenv("RESET_AT")) : -1;
    // MOUSE_AT=n: from frame n on, move an ST mouse in the mouse port to the right (quadrature on
    // XA = pin 2 = bit 1, XB = pin 1 = bit 0, one step every 2 ms); MOUSE_AMIGA=1: Amiga mouse wiring
    // (H = pin 2 = bit 1, HQ = pin 4 = bit 3)
    int mouse_at = getenv("MOUSE_AT") ? atoi(getenv("MOUSE_AT")) : -1;
    bool mouse_amiga = getenv("MOUSE_AMIGA") != nullptr;
    int mouse_phase = 0; uint64_t mouse_next = 0;
    top->joy_mouse = 0;
    // KEY_AT=n KEY=i: press the ST matrix key i (column * 8 + row) from frame n on for 5 frames;
    // KEY_EVERY=m: press it again every m frames
    int key_at = getenv("KEY_AT") ? atoi(getenv("KEY_AT")) : -1;
    int key_idx = getenv("KEY") ? atoi(getenv("KEY")) : 0;
    int key_every = getenv("KEY_EVERY") ? atoi(getenv("KEY_EVERY")) : 0;
    while (frame < frames) {
        if (key_at >= 0 && frame == key_at && (top->kbd_matrix[key_idx / 32] >> (key_idx % 32) & 1)) {
            printf("key %d pressed at frame %d\n", key_idx, frame);
            top->kbd_matrix[key_idx / 32] &= ~(1u << (key_idx % 32));
        }
        if (key_at >= 0 && frame == key_at + 5) {
            printf("key %d released at frame %d\n", key_idx, frame);
            top->kbd_matrix[key_idx / 32] |= 1u << (key_idx % 32);
            key_at = key_every > 5 ? key_at + key_every : -1;
        }
        if (frame == reset_at) {
            printf("reset at frame %d\n", frame);
            top->reset_in = 1; top->dio_download = 1;
            for (int i = 0; i < 64; i++) cycle32();
            top->reset_in = 0; top->dio_download = 0;
            reset_at = -1;
        }
        tick();
        if ((ticks % 6) != 1) continue;   // right after the rising edge of clk_32

        if (mouse_at >= 0 && frame >= mouse_at && ticks >= mouse_next) {
            static const int q[4][2] = {{0, 0}, {1, 0}, {1, 1}, {0, 1}};   // (A, B) quadrature
            int a = q[mouse_phase][0], b = q[mouse_phase][1];
            top->joy_mouse = mouse_amiga ? ((a << 1) | (b << 3)) : ((a << 1) | b);
            mouse_phase = (mouse_phase + 1) & 3;
            mouse_next = ticks + 6 * 64000;   // 2 ms at 32 MHz
        }

        if (rf_name) {
            bool rdata, index, track0, wprot;
            rd.step(top->rfd_sel_a, top->rfd_motor, top->rfd_side, top->rfd_dir_in, top->rfd_step, frame,
                    rdata, index, track0, wprot);
            top->rfd_rdata = rdata; top->rfd_index = index; top->rfd_track0 = track0; top->rfd_wprot = wprot;
        }

        // floppy A: mount while running (FLOPPY_AT), serve reads like the M2M firmware
        if (fd_name && frame == fd_at && fd_state == 0) {
            printf("floppy mounted at frame %d\n", frame);
            top->img_size = fd.size();
            top->fd_img_mounted = 1; cycle32(); cycle32();
            top->fd_img_mounted = 0;
            fd_at = -1;
        }
        if (fd_name) {
            if (fd_wait) fd_wait--;
            else switch (fd_state) {
            case 0:
                if (top->fd_sd_rd & 1) { fd_lba = top->fd_sd_lba; top->fd_sd_ack = 1; fd_idx = 0; fd_state = 1; fd_reads++;
                                         printf("floppy read sector %u (frame %d)\n", fd_lba, frame); }
                else if (top->fd_sd_wr & 1) { fd_lba = top->fd_sd_lba; top->fd_sd_ack = 1; fd_idx = 0; fd_state = 3;
                                         printf("floppy WRITE sector %u (frame %d)\n", fd_lba, frame); }
                break;
            case 1: {
                size_t o = (size_t)fd_lba * 512 + fd_idx * 2;
                uint8_t b0 = o < fd.size() ? fd[o] : 0, b1 = o + 1 < fd.size() ? fd[o + 1] : 0;
                top->sd_buff_addr = fd_idx; top->sd_buff_dout = b0 | (b1 << 8); top->sd_buff_wr = 1;
                fd_state = 2; fd_wait = 2; break; }
            case 2:
                top->sd_buff_wr = 0; fd_wait = 8;
                if (++fd_idx == 256) { top->fd_sd_ack = 0; fd_state = 0; fd_wait = 20; } else fd_state = 1;
                break;
            case 3:     // write: step through the sector buffer, the data is not stored
                top->sd_buff_addr = fd_idx; fd_wait = 3;
                if (++fd_idx == 256) { top->fd_sd_ack = 0; fd_state = 0; fd_wait = 20; }
                break;
            }
        }

        // hard disk: emulate the M2M firmware (slowly, one byte per 16 cycles like QNICE)
        if (hd_name) {
            if (hd_wait) hd_wait--;
            else switch (hd_state) {
            case 0:
                if (top->hd_sd_rd & 1) { hd_lba = top->hd_sd_lba; top->hd_sd_ack = 1; hd_idx = 0; hd_state = 1; hd_reads++;
                                         if (hd_trace) printf("hd read sector %u (frame %d)\n", hd_lba, frame); }
                else if (top->hd_sd_wr & 1) { hd_lba = top->hd_sd_lba; top->hd_sd_ack = 1; hd_idx = 0; hd_state = 3; hd_writes++;
                                         if (hd_trace) printf("hd write sector %u (frame %d)\n", hd_lba, frame); }
                break;
            case 1: {   // write one word into the sector buffer
                size_t o = (size_t)hd_lba * 512 + hd_idx * 2;
                uint8_t b0 = o < hd.size() ? hd[o] : 0, b1 = o + 1 < hd.size() ? hd[o + 1] : 0;
                top->sd_buff_addr = hd_idx; top->sd_buff_dout = b0 | (b1 << 8); top->sd_buff_wr = 1;
                hd_state = 2; hd_wait = 2; break; }
            case 2:
                top->sd_buff_wr = 0; hd_wait = 8;
                if (++hd_idx == 256) { top->hd_sd_ack = 0; hd_state = 0; hd_wait = 20; } else hd_state = 1;
                break;
            case 3:     // read one word from the sector buffer
                top->sd_buff_addr = hd_idx; hd_state = 4; hd_wait = 3; break;
            case 4: {
                size_t o = (size_t)hd_lba * 512 + hd_idx * 2;
                if (o + 1 < hd.size()) { hd[o] = top->hd_sd_buff_din & 0xff; hd[o + 1] = top->hd_sd_buff_din >> 8; }
                if (++hd_idx == 256) { hd_state = 5; hd_wait = hd_wr_delay; } else hd_state = 3;
                break; }
            case 5:     // end of a write: the firmware raises the ack after the SD card write
                top->hd_sd_ack = 0; hd_state = 0; hd_wait = 20; break;
            }
        }
        if (top->video_ce) {
            if (!top->video_hblank && !top->video_vblank && x < W && y < H) {
                uint8_t* p = &img[(y * W + x) * 3];
                p[0] = top->video_r8; p[1] = top->video_g8; p[2] = top->video_b8;
            }
            if (!top->video_hblank && !top->video_vblank) {
                x++;
                if (hx < hfirst) hfirst = hx;
                if (hx > hlast) hlast = hx;
            }
            hx++;
        }
        if (top->video_hs && !old_hs) { if (x > maxx) maxx = x; if (x > 0) y++; x = 0; hx = 0; lines++; }
        old_hs = top->video_hs;
        if (!top->dbg_cpu_as_n && old_as) { n_bus++; last_a = top->dbg_cpu_a << 1; }
        old_as = top->dbg_cpu_as_n;
        if (top->video_vs && !old_vs) {
            if (y > maxy) maxy = y;
            char name[256];
            if (frame % 10 == 9 || frame == frames - 1 || (dump_from >= 0 && frame >= dump_from)) {
                snprintf(name, sizeof(name), "%s_%03d.ppm", prefix.c_str(), frame);
                FILE* o = fopen(name, "wb");
                fprintf(o, "P6 %d %d 255\n", W, H); fwrite(img.data(), 1, img.size(), o); fclose(o);
            }
            printf("frame %d: %dx%d active, bus cycles %llu, last addr %06x, mono %d, reset %d, sdram err %d, hd rd %llu wr %llu, acsi sel %d busy %d state %d present %d irq %d din %02x mode %04x gpip %02x\n",
                   frame, maxx, y, (unsigned long long)n_bus, last_a, top->video_mono, top->dbg_reset, top->dbg_sdram_errors,
                   (unsigned long long)hd_reads, (unsigned long long)hd_writes,
                   top->dbg_acsi_sel, top->dbg_acsi_busy, top->dbg_acsi_state, top->dbg_hd_present,
                   top->dbg_acsi_irq, top->dbg_acsi_din, top->dbg_dma_mode, top->dbg_gpip);
            if (rf_name) printf("frame %d real floppy: head %d side %d, revolutions %llu, steps %llu, sel %d motor %d\n",
                                frame, rd.head, rd.sd, (unsigned long long)rd.revs, (unsigned long long)rd.steps,
                                top->rfd_sel_a, top->rfd_motor);
            printf("frame %d timing: %d lines, %.2f Hz, active pixels %d..%d after hsync\n", frame, lines,
                   6 * 32.083333e6 / (double)(ticks - vs_ticks), hfirst, hlast);
            fflush(stdout);
            frame++; y = 0; maxx = 0; lines = 0; vs_ticks = ticks; hfirst = 1 << 30; hlast = -1;
        }
        old_vs = top->video_vs;
    }
    if (hd_name && getenv("HD_OUT")) {
        FILE* h = fopen(getenv("HD_OUT"), "wb");
        fwrite(hd.data(), 1, hd.size(), h); fclose(h);
        printf("hard disk image saved: %s\n", getenv("HD_OUT"));
    }
    delete top;
    return 0;
}
