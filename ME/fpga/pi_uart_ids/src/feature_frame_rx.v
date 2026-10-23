`timescale 1ns/1ps
// COBS FEATURE decoder. CRC and unpack proceed one byte per clock after the
// delimiter so the 50-MHz datapath has no wide single-cycle CRC/unpack path.
module feature_frame_rx(
 input wire clk,input wire rst_n,input wire [7:0] rx_data,input wire rx_valid,
 output reg frame_valid,output reg [15:0] seq_id,output reg [615:0] features,
 output reg bad_cobs,output reg bad_crc,output reg bad_length
);
 localparam CAP=0,CODE=1,COPY=2,INSERT=3,HEADER=4,CRC_RUN=5,UNPACK=6,EMIT=7;
 reg [3:0] state; reg [7:0] enc[0:127]; reg [7:0] dec[0:95];
 reg [7:0] enc_len,enc_i,dec_len,remain; reg insert_zero;
 reg [6:0] crc_i,unpack_i; reg [15:0] crc; reg [615:0] feature_work;
 function [15:0] crc_next; input [15:0] c; input [7:0] d; integer q; reg [15:0] t; begin
  t=c^{d,8'h00};for(q=0;q<8;q=q+1)t=t[15]?((t<<1)^16'h1021):(t<<1);crc_next=t;
 end endfunction
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin
   state<=CAP;enc_len<=0;enc_i<=0;dec_len<=0;remain<=0;frame_valid<=0;seq_id<=0;features<=0;feature_work<=0;
   bad_cobs<=0;bad_crc<=0;bad_length<=0;crc<=0;crc_i<=0;unpack_i<=0;
  end else begin
   frame_valid<=0;
   case(state)
    CAP: if(rx_valid) begin
     if(rx_data==0) begin if(enc_len!=0)begin enc_i<=0;dec_len<=0;state<=CODE;end end
     else if(enc_len<127)begin enc[enc_len]<=rx_data;enc_len<=enc_len+1'b1;end
     else begin bad_length<=1;enc_len<=0;end
    end
    CODE: if(enc_i>=enc_len)state<=HEADER;
    else if(enc[enc_i]==0)begin bad_cobs<=1;enc_len<=0;state<=CAP;end
    else begin
     remain<=enc[enc_i]-1'b1;insert_zero<=((enc[enc_i]!=8'hff)&&((enc_i+enc[enc_i])<enc_len));enc_i<=enc_i+1'b1;
     if(enc[enc_i]==1)begin if((enc[enc_i]!=8'hff)&&((enc_i+enc[enc_i])<enc_len))state<=INSERT;else state<=CODE;end
     else state<=COPY;
    end
    COPY: if(enc_i>=enc_len||dec_len>=95)begin bad_cobs<=1;enc_len<=0;state<=CAP;end
    else begin
     dec[dec_len]<=enc[enc_i];dec_len<=dec_len+1'b1;enc_i<=enc_i+1'b1;
     if(remain==1)begin if(insert_zero)state<=INSERT;else state<=CODE;end else remain<=remain-1'b1;
    end
    INSERT: if(dec_len>=95)begin bad_cobs<=1;enc_len<=0;state<=CAP;end
    else begin dec[dec_len]<=0;dec_len<=dec_len+1'b1;state<=CODE;end
    HEADER: begin
     if(dec_len!=85||dec[0]!=8'h01||dec[1]!=8'h10||{dec[5],dec[4]}!=16'd77)begin bad_length<=1;enc_len<=0;state<=CAP;end
     else begin seq_id<={dec[3],dec[2]};crc<=16'hffff;crc_i<=0;feature_work<=0;state<=CRC_RUN;end
    end
    CRC_RUN: if(crc_i<83)begin crc<=crc_next(crc,dec[crc_i]);crc_i<=crc_i+1'b1;end
    else if(crc!={dec[84],dec[83]})begin bad_crc<=1;enc_len<=0;state<=CAP;end
    else begin unpack_i<=0;state<=UNPACK;end
    UNPACK: begin
     feature_work[unpack_i*8 +: 8]<=dec[6+unpack_i];
     if(unpack_i==76)state<=EMIT;else unpack_i<=unpack_i+1'b1;
    end
    EMIT: begin features<=feature_work;frame_valid<=1;enc_len<=0;state<=CAP;end
    default: state<=CAP;
   endcase
  end
 end
endmodule
