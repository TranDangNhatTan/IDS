`timescale 1ns/1ps
// Explicit GW5A BSRAM: 1273 x 64 bits, synchronous read.
module tree_model_bram_v2 #(parameter NODE_COUNT=1273)(
 input wire clk,input wire rst_n,input wire [11:0] read_addr,output reg [63:0] read_data,
 input wire write_en,input wire [11:0] write_addr,input wire [63:0] write_data,
 input wire commit,input wire [15:0] commit_version,output reg [15:0] model_version
);
`ifdef SIMULATION
 reg [63:0] sim_memory[0:NODE_COUNT-1];
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin read_data<=0;model_version<=0;end else begin
   if(write_en && write_addr<NODE_COUNT) sim_memory[write_addr]<=write_data;
   if(read_addr<NODE_COUNT) read_data<=sim_memory[read_addr]; else read_data<=64'hC000000000000000;
   if(commit) model_version<=commit_version;
  end
 end
`else
 wire [63:0] d0,d1,u0,u1;
 wire sel0=(read_addr<12'd1024),sel1=(read_addr>=12'd1024)&&(read_addr<NODE_COUNT);
 wire we0=write_en&&(write_addr<12'd1024),we1=write_en&&(write_addr>=12'd1024)&&(write_addr<NODE_COUNT);
 wire [13:0] ra={read_addr[9:0],4'b0},wa={write_addr[9:0],4'b0};
 genvar lane;
 generate for(lane=0;lane<4;lane=lane+1) begin:g_bram
  DPB #(.READ_MODE0(1'b0),.READ_MODE1(1'b0),.WRITE_MODE0(2'b00),.WRITE_MODE1(2'b00),.BIT_WIDTH_0(16),.BIT_WIDTH_1(16),.BLK_SEL_0(3'b000),.BLK_SEL_1(3'b000),.RESET_MODE("SYNC")) b0(.DOA(u0[lane*16 +:16]),.DOB(d0[lane*16 +:16]),.DIA(write_data[lane*16 +:16]),.DIB(16'd0),.BLKSELA(3'b000),.BLKSELB(3'b000),.ADA(wa),.ADB(ra),.WREA(we0),.WREB(1'b0),.CLKA(clk),.CLKB(clk),.CEA(we0),.CEB(1'b1),.OCEA(1'b0),.OCEB(1'b0),.RESETA(1'b0),.RESETB(1'b0));
  DPB #(.READ_MODE0(1'b0),.READ_MODE1(1'b0),.WRITE_MODE0(2'b00),.WRITE_MODE1(2'b00),.BIT_WIDTH_0(16),.BIT_WIDTH_1(16),.BLK_SEL_0(3'b000),.BLK_SEL_1(3'b000),.RESET_MODE("SYNC")) b1(.DOA(u1[lane*16 +:16]),.DOB(d1[lane*16 +:16]),.DIA(write_data[lane*16 +:16]),.DIB(16'd0),.BLKSELA(3'b000),.BLKSELB(3'b000),.ADA(wa),.ADB(ra),.WREA(we1),.WREB(1'b0),.CLKA(clk),.CLKB(clk),.CEA(we1),.CEB(1'b1),.OCEA(1'b0),.OCEB(1'b0),.RESETA(1'b0),.RESETB(1'b0));
 end endgenerate
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin read_data<=0;model_version<=0;end else begin
   if(sel0)read_data<=d0;else if(sel1)read_data<=d1;else read_data<=64'hC000000000000000;
   if(commit)model_version<=commit_version;
  end
 end
`endif
endmodule
