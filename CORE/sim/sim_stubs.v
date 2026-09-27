// Simulation-only stubs

// Xilinx ODDR: SAME_EDGE, D1 during the high phase, D2 during the low phase
module ODDR #(parameter DDR_CLK_EDGE="SAME_EDGE", parameter INIT=1'b0, parameter SRTYPE="SYNC")
  (output Q, input C, input CE, input D1, input D2, input R, input S);
  assign Q = C ? D1 : D2;
endmodule

// MFP USART (VHDL in the real design): idle
module USART_TOP (
  input CLK, CEP, CEN, RESETn, DSn, CSn, RWn,
  input [5:1] RS, input [7:0] DATA_IN, output [7:0] DATA_OUT, output DATA_OUT_EN,
  input RC, TC, SI, output SO, output SO_EN,
  output RX_ERR_INT, RX_BUFF_INT, TX_ERR_INT, TX_BUFF_INT, output RRn, TRn);
  assign DATA_OUT = 8'h00; assign DATA_OUT_EN = 1'b0; assign SO = 1'b1; assign SO_EN = 1'b0;
  assign RX_ERR_INT = 1'b0; assign RX_BUFF_INT = 1'b0; assign TX_ERR_INT = 1'b0; assign TX_BUFF_INT = 1'b0;
  assign RRn = 1'b1; assign TRn = 1'b1;
endmodule

// YM2149 volume table (VHDL in the real design): simple linear approximation
module vol_table (input CLK, input [11:0] ADDR_A, output reg [9:0] DATA_A, input [11:0] ADDR_B, output reg [9:0] DATA_B);
  always @(posedge CLK) begin
    DATA_A <= {ADDR_A[11:8], 6'd0} + {ADDR_A[7:4], 6'd0} + {ADDR_A[3:0], 6'd0};
    DATA_B <= {ADDR_B[11:8], 6'd0} + {ADDR_B[7:4], 6'd0} + {ADDR_B[3:0], 6'd0};
  end
endmodule
