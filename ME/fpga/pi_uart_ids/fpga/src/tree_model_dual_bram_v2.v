`timescale 1ns/1ps
// Two explicit 1273x64 BSRAM images. Writes always target the inactive image;
// commit flips one bit, so a failed upload never changes the active model.
module tree_model_dual_bram_v2 #(parameter NODE_COUNT=1273)(
 input wire clk,input wire rst_n,input wire [11:0] read_addr,output reg [63:0] read_data,
 input wire write_en,input wire [11:0] write_addr,input wire [63:0] write_data,
 input wire commit,input wire [15:0] commit_version,output reg [15:0] model_version
);
`ifdef SIMULATION
 reg [63:0] bank0[0:NODE_COUNT-1],bank1[0:NODE_COUNT-1];reg active;
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n)begin active<=0;read_data<=0;model_version<=0;end else begin
   if(write_en&&write_addr<NODE_COUNT)if(active)bank0[write_addr]<=write_data;else bank1[write_addr]<=write_data;
   if(read_addr<NODE_COUNT)read_data<=active?bank1[read_addr]:bank0[read_addr];else read_data<=64'hC000000000000000;
   if(commit)begin active<=~active;model_version<=commit_version;end
  end
 end
`else
 wire active;reg active_r;assign active=active_r;
 wire page0=(read_addr<12'd1024),page1=(read_addr>=12'd1024)&&(read_addr<NODE_COUNT);
 wire wr0=write_en&&!active&&(write_addr<12'd1024),wr1=write_en&&!active&&(write_addr>=12'd1024)&&(write_addr<NODE_COUNT);
 wire wr2=write_en&&active&&(write_addr<12'd1024),wr3=write_en&&active&&(write_addr>=12'd1024)&&(write_addr<NODE_COUNT);
 wire [13:0] ra={read_addr[9:0],4'b0},wa={write_addr[9:0],4'b0};
 wire [63:0] b00,b01,b10,b11,u00,u01,u10,u11;
 genvar lane;generate for(lane=0;lane<4;lane=lane+1)begin:g
  DPB #(.READ_MODE0(1'b0),.READ_MODE1(1'b0),.WRITE_MODE0(2'b00),.WRITE_MODE1(2'b00),.BIT_WIDTH_0(16),.BIT_WIDTH_1(16),.BLK_SEL_0(3'b000),.BLK_SEL_1(3'b000),.RESET_MODE("SYNC")) m00(.DOA(u00[lane*16+:16]),.DOB(b00[lane*16+:16]),.DIA(write_data[lane*16+:16]),.DIB(16'd0),.BLKSELA(3'b000),.BLKSELB(3'b000),.ADA(wa),.ADB(ra),.WREA(wr0),.WREB(1'b0),.CLKA(clk),.CLKB(clk),.CEA(wr0),.CEB(1'b1),.OCEA(1'b0),.OCEB(1'b0),.RESETA(1'b0),.RESETB(1'b0));
  DPB #(.READ_MODE0(1'b0),.READ_MODE1(1'b0),.WRITE_MODE0(2'b00),.WRITE_MODE1(2'b00),.BIT_WIDTH_0(16),.BIT_WIDTH_1(16),.BLK_SEL_0(3'b000),.BLK_SEL_1(3'b000),.RESET_MODE("SYNC")) m01(.DOA(u01[lane*16+:16]),.DOB(b01[lane*16+:16]),.DIA(write_data[lane*16+:16]),.DIB(16'd0),.BLKSELA(3'b000),.BLKSELB(3'b000),.ADA(wa),.ADB(ra),.WREA(wr1),.WREB(1'b0),.CLKA(clk),.CLKB(clk),.CEA(wr1),.CEB(1'b1),.OCEA(1'b0),.OCEB(1'b0),.RESETA(1'b0),.RESETB(1'b0));
  DPB #(.READ_MODE0(1'b0),.READ_MODE1(1'b0),.WRITE_MODE0(2'b00),.WRITE_MODE1(2'b00),.BIT_WIDTH_0(16),.BIT_WIDTH_1(16),.BLK_SEL_0(3'b000),.BLK_SEL_1(3'b000),.RESET_MODE("SYNC")) m10(.DOA(u10[lane*16+:16]),.DOB(b10[lane*16+:16]),.DIA(write_data[lane*16+:16]),.DIB(16'd0),.BLKSELA(3'b000),.BLKSELB(3'b000),.ADA(wa),.ADB(ra),.WREA(wr2),.WREB(1'b0),.CLKA(clk),.CLKB(clk),.CEA(wr2),.CEB(1'b1),.OCEA(1'b0),.OCEB(1'b0),.RESETA(1'b0),.RESETB(1'b0));
  DPB #(.READ_MODE0(1'b0),.READ_MODE1(1'b0),.WRITE_MODE0(2'b00),.WRITE_MODE1(2'b00),.BIT_WIDTH_0(16),.BIT_WIDTH_1(16),.BLK_SEL_0(3'b000),.BLK_SEL_1(3'b000),.RESET_MODE("SYNC")) m11(.DOA(u11[lane*16+:16]),.DOB(b11[lane*16+:16]),.DIA(write_data[lane*16+:16]),.DIB(16'd0),.BLKSELA(3'b000),.BLKSELB(3'b000),.ADA(wa),.ADB(ra),.WREA(wr3),.WREB(1'b0),.CLKA(clk),.CLKB(clk),.CEA(wr3),.CEB(1'b1),.OCEA(1'b0),.OCEB(1'b0),.RESETA(1'b0),.RESETB(1'b0));
 end endgenerate
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin active_r<=0;read_data<=0;model_version<=0;end else begin
   if(!active)begin if(page0)read_data<=b00;else if(page1)read_data<=b01;else read_data<=64'hC000000000000000;end
   else begin if(page0)read_data<=b10;else if(page1)read_data<=b11;else read_data<=64'hC000000000000000;end
   if(commit)begin active_r<=~active_r;model_version<=commit_version;end
  end
 end
`endif
endmodule
