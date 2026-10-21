// fpu_rv.v - the MC68882 service of the Falcon's FPU bridge on a RISC-V in the FPGA
//
// On MiSTer the bridge (falcon_fpu_bridge.sv) posts each FPU instruction into a mailbox in DDR3
// and a program on the ARM executes it (tools/falcon_fpu). The MEGA65 has no ARM: here a
// PicoRV32 (RV32IM) runs the same program (CORE/falcon_fpu/rv: Hatari's 68882 emulation), and
// the mailbox is a dual-port block RAM between the bridge's DMA port (d3, clk_32) and the
// RISC-V (clk_96). Memory map of the RISC-V:
//   $00000000  256 KB RAM: code, data, stack (loaded at configuration from G_HEX)
//   $10000000  1 KB mailbox (guest $E90000..$E903FF): 32-bit words, bytes in memory order
//   $20000000  debug byte out, $20000004 exit (simulation only, see sim/fpu_rv)
// The bridge side: the d3 port of falcon_memarb (16-bit big-endian words, be[1] = wdata[15:8]
// = the even byte; req held until a one clock ack, read data valid with the ack). The bridge
// only addresses the mailbox through it (guest $E90000 + offset).
//
// The program is never reset: it runs from the configuration on, like the service on MiSTer
// that Main starts with the core (its heartbeat makes the bridge report the FPU).
//
// MEGA65 port done by Chris Freeman in 2026, licensed under GPL v3
`default_nettype none

module fpu_rv #(
	parameter G_HEX = "fpu_rv.hex"
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
wire        mem_valid, mem_instr;
reg         mem_ready;
wire [31:0] mem_addr, mem_wdata;
wire  [3:0] mem_wstrb;
reg  [31:0] mem_rdata;
wire        mem_la_read, mem_la_write;      // look-ahead: the access that starts next clock
wire [31:0] mem_la_addr, mem_la_wdata;
wire  [3:0] mem_la_wstrb;

// a short reset after the configuration (PicoRV32 needs one), then it runs for good
reg  [3:0] rv_rst = 4'd0;
wire       rv_resetn = rv_rst[3];
always @(posedge clk_96) if (!rv_rst[3]) rv_rst <= rv_rst + 4'd1;

picorv32 #(
	.ENABLE_COUNTERS(1), .ENABLE_COUNTERS64(0), .ENABLE_REGS_DUALPORT(1),
	.BARREL_SHIFTER(1), .COMPRESSED_ISA(0), .ENABLE_MUL(0), .ENABLE_FAST_MUL(1), .ENABLE_DIV(1),
	.ENABLE_IRQ(0), .CATCH_MISALIGN(0), .CATCH_ILLINSN(0),
	.PROGADDR_RESET(32'h0000_0000), .STACKADDR(32'h0004_0000)
) cpu (
	.clk(clk_96), .resetn(rv_resetn), .trap(),
	.mem_valid(mem_valid), .mem_instr(mem_instr), .mem_ready(mem_ready),
	.mem_addr(mem_addr), .mem_wdata(mem_wdata), .mem_wstrb(mem_wstrb), .mem_rdata(mem_rdata),
	.mem_la_read(mem_la_read), .mem_la_write(mem_la_write), .mem_la_addr(mem_la_addr),
	.mem_la_wdata(mem_la_wdata), .mem_la_wstrb(mem_la_wstrb),
	.pcpi_valid(), .pcpi_insn(), .pcpi_rs1(), .pcpi_rs2(),
	.pcpi_wr(1'b0), .pcpi_rd(32'd0), .pcpi_wait(1'b0), .pcpi_ready(1'b0),
	.irq(32'd0), .eoi(),
	.trace_valid(), .trace_data()
);

// ---------------------------------------------------------------------------
// RAM: 64 K x 32, no wait state: the look-ahead interface gives the address a clock before
// mem_valid, so the block RAM reads (or writes) then and mem_ready comes with mem_valid
// ---------------------------------------------------------------------------
(* ram_style = "block" *) reg [31:0] ram [0:65535];
initial $readmemh(G_HEX, ram);

wire sel_ram = mem_addr[31:28] == 4'h0;
wire sel_mb  = mem_addr[31:28] == 4'h1;
wire sel_io  = mem_addr[31:28] == 4'h2;
reg  [31:0] ram_q, mb_q;
reg   [1:0] rsel;

// the access without look-ahead (the first fetch after the reset): one wait state
wire la_ram = (mem_la_read || mem_la_write) && mem_la_addr[31:28] == 4'h0;
wire nl_ram = mem_valid && sel_ram && !mem_ready;
wire        ram_we = la_ram ? mem_la_write : nl_ram && mem_wstrb != 4'd0;
wire [15:0] ram_a  = la_ram ? mem_la_addr[17:2] : mem_addr[17:2];
wire [31:0] ram_d  = la_ram ? mem_la_wdata : mem_wdata;
wire  [3:0] ram_be = la_ram ? mem_la_wstrb : mem_wstrb;

always @(posedge clk_96) begin
	if (ram_we) begin
		if (ram_be[0]) ram[ram_a][ 7: 0] <= ram_d[ 7: 0];
		if (ram_be[1]) ram[ram_a][15: 8] <= ram_d[15: 8];
		if (ram_be[2]) ram[ram_a][23:16] <= ram_d[23:16];
		if (ram_be[3]) ram[ram_a][31:24] <= ram_d[31:24];
	end
	ram_q <= ram[ram_a];
end

// ---------------------------------------------------------------------------
// mailbox: 256 x 32 single port in the clk_96 domain, as 4 byte lanes (lane k = byte address
// 4m + k), shared by the bridge (priority) and the RISC-V (waits a clock). A true dual-port RAM
// with one port per clock would return undefined data when the bridge polls STATUS while the
// RISC-V writes it; with one port that cannot happen. clk_32 and clk_96 come from the same
// MMCM (clk.vhd), so the d3 signals are sampled directly.
// ---------------------------------------------------------------------------
(* ram_style = "block" *) reg [7:0] mb0 [0:255];
(* ram_style = "block" *) reg [7:0] mb1 [0:255];
(* ram_style = "block" *) reg [7:0] mb2 [0:255];
(* ram_style = "block" *) reg [7:0] mb3 [0:255];
integer i;
initial for (i = 0; i < 256; i = i + 1) begin mb0[i] = 8'd0; mb1[i] = 8'd0; mb2[i] = 8'd0; mb3[i] = 8'd0; end

// the bridge's 16-bit word at byte offset 4m + 2h is lanes 2h (even byte, wdata[15:8]) and
// 2h + 1 (odd byte, wdata[7:0])
reg        d3_busy = 1'b0;     // taken, until the bridge drops req (after the ack)
reg        d3_pend = 1'b0;     // the read data comes next clock
reg        d3_h;
reg        done_t = 1'b0;      // toggles when an access is done (-> d3_ack in clk_32)
wire       d3_go = d3_req && !d3_busy;
wire       rv_mb = mem_valid && sel_mb && !d3_go;
wire [7:0] mb_a  = d3_go ? d3_addr[9:2] : mem_addr[9:2];
wire [3:0] mb_we = d3_go ? (d3_we ? (d3_addr[1] ? {d3_be[0], d3_be[1], 2'b00} : {2'b00, d3_be[0], d3_be[1]}) : 4'd0)
                         : (rv_mb ? mem_wstrb : 4'd0);
wire [31:0] mb_d = d3_go ? {d3_wdata[7:0], d3_wdata[15:8], d3_wdata[7:0], d3_wdata[15:8]} : mem_wdata;

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
		d3_h    <= d3_addr[1];
	end else if (d3_busy && !d3_req && !d3_pend) begin
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

// RISC-V bus cycle: the RAM through the look-ahead (above); the mailbox and the debug port with
// one wait state (registered address), and a mailbox access waits while the bridge has it
always @(posedge clk_96) begin
	mem_ready <= 1'b0;
	dbg_out   <= 1'b0;
	if (la_ram || nl_ram) begin
		mem_ready <= 1'b1;
		rsel      <= 2'b01;
	end else if (mem_valid && !mem_ready && !sel_ram && !(sel_mb && d3_go)) begin
		mem_ready <= 1'b1;
		rsel      <= {sel_mb, sel_ram};
		if (sel_io && mem_wstrb != 4'd0) begin
			if (mem_addr[2] == 1'b0) begin dbg_out <= 1'b1; dbg_byte <= mem_wdata[7:0]; end
			else begin dbg_exit <= 1'b1; dbg_code <= mem_wdata; end
		end
	end
end
always @(*) mem_rdata = rsel[0] ? ram_q : rsel[1] ? mb_q : 32'd0;
initial begin dbg_exit = 1'b0; dbg_code = 32'd0; dbg_byte = 8'd0; dbg_out = 1'b0; end

endmodule
`default_nettype wire
