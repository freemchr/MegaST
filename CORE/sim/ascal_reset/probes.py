#!/usr/bin/env python3
"""Simulation copies with a state report (issue #26 bench). Usage: probes.py M2M_VHDL_DIR OUTDIR"""
import sys, os
src, out = sys.argv[1], sys.argv[2]

def patch(rel, endmark, ctx, proc, extra=()):
    s = open(os.path.join(src, rel)).read()
    for a, b in extra:
        assert a in s, a
        s = s.replace(a, b)
    i = s.rindex(endmark)
    s = s[:i] + proc + s[i:]
    s = ctx + s
    open(os.path.join(out, os.path.basename(rel)), 'w').write(s)

b = "std_logic'image"
patch('av_pipeline/ascal.vhd', 'END ARCHITECTURE rtl;', 'library work; use work.dbg_pkg.all;\n', f'''
  DbgProbe: PROCESS BEGIN
    WAIT UNTIL probe_now;
    REPORT "PROBE ascal avl: state=" & type_avl_state'image(avl_state) & " read_sr=" & {b}(avl_read_sr) &
      " write_sr=" & {b}(avl_write_sr) & " read_i=" & {b}(avl_read_i) & " write_i=" & {b}(avl_write_i) &
      " readack=" & {b}(avl_readack) & " readdataack=" & {b}(avl_readdataack) &
      " read_sync=" & {b}(avl_read_sync) & {b}(avl_read_sync2) & " write_sync=" & {b}(avl_write_sync) & {b}(avl_write_sync2) &
      " avl_wad=" & integer'image(avl_wad) & " avl_rad=" & integer'image(avl_rad) & " reset_na=" & {b}(avl_reset_na);
    REPORT "PROBE ascal out: o_state=" & enum_o_state'image(o_state) & " o_read=" & {b}(o_read) &
      " o_read_pre=" & {b}(o_read_pre) & " readack_sync=" & {b}(o_readack_sync) & {b}(o_readack_sync2) &
      " readdataack_sync=" & {b}(o_readdataack_sync) & {b}(o_readdataack_sync2) &
      " o_readlev=" & integer'image(o_readlev) & " o_copylev=" & integer'image(o_copylev) & " o_run=" & {b}(o_run);
    REPORT "PROBE ascal in: i_write=" & {b}(i_write) & " i_wreq=" & {b}(i_wreq);
    WAIT;
  END PROCESS;
''')

patch('memory/avm_arbit.vhd', 'end architecture synthesis;', 'library work; use work.dbg_pkg.all;\n', f'''
   dbg_probe : process begin
      wait until probe_now;
      report "PROBE arbit " & avm_arbit'path_name & ": grant0=" & {b}(s0_active_grant) & " grant1=" & {b}(s1_active_grant) &
         " burstcount=" & integer'image(to_integer(unsigned(burstcount))) &
         " s0 rd/wr=" & {b}(s0_avm_read_i) & {b}(s0_avm_write_i) & " s1 rd/wr=" & {b}(s1_avm_read_i) & {b}(s1_avm_write_i) &
         " m wait=" & {b}(m_avm_waitrequest_i);
      wait;
   end process;
''')

patch('memory/avm_decrease.vhd', 'end architecture synthesis;', 'library work; use work.dbg_pkg.all;\n', f'''
   dbg_probe : process begin
      wait until probe_now;
      report "PROBE decrease: state=" & t_state'image(state) & " s rd/wr=" & {b}(s_avm_read_i) & {b}(s_avm_write_i) &
         " s wait=" & {b}(s_avm_waitrequest_o) & " m rd/wr=" & {b}(m_avm_read_o) & {b}(m_avm_write_o) &
         " m wait=" & {b}(m_avm_waitrequest_i);
      wait;
   end process;
''')
