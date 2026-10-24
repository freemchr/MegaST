// Strict behavioral model of the IS42S16320F SDRAM for the Falcon SDRAM adapter
// (falcon_sdram.v): burst length 4 for reads, single writes (mode 0x222, as
// sdram_m65.v uses it), CAS latency 2, auto precharge, DQM per write, and
// checks of the timing the adapter must keep
// (in clocks of 10.4 ns, the -7 speed grade at 96 MHz):
//   tRCD 2 (ACTIVE -> READ/WRITE), tRAS 5 (ACTIVE -> precharge), tRP 2,
//   tWR 2 (last write beat -> precharge), tRFC 6, refresh at least every 7.8 us,
//   no command to a bank that is not idle/open, no data bus conflict.
// Read data uses the same convention as ../sdram_model.v: beat 0 is driven from
// the clock edge CL cycles after the READ until the next edge.
module sdram_strict (
  input clk, input cs_n, input ras_n, input cas_n, input we_n,
  input [1:0] ba, input [12:0] a, input dqml, input dqmh, inout [15:0] dq,
  input fpga_drives     // the FPGA drives dq (for the conflict check)
);
  localparam CL = 2, T_RCD = 2, T_RAS = 5, T_RP = 2, T_WR = 2, T_RFC = 6, T_REF = 750;

  reg [15:0] mem [0:(1<<25)-1];   // {ba, row[12:0], col[9:0]}: 64 MB (the whole IS42S16320F)
  integer    errors = 0, refs = 0;
  longint    cyc = 0, last_ref = -1;   // 64 bit: a 32-bit count wraps after 22 s at 96 MHz
  reg        mode_set = 0;

  // per bank: open row, time of ACTIVE, time from which it is idle again
  reg [12:0] row [0:3];
  reg        open [0:3];
  longint    t_act [0:3], t_idle [0:3];
  longint    t_ref_done = 0;

  // read data pipeline: slot = cycle number mod 16
  reg        o_valid [0:15];
  reg [24:0] o_addr  [0:15];
  reg [15:0] dq_out;
  reg        dq_oe = 0;
  assign dq = dq_oe ? dq_out : 16'bz;

  // write burst in progress
  integer    w_left = 0;
  reg [24:0] w_addr;

  integer i;
  initial begin
    for (i = 0; i < 16; i = i + 1) o_valid[i] = 0;
    for (i = 0; i < 4; i = i + 1) begin open[i] = 0; t_idle[i] = 0; t_act[i] = 0; end
    for (i = 0; i < (1<<25); i = i + 1) mem[i] = 16'h0000;
  end

  task err(input [8*48-1:0] msg); begin
    $display("SDRAM model, cycle %0d: %0s", cyc, msg); errors = errors + 1;
  end endtask

  wire [3:0] cmd = {cs_n, ras_n, cas_n, we_n};
  localparam CMD_ACTIVE = 4'b0011, CMD_READ = 4'b0101, CMD_WRITE = 4'b0100, CMD_PRECHARGE = 4'b0010,
             CMD_REFRESH = 4'b0001, CMD_MODE = 4'b0000, CMD_NOP = 4'b0111;

  integer b, s;
  always @(posedge clk) begin
    cyc = cyc + 1;

    // read data out
    s = cyc % 16;
    dq_oe  <= o_valid[s];
    dq_out <= mem[o_addr[s]];
    if (o_valid[s] && fpga_drives) err("data bus conflict (read data)");
    o_valid[s] = 0;

    // write data in
    if (w_left != 0) begin
      if (!fpga_drives) err("write beat without data");
      if (!dqml) mem[w_addr][7:0]  = dq[7:0];
      if (!dqmh) mem[w_addr][15:8] = dq[15:8];
      w_addr = {w_addr[24:2], w_addr[1:0] + 2'd1};
      w_left = w_left - 1;
    end

    if (mode_set && last_ref >= 0 && cyc - last_ref > T_REF) begin
      err("refresh interval too long"); last_ref = cyc;
    end

    if (cmd != CMD_NOP && cmd[3] == 1'b0) begin
      if (cmd != CMD_MODE && cmd != CMD_PRECHARGE && cmd != CMD_REFRESH && cyc < t_ref_done) err("command during tRFC");
      if (w_left != 0 && cmd != CMD_NOP) err("command during a write burst");
    end

    case (cmd)
      CMD_MODE: begin
        mode_set = 1;
        if (a != 13'h222) err("unexpected mode register");
      end
      CMD_PRECHARGE: begin
        if (!a[10]) err("precharge of one bank");
        for (b = 0; b < 4; b = b + 1) begin open[b] = 0; t_idle[b] = cyc + T_RP; end
      end
      CMD_REFRESH: begin
        for (b = 0; b < 4; b = b + 1) if (open[b] || cyc < t_idle[b]) err("refresh with a bank not idle");
        t_ref_done = cyc + T_RFC;
        last_ref = cyc; refs = refs + 1;
      end
      CMD_ACTIVE: begin
        if (!mode_set) err("ACTIVE before mode set");
        if (open[ba]) err("ACTIVE on an open bank");
        if (cyc < t_idle[ba]) err("ACTIVE before precharge done (tRP/tWR)");
        if (cyc < t_ref_done) err("ACTIVE during tRFC");
        row[ba] = a; open[ba] = 1; t_act[ba] = cyc;
      end
      CMD_READ: begin
        if (!open[ba]) err("READ on a closed bank");
        if (cyc - t_act[ba] < T_RCD) err("READ before tRCD");
        if (a[1:0] != 0) err("READ not at a 4-beat boundary");
        for (i = 0; i < 4; i = i + 1) begin
          if (o_valid[(cyc + CL + i) % 16]) err("read bursts overlap");
          o_valid[(cyc + CL + i) % 16] = 1;
          o_addr[(cyc + CL + i) % 16]  = {ba, row[ba], a[9:0]} + i;
        end
        if (a[10]) begin   // auto precharge after the burst
          if (cyc + 4 - t_act[ba] < T_RAS) err("tRAS violated (read)");
          open[ba] = 0; t_idle[ba] = cyc + 4 + T_RP;
        end
      end
      CMD_WRITE: begin
        if (!open[ba]) err("WRITE on a closed bank");
        if (cyc - t_act[ba] < T_RCD) err("WRITE before tRCD");
        w_addr = {ba, row[ba], a[9:0]};
        if (!fpga_drives) err("WRITE without data");
        if (!dqml) mem[w_addr][7:0]  = dq[7:0];
        if (!dqmh) mem[w_addr][15:8] = dq[15:8];
        if (a[10]) begin   // auto precharge: tWR after the (single) write
          if (cyc + T_WR - t_act[ba] < T_RAS) err("tRAS violated (write)");
          open[ba] = 0; t_idle[ba] = cyc + T_WR + T_RP + 1;
        end
      end
      default: ;
    endcase
  end
endmodule
