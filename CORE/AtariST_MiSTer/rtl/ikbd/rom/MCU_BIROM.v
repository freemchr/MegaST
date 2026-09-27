// altera message_off 10030

module MCU_BIROM
  (
   input 	CLK,
   input [11:0] AD,
   output reg [7:0] DO
   );
   
   reg [7:0] 	rom[0:4095];
   initial begin
`ifdef VERILATOR
      $readmemh ("../rom/ikbd.hex", rom, 0);
`else
      $readmemh ("ikbd.mem", rom, 0);      // MEGA65: ikbd.mem is part of the Vivado project
`endif
   end
   
   always @(posedge CLK) begin
      DO <= rom[AD];
   end
   
endmodule // MCU_BIROM
