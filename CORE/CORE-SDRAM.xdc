## Atari ST/STe for MEGA65: SDRAM constraints, only in the R4/R5/R6 projects (the R3/R3A has
## no SDRAM, see CORE/verilog/bram_m65.v)

## SDRAM (MEGA65 R4/R5/R6)
## All SDRAM signals are registered in the IOBs. The SDRAM clock is the inverted 96 MHz clock
## (ODDR), i.e. the SDRAM samples in the middle of the FPGA's output data eye and the FPGA samples
## the read data one 96 MHz clock cycle later (CAS latency 2), just like on MiSTer.
set_property IOB TRUE [get_ports {sdram_a_o[*] sdram_ba_o[*] sdram_ras_n_o sdram_cas_n_o sdram_we_n_o sdram_cs_n_o sdram_dqml_o sdram_dqmh_o}]
set_property IOB TRUE [get_ports {sdram_dq_io[*]}]
set_false_path -to   [get_ports {sdram_clk_o sdram_cke_o sdram_a_o[*] sdram_ba_o[*] sdram_ras_n_o sdram_cas_n_o sdram_we_n_o sdram_cs_n_o sdram_dqml_o sdram_dqmh_o sdram_dq_io[*]}]
set_false_path -from [get_ports {sdram_dq_io[*]}]
