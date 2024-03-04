// Copyright 1986-2018 Xilinx, Inc. All Rights Reserved.
// --------------------------------------------------------------------------------
// Tool Version: Vivado v.2018.3 (win64) Build 2405991 Thu Dec  6 23:38:27 MST 2018
// Date        : Thu Nov 30 00:39:56 2023
// Host        : bhamwin10 running 64-bit major release  (build 9200)
// Command     : write_verilog -force -mode synth_stub
//               D:/sphenix/MVTX_dec/MVTX_dec.srcs/sources_1/ip/fifo_hitdata_19x128/fifo_hitdata_19x128_stub.v
// Design      : fifo_hitdata_19x128
// Purpose     : Stub declaration of top-level module interface
// Device      : xcku115-flvf1924-2-e
// --------------------------------------------------------------------------------

// This empty module with port declaration file causes synthesis tools to infer a black box for IP.
// The synthesis directives are for Synopsys Synplify support to prevent IO buffer insertion.
// Please paste the declaration into a Verilog source file or add the file as an additional source.
(* x_core_info = "fifo_generator_v13_2_3,Vivado 2018.3" *)
module fifo_hitdata_19x128(clk, srst, din, wr_en, rd_en, dout, full, empty, valid, 
  wr_rst_busy, rd_rst_busy)
/* synthesis syn_black_box black_box_pad_pin="clk,srst,din[18:0],wr_en,rd_en,dout[18:0],full,empty,valid,wr_rst_busy,rd_rst_busy" */;
  input clk;
  input srst;
  input [18:0]din;
  input wr_en;
  input rd_en;
  output [18:0]dout;
  output full;
  output empty;
  output valid;
  output wr_rst_busy;
  output rd_rst_busy;
endmodule
