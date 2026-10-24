// Flux level model of the MEGA65's internal floppy drive (the ST test bench tb.cpp and the Falcon's,
// falcon_m65/sim_main.cpp). MEGA65 port done by Chris Freeman in 2026, licensed under GPL v3
#pragma once
#include <cstdio>
#include <cstdint>
#include <vector>

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
