# Test data for rosmfix_test.asm: the menu of config.vhd (OPTM_GROUPS as the config.vhd device delivers
# it, the OPTM_G_STDSEL defaults) and settings files to check. Also the expected result of each
# (the rule of rosmfix.asm, written independently here).
#   gen.py <config.vhd> <out.asm> <expected.txt> [stcfg ...]
import re, sys

vhd = open(sys.argv[1]).read()
consts = {}
for name, val in re.findall(r'constant\s+(OPTM_G_\w+)\s*:\s*integer\s*:=\s*([^;]+);', vhd):
    val = val.strip()
    m = re.fullmatch(r'16#([0-9A-Fa-f]+)#', val)
    consts[name] = int(m.group(1), 16) if m else int(val)
blk = vhd[vhd.index('constant OPTM_GROUPS'):]
blk = blk[blk.index('(') + 1:blk.index(');')]
items = [re.sub(r'--.*', '', l).strip().rstrip(',') for l in blk.split('\n')]
items = [eval(i, {}, consts) for i in items if i]
n = len(items)
groups = [((v >> 15) & 1) << 15 | ((v >> 14) & 1) << 14 | ((v >> 12) & 1) << 12 | (v & 0xFF) for v in items]
std = [(v >> 8) & 1 for v in items]

def gid(w):
    if w & 0x8000 or w & 0x4000: return 0
    g = w & 0xFF
    return 0 if g == 0xFF else g

def fix(cfg):
    out = list(cfg)
    for g in {gid(w) for w in groups} - {0}:
        idx = [i for i in range(n) if gid(groups[i]) == g]
        if sum(cfg[i] for i in idx) != 1:
            for i in idx: out[i] = std[i]
    return out

cases = []
for f in sys.argv[4:]:
    b = open(f, 'rb').read()
    assert len(b) == n, f'{f}: {len(b)} bytes, menu has {n} items'
    cases.append(list(b))
cases.append(fix(std))                              # the defaults: valid, unchanged
c = list(std); c[12], c[13] = 0, 1; cases.append(c)  # valid other choice, unchanged
multi = [g for g in {gid(w) for w in groups} - {0} if sum(gid(w) == g for w in groups) > 1]
c = list(std)                                       # two selected in every group
for g in multi:
    idx = [i for i in range(n) if gid(groups[i]) == g]
    c[idx[0]] = c[idx[1]] = 1
cases.append(c)
cases.append([0] * n)                               # nothing selected at all
cases.append([1] * n)                               # everything selected

with open(sys.argv[2], 'w') as o:
    o.write(f'TD_ITEMS        .EQU    {n}\nTD_CASES        .EQU    {len(cases)}\n')
    def dw(label, vals):
        o.write(f'{label:<16}.DW     ' + ', '.join(f'0x{v:04X}' for v in vals[:16]) + '\n')
        for k in range(16, len(vals), 16):
            o.write(' ' * 16 + '.DW     ' + ', '.join(f'0x{v:04X}' for v in vals[k:k + 16]) + '\n')
    dw('TD_GROUPS', groups)
    dw('TD_STD', std)
    dw('TD_CFG', [v for c in cases for v in c])
with open(sys.argv[3], 'w') as o:
    for k, c in enumerate(cases):
        o.write(f'CASE {k}: ' + ''.join(str(v) for v in fix(c)) + '\n')
print(f'{n} menu items, {len(multi)} groups of options, {len(cases)} cases')
