`timescale 1ns/1ps
// Generic v2 COBS transmitter for ACK (5-byte) and RESULT (7-byte) payloads.
module cobs_frame_tx_v2(
 input wire clk,input wire rst_n,input wire start,input wire [7:0] frame_type,input wire [15:0] frame_seq,
 input wire [7:0] payload_len,input wire [615:0] payload,output wire uart_tx,output reg busy,output reg done
);
 localparam IDLE=0,BUILD=1,CRC=2,COBS_INIT=3,COBS=4,SEND=5;
 reg [2:0] state;reg [7:0] raw[0:84];reg [7:0] enc[0:86];reg [7:0] typ;reg [15:0] seq;reg [7:0] plen;
 reg [615:0] pay;reg [7:0] raw_i,raw_len,crc_i,out_i,code_i,enc_i,enc_len;reg [8:0] code;reg [15:0] crc;
 reg tx_start,sending;reg [7:0] tx_data;wire tx_busy,tx_done;integer q;
 function [15:0] crc_next;input [15:0] c;input [7:0] d;integer j;reg [15:0] t;begin t=c^{d,8'h00};for(j=0;j<8;j=j+1)t=t[15]?((t<<1)^16'h1021):(t<<1);crc_next=t;end endfunction
 uart_tx_sync tx(.clk(clk),.rst_n(rst_n),.start(tx_start),.data(tx_data),.tx(uart_tx),.busy(tx_busy),.done(tx_done));
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin state<=IDLE;busy<=0;done<=0;tx_start<=0;sending<=0;end else begin done<=0;tx_start<=0;case(state)
   IDLE:if(start&&!busy)begin busy<=1;typ<=frame_type;seq<=frame_seq;plen<=payload_len;pay<=payload;raw_i<=0;state<=BUILD;end
   BUILD:begin
    case(raw_i)
     0:raw[0]<=8'h02;1:raw[1]<=typ;2:raw[2]<=seq[7:0];3:raw[3]<=seq[15:8];4:raw[4]<=plen;5:raw[5]<=0;
     default:if(raw_i<(6+plen))raw[raw_i]<=pay[(raw_i-6)*8 +:8];
    endcase
    if(raw_i==(5+plen))begin raw_len<=8+plen;crc<=16'hffff;crc_i<=0;state<=CRC;end else raw_i<=raw_i+1'b1;
   end
   CRC:if(crc_i<(6+plen))begin crc<=crc_next(crc,raw[crc_i]);crc_i<=crc_i+1'b1;end else begin raw[6+plen]<=crc[7:0];raw[7+plen]<=crc[15:8];state<=COBS_INIT;end
   COBS_INIT:begin raw_i<=0;out_i<=1;code_i<=0;code<=1;state<=COBS;end
   COBS:if(raw_i<raw_len)begin
    if(raw[raw_i]==0)begin enc[code_i]<=code[7:0];code_i<=out_i;out_i<=out_i+1'b1;code<=1;end
    else begin enc[out_i]<=raw[raw_i];out_i<=out_i+1'b1;code<=code+1'b1;end raw_i<=raw_i+1'b1;
   end else begin enc[code_i]<=code[7:0];enc[out_i]<=0;enc_len<=out_i+1'b1;enc_i<=0;sending<=0;state<=SEND;end
   SEND:if(!sending)begin if(enc_i<enc_len&&!tx_busy)begin tx_data<=enc[enc_i];tx_start<=1;sending<=1;end else if(enc_i>=enc_len)begin busy<=0;done<=1;state<=IDLE;end end else if(tx_done)begin enc_i<=enc_i+1'b1;sending<=0;end
   default:state<=IDLE;
  endcase end
 end
endmodule
