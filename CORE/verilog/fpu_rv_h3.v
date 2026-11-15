// fpu_rv_h3.v - the MC68882 service of the Falcon's FPU bridge on a RISC-V in the FPGA:
// fpu_rv.v with Hazard3 (Luke Wren, Apache 2.0, CORE/hazard3) instead of PicoRV32.
//
// Same ports, memory map, mailbox and program (CORE/falcon_fpu/rv) as fpu_rv.v; only the CPU
// and its RAM interface differ. PicoRV32 needs about 4 clocks per instruction; Hazard3 is a
// 3-stage pipeline (about 1.2), RV32IM with a single-cycle MUL. In the core it runs on its own
// clock, 80.2 MHz (clk_96 is the name of the port, clk.vhd CLKOUT2): it does not reach 96 MHz in
// the whole design (WNS -1.2 ns, register file to RAM address). MULH_FAST (-2.6 ns) and the bit
// manipulation extensions (regfile to fetch address) are off for the same reason; the register file
// is in LUT RAM (HAZARD3_REGFILE_RAM_STYLE_DISTRIBUTED, defined in the Vivado projects).
// The mailbox side (clk_32) samples the bridge's request in the RISC-V's clock: both clocks come
// from the same MMCM, their nearest edges are 6.2 ns apart, and Vivado times the crossing.
//   $00000000  256 KB RAM: code, data, stack (loaded at configuration from G_HEX)
//   $10000000  1 KB mailbox (guest $E90000..$E903FF): 32-bit words, bytes in memory order
//   $20000000  debug byte out, $20000004 exit (simulation only, see sim/fpu_rv)
//
// Buses: Hazard3's instruction port reads port A of the RAM, its data port uses port B (RAM)
// and the mailbox. Both are AHB-Lite: the address phase puts the address on the RAM, which
// reads at the end of it, so read data is there in the data phase (no wait state). A write
// gets its data in the data phase and writes then; a RAM read whose address phase falls on
// that clock waits one clock (the port is busy). The mailbox (shared with the bridge, which
// has priority) and the debug port are accessed in the data phase, with wait states.
//
// The program is never reset: it runs from the configuration on (see fpu_rv.v).
//
// MEGA65 port done by Chris Freeman in 2026, licensed under GPL v3
`default_nettype none

module fpu_rv #(
	parameter G_HEX = "fpu_rv_h3.mem"
) (
	input  wire        clk_96,

	// bridge side (clk_32)
	input  wire        clk_32,
	input  wire        d3_req,
	input  wire        d3_we,
	input  wire [23:1] d3_addr,
	input  wire  [1:0] d3_be,
	input  wire [15:0] d3_wdata,
	output reg  [15:0] d3_rdata,
	output reg         d3_ack,

	// simulation
	output reg         dbg_out,       // dbg_byte is a byte of the program's stdout
	output reg   [7:0] dbg_byte,
	output reg         dbg_exit,      // the program ended (dbg_code)
	output reg  [31:0] dbg_code
);

// ---------------------------------------------------------------------------
// RISC-V
// ---------------------------------------------------------------------------
reg  [3:0] rv_rst = 4'd0;
wire       rv_resetn = rv_rst[3];
always @(posedge clk_96) if (!rv_rst[3]) rv_rst <= rv_rst + 4'd1;

wire [31:0] i_haddr, d_haddr, d_hwdata;
wire  [1:0] i_htrans, d_htrans;
wire  [2:0] d_hsize;
wire        d_hwrite;
wire [31:0] i_hrdata;
reg  [31:0] d_hrdata;
wire        d_hready;
wire        pwrup_req;

hazard3_cpu_2port #(
	.RESET_VECTOR(32'h0000_0000), .MTVEC_INIT(32'h0000_0000),
	.EXTENSION_A(0), .EXTENSION_C(0), .EXTENSION_M(1),
	.EXTENSION_ZBA(0), .EXTENSION_ZBB(0), .EXTENSION_ZBS(0),	// off: 96 MHz (regfile -> fetch_addr)
	.CSR_M_MANDATORY(1), .CSR_M_TRAP(1), .CSR_COUNTER(1),
	.DEBUG_SUPPORT(0), .NUM_IRQS(1),
	.MULDIV_UNROLL(2), .MUL_FAST(1), .MUL_FASTER(0), .MULH_FAST(0),	// MULH_FAST: -2.6 ns at 96 MHz
	.FAST_BRANCHCMP(1), .BRANCH_PREDICTOR(1), .REDUCED_BYPASS(0)
) cpu (
	.clk(clk_96), .clk_always_on(clk_96), .rst_n(rv_resetn),
	.pwrup_req(pwrup_req), .pwrup_ack(pwrup_req), .clk_en(), .unblock_out(), .unblock_in(1'b0),

	.i_haddr(i_haddr), .i_hwrite(), .i_htrans(i_htrans), .i_hsize(), .i_hburst(), .i_hprot(),
	.i_hmastlock(), .i_hmaster(), .i_hready(1'b1), .i_hresp(1'b0), .i_hwdata(), .i_hrdata(i_hrdata),

	.d_haddr(d_haddr), .d_hwrite(d_hwrite), .d_htrans(d_htrans), .d_hsize(d_hsize), .d_hburst(),
	.d_hprot(), .d_hmastlock(), .d_hmaster(), .d_hexcl(), .d_hready(d_hready), .d_hresp(1'b0),
	.d_hexokay(1'b1), .d_hwdata(d_hwdata), .d_hrdata(d_hrdata),

	.fence_i_vld(), .fence_d_vld(), .fence_rdy(1'b1),

	.dbg_req_halt(1'b0), .dbg_req_halt_on_reset(1'b0), .dbg_req_resume(1'b0), .dbg_halted(),
	.dbg_running(), .dbg_data0_rdata(32'd0), .dbg_data0_wdata(), .dbg_data0_wen(),
	.dbg_instr_data(32'd0), .dbg_instr_data_vld(1'b0), .dbg_instr_data_rdy(),
	.dbg_instr_caught_exception(), .dbg_instr_caught_ebreak(),
	.dbg_sbus_addr(32'd0), .dbg_sbus_write(1'b0), .dbg_sbus_size(2'd0), .dbg_sbus_vld(1'b0),
	.dbg_sbus_rdy(), .dbg_sbus_err(), .dbg_sbus_wdata(32'd0), .dbg_sbus_rdata(),

	.mhartid_val(32'd0), .eco_version(4'd0),
	.irq(1'b0), .soft_irq(1'b0), .timer_irq(1'b0)
);

// ---------------------------------------------------------------------------
// RAM: 64 K x 32, true dual port: A = instruction fetch, B = data
// ---------------------------------------------------------------------------
(* ram_style = "block" *) reg [31:0] ram [0:65535];
initial $readmemh(G_HEX, ram);

reg [31:0] ram_qa, ram_qb;
always @(posedge clk_96) ram_qa <= ram[i_haddr[17:2]];
assign i_hrdata = ram_qa;

// data port: the address phase that hready accepts (htrans NONSEQ/SEQ)
wire        d_ap  = d_htrans[1] && d_hready;
wire  [3:0] d_sel = d_haddr[31:28] == 4'h0 ? 4'b0001 : d_haddr[31:28] == 4'h1 ? 4'b0010 :
                    d_haddr[31:28] == 4'h2 ? 4'b0100 : 4'b1000;
// byte lanes of the access (hsize 0 byte, 1 halfword, 2 word)
wire  [3:0] d_be  = d_hsize == 3'd0 ? 4'b0001 << d_haddr[1:0] :
                    d_hsize == 3'd1 ? (d_haddr[1] ? 4'b1100 : 4'b0011) : 4'b1111;

// the data phase: what the address phase registered
reg         dp      = 1'b0;     // a data phase is in progress
reg         dp_wr;
reg   [3:0] dp_sel;
reg   [3:0] dp_be;
reg  [31:0] dp_addr;
reg         dp_done;            // write done (RAM), or mailbox read issued / done
reg         mb_rd_pend;         // mailbox read data comes next clock

// the RAM write of a data phase, and the RAM read of an address phase in the same clock:
// the write goes first, the read waits a clock
wire ram_wr_now = dp && dp_wr && dp_sel[0] && !dp_done;
wire rd_ap_ram  = d_htrans[1] && !d_hwrite && d_sel[0];

// mailbox (below): the RISC-V uses it in the data phase when the bridge does not
reg  d3_busy = 1'b0, d3_pend = 1'b0, d3_h, done_t = 1'b0;
// the bridge's access sampled in this clock first: straight from clk_32 the request reached
// Hazard3's stall logic through the mailbox arbitration (11 levels, -0.05 ns in the 6.2 ns
// between the clk_32 and 80 MHz edges); one clock later it is all within this clock
reg        q_req = 1'b0, q_we = 1'b0;
reg  [9:1] q_addr = 9'd0;
reg  [1:0] q_be = 2'd0;
reg [15:0] q_wdata = 16'd0;
always @(posedge clk_96) begin
	q_req <= d3_req; q_we <= d3_we; q_addr <= d3_addr[9:1]; q_be <= d3_be; q_wdata <= d3_wdata;
end
wire d3_go = q_req && !d3_busy;
wire mb_now = dp && dp_sel[1] && !dp_done && !d3_go;     // RISC-V access to the mailbox this clock
reg [31:0] mb_q;

// hready: the data phase ends this clock
//   RAM read: data is in ram_qb (the address phase read it)
//   RAM write: written this clock; if the next address phase is a RAM read, it needs the port
//     too: the write is done now, hready low, and the read address is taken next clock
//   mailbox write: written this clock unless the bridge has the port
//   mailbox read: the access this clock (mb_now), data next clock
//   debug port: at once
assign d_hready = !dp ? 1'b1 :
                  dp_sel[0] ? (dp_wr ? !(ram_wr_now && rd_ap_ram) : 1'b1) :
                  dp_sel[1] ? (dp_wr ? mb_now : mb_rd_pend) :
                  1'b1;

// port B: the write of a data phase, else the read of an address phase
wire [15:0] rb_a  = ram_wr_now ? dp_addr[17:2] : d_haddr[17:2];
always @(posedge clk_96) begin
	if (ram_wr_now) begin
		if (dp_be[0]) ram[rb_a][ 7: 0] <= d_hwdata[ 7: 0];
		if (dp_be[1]) ram[rb_a][15: 8] <= d_hwdata[15: 8];
		if (dp_be[2]) ram[rb_a][23:16] <= d_hwdata[23:16];
		if (dp_be[3]) ram[rb_a][31:24] <= d_hwdata[31:24];
	end
	ram_qb <= ram[rb_a];
end

always @(posedge clk_96) begin
	dbg_out <= 1'b0;
	if (!rv_resetn) begin
		dp <= 1'b0;
		dp_done <= 1'b0;
		mb_rd_pend <= 1'b0;
	end else begin
		mb_rd_pend <= 1'b0;
		if (mb_now) begin
			dp_done <= 1'b1;
			if (!dp_wr) mb_rd_pend <= 1'b1;
		end
		if (ram_wr_now) dp_done <= 1'b1;
		if (dp && dp_sel[2] && dp_wr) begin
			if (dp_addr[2] == 1'b0) begin dbg_out <= 1'b1; dbg_byte <= d_hwdata[7:0]; end
			else begin dbg_exit <= 1'b1; dbg_code <= d_hwdata; end
		end
		if (d_hready) begin
			dp      <= d_ap;
			dp_wr   <= d_hwrite;
			dp_sel  <= d_sel;
			dp_be   <= d_be;
			dp_addr <= d_haddr;
			dp_done <= 1'b0;
		end
	end
end

always @(*) d_hrdata = dp_sel[1] ? mb_q : ram_qb;

// ---------------------------------------------------------------------------
// mailbox: as in fpu_rv.v (256 x 32 single port, 4 byte lanes, the bridge first)
// ---------------------------------------------------------------------------
(* ram_style = "block" *) reg [7:0] mb0 [0:255];
(* ram_style = "block" *) reg [7:0] mb1 [0:255];
(* ram_style = "block" *) reg [7:0] mb2 [0:255];
(* ram_style = "block" *) reg [7:0] mb3 [0:255];
integer i;
initial for (i = 0; i < 256; i = i + 1) begin mb0[i] = 8'd0; mb1[i] = 8'd0; mb2[i] = 8'd0; mb3[i] = 8'd0; end

wire [7:0] mb_a  = d3_go ? q_addr[9:2] : dp_addr[9:2];
wire [3:0] mb_we = d3_go ? (q_we ? (q_addr[1] ? {q_be[0], q_be[1], 2'b00} : {2'b00, q_be[0], q_be[1]}) : 4'd0)
                         : (mb_now && dp_wr ? dp_be : 4'd0);
wire [31:0] mb_d = d3_go ? {q_wdata[7:0], q_wdata[15:8], q_wdata[7:0], q_wdata[15:8]} : d_hwdata;

always @(posedge clk_96) begin
	if (mb_we[0]) mb0[mb_a] <= mb_d[ 7: 0];
	if (mb_we[1]) mb1[mb_a] <= mb_d[15: 8];
	if (mb_we[2]) mb2[mb_a] <= mb_d[23:16];
	if (mb_we[3]) mb3[mb_a] <= mb_d[31:24];
	mb_q <= {mb3[mb_a], mb2[mb_a], mb1[mb_a], mb0[mb_a]};
end

always @(posedge clk_96) begin
	d3_pend <= 1'b0;
	if (d3_go) begin
		d3_busy <= 1'b1;
		d3_pend <= 1'b1;
		d3_h    <= q_addr[1];
	end else if (d3_busy && !q_req && !d3_pend) begin
		d3_busy <= 1'b0;
	end
	if (d3_pend) begin
		d3_rdata <= d3_h ? {mb_q[23:16], mb_q[31:24]} : {mb_q[7:0], mb_q[15:8]};
		done_t   <= ~done_t;
	end
end

// the ack: one clk_32 clock per access
reg done_s = 1'b0;
always @(posedge clk_32) begin
	d3_ack <= done_t != done_s;
	done_s <= done_t;
end
initial begin d3_ack = 1'b0; d3_rdata = 16'd0; end
initial begin dbg_exit = 1'b0; dbg_code = 32'd0; dbg_byte = 8'd0; dbg_out = 1'b0; end

endmodule
`default_nettype wire
