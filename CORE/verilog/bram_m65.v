//
// bram_m65.v
//
// MEGA65 R3/R3A (no SDRAM): ST RAM, TOS and cartridge in the FPGA's block RAM
//
// Drop-in replacement for sdram_m65.v with the same chipset interface and the same timing: the
// 8 MHz bus cycle is divided into 12 clk_96 cycles, a RAM access is taken over at t = 0 (or, if
// there is none, a ROM access with a new address), and the read data appears at t = 6 like the
// first word of the SDRAM burst.
//
// Memory map (word addresses, see atarist_m65.sv):
//   ST RAM     512 KB   $000000 - $07FFFF
//   TOS        256 KB   $E00000 - $E3FFFF (a 192k TOS is also stored here, see rom_a)
//   cartridge  128 KB   $FA0000 - $FBFFFF
// Writes to other addresses are ignored, reads return $FFFF. The 64 bit port (Viking card only)
// is not supported.
//
// Block RAM: 128 (RAM) + 64 (TOS) + 32 (cartridge) RAMB36.
//
// This machine is based on AtariST_MiSTer
// Powered by MiSTer2MEGA65
// MEGA65 port done by Chris Freeman in 2026 and licensed under GPL v3
//
module bram_m65 (
	input             clk_96,     // the memory is accessed at 96 MHz
	input             clk_8_en,   // 8 MHz chipset clock to which the cycle is synchronized
	input      [15:0] din,        // data input from chipset/cpu
	output     [63:0] dout64,     // not supported (Viking card)
	output reg [15:0] dout,
	input      [23:0] addr,       // 24 bit word address
	input      [1:0]  ds,         // upper/lower data strobe
	input             req,        // cpu/chipset requests read/write
	input             we,         // cpu/chipset requests write
	input             rom_oe,
	input      [23:0] rom_addr,
	output reg [15:0] rom_dout
);

localparam STATE_FIRST  = 4'd0;
localparam STATE_ACCESS = 4'd1;
localparam STATE_READ   = 4'd6;   // = STATE_READ of sdram_m65.v
localparam STATE_LAST   = 4'd11;

assign dout64 = 64'd0;

// cycle counter, exactly like sdram_m65.v
reg [3:0] t;
always @(posedge clk_96) begin
	reg clk_8_enD;
	clk_8_enD <= clk_8_en;
	if (~clk_8_enD & clk_8_en) t <= 4'hA; else t <= t + 1'd1;
	if (t == STATE_LAST) t <= STATE_FIRST;
end

// address decoding (word addresses)
function [1:0] region(input [23:0] a);   // 0 = none, 1 = RAM, 2 = TOS, 3 = cartridge
	if (a[23:18] == 6'h00)                     region = 2'd1;   // $000000-$07FFFF
	else if (a[23:17] == 7'b0111_000)          region = 2'd2;   // $E00000-$E3FFFF
	else if (a[23:16] == 8'h7D)                region = 2'd3;   // $FA0000-$FBFFFF
	else                                       region = 2'd0;
endfunction

reg  [1:0] sel;          // region of the current access
reg [17:0] idx;          // word index within the region
reg        wr;
reg  [1:0] wr_ds;
reg [15:0] wr_data;
reg        rd;
reg        rd_rom;
reg [23:0] addr_latch;

(* ram_style = "block" *) reg [7:0]  ram_h  [0:262143];
(* ram_style = "block" *) reg [7:0]  ram_l  [0:262143];
(* ram_style = "block" *) reg [15:0] tos    [0:131071];
(* ram_style = "block" *) reg [15:0] cart   [0:65535];

reg  [7:0] q_ram_h, q_ram_l;
reg [15:0] q_tos, q_cart;

always @(posedge clk_96) begin
	if (t == STATE_FIRST) begin
		wr <= 1'b0;
		rd <= 1'b0;
		if (req) begin
			sel        <= region(addr);
			idx        <= addr[17:0];
			wr         <= we;
			rd         <= ~we;
			rd_rom     <= 1'b0;
			wr_ds      <= ds;
			wr_data    <= din;
			addr_latch <= addr;
		end else if (rom_oe && (addr_latch != rom_addr)) begin
			sel        <= region(rom_addr);
			idx        <= rom_addr[17:0];
			rd         <= 1'b1;
			rd_rom     <= 1'b1;
			addr_latch <= rom_addr;
		end
	end

	if (t == STATE_READ && rd) begin
		if (rd_rom) begin
			case (sel)
				2'd1: rom_dout <= { q_ram_h, q_ram_l };
				2'd2: rom_dout <= q_tos;
				2'd3: rom_dout <= q_cart;
				default: rom_dout <= 16'hFFFF;
			endcase
		end else begin
			case (sel)
				2'd1: dout <= { q_ram_h, q_ram_l };
				2'd2: dout <= q_tos;
				2'd3: dout <= q_cart;
				default: dout <= 16'hFFFF;
			endcase
		end
	end
end

// single port block RAMs, accessed once per bus cycle at t = 1 (registered read)
wire access = (t == STATE_ACCESS);

always @(posedge clk_96) begin
	if (access && sel == 2'd1) begin
		if (wr && wr_ds[1]) ram_h[idx] <= wr_data[15:8];
		q_ram_h <= ram_h[idx];
	end
end

always @(posedge clk_96) begin
	if (access && sel == 2'd1) begin
		if (wr && wr_ds[0]) ram_l[idx] <= wr_data[7:0];
		q_ram_l <= ram_l[idx];
	end
end

always @(posedge clk_96) begin
	if (access && sel == 2'd2) begin
		if (wr) tos[idx[16:0]] <= wr_data;
		q_tos <= tos[idx[16:0]];
	end
end

always @(posedge clk_96) begin
	if (access && sel == 2'd3) begin
		if (wr) cart[idx[15:0]] <= wr_data;
		q_cart <= cart[idx[15:0]];
	end
end

endmodule
