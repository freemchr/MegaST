//
// acsi_ctrl.sv
//
// Atari ST for MEGA65: ACSI hard disk "IO controller"
//
// On MiSTer (and MiST), the ACSI commands that the Atari sends to the DMA
// chip (dma.v / acsi.v) are executed by the ARM (HPS) software, see
// Main_MiSTer/support/st/st_tos.cpp, handle_acsi(). The MEGA65 has no such
// processor that is fast enough, so this module executes the ACSI commands in
// hardware. It uses the same protocol as hps_ext.v towards dma.v and supports
// the same SCSI commands as the MiSTer software:
//
//    0x00 TEST UNIT READY, 0x03 REQUEST SENSE, 0x04 FORMAT UNIT (no-op),
//    0x08 READ(6), 0x0A WRITE(6), 0x12 INQUIRY, 0x1A MODE SENSE(6),
//    0x25 READ CAPACITY, 0x28 READ(10), 0x2A WRITE(10)
//    (ICD extended commands are unwrapped by acsi.v)
//
// The hard disk image sectors are read/written using the MiSTer "SD" block
// interface (one 512 byte sector at a time), which is connected to the M2M
// virtual drives (drive 2 = ACSI target 0, drive 3 = ACSI target 1).
//
// Byte order: the DMA FIFO words are big endian ({byte 0, byte 1}), the SD
// sector buffer words are little endian ({byte 1, byte 0}) like MiSTer's
// hps_io in WIDE mode.
//
// This machine is based on AtariST_MiSTer
// Powered by MiSTer2MEGA65
// MEGA65 port done by Chris Freeman in 2026 and licensed under GPL v3
//

module acsi_ctrl (
	input             clk,             // 32 MHz
	input             reset,

	// hard disk images: size in bytes (0 = no image), latched on mount
	input       [1:0] img_mounted,
	input      [31:0] img_size,
	input             img_readonly,
	output      [1:0] present,         // ACSI target 0/1 has an image

	// dma.v IO controller interface
	output reg        dio_data_in_strobe,
	output reg [15:0] dio_data_in_reg,
	output reg        dio_data_out_strobe,
	input      [15:0] dio_data_out_reg,
	output reg        dio_dma_ack,
	output reg  [7:0] dio_dma_status,
	output reg        dio_dma_nak,
	input       [7:0] dio_status_in,
	output reg  [3:0] dio_status_index,
	input       [3:0] dio_fifo_used,
	input             dio_cmd_start,   // the CPU starts a new command (first command byte)
	input             dio_fifo_reset,  // the CPU toggles the DMA direction (FIFO reset)

	// MiSTer "SD" block interface
	output reg [31:0] sd_lba,
	output reg  [1:0] sd_rd,
	output reg  [1:0] sd_wr,
	input       [1:0] sd_ack,
	input       [7:0] sd_buff_addr,
	input      [15:0] sd_buff_dout,
	output reg [15:0] sd_buff_din,
	input             sd_buff_wr,

	output            led
);

// ---------------------------------------------------------------------------
// hard disk image sizes
// ---------------------------------------------------------------------------

reg [31:0] blocks[2];
reg  [1:0] ro;

always @(posedge clk) begin
	for (int i = 0; i < 2; i++) begin
		if (img_mounted[i]) begin
			blocks[i] <= {9'd0, img_size[31:9]};
			ro[i]     <= img_readonly;
		end
	end
end

assign present = { blocks[1] != 0, blocks[0] != 0 };

// ---------------------------------------------------------------------------
// sector buffer (256 x 16 bit, little endian words)
// ---------------------------------------------------------------------------

reg [15:0] sbuf[256];
reg  [7:0] sbuf_addr;
reg [15:0] sbuf_wdata;
reg        sbuf_we;
reg [15:0] sbuf_q;

wire sd_ack_any = |sd_ack;

always @(posedge clk) begin
	if (sd_buff_wr & sd_ack_any) sbuf[sd_buff_addr] <= sd_buff_dout;
	sd_buff_din <= sbuf[sd_buff_addr];
end

always @(posedge clk) begin
	if (sbuf_we) sbuf[sbuf_addr] <= sbuf_wdata;
	sbuf_q <= sbuf[sbuf_addr];
end

// ---------------------------------------------------------------------------
// command execution
// ---------------------------------------------------------------------------

localparam S_IDLE      = 0;
localparam S_POLL      = 1;
localparam S_CMD       = 2;
localparam S_DECODE    = 3;
localparam S_RESP      = 4;   // send a response from resp_byte()
localparam S_RD_REQ    = 5;   // read a sector from the SD interface
localparam S_RD_WAIT   = 6;
localparam S_RD_PUSH   = 7;   // push the sector into the DMA FIFO
localparam S_WR_PULL   = 8;   // pull a sector from the DMA FIFO
localparam S_WR_REQ    = 9;   // write the sector using the SD interface
localparam S_WR_WAIT   = 10;
localparam S_ACK       = 11;
localparam S_NAK       = 12;
localparam S_WAIT_IDLE = 13;

reg  [3:0] state;
reg  [3:0] idx;
reg  [7:0] cmd[10];
reg  [2:0] target;
reg  [7:0] asc[2];
reg [31:0] lba;
reg [16:0] length;            // sectors or bytes
reg  [8:0] words;             // words of the current response / sector
reg  [8:0] word_cnt;
reg  [1:0] spacing;           // spacing between strobes
reg [24:0] timeout;
reg  [1:0] sd_ackD;
reg        tgt;               // 0/1: ACSI target
reg  [7:0] status;
reg        abort;
reg        moved;             // data words of this command went through the DMA FIFO
reg        fifo_ready;        // dio_fifo_used != 0 for at least one cycle
reg        stale;             // busy still belongs to a cancelled command
reg        led_r;
assign led = led_r;

wire [7:0] opcode = cmd[0];
wire [2:0] device = cmd[1][7:5];

wire [31:0] blocks_m1 = blocks[tgt] - 1'd1;

// response data of the non-sector commands (byte index i)
function [7:0] resp_byte(input [8:0] i);
	resp_byte = 8'h00;
	case (opcode)
		8'h03: begin   // REQUEST SENSE
			if (i == 7) resp_byte = 8'h0b;
			if (asc[tgt] != 0 && i == 2)  resp_byte = 8'h05;
			if (asc[tgt] != 0 && i == 12) resp_byte = asc[tgt];
		end
		8'h12: begin   // INQUIRY
			case (i)
				0:  resp_byte = (device != 0) ? 8'h7f : 8'h00;
				2:  resp_byte = 8'h02;
				4:  resp_byte = length[7:0] - 8'd5;
				8:  resp_byte = "M";  9: resp_byte = "E"; 10: resp_byte = "G"; 11: resp_byte = "A";
				12: resp_byte = "6"; 13: resp_byte = "5"; 14: resp_byte = " "; 15: resp_byte = " ";
				16: resp_byte = "H"; 17: resp_byte = "A"; 18: resp_byte = "R"; 19: resp_byte = "D";
				20: resp_byte = "D"; 21: resp_byte = "I"; 22: resp_byte = "S"; 23: resp_byte = "K";
				24: resp_byte = " "; 25: resp_byte = tgt ? "1" : "0";
				26, 27, 28, 29, 30, 31: resp_byte = " ";
				32: resp_byte = "M"; 33: resp_byte = "6"; 34: resp_byte = "5"; 35: resp_byte = " ";
				default: ;
			endcase
		end
		8'h1a: begin   // MODE SENSE
			case (i)
				3:  resp_byte = 8'h08;
				5:  resp_byte = blocks[tgt][23:16];
				6:  resp_byte = blocks[tgt][15:8];
				7:  resp_byte = blocks[tgt][7:0];
				10: resp_byte = 8'h02;
				default: ;
			endcase
		end
		8'h25: begin   // READ CAPACITY
			case (i)
				0: resp_byte = blocks_m1[31:24];
				1: resp_byte = blocks_m1[23:16];
				2: resp_byte = blocks_m1[15:8];
				3: resp_byte = blocks_m1[7:0];
				6: resp_byte = 8'h02;
				default: ;
			endcase
		end
		default: ;
	endcase
endfunction

// A command is cancelled when the CPU starts a new one or resets the DMA FIFO while it is
// still running. This happens when the driver times out (a long write through the slow SD
// path of the M2M firmware) and retries. Without it, the controller took the data of the
// retry as the next sectors of the old command and wrote them to the wrong sectors, and the
// ack of the old command was taken as the answer to the retry (which then never ran).
// A sector that is being read or written via the SD interface is finished first. A FIFO
// reset only counts once data has moved: a driver may set the DMA direction after the
// command bytes. When a FIFO reset cancels the command, acsi.v still shows it as busy until
// the next command starts, so it must not be executed again (it would take the first sector
// of the retry's data from the DMA, and the retry would then write everything one sector off).
wire running   = state != S_IDLE && state != S_POLL && state != S_WAIT_IDLE;
wire abort_now = running & (abort | dio_cmd_start | (dio_fifo_reset & moved));

wire  [8:0] words_pad = {words[8:3] + (words[2:0] != 0), 3'b000};
wire [32:0] lba_end   = {1'b0, lba} + length;
wire        in_range  = lba_end <= {1'b0, blocks[tgt]};

always @(posedge clk) begin
	sbuf_we <= 1'b0;
	sd_ackD <= sd_ack;
	// dma.v raises the fill level in the cycle it stores a word, but its data output
	// (dio_data_out_reg) is a register that shows the word one cycle later
	fifo_ready <= dio_fifo_used != 4'd0;
	if (running && dio_fifo_reset && moved && !abort) stale <= 1'b1;
	if (dio_cmd_start) stale <= 1'b0;
	if (spacing != 0) spacing <= spacing - 1'd1;
	if (timeout != 0) timeout <= timeout - 1'd1;

	if (reset) begin
		state  <= S_IDLE;
		sd_rd  <= 2'b00;
		sd_wr  <= 2'b00;
		asc[0] <= 8'h00;
		asc[1] <= 8'h00;
		led_r  <= 1'b0;
		abort  <= 1'b0;
		stale  <= 1'b0;
	end else if (abort_now && state != S_RD_WAIT && state != S_WR_WAIT) begin
		// cancelled: no ack (the CPU already waits for the new command)
		state <= S_IDLE;
	end else case (state)

	S_IDLE: begin
		abort            <= 1'b0;
		led_r            <= 1'b0;
		dio_status_index <= 4'd10;
		state            <= S_POLL;
	end

	// status byte 10: { target, 4'b0, busy }
	S_POLL: if (dio_status_in[0] && !stale) begin
		target           <= dio_status_in[7:5];
		tgt              <= dio_status_in[5];
		dio_status_index <= 4'd0;
		idx              <= 4'd0;
		state            <= S_CMD;
	end

	// read the command bytes 0..9: dio_status_index is a register (always equal to idx
	// here) and acsi.v returns the selected byte combinationally
	S_CMD: begin
		cmd[idx] <= dio_status_in;
		if (idx == 4'd9) begin
			state <= S_DECODE;
		end else begin
			idx              <= idx + 1'd1;
			dio_status_index <= idx + 1'd1;
		end
	end

	S_DECODE: begin
		// defaults for the 6 byte commands
		lba      <= {11'd0, cmd[1][4:0], cmd[2], cmd[3]};
		length   <= (cmd[4] == 0) ? 17'd256 : {9'd0, cmd[4]};
		word_cnt <= 9'd0;
		spacing  <= 2'd3;
		timeout  <= 25'h1ffffff;   // ~1 s
		status   <= 8'h00;
		moved    <= 1'b0;

		if (target >= 2 || blocks[target[0]] == 0) begin
			state <= S_NAK;
		end else begin
			case (opcode)
				8'h00, 8'h04: begin
					if (device == 0) begin asc[tgt] <= 8'h00; status <= 8'h00; end
					else             begin asc[tgt] <= 8'h25; status <= 8'h02; end
					state <= S_ACK;
				end
				8'h03: begin
					if (device != 0) asc[tgt] <= 8'h25;
					words <= 9'd9;           // 18 bytes
					state <= S_RESP;
				end
				8'h12: begin
					words <= {1'b0, (cmd[4] == 0) ? 8'd128 : {1'b0, cmd[4][7:1]}};
					state <= S_RESP;
				end
				8'h1a: begin
					if (device == 0) begin
						words <= {1'b0, (cmd[4] == 0) ? 8'd128 : {1'b0, cmd[4][7:1]}};
						state <= S_RESP;
					end else begin
						asc[tgt] <= 8'h25; status <= 8'h02; state <= S_ACK;
					end
				end
				8'h25: begin
					if (device == 0) begin
						words <= 9'd4;
						state <= S_RESP;
					end else begin
						asc[tgt] <= 8'h25; status <= 8'h02; state <= S_ACK;
					end
				end
				8'h08, 8'h0a, 8'h28, 8'h2a: begin
					if (opcode[5]) begin   // (10) commands
						lba    <= {cmd[2], cmd[3], cmd[4], cmd[5]};
						length <= {1'b0, cmd[7], cmd[8]};
					end
					state <= S_RD_REQ;      // range check in the next state
					if (device != 0) begin
						asc[tgt] <= 8'h25; status <= 8'h02; state <= S_ACK;
					end
				end
				default: begin
					asc[tgt] <= 8'h20;
					status   <= 8'h02;
					state    <= S_ACK;
				end
			endcase
		end
	end

	// response of a non-sector command: two bytes per word, big endian.
	// The ST's DMA only writes complete 16 byte blocks from its FIFO to RAM, so the
	// response is padded with zeros to a multiple of 8 words (resp_byte() is zero there).
	// dma.v only starts writing a block to RAM when the write pointer is exactly at the
	// end of that block, so at most 8 words may be in the FIFO (here and in S_RD_PUSH).
	S_RESP: begin
		if (word_cnt == words_pad) begin
			asc[tgt] <= 8'h00;
			state <= S_ACK;
		end else if (spacing == 0 && dio_fifo_used < 4'd8) begin
			dio_data_in_reg    <= {resp_byte({word_cnt[7:0], 1'b0}), resp_byte({word_cnt[7:0], 1'b1})};
			dio_data_in_strobe <= ~dio_data_in_strobe;
			word_cnt           <= word_cnt + 1'd1;
			spacing            <= 2'd3;
			timeout            <= 25'h1ffffff;
		end else if (timeout == 0) begin
			status <= 8'h02; state <= S_ACK;
		end
	end

	// ---------------- READ ----------------
	S_RD_REQ: begin
		if (!in_range || (opcode[1] && ro[tgt])) begin
			asc[tgt] <= opcode[1] ? 8'h27 : 8'h21;   // write protected / lba out of range
			status   <= 8'h02;
			state    <= S_ACK;
		end else if (length == 0) begin
			asc[tgt] <= 8'h00;
			status   <= 8'h00;
			state    <= S_ACK;
		end else if (opcode[1]) begin
			// WRITE: first get the sector from the DMA
			word_cnt  <= 9'd0;
			sbuf_addr <= 8'd0;
			state     <= S_WR_PULL;
		end else begin
			led_r       <= 1'b1;
			sd_lba      <= lba;
			sd_rd[tgt]  <= 1'b1;
			state       <= S_RD_WAIT;
		end
	end

	S_RD_WAIT: begin
		if (sd_ack[tgt]) sd_rd <= 2'b00;
		if (abort_now) abort <= 1'b1;
		if (sd_ackD[tgt] & ~sd_ack[tgt] & abort_now) begin
			state     <= S_IDLE;
		end else if (sd_ackD[tgt] & ~sd_ack[tgt]) begin
			word_cnt  <= 9'd0;
			sbuf_addr <= 8'd0;
			spacing   <= 2'd3;
			timeout   <= 25'h1ffffff;
			state     <= S_RD_PUSH;
		end
	end

	S_RD_PUSH: begin
		if (word_cnt == 9'd256) begin
			lba    <= lba + 1'd1;
			length <= length - 1'd1;
			state  <= S_RD_REQ;
		end else if (spacing == 0 && dio_fifo_used < 4'd8) begin
			// sbuf_q holds the word at sbuf_addr (the address is set >= 3 cycles earlier)
			dio_data_in_reg    <= {sbuf_q[7:0], sbuf_q[15:8]};
			dio_data_in_strobe <= ~dio_data_in_strobe;
			moved              <= 1'b1;
			word_cnt           <= word_cnt + 1'd1;
			sbuf_addr          <= sbuf_addr + 1'd1;
			spacing            <= 2'd3;
			timeout            <= 25'h1ffffff;
		end else if (timeout == 0) begin
			status <= 8'h02; state <= S_ACK;
		end
	end

	// ---------------- WRITE ----------------
	S_WR_PULL: begin
		if (word_cnt == 9'd256) begin
			led_r       <= 1'b1;
			sd_lba      <= lba;
			sd_wr[tgt]  <= 1'b1;
			state       <= S_WR_WAIT;
		end else if (spacing == 0 && fifo_ready && dio_fifo_used != 4'd0) begin
			sbuf_we             <= 1'b1;
			sbuf_wdata          <= {dio_data_out_reg[7:0], dio_data_out_reg[15:8]};
			dio_data_out_strobe <= ~dio_data_out_strobe;
			moved               <= 1'b1;
			word_cnt            <= word_cnt + 1'd1;
			spacing             <= 2'd3;
			timeout             <= 25'h1ffffff;
		end else if (timeout == 0) begin
			status <= 8'h02; state <= S_ACK;
		end
		// the address is incremented after the write
		if (sbuf_we) sbuf_addr <= sbuf_addr + 1'd1;
	end

	S_WR_WAIT: begin
		if (sd_ack[tgt]) sd_wr <= 2'b00;
		if (abort_now) abort <= 1'b1;
		if (sd_ackD[tgt] & ~sd_ack[tgt] & abort_now) begin
			state     <= S_IDLE;
		end else if (sd_ackD[tgt] & ~sd_ack[tgt]) begin
			lba       <= lba + 1'd1;
			length    <= length - 1'd1;
			state     <= S_RD_REQ;
		end
	end

	// ---------------- done ----------------
	S_ACK: begin
		dio_dma_status <= status;
		dio_dma_ack    <= ~dio_dma_ack;
		state          <= S_WAIT_IDLE;
		idx            <= 4'd0;
		dio_status_index <= 4'd10;
	end

	S_NAK: begin
		dio_dma_nak      <= ~dio_dma_nak;
		dio_status_index <= 4'd10;
		idx              <= 4'd0;
		state            <= S_WAIT_IDLE;
	end

	// wait until acsi.v has seen the ack/nak (busy flag cleared)
	S_WAIT_IDLE: begin
		idx <= idx + 1'd1;
		if (idx == 4'd15 && !dio_status_in[0]) state <= S_IDLE;
	end

	default: state <= S_IDLE;
	endcase
end

endmodule
