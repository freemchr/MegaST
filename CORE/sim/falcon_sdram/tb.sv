// Test of falcon_sdram.v: a master that behaves like falcon_memarb (one command
// at a time, RD/WE held until BUSY is low, reads of 1 or 4 words, 4-word reads
// aligned to 32 bytes) runs random reads and writes with random byte enables
// and compares every read word with a reference memory. The SDRAM model
// (sdram_strict.v) checks the SDRAM timing.
`timescale 1ps/1ps
module tb;
  reg clk_96 = 0, clk_32 = 0;
  always #5208  clk_96 = ~clk_96;   // rising edges of clk_32 fall on rising edges of clk_96
  always #15624 clk_32 = ~clk_32;

  reg         init = 1;
  wire        busy;
  reg   [2:0] burstcnt = 1;
  reg  [20:0] addr = 0;
  wire [63:0] dout;
  wire        dout_ready;
  reg         rd = 0, we = 0;
  reg  [63:0] din = 0;
  reg   [7:0] be = 0;

  wire [15:0] sd_data;
  wire [12:0] sd_addr;
  wire  [1:0] sd_dqm, sd_ba;
  wire        sd_cs, sd_we, sd_ras, sd_cas, sd_clk;

  falcon_sdram dut (
    .init(init), .clk_32(clk_32), .clk_96(clk_96),
    .busy(busy), .burstcnt(burstcnt), .addr(addr), .dout(dout), .dout_ready(dout_ready),
    .rd(rd), .din(din), .be(be), .we(we),
    .sd_data(sd_data), .sd_addr(sd_addr), .sd_dqm(sd_dqm), .sd_ba(sd_ba),
    .sd_cs(sd_cs), .sd_we(sd_we), .sd_ras(sd_ras), .sd_cas(sd_cas), .sd_clk(sd_clk)
  );

  sdram_strict sdram (
    .clk(sd_clk), .cs_n(sd_cs), .ras_n(sd_ras), .cas_n(sd_cas), .we_n(sd_we),
    .ba(sd_ba), .a(sd_addr), .dqml(sd_dqm[0]), .dqmh(sd_dqm[1]), .dq(sd_data),
    .fpga_drives(dut.sd_doe[0])
  );

  // reference memory (only the addresses the test uses)
  reg [63:0] ref_mem [int];
  function [63:0] ref_rd(input [20:0] a);
    ref_rd = ref_mem.exists(a) ? ref_mem[a] : 64'h0;
  endfunction

  integer errors = 0, n_rd = 0, n_rd4 = 0, n_wr = 0, words = 0;
  longint t_start, t_busy;
  integer  max_wait = 0;

  // a few rows in every bank, plus the edges of the 16 MB
  function [20:0] rnd_addr();
    reg [20:0] a;
    a = {$urandom} & 21'h1fffff;
    case ($urandom % 4)
      0: a = {a[20:10] & 11'h007, a[9:0]};       // few rows: hits and misses of open rows
      1: a = {11'h7ff, a[9:0]};                  // last row of each bank
      default: ;
    endcase
    rnd_addr = a;
  endfunction

  // The master drives its signals at the falling edge of clk_32 (no races with the
  // DUT); RD/WE are taken at the first rising edge with BUSY low.
  task automatic cmd_issue();
    t_start = $time;
    do @(posedge clk_32); while (busy);
    if (($time - t_start) / 31248 > max_wait) max_wait = ($time - t_start) / 31248;
    @(negedge clk_32);
    rd = 0; we = 0;
  endtask

  task automatic do_write(input [20:0] a, input [63:0] d, input [7:0] m);
    integer i;
    reg [63:0] r;
    @(negedge clk_32);
    addr = a; din = d; be = m; burstcnt = 1; we = 1;
    cmd_issue();
    r = ref_rd(a);
    for (i = 0; i < 8; i = i + 1) if (m[i]) r[8*i +: 8] = d[8*i +: 8];
    ref_mem[a] = r;
    n_wr = n_wr + 1;
  endtask

  task automatic do_read(input [20:0] a, input integer n);
    integer i, got;
    reg [20:0] wa;
    @(negedge clk_32);
    addr = a; burstcnt = n; rd = 1;
    cmd_issue();
    got = 0;
    while (got < n) begin
      @(posedge clk_32);
      if (dout_ready) begin
        wa = a + got;
        if (dout !== ref_rd(wa)) begin
          if (errors < 10) $display("ERROR: read %06x word %0d: %016x, expected %016x, model %04x %04x %04x %04x, t=%0t", a, got, dout, ref_rd(wa),
            sdram.mem[{wa[9:8], wa[20:10], wa[7:0], 2'd3}], sdram.mem[{wa[9:8], wa[20:10], wa[7:0], 2'd2}],
            sdram.mem[{wa[9:8], wa[20:10], wa[7:0], 2'd1}], sdram.mem[{wa[9:8], wa[20:10], wa[7:0], 2'd0}], $time);
          errors = errors + 1;
        end
        got = got + 1; words = words + 1;
      end
      if ($time - t_start > 64'd5_000_000) begin $display("ERROR: read %06x timed out", a); errors = errors + 1; got = n; end
    end
    if (n == 4) n_rd4 = n_rd4 + 1; else n_rd = n_rd + 1;
  endtask

  // no DOUT_READY outside of reads
  reg in_read = 0;

  integer k, ops;
  reg [20:0] a;
  initial begin
    ops = 40000;
    if ($value$plusargs("ops=%d", ops)) ;
    repeat (20) @(posedge clk_32);
    init <= 0;
    // wait for the initialization (BUSY)
    do @(posedge clk_32); while (busy);
    $display("SDRAM initialized after %0t us", $time / 1000000);
    for (k = 0; k < ops; k = k + 1) begin
      a = rnd_addr();
      case ($urandom % 8)
        0, 1, 2:  do_write(a, {$urandom, $urandom}, ($urandom % 4 == 0) ? 8'hff : $urandom);
        3, 4:     do_read({a[20:2], 2'b00}, 4);
        default:  do_read(a, 1);
      endcase
      if ($urandom % 4 == 0) repeat ($urandom % 40) @(posedge clk_32);   // idle gaps (refresh gets in)
    end
    // read back everything written
    foreach (ref_mem[i]) do_read(i, 1);
    repeat (50) @(posedge clk_32);
    $display("%0d writes, %0d single reads, %0d 4-word reads, %0d words checked, %0d refreshes, longest BUSY wait %0d clocks",
             n_wr, n_rd, n_rd4, words, sdram.refs, max_wait);
    $display("%0d data errors, %0d SDRAM timing errors", errors, sdram.errors);
    if (errors == 0 && sdram.errors == 0) $display("PASS"); else $display("FAIL");
    $finish;
  end
endmodule
