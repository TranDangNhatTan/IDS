`timescale 1ns/1ps
// Human-readable result stream at 115200: "IDS,c,l,s,v,a,e\r\n".
module ids_uart_telemetry #(parameter integer CLKS_PER_BIT=434) (
 input wire clk,input wire rst_n,input wire result_valid,input wire [5:0] class_id,input wire [11:0] leaf_node,input wire [7:0] step_count,
 input wire active_bank,input wire [15:0] model_version,input wire parser_error,input wire flow_table_full,input wire [2:0] error_code,output wire uart_tx
);
 reg [4:0] index; reg active; reg [5:0] c; reg [11:0] l; reg [7:0] s; reg a; reg [15:0] v; reg [2:0] e; reg tx_start; reg [7:0] tx_data; wire tx_busy;
 function [7:0] hx; input [3:0] n; begin hx=(n<10)?(8'h30+n):(8'h41+n-10); end endfunction
 function [7:0] byte_at; input [4:0] i; begin case(i)
 0:byte_at="I";1:byte_at="D";2:byte_at="S";3:byte_at=",";4:byte_at=hx({2'b0,c[5:4]});5:byte_at=hx(c[3:0]);6:byte_at=",";
 7:byte_at=hx(l[11:8]);8:byte_at=hx(l[7:4]);9:byte_at=hx(l[3:0]);10:byte_at=",";11:byte_at=hx(s[7:4]);12:byte_at=hx(s[3:0]);13:byte_at=",";
 14:byte_at=hx({3'b0,e});15:byte_at=",";16:byte_at=a?"1":"0";17:byte_at=",";18:byte_at=hx(v[7:4]);19:byte_at=hx(v[3:0]);20:byte_at=8'h0D;default:byte_at=8'h0A; endcase end endfunction
 uart_tx_byte #(.CLKS_PER_BIT(CLKS_PER_BIT)) tx(.clk(clk),.rst_n(rst_n),.start(tx_start),.data(tx_data),.tx(uart_tx),.busy(tx_busy),.done());
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin index<=0;active<=0;tx_start<=0;tx_data<=0;c<=0;l<=0;s<=0;a<=0;v<=1;e<=0;end
  else begin tx_start<=0;if(!active&&result_valid)begin c<=class_id;l<=leaf_node;s<=step_count;a<=active_bank;v<=model_version;e<=error_code;index<=0;active<=1;end
   else if(active&&!tx_busy)begin tx_data<=byte_at(index);tx_start<=1;if(index==21)active<=0;else index<=index+1'b1;end end
 end
endmodule

