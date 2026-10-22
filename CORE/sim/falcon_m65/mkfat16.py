#!/usr/bin/env python3
# Copied from the NF4 archive work: an MBR hard disk image with FAT16 partitions for the test bench.
# Builds a raw hard disk image (MBR, up to 4 primary FAT16 partitions) from host directories.
#   mkfat16.py IMAGE SPEC...        SPEC = LABEL:SIZE_MB:DIR[+DIR...]   (DIR=path or path=>NAME)
# Every DIR goes into the partition's root; "path=>NAME" puts the contents of path into \NAME.
# Long or invalid names become 8.3 names (BASE~N.EXT on collisions); each partition gets
# \NAMES.TXT with every renamed path.  verify: mkfat16.py --verify IMAGE SPEC...
import os, re, struct, sys, hashlib

SEC, SPC, RESERVED, NFATS, ROOT_ENTRIES, ALIGN = 512, 16, 4, 2, 512, 2048
CLUSTER = SEC * SPC
VALID = set("ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-!#$%&'()@^`{}~")
DATE = ((2006 - 1980) << 9) | (5 << 5) | 29      # the archive's last update, 29.05.2006
TIME = 12 << 11

def clean(s):
    return ''.join(c if c in VALID else '_' for c in s.upper())

def short_names(names):
    """host names of one directory -> {host name: (8, 3) name}, renamed ones flagged"""
    out, used = {}, set()
    for n in sorted(names, key=lambda x: x.upper()):
        u = n.upper().rstrip('.')
        base, ext = (u.rsplit('.', 1) + [''])[:2] if '.' in u.lstrip('.') else (u, '')
        b, e = clean(base.lstrip('.')) or '_', clean(ext)
        exact = (b == base and e == ext and len(b) <= 8 and len(e) <= 3)
        b, e = b[:8], e[:3]
        if not exact or (b, e) in used:
            i = 1
            while True:
                t = ('%s~%d' % (b[:7 - len(str(i))], i)) if (not exact or (b, e) in used) else b
                if (t, e) not in used: b = t; break
                i += 1
        used.add((b, e)); out[n] = ((b, e), not exact or u != n.upper())
    return out

def disp(be):
    return be[0] + ('.' + be[1] if be[1] else '')

class Node:
    def __init__(self, host, name, isdir):
        self.host, self.name, self.isdir, self.kids, self.cl, self.size = host, name, isdir, [], 0, 0

def build_tree(srcs):
    root = Node(None, ('', ''), True)
    renamed = []
    def add(parent, host, path):
        ents = sorted(os.listdir(host))
        names = short_names(ents)
        for e in ents:
            p = os.path.join(host, e); (be, ren) = names[e]
            if ren: renamed.append('%s\\%s  <-  %s' % (path, disp(be), e))
            n = Node(p, be, os.path.isdir(p)); parent.kids.append(n)
            if n.isdir: add(n, p, path + '\\' + disp(be))
            else: n.size = os.path.getsize(p)
    for s in srcs:
        if '=>' in s:
            host, name = s.split('=>')
            n = Node(host, (name, ''), True); root.kids.append(n); add(n, host, '\\' + name)
        else:
            add(root, s, '')
    return root, renamed

def dir_bytes(n): return (len(n.kids) + 2) * 32

def layout(part_secs):
    clusters_guess = part_secs // SPC
    fat_secs = (clusters_guess + 2) * 2 // SEC + 1
    root_secs = ROOT_ENTRIES * 32 // SEC
    data0 = RESERVED + NFATS * fat_secs + root_secs
    nclus = (part_secs - data0) // SPC
    assert 4085 <= nclus < 65525, nclus
    return fat_secs, root_secs, data0, nclus

def entry(name, attr, cl, size):
    return struct.pack('<8s3sB10sHHHI', name[0].ljust(8).encode(), name[1].ljust(3).encode(), attr,
                       b'\0' * 10, TIME, DATE, cl, size)

def make_part(img, start, secs, label, root):
    fat_secs, root_secs, data0, nclus = layout(secs)
    fat = [0xFFF8, 0xFFFF] + [0] * nclus
    nxt = [2]
    def alloc(nbytes):
        n = max(1, (nbytes + CLUSTER - 1) // CLUSTER); c0 = nxt[0]
        if c0 + n - 2 > nclus: raise SystemExit('partition %s full' % label)
        for i in range(n): fat[c0 + i] = c0 + i + 1 if i < n - 1 else 0xFFFF
        nxt[0] += n; return c0
    def walk(n):                                        # allocate: directories then files, depth first
        for k in n.kids:
            if k.isdir: k.cl = alloc(dir_bytes(k))
            elif k.size: k.cl = alloc(k.size)
        for k in n.kids:
            if k.isdir: walk(k)
    walk(root)
    off = lambda cl: (start + data0 + (cl - 2) * SPC) * SEC
    def write_dir(n, parent_cl):
        b = bytearray()
        if n is not root:
            b += entry(('.', ''), 0x10, n.cl, 0) + entry(('..', ''), 0x10, parent_cl, 0)
        for k in n.kids:
            b += entry(k.name, 0x10 if k.isdir else 0x20, k.cl, 0 if k.isdir else k.size)
        if n is root:
            b = entry((label[:8], label[8:11]), 0x08, 0, 0) + b
            assert len(b) <= ROOT_ENTRIES * 32, 'root of %s: too many entries' % label
            img.seek((start + RESERVED + NFATS * fat_secs) * SEC)
        else:
            img.seek(off(n.cl))
        img.write(bytes(b))
        for k in n.kids:
            if k.isdir: write_dir(k, 0 if n is root else n.cl)
            elif k.size:
                img.seek(off(k.cl))
                with open(k.host, 'rb') as f: img.write(f.read())
    write_dir(root, 0)
    bs = bytearray(SEC)
    bs[0:3] = b'\xEB\x3C\x90'; bs[3:11] = b'MEGAST  '
    struct.pack_into('<HBHBHHBHHHII', bs, 11, SEC, SPC, RESERVED, NFATS, ROOT_ENTRIES,
                     secs if secs < 65536 else 0, 0xF8, fat_secs, 63, 255, start, secs if secs >= 65536 else 0)
    struct.pack_into('<BBBI11s8s', bs, 36, 0x80, 0, 0x29, 0x4D535431, label.ljust(11).encode(), b'FAT16   ')
    bs[510:512] = b'\x55\xAA'
    img.seek(start * SEC); img.write(bytes(bs))
    fb = struct.pack('<%dH' % len(fat), *fat).ljust(fat_secs * SEC, b'\0')
    for i in range(NFATS):
        img.seek((start + RESERVED + i * fat_secs) * SEC); img.write(fb)
    return (nxt[0] - 2) * CLUSTER, nclus * CLUSTER

def parse(specs):
    out = []
    for s in specs:
        label, mb, dirs = s.split(':', 2)
        out.append((label.upper(), int(mb), dirs.split('+')))
    return out

def build(path, specs):
    parts, lba, mbr = parse(specs), ALIGN, bytearray(SEC)
    with open(path, 'wb') as img:
        for i, (label, mb, dirs) in enumerate(parts):
            secs = mb * 2048
            root, renamed = build_tree(dirs)
            if renamed:
                txt = ('Renamed to 8.3 (new name  <-  original name):\r\n' + '\r\n'.join(renamed) + '\r\n').encode('latin1', 'replace')
                tmp = path + '.names%d.txt' % i
                open(tmp, 'wb').write(txt)
                n = Node(tmp, ('NAMES', 'TXT'), False); n.size = len(txt); root.kids.append(n)
            used, total = make_part(img, lba, secs, label, root)
            print('%s: LBA %d, %d MB, %.0f of %.0f MB used, %d renamed' % (label, lba, mb, used / 2**20, total / 2**20, len(renamed)))
            struct.pack_into('<B3sB3sII', mbr, 446 + 16 * i, 0, b'\xFE\xFF\xFF', 0x06, b'\xFE\xFF\xFF', lba, secs)
            lba += secs
        mbr[510:512] = b'\x55\xAA'
        img.seek(0); img.write(bytes(mbr))
        img.truncate(lba * SEC)
    print('image %s: %d sectors (%.0f MB)' % (path, lba, lba * SEC / 2**20))

# ---- independent reader for the check ----
def verify(path, specs):
    f = open(path, 'rb'); rd = lambda lba, n: (f.seek(lba * SEC), f.read(n * SEC))[1]
    mbr = rd(0, 1); assert mbr[510:512] == b'\x55\xAA'
    bad = files = 0
    for i, (label, mb, dirs) in enumerate(parse(specs)):
        t, lba, secs = mbr[446 + 16 * i + 4], *struct.unpack_from('<II', mbr, 446 + 16 * i + 8)
        bs = rd(lba, 1)
        bps, spc, res, nf, nroot, s16, _, fsz = struct.unpack_from('<HBHBHHBH', bs, 11)
        fat = struct.unpack('<%dH' % (fsz * SEC // 2), rd(lba + res, fsz))
        root0 = lba + res + nf * fsz; rs = nroot * 32 // SEC; d0 = root0 + rs
        def chain(cl):
            out = []
            while 2 <= cl < 0xFFF8: out.append(cl); cl = fat[cl]
            return out
        def readcl(cl, size=None):
            b = b''.join(rd(d0 + (c - 2) * spc, spc) for c in chain(cl))
            return b if size is None else b[:size]
        def ents(b):
            for o in range(0, len(b), 32):
                e = b[o:o + 32]
                if e[0] == 0: break
                if e[0] == 0xE5 or e[11] & 0x08: continue
                nm = e[0:8].decode().rstrip() + ('.' + e[8:11].decode().rstrip() if e[8:11].strip() else '')
                if nm in ('.', '..'): continue
                yield nm, e[11], *struct.unpack_from('<HI', e, 26)
        tree = {}
        def walk(b, p):
            for nm, attr, cl, size in ents(b):
                if attr & 0x10: walk(readcl(cl), p + '\\' + nm)
                else: tree[(p + '\\' + nm).upper()] = (cl, size)
        walk(rd(root0, rs), '')
        root, renamed = build_tree(dirs)
        def cmp(n, p):
            nonlocal bad, files
            for k in n.kids:
                q = p + '\\' + disp(k.name)
                if k.isdir: cmp(k, q); continue
                files += 1
                cl, size = tree.get(q.upper(), (None, None))
                data = open(k.host, 'rb').read()
                if size != len(data) or (size and readcl(cl, size) != data):
                    bad += 1
                    if bad < 10: print('MISMATCH', label, q)
        cmp(root, '')
        print('%s: type %02x, %d files in image, %d sectors/cluster' % (label, t, len(tree), spc))
    print('checked %d files, %d mismatches' % (files, bad))
    return bad == 0

if __name__ == '__main__':
    if sys.argv[1] == '--verify': sys.exit(0 if verify(sys.argv[2], sys.argv[3:]) else 1)
    build(sys.argv[1], sys.argv[2:])
