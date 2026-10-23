`timescale 1ns/1ps
// Generic v2 COBS receiver. It accepts decoded payloads up to 77 bytes.
module cobs_frame_rx_v2(
 input wire clk,input wire rst_n,input wire [7:0] rx_data,input wire rx_valid,
 output reg frame_valid,output reg [7:0] frame_type,output reg [15:0] frame_seq,
 output reg [7:0] payload_len,output reg [615:0] payload,
 output reg bad_cobs,output reg bad_crc,output reg bad_length,output reg bad_version
);
 localparam CAP=0,CODE=1,COPY=2,INSERT=3,HDR=4,CRC=5,UNPACK=6,EMIT=7;
 reg [2:0] state;reg [7:0] enc[0:127];reg [7:0] dec[0:95];
 reg [7:0] enc_len,enc_i,dec_len,remain,plen;reg insert_zero;reg [6:0] crc_i,unpack_i;
 reg [15:0] crc;reg [615:0] payload_work;
 function [15:0] crc_next;input [15:0] c;input [7:0] d;integer q;reg [15:0] t;begin
  t=c^{d,8'h00};for(q=0;q<8;q=q+1)t=t[15]?((t<<1)^16'h1021):(t<<1);crc_next=t;
 end endfunction
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n)begin state<=CAP;enc_len<=0;enc_i<=0;dec_len<=0;remain<=0;frame_valid<=0;frame_type<=0;frame_seq<=0;payload_len<=0;payload<=0;payload_work<=0;bad_cobs<=0;bad_crc<=0;bad_length<=0;bad_version<=0;crc<=0;crc_i<=0;unpack_i<=0;plen<=0;end
  else begin frame_valid<=0;case(state)
   CAP:if(rx_valid)begin if(rx_data==0)begin if(enc_len!=0)begin enc_i<=0;dec_len<=0;state<=CODE;end end else if(enc_len<127)begin enc[enc_len]<=rx_data;enc_len<=enc_len+1'b1;end else begin bad_length<=1;enc_len<=0;end end
   CODE:if(enc_i>=enc_len)state<=HDR;else if(enc[enc_i]==0)begin bad_cobs<=1;enc_len<=0;state<=CAP;end else begin remain<=enc[enc_i]-1'b1;insert_zero<=((enc[enc_i]!=8'hff)&&((enc_i+enc[enc_i])<enc_len));enc_i<=enc_i+1'b1;if(enc[enc_i]==1)begin if((enc[enc_i]!=8'hff)&&((enc_i+enc[enc_i])<enc_len))state<=INSERT;else state<=CODE;end else state<=COPY;end
   COPY:if(enc_i>=enc_len||dec_len>=95)begin bad_cobs<=1;enc_len<=0;state<=CAP;end else begin dec[dec_len]<=enc[enc_i];dec_len<=dec_len+1'b1;enc_i<=enc_i+1'b1;if(remain==1)begin if(insert_zero)state<=INSERT;else state<=CODE;end else remain<=remain-1'b1;end
   INSERT:if(dec_len>=95)begin bad_cobs<=1;enc_len<=0;state<=CAP;end else begin dec[dec_len]<=0;dec_len<=dec_len+1'b1;state<=CODE;end
   HDR:begin
    plen<={dec[5],dec[4]};
    if(dec_len<8||dec[0]!=8'h02)begin if(dec[0]!=8'h02)bad_version<=1;else bad_length<=1;enc_len<=0;state<=CAP;end
    else if({dec[5],dec[4]}>77||dec_len!={dec[5],dec[4]}+8)begin bad_length<=1;enc_len<=0;state<=CAP;end
    else begin frame_type<=dec[1];frame_seq<={dec[3],dec[2]};payload_len<={dec[5],dec[4]};payload_work<=0;crc<=16'hffff;crc_i<=0;state<=CRC;end
   end
   CRC:if(crc_i<(6+plen))begin crc<=crc_next(crc,dec[crc_i]);crc_i<=crc_i+1'b1;end else if(crc!={dec[7+plen],dec[6+plen]})begin bad_crc<=1;enc_len<=0;state<=CAP;end else if(plen==0)state<=EMIT;else begin unpack_i<=0;state<=UNPACK;end
   UNPACK:begin payload_work[unpack_i*8 +:8]<=dec[6+unpack_i];if(unpack_i+1>=plen)state<=EMIT;else unpack_i<=unpack_i+1'b1;end
   EMIT:begin payload<=payload_work;frame_valid<=1;enc_len<=0;state<=CAP;end
   default:state<=CAP;
  endcase end
 end
endmodule
