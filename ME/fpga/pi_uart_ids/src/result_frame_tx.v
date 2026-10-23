`timescale 1ns/1ps
// COBS encodes the fixed v1 RESULT decoded frame (15 bytes), then appends 00.
module result_frame_tx(input wire clk,input wire rst_n,input wire start,input wire [15:0] seq_id,input wire [5:0] class_id,input wire [11:0] leaf_node,input wire [7:0] step_count,input wire [2:0] error_code,input wire [15:0] model_version,output wire uart_tx,output reg busy,output reg done);
 reg [7:0] raw[0:14]; reg [7:0] enc[0:17]; reg [4:0] enc_len,enc_i; reg [1:0] build; reg tx_start; reg [7:0] tx_data; reg sending_byte; wire tx_busy,tx_done;
 integer i,k,code_i,out_i; reg [8:0] code; reg [15:0] crc;
 function [15:0] crc_next; input [15:0] c; input [7:0] d; integer q; reg [15:0] t; begin t=c^{d,8'h00};for(q=0;q<8;q=q+1)t=t[15]?((t<<1)^16'h1021):(t<<1);crc_next=t;end endfunction
 uart_tx_sync tx(.clk(clk),.rst_n(rst_n),.start(tx_start),.data(tx_data),.tx(uart_tx),.busy(tx_busy),.done(tx_done));
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin busy<=0;done<=0;build<=0;enc_len<=0;enc_i<=0;tx_start<=0;tx_data<=0;sending_byte<=0;end else begin
   done<=0;tx_start<=0;
   if(!busy && start) begin raw[0]<=1;raw[1]<=8'h20;raw[2]<=seq_id[7:0];raw[3]<=seq_id[15:8];raw[4]<=7;raw[5]<=0;raw[6]<={2'b0,class_id};raw[7]<=leaf_node[7:0];raw[8]<={4'b0,leaf_node[11:8]};raw[9]<=step_count;raw[10]<={5'b0,error_code};raw[11]<=model_version[7:0];raw[12]<=model_version[15:8];busy<=1;build<=1;end
   else if(build==1) begin crc=16'hffff;for(i=0;i<13;i=i+1)crc=crc_next(crc,raw[i]);raw[13]<=crc[7:0];raw[14]<=crc[15:8];build<=2;end
   else if(build==2) begin
    // COBS: code byte at code_i, non-zero body begins at enc[1].
    out_i=1;code_i=0;code=1;
    for(k=0;k<15;k=k+1) begin
      if(raw[k]==0) begin enc[code_i]=code[7:0];code_i=out_i;out_i=out_i+1;code=1;end
      else begin enc[out_i]=raw[k];out_i=out_i+1;code=code+1; if(code==9'h0ff)begin enc[code_i]=code[7:0];code_i=out_i;out_i=out_i+1;code=1;end end
    end
    enc[code_i]=code[7:0];enc[out_i]=0;enc_len<=out_i+1;enc_i<=0;sending_byte<=0;build<=0;
   end else if(busy) begin
    if(!sending_byte) begin
      if(enc_i<enc_len && !tx_busy) begin tx_data<=enc[enc_i];tx_start<=1;sending_byte<=1;end
      else if(enc_i>=enc_len) begin busy<=0;done<=1;end
    end else if(tx_done) begin enc_i<=enc_i+1'b1;sending_byte<=0;end
   end
  end
 end
endmodule
