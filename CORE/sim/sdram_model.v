// Behavioral model of the IS42S16320F SDRAM (only what the Atari ST controller uses):
// ACTIVE, READ/WRITE with auto precharge, burst length 4 (reads), single writes, CAS latency 2.
//
// Timing: zero delay model. The read data of the first burst word is driven at the
// SDRAM clock edge that is CL cycles after the READ command until the next edge. This
// corresponds to the real data valid window (tAC after CL-1 .. tOH after CL) shifted by the
// output/input delays of the FPGA, i.e. the FPGA captures the first word with its clock edge
// that follows the SDRAM edge CL cycles after the command.
module sdram_model (
  input clk, input cke, input cs_n, input ras_n, input cas_n, input we_n,
  input [1:0] ba, input [12:0] a, input dqml, input dqmh, inout [15:0] dq
);
  reg [15:0] mem [0:(1<<23)-1];   // {ba, row[11:0], col[8:0]}
  reg [12:0] row [0:3];
  reg [22:0] rd_addr;
  reg  [3:0] rd_cnt;      // remaining words
  reg  [2:0] rd_delay;
  reg [15:0] dq_out;
  reg        dq_oe;
  reg        mode_set;
  integer    errors = 0;

  assign dq = dq_oe ? dq_out : 16'bz;

  wire [3:0] cmd = {cs_n, ras_n, cas_n, we_n};
  localparam CMD_ACTIVE = 4'b0011, CMD_READ = 4'b0101, CMD_WRITE = 4'b0100, CMD_PRECHARGE = 4'b0010,
             CMD_REFRESH = 4'b0001, CMD_MODE = 4'b0000;

  always @(posedge clk) begin
    dq_oe <= 1'b0;
    // read burst output pipeline
    if (rd_delay != 0) begin
      rd_delay <= rd_delay - 1'd1;
    end
    if (rd_delay == 1 || (rd_delay == 0 && rd_cnt != 0)) begin
      if (rd_cnt != 0) begin
        dq_out  <= mem[rd_addr];
        dq_oe   <= 1'b1;
        rd_addr <= {rd_addr[22:2], rd_addr[1:0] + 2'd1};   // sequential burst, wraps within 4 words
        rd_cnt  <= rd_cnt - 1'd1;
      end
    end

    case (cmd)
      CMD_MODE: begin
        mode_set <= 1'b1;
        if (a[6:4] != 3'd2 || a[2:0] != 3'b010 || a[9] != 1'b1) begin
          $display("SDRAM model: unexpected mode register %h", a); errors = errors + 1;
        end
      end
      CMD_ACTIVE: row[ba] <= a;
      CMD_READ: begin
        if (!mode_set) begin $display("SDRAM model: READ before mode set"); errors = errors + 1; end
        if (row[ba][12] || a[9]) begin $display("SDRAM model: address out of modelled range"); errors = errors + 1; end
        rd_addr  <= {ba, row[ba][11:0], a[8:0]};
        rd_cnt   <= 4;
        rd_delay <= 2;   // CAS latency 2
      end
      CMD_WRITE: begin
        if (row[ba][12] || a[9]) begin $display("SDRAM model: address out of modelled range"); errors = errors + 1; end
        if (!dqml) mem[{ba, row[ba][11:0], a[8:0]}][7:0]  <= dq[7:0];
        if (!dqmh) mem[{ba, row[ba][11:0], a[8:0]}][15:8] <= dq[15:8];
      end
      default: ;
    endcase
  end
endmodule
