//
// viking_scale.sv
//
// Atari ST for MEGA65: 2:1 downscaler for the Viking/SM194 1280x1024 card
//
// The Viking card (viking.v) outputs 1280x1024 monochrome pixels with a pixel
// clock of 96 MHz (1536 x 1046 clocks per frame, 59.9 Hz). This is too much for
// the M2M framework's video pipeline (32 MHz video clock, ascal: max. 1024
// input pixels per line, no downscaling). This module averages 2 x 2 pixels
// into one grey pixel (5 grey levels) and outputs 640x512 in the 32 MHz clock
// domain: One output line is exactly two Viking lines (2 x 1536 clk_96 =
// 1024 clk_32), so input and output stay locked without any FIFO.
//
// Output: 1024 x 523 clocks per frame @ 32.083 MHz = 31.3 kHz, 59.9 Hz
//
// Atari ST port 2026, licensed under GPL v3
//

module viking_scale (
	// Viking side (clk_96)
	input            clk_96,
	input            in_hblank,
	input            in_vblank,
	input            in_vs,
	input            in_pix,

	// Video output (clk_32, phase aligned to clk_96)
	input            clk_32,
	output reg [7:0] grey,
	output reg       hs,
	output reg       vs,
	output reg       hblank,
	output reg       vblank
);

localparam OH_START = 11'd200;   // first active output pixel
localparam OH_LEN   = 11'd640;
localparam OHS_LEN  = 11'd64;    // hsync length

// ------------------------------------------------------------------------
// input side (clk_96)
// ------------------------------------------------------------------------

reg  [1:0] line_sum[640];        // sum of the two pixels of each pair of the even line
reg  [2:0] out_mem[2048];        // double buffered output lines (0..4): {bank, x}

reg [10:0] in_x;
reg        in_odd;               // odd line of a line pair
reg        in_bank;              // output bank that is being written
reg        in_hblankD, in_vblankD;
reg        first_pix;
reg        pair_active;          // the current line pair is part of the active image
reg  [1:0] start_stretch;        // start of an output line: stretched for the 32 MHz domain
reg        done_bank;            // bank of the last completed line pair
reg        done_active;

wire [1:0] pair = {1'b0, first_pix} + {1'b0, in_pix};

always @(posedge clk_96) begin
	in_hblankD <= in_hblank;
	in_vblankD <= in_vblank;
	if (start_stretch != 0) start_stretch <= start_stretch - 1'd1;

	// start of the active image: first line is an even line
	if (in_vblankD & ~in_vblank) begin
		in_odd <= 1'b0;
	end

	// start of an active line
	if (in_hblankD & ~in_hblank) in_x <= 11'd0;

	if (~in_hblank & ~in_vblank) begin
		in_x <= in_x + 1'd1;
		if (!in_x[0]) begin
			first_pix <= in_pix;
		end else if (!in_odd) begin
			line_sum[in_x[10:1]] <= pair;
		end else begin
			out_mem[{in_bank, in_x[10:1]}] <= {1'b0, line_sum[in_x[10:1]]} + {1'b0, pair};
		end
	end

	// end of every line (also during vblank, to keep the output line rate constant)
	if (~in_hblankD & in_hblank) begin
		in_odd <= ~in_odd;
		if (in_odd) begin
			pair_active   <= 1'b0;
			done_active   <= pair_active | ~in_vblank;
			done_bank     <= in_bank;
			in_bank       <= ~in_bank;
			start_stretch <= 2'd3;
		end else begin
			pair_active   <= ~in_vblank;
		end
	end
end

// ------------------------------------------------------------------------
// output side (clk_32)
// ------------------------------------------------------------------------

reg [10:0] oh_cnt;
reg        startD;
reg        out_bank;
reg        out_active;
reg  [2:0] q;
reg  [1:0] in_vs_s;

wire start = (start_stretch != 0);
wire [10:0] oh_px = oh_cnt - OH_START;

always @(posedge clk_32) begin
	startD  <= start;
	in_vs_s <= {in_vs_s[0], in_vs};
	oh_cnt  <= oh_cnt + 1'd1;

	if (start & ~startD) begin
		oh_cnt     <= 11'd0;
		out_bank   <= done_bank;
		out_active <= done_active;
	end

	q <= out_mem[{out_bank, oh_px[9:0]}];

	// one clock of pipeline delay for the memory
	hs     <= (oh_cnt < OHS_LEN);
	hblank <= !(oh_cnt > OH_START && oh_cnt <= OH_START + OH_LEN);
	vblank <= !out_active;
	vs     <= in_vs_s[1];
	case (q)
		3'd0:    grey <= 8'd0;
		3'd1:    grey <= 8'd64;
		3'd2:    grey <= 8'd128;
		3'd3:    grey <= 8'd192;
		default: grey <= 8'd255;
	endcase
end

endmodule
