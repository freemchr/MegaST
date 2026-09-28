//
// Atari ST/STe for MEGA65
//
// Mega ST real time clock (Ricoh RP5C15) at $FFFC21 - $FFFC3F (odd bytes, 4 bit registers)
//
// The time is the time of the MEGA65's battery backed real time clock (M2M main_rtc_i). Like the
// RTC emulation of Hatari, writes to the time registers are ignored (set the clock in the MEGA65's
// configuration utility), while the registers of bank 1 (alarm etc.) are plain memory: TOS detects
// the RTC by writing to them and reading the values back.
//
//    Register  Bank 0              Bank 1
//    0         seconds   units     clock output select
//    1         seconds   tens      adjust
//    2         minutes   units     alarm minutes units
//    3         minutes   tens      alarm minutes tens
//    4         hours     units     alarm hours units
//    5         hours     tens      alarm hours tens
//    6         day of week         alarm day of week
//    7         day       units     alarm day units
//    8         day       tens      alarm day tens
//    9         month     units     -
//    A         month     tens      12/24 hour select
//    B         year      units     leap year counter
//    C         year      tens      -
//    D         mode (bit 0: bank)
//    E         test (write only)
//    F         reset (write only)
//
// The year registers count from 1980, the MEGA65 RTC counts from 2000.
//
// Atari ST port 2026, licensed under GPL v3
//

module rp5c15_m65 (
	input         clk,
	input         reset,

	input         sel,        // CPU access to $FFFC20 - $FFFC3F, lower data strobe
	input         rw,         // 1 = read
	input   [3:0] addr,       // register number (A4..A1)
	input   [3:0] din,
	output  [3:0] dout,

	input  [64:0] rtc         // M2M format: BCD sec, min, hour, day, month, year (2000 based), day of week
);

// the MEGA65 RTC comes from another clock domain: only take it over when it is stable
reg [55:0] rtc_d, rtc_s;
always @(posedge clk) begin
	rtc_d <= rtc[55:0];
	if (rtc_d == rtc[55:0]) rtc_s <= rtc_d;
end

wire [7:0] sec   = rtc_s[ 7: 0];
wire [7:0] min   = rtc_s[15: 8];
wire [7:0] hour  = rtc_s[23:16];
wire [7:0] day   = rtc_s[31:24];
wire [7:0] month = rtc_s[39:32];
wire [7:0] year  = rtc_s[47:40];
wire [2:0] wday  = rtc_s[50:48];

// year since 1980 = year since 2000 + 20 (as BCD)
wire [6:0] year_1980 = year[7:4] * 4'd10 + year[3:0] + 7'd20;
wire [3:0] year_tens  = year_1980 / 7'd10;
wire [3:0] year_units = year_1980 % 7'd10;

reg [3:0] mode;
reg [3:0] bank1[13];

always @(posedge clk) begin
	if (reset) begin
		mode <= 4'd0;
	end else if (sel && !rw) begin
		if (addr == 4'hD)
			mode <= din;
		else if (mode[0] && addr < 4'hD)
			bank1[addr] <= din;
	end
end

reg [3:0] rdata;
always @(*) begin
	rdata = 4'd0;
	if (addr == 4'hD)
		rdata = mode;
	else if (addr < 4'hD) begin
		if (mode[0])
			rdata = bank1[addr];
		else case (addr)
			4'h0: rdata = sec[3:0];
			4'h1: rdata = sec[7:4];
			4'h2: rdata = min[3:0];
			4'h3: rdata = min[7:4];
			4'h4: rdata = hour[3:0];
			4'h5: rdata = hour[7:4];
			4'h6: rdata = {1'b0, wday};
			4'h7: rdata = day[3:0];
			4'h8: rdata = day[7:4];
			4'h9: rdata = month[3:0];
			4'hA: rdata = month[7:4];
			4'hB: rdata = year_units;
			4'hC: rdata = year_tens;
			default: rdata = 4'd0;
		endcase
	end
end

assign dout = rdata;

endmodule
