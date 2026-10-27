#!/usr/bin/env python3
"""
Puts the MegaST logo onto the welcome screen of the on-screen display (OSD) as font characters.

The OSD is a text screen of 16x16 characters, each with one foreground and one background colour
(attribute byte: bit 7 inverse, bit 6 dark, bits 5..3 background, bits 2..0 foreground; the 16
colours come from OSM_PALETTE in globals.vhd). The logo is rebuilt from such cells: letters 64
pixels (4 rows) high in a grey pill of 5 rows, each of the four colour stripes in its own row, so
that no cell needs more than one colour on its background. The cells become characters in a copy
of the M2M font (codes the core does not use otherwise), and the logo becomes the VHDL string
SCR_LOGO in config.vhd: the characters with ESC + attribute bytes (SCR$PRINTSTR in screen.asm).

    python3 tools/osd_logo.py [--preview out.png]

Reads doc/logo/megast-logo.png and M2M/font/Anikki-16x16-m2m.rom; writes CORE/font/MegaST-16x16.rom
and the block between the osd_logo.py markers in CORE/vhdl/config.vhd. Needs Pillow and numpy.
For another core: change the geometry below (letters, stripes, sizes) and the palette indices.

Part of MegaST (Atari ST/STe for MEGA65), done by Chris Freeman in 2026, licensed under GPL v3
"""

import argparse
import os
import re

import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LOGO = os.path.join(ROOT, 'doc/logo/megast-logo.png')
FONT_IN = os.path.join(ROOT, 'M2M/font/Anikki-16x16-m2m.rom')
FONT_OUT = os.path.join(ROOT, 'CORE/font/MegaST-16x16.rom')
CONFIG = os.path.join(ROOT, 'CORE/vhdl/config.vhd')

# geometry of doc/logo/megast-logo.png (pixels)
C_X0, C_X1 = 126, 1864                 # letters: left and right edge
C_Y0, C_Y1 = 69, 295                   # letters: top and bottom edge
S_X = 1416                             # the stripes are left of it, the S of "ST" right of it
STRIPES = [(3, 85), (4, 138), (5, 190), (6, 241)]    # class and top edge of each stripe
SLANT = 25 / 52                        # the stripes start along the slant of the A: x per y

# the logo on the OSD: cells, letters 64 pixels high at y 8..72 of the pill
CW, CH = 35, 5
LOGO_X = 1                             # spaces before the logo (after the frame)

# colour classes of the logo: 0 outside the pill, 1 pill grey, 2 white, 3 blue, 4 green, 5 yellow,
# 6 orange; colours of the source and the palette index of each class in the dark half of
# OSM_PALETTE (attribute bit 6 = 1: fg = 8 + bits 2..0, bg = 8 + bits 5..3)
REF = {1: (43, 43, 43), 2: (240, 240, 240), 3: (0, 137, 252), 4: (6, 235, 17), 5: (252, 248, 3), 6: (253, 71, 0)}
DARK_IDX = {1: 0, 2: 1, 3: 2, 4: 3, 5: 4, 6: 5}      # 8 + n
ATTR_STD = 0x0B                        # M2M$SA_COL_STD: text (index 3) on the background (index 1)
ATTR_END = 0x08                        # pill grey (index 0) on the screen background (index 1)

# font codes the core never prints: not ASCII, not the M2M frame/line/menu characters
KEEP = {0, 7, 10, 13, 16, 17, 27, 182, 185, 186, 187, 188, 196, 199, 200, 201, 204, 205, 254, 255}
FREE = [c for c in list(range(1, 32)) + list(range(127, 256)) if c not in KEEP]


def classify(im):
    refs = np.array([REF[k] for k in sorted(REF)])
    d = ((im[:, :, None, :] - refs[None, None]) ** 2).sum(3)
    cls = d.argmin(2) + 1
    cls[im.sum(2) < 45] = 0
    return cls


def render(cls):
    """the logo as classes on the CW x CH cell canvas"""
    W, H = CW * 16, CH * 16
    s = 64 / (C_Y1 - C_Y0)
    mx = (W - (C_X1 - C_X0) * s) / 2

    def src(x, y):
        return C_X0 + (x - mx) / s, C_Y0 + (y - 8) / s

    def sample(xs, ys):
        xi, yi = int(round(xs)), int(round(ys))
        if 0 <= yi < cls.shape[0] and 0 <= xi < cls.shape[1]:
            return cls[yi, xi]
        return 0

    R = H / 2
    canvas = np.zeros((H, W), int)
    for y in range(H):
        for x in range(W):
            xc = min(max(x + 0.5, R), W - R)
            if (x + 0.5 - xc) ** 2 + (y + 0.5 - R) ** 2 > R * R:
                continue
            votes = {}
            for dy in (0.17, 0.5, 0.83):
                for dx in (0.17, 0.5, 0.83):
                    xs, ys = src(x + dx, y + dy)
                    k = sample(xs, ys)
                    k = k if k == 2 or (k == 3 and xs >= S_X) else 1
                    votes[k] = votes.get(k, 0) + 1
            canvas[y, x] = max(votes, key=votes.get)
    # stripe i into cell row i + 1, from the top of the row, moved along the slant
    for i, (k, top) in enumerate(STRIPES):
        dy = 16 * (i + 1) - ((top - C_Y0) * s + 8)
        for y in range(16 * (i + 1), 16 * (i + 1) + 10):
            for x in range(W):
                xs, ys = src(x + 0.5 - SLANT * dy, y + 0.5 - dy)
                if xs < S_X and sample(xs, ys) == k and canvas[y, x] == 1:
                    canvas[y, x] = k
    return canvas


def cells_of(canvas):
    """per cell: (fg class, bg class, 16 rows of 16 bits); one colour besides the background"""
    cells = []
    for cy in range(CH):
        row = []
        for cx in range(CW):
            c = canvas[cy * 16:(cy + 1) * 16, cx * 16:(cx + 1) * 16].copy()
            if (c == 0).any() and (c > 1).any():
                c[c == 0] = 1          # a letter in the round end: square the few pixels off
            ks, ns = np.unique(c[c > 1], return_counts=True)
            if len(ks) > 1:            # two colours: the larger part stays, the rest becomes grey
                keep = ks[ns.argmax()]
                c[(c > 1) & (c != keep)] = 1
            bg = 0 if (c == 0).any() else 1
            fgs = [k for k in np.unique(c) if k != bg]
            fg = fgs[0] if fgs else bg
            glyph = [sum(1 << (15 - x) for x in range(16) if c[y, x] == fg) for y in range(16)]
            row.append((int(fg), bg, glyph))
        cells.append(row)
    return cells


def encode(cells, font):
    """font codes and attributes of the cells; the new glyphs go into font"""
    slots, out = {}, []
    for row in cells:
        line = []
        for fg, bg, g in row:
            t = tuple(g)
            if bg == 0:                # outside the pill: screen background, pill grey as fg
                attr = ATTR_STD if not any(t) else ATTR_END
            else:                      # on the pill: dark half
                attr = 0x40 | (DARK_IDX[1] << 3) | DARK_IDX.get(fg, 0)
            if not any(t):
                code = 32
            elif all(v == 0xFFFF for v in t):   # all foreground: a space with the colour as bg
                code, attr = 32, 0x40 | (DARK_IDX[fg] << 3)
            else:
                if t not in slots:
                    if len(slots) == len(FREE):
                        raise SystemExit('too many different logo characters')
                    slots[t] = FREE[len(slots)]
                    font[slots[t]] = list(t)
                code = slots[t]
            line.append((code, attr))
        out.append(line)
    return out, len(slots)


def vhdl(rows):
    lines = ['constant SCR_LOGO : string :=']
    for row in rows:
        parts, cur = [], None
        parts.append('CHR_ESC & character\'val(16#%02X#) & "%s"' % (ATTR_STD, ' ' * LOGO_X))
        cur = ATTR_STD
        for code, attr in row:
            if attr != cur:
                parts.append('CHR_ESC & character\'val(16#%02X#)' % attr)
                cur = attr
            parts.append('" "' if code == 32 else 'character\'val(%d)' % code)
        parts.append('"\\n"')
        # 6 terms per source line
        for i in range(0, len(parts), 6):
            lines.append('   ' + ' & '.join(parts[i:i + 6]) + ' &')
    lines.append('   CHR_ESC & character\'val(16#%02X#);' % ATTR_STD)
    return lines


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n\n')[1])
    ap.add_argument('--preview', help='also write a PNG of the logo cells (2x)')
    a = ap.parse_args()

    cls = classify(np.array(Image.open(LOGO).convert('RGB')).astype(int))
    cells = cells_of(render(cls))
    rom = [l.strip() for l in open(FONT_IN) if l.strip()]
    font = {c: [int(rom[c * 16 + y], 2) for y in range(16)] for c in range(256)}
    rows, n = encode(cells, font)
    os.makedirs(os.path.dirname(FONT_OUT), exist_ok=True)
    with open(FONT_OUT, 'w') as f:
        for c in range(256):
            for v in font[c]:
                f.write('{:016b}\n'.format(v))

    text = open(CONFIG).read()
    begin = '-- osd_logo.py: begin (generated by tools/osd_logo.py, do not edit)\n'
    end = '-- osd_logo.py: end\n'
    m = re.search(re.escape(begin) + '.*?' + re.escape(end), text, re.S)
    if not m:
        raise SystemExit('config.vhd: osd_logo.py markers not found')
    block = begin + '\n'.join(vhdl(rows)) + '\n' + end
    open(CONFIG, 'w').write(text[:m.start()] + block + text[m.end():])
    print('%d logo characters (of %d free codes), %s, config.vhd updated' % (n, len(FREE), FONT_OUT))

    if a.preview:
        pal = {0: (255, 255, 255), 1: (43, 43, 43), 2: (240, 240, 240), 3: (0, 137, 252),
               4: (6, 235, 17), 5: (252, 248, 3), 6: (253, 71, 0)}
        img = np.zeros((CH * 16, CW * 16, 3), np.uint8)
        for cy, row in enumerate(cells):
            for cx, (fg, bg, g) in enumerate(row):
                for y in range(16):
                    for x in range(16):
                        img[cy * 16 + y, cx * 16 + x] = pal[fg] if (g[y] >> (15 - x)) & 1 else pal[bg]
        Image.fromarray(img).resize((CW * 32, CH * 32), Image.NEAREST).save(a.preview)


if __name__ == '__main__':
    main()
