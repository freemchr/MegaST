#!/usr/bin/env python3
# Converts the WF1772IP sources (16 MHz clock) to a clock enable: every clocked process only
# advances when CE = '1', so the IP runs on the 32 MHz core clock with CE at half rate.
# The INPORT process (RDn sampled on the falling clock edge) becomes a rising edge register
# without CE (m65_floppy_port already synchronises RDATA).
# Usage: wf1772_ce.py [--fix-only] <original dir> <output dir>  (bug fixes: FIXES below)
import os, re, sys

EDGE = re.compile(r"^(\s*)(els)?if CLK = '1' and CLK' event then\s*$", re.I)
WAIT = re.compile(r"^(\s*)wait until CLK = '1' and CLK' event;\s*$", re.I)
WAITF = re.compile(r"^(\s*)wait until CLK = '0' and CLK' event;\s*$", re.I)
PSTART = re.compile(r"^(\s*)(\w+\s*:\s*)?process\b(.*)$", re.I)
PEND = re.compile(r"^\s*end process", re.I)
PORT_CLK = re.compile(r"^(\s*)CLK(\s*):(\s*)in std_logic;(.*)$", re.I)
MAP_CLK = re.compile(r"^(\s*)CLK(\s*)=>(\s*)CLK,(.*)$", re.I)

def code(l):
    return l.split('--')[0]

def is_if(l):
    c = code(l).strip().lower()
    return bool(re.match(r"if\b", c)) and c.endswith('then')

def is_endif(l):
    return bool(re.match(r"end if\b", code(l).strip().lower()))

def is_else(l):
    c = code(l).strip().lower()
    return bool(re.match(r"(elsif|else)\b", c))

def convert(text, name):
    lines = text.split('\n')
    out = []
    i = 0
    n_edge = n_wait = 0
    while i < len(lines):
        l = lines[i]
        m = PSTART.match(code(l))
        if m and not code(l).strip().lower().startswith('end'):
            j = i
            while not PEND.match(lines[j]):
                j += 1
            body = lines[i:j + 1]
            edges = [k for k, b in enumerate(body) if EDGE.match(b)]
            waits = [k for k, b in enumerate(body) if WAIT.match(b)]
            waitf = [k for k, b in enumerate(body) if WAITF.match(b)]
            assert len(edges) + len(waits) + len(waitf) <= 1, (name, i)
            if edges:
                k = edges[0]
                ind = EDGE.match(body[k]).group(1)
                depth, close = 1, None
                for q in range(k + 1, len(body)):
                    if is_if(body[q]):
                        depth += 1
                    elif is_endif(body[q]):
                        depth -= 1
                        if depth == 0:
                            close = q
                            break
                    elif depth == 1 and is_else(body[q]):
                        raise SystemExit('%s:%d: branch after the clock edge' % (name, i + q + 1))
                assert close is not None, (name, i)
                rest = [b for b in body[close + 1:-1] if code(b).strip()]
                if rest:
                    print('note: %s:%d: code after the clocked if (check by hand): %s' % (name, i + close + 1, rest[0].strip()))
                body[k] = body[k] + '\n' + ind + "    if CE = '1' then -- MegaST: clock enable"
                body[close] = ind + "    end if; -- MegaST: clock enable\n" + body[close]
                n_edge += 1
            elif waits or waitf:
                k = (waits or waitf)[0]
                ind = (WAIT.match(body[k]) or WAITF.match(body[k])).group(1)
                hdr = PSTART.match(body[0])
                assert hdr.group(3).strip() == '' or hdr.group(3).strip().startswith('--'), (name, body[0])
                body[0] = body[0].rstrip() + '(CLK) -- MegaST: clocked process instead of wait until'
                if waits:
                    body[k] = ind + "if CLK = '1' and CLK' event then -- MegaST: clock enable\n" + ind + "if CE = '1' then"
                    body[-1] = ind + "end if;\n" + ind + "end if;\n" + body[-1]
                else:
                    body[k] = ind + "if CLK = '1' and CLK' event then -- MegaST: rising edge (RDATA is synchronised outside)"
                    body[-1] = ind + "end if;\n" + body[-1]
                n_wait += 1
            out.extend(body)
            i = j + 1
            continue
        mp = PORT_CLK.match(l)
        if mp:
            out.append(l)
            out.append("%sCE%s:%sin std_logic := '1'; -- MegaST: clock enable (CLK / 2 for the 16 MHz timing)" % (mp.group(1), mp.group(2), mp.group(3)))
            i += 1
            continue
        mm = MAP_CLK.match(l)
        if mm:
            out.append(l)
            out.append("%sCE%s=>%sCE," % (mm.group(1), mm.group(2), mm.group(3)))
            i += 1
            continue
        out.append(l)
        i += 1
    return '\n'.join(out), n_edge, n_wait

# Bug fixes, applied to the original before the conversion: (file, original text, replacement).
# Force interrupt from idle (issue #24): IDLE started a command on CMD_WR (the bus write, combinational)
# while CMD (the command register) still held the previous command. A force interrupt written while idle
# therefore restarted the previous command: after a reset a restore with spin-up, busy until 6 index
# pulses. A command written next was ignored (EmuTOS: no drive A:). IDLE now waits for the second clock
# of the write, when CMD holds the new value.
FIXES = [
    ('wf1772ip_control.vhd',
     "signal CMD_WR           : boolean;\n",
     "signal CMD_WR           : boolean;\n"
     "signal CMD_WR_D         : boolean; -- MegaST fix: CMD_WR one clock later (force interrupt from idle)\n"),
    ('wf1772ip_control.vhd',
     "                if CMD_WR = true and CMD /= x\"FF\" and CMD(7 downto 4) /= x\"D\" then\n",
     "                -- MegaST fix: CMD_WR_D, CMD holds the new command from the second clock of the write on.\n"
     "                if CMD_WR = true and CMD_WR_D = true and CMD /= x\"FF\" and CMD(7 downto 4) /= x\"D\" then\n"),
    ('wf1772ip_control.vhd',
     "    CMD_WR <= true when CSn = '0' and A1 = '0' and A0 = '0' and RWn = '0' else false; -- Command register write.\n",
     "    CMD_WR <= true when CSn = '0' and A1 = '0' and A0 = '0' and RWn = '0' else false; -- Command register write.\n"
     "\n"
     "    P_CMD_WR_D: process(RESETn, CLK) -- MegaST fix: force interrupt from idle\n"
     "    begin\n"
     "        if RESETn = '0' then\n"
     "            CMD_WR_D <= false;\n"
     "        elsif CLK = '1' and CLK' event then\n"
     "            CMD_WR_D <= CMD_WR;\n"
     "        end if;\n"
     "    end process P_CMD_WR_D;\n"),
]

def fix(text, name):
    for f, old, new in FIXES:
        if f == name:
            assert text.count(old) == 1, (name, old)
            text = text.replace(old, new)
    return text

# --fix-only: only the bug fixes, no clock enable (the reference of the equivalence test)
fix_only = sys.argv[1] == '--fix-only'
if fix_only:
    del sys.argv[1]
src, dst = sys.argv[1], sys.argv[2]
os.makedirs(dst, exist_ok=True)
for f in sorted(os.listdir(src)):
    if not f.endswith('.vhd') or f == 'wf1772ip_top.vhd':
        continue
    t = open(os.path.join(src, f), encoding='latin-1').read().replace('\r', '')
    t = fix(t, f)
    if fix_only:
        open(os.path.join(dst, f), 'w', encoding='latin-1').write(t)
        continue
    t, ne, nw = convert(t, f)
    if ne or nw or 'CE' in t:
        t = t.replace('\n', '\n', 0)
    open(os.path.join(dst, f), 'w', encoding='latin-1').write(t)
    print('%-28s clocked processes converted: %2d, wait processes: %d' % (f, ne, nw))
