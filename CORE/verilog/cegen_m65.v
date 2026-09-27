//
// cegen_m65.v
//
// MEGA65: Verilog replacement for AtariST_MiSTer/rtl/mfp/CEGen.vhd
//
// The original VHDL entity uses "integer" ports, which are not supported on
// Vivado's mixed language (Verilog/VHDL) boundary. This module behaves
// exactly the same: it generates the clock enable CE with an average rate of
// CLK * OUT_CLK / IN_CLK (fractional divider, updated on the falling edge).
//

module CEGen
(
	input             CLK,
	input             RST_N,
	input      [31:0] IN_CLK,
	input      [31:0] OUT_CLK,
	output reg        CE
);

reg [31:0] clk_sum;

always @(negedge CLK or negedge RST_N) begin
	if (!RST_N) begin
		clk_sum <= 32'd0;
		CE      <= 1'b0;
	end else begin
		CE <= 1'b0;
		if (clk_sum + OUT_CLK >= IN_CLK) begin
			clk_sum <= clk_sum + OUT_CLK - IN_CLK;
			CE      <= 1'b1;
		end else begin
			clk_sum <= clk_sum + OUT_CLK;
		end
	end
end

endmodule
