`timescale 1ns/1ps
// Concise, event-driven UART diagnostic (115200 8-N-1).
// One BOOT snapshot is guaranteed. Afterwards a line is emitted only when a
// new receive layer is reached, each 256-word model milestone, model-ready
// changes, or the first parser error occurs. Background traffic cannot spam it.
// X=raw RX_CTL, F=Ethernet frame, I=IPv4, U=UDP, P=port 55002, M=MOD1/FTR2.
// Example: IDS X=1 F=00000123 I=1 U=1 P=1 M=1 W=04F9 A=4F8 R=1 E=0
module ids_uart_trace #(parameter integer REPORT_CYCLES=50_000_000)(
 input wire clk,input wire rst_n,
 input wire [31:0] frames,input wire [31:0] ipv4,input wire [31:0] ip_udp,
 input wire [31:0] dst_port,input wire [31:0] magic,
 input wire [31:0] header0,input wire [31:0] header1,input wire [31:0] header2,input wire [31:0] raw_rx_ctl_cycles,
 input wire [95:0] raw_nibbles,input wire [4:0] raw_nibble_count,
 input wire [15:0] accepted_words,
 input wire [11:0] last_write_addr,input wire [15:0] last_write_low,
 input wire model_ready,input wire parser_error,output wire uart_tx
);
 localparam integer LINE_BYTES=89;
 localparam [15:0] MODEL_WORDS=16'd1273;
 reg [31:0] timer;
 reg [6:0] char_index;
 reg active,tx_start,pending_change,pending_error,error_reported;reg [7:0] tx_data;
 reg [31:0] f_l;reg [15:0] w_l;reg [11:0] a_l;reg [95:0] n_l;reg [4:0] c_l;reg x_l,i_l,u_l,p_l,m_l,r_l,e_l;
 reg x_seen,f_seen,i_seen,u_seen,p_seen,m_seen,k_seen,t_seen;reg [15:0] w_seen;reg r_seen;
 wire raw_now=(raw_rx_ctl_cycles!=0);
 wire frame_now=(frames!=0),ipv4_now=(ipv4!=0),udp_now=(ip_udp!=0),port_now=(dst_port!=0),magic_now=(magic!=0);
 wire new_rx_stage=(raw_nibble_count!=c_l)||(raw_now&&!x_seen)||(frame_now&&!f_seen)||(ipv4_now&&!i_seen)||
                   (udp_now&&!u_seen)||(port_now&&!p_seen)||(magic_now&&!m_seen);
 wire model_progress=(accepted_words[15:8]!=w_seen[15:8])||
                     ((accepted_words==0)&&(w_seen!=0))||
                     ((accepted_words==MODEL_WORDS)&&(w_seen!=MODEL_WORDS));
 wire meaningful_change=new_rx_stage||model_progress||(model_ready!=r_seen)||(parser_error&&!error_reported);
 wire tx_busy,tx_done;
 function [7:0] hex;input [3:0] n;begin hex=(n<10)?(8'h30+n):(8'h41+n-10);end endfunction
 function [7:0] byte_at;input [6:0] n;begin
  case(n)
   0:byte_at="I";1:byte_at="D";2:byte_at="S";3:byte_at=" ";
   4:byte_at="X";5:byte_at="=";6:byte_at=x_l?"1":"0";7:byte_at=" ";
   8:byte_at="F";9:byte_at="=";10:byte_at=hex(f_l[31:28]);11:byte_at=hex(f_l[27:24]);12:byte_at=hex(f_l[23:20]);13:byte_at=hex(f_l[19:16]);14:byte_at=hex(f_l[15:12]);15:byte_at=hex(f_l[11:8]);16:byte_at=hex(f_l[7:4]);17:byte_at=hex(f_l[3:0]);18:byte_at=" ";
   19:byte_at="I";20:byte_at="=";21:byte_at=i_l?"1":"0";22:byte_at=" ";
   23:byte_at="U";24:byte_at="=";25:byte_at=u_l?"1":"0";26:byte_at=" ";
   27:byte_at="P";28:byte_at="=";29:byte_at=p_l?"1":"0";30:byte_at=" ";
   31:byte_at="M";32:byte_at="=";33:byte_at=m_l?"1":"0";34:byte_at=" ";
   35:byte_at="W";36:byte_at="=";37:byte_at=hex(w_l[15:12]);38:byte_at=hex(w_l[11:8]);39:byte_at=hex(w_l[7:4]);40:byte_at=hex(w_l[3:0]);41:byte_at=" ";
   42:byte_at="A";43:byte_at="=";44:byte_at=hex(a_l[11:8]);45:byte_at=hex(a_l[7:4]);46:byte_at=hex(a_l[3:0]);47:byte_at=" ";
   48:byte_at="R";49:byte_at="=";50:byte_at=r_l?"1":"0";51:byte_at=" ";
   52:byte_at="E";53:byte_at="=";54:byte_at=e_l?"1":"0";55:byte_at=" ";
   56:byte_at="C";57:byte_at="=";58:byte_at=hex({3'b0,c_l[4]});59:byte_at=hex(c_l[3:0]);60:byte_at=" ";
   61:byte_at="H";62:byte_at="=";
   63:byte_at=hex(n_l[95:92]);64:byte_at=hex(n_l[91:88]);65:byte_at=hex(n_l[87:84]);66:byte_at=hex(n_l[83:80]);
   67:byte_at=hex(n_l[79:76]);68:byte_at=hex(n_l[75:72]);69:byte_at=hex(n_l[71:68]);70:byte_at=hex(n_l[67:64]);
   71:byte_at=hex(n_l[63:60]);72:byte_at=hex(n_l[59:56]);73:byte_at=hex(n_l[55:52]);74:byte_at=hex(n_l[51:48]);
   75:byte_at=hex(n_l[47:44]);76:byte_at=hex(n_l[43:40]);77:byte_at=hex(n_l[39:36]);78:byte_at=hex(n_l[35:32]);
   79:byte_at=hex(n_l[31:28]);80:byte_at=hex(n_l[27:24]);81:byte_at=hex(n_l[23:20]);82:byte_at=hex(n_l[19:16]);
   83:byte_at=hex(n_l[15:12]);84:byte_at=hex(n_l[11:8]);85:byte_at=hex(n_l[7:4]);86:byte_at=hex(n_l[3:0]);87:byte_at=8'h0D;
   default:byte_at=8'h0A;
  endcase
 end endfunction
 uart_tx_byte tx(.clk(clk),.rst_n(rst_n),.start(tx_start),.data(tx_data),.tx(uart_tx),.busy(tx_busy),.done(tx_done));
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   timer<=0;char_index<=0;active<=0;tx_start<=0;pending_change<=1;pending_error<=0;error_reported<=0;tx_data<=0;
   f_l<=0;w_l<=0;a_l<=0;n_l<=0;c_l<=0;x_l<=0;i_l<=0;u_l<=0;p_l<=0;m_l<=0;r_l<=0;e_l<=0;
   x_seen<=0;f_seen<=0;i_seen<=0;u_seen<=0;p_seen<=0;m_seen<=0;k_seen<=0;t_seen<=0;w_seen<=0;r_seen<=0;
  end else begin
   tx_start<=0;
   if(parser_error&&!error_reported)begin pending_error<=1;error_reported<=1;end
   if(!active)begin
    if(meaningful_change)pending_change<=1;
    if(timer==REPORT_CYCLES-1)begin
     timer<=0;
     if(pending_change||meaningful_change)begin
      active<=1;char_index<=0;pending_change<=0;pending_error<=0;
      // Before a valid protocol header exists, H exposes the first 24 raw
      // RGMII nibbles.  This makes a failed frame self-diagnosing (pin order,
      // nibble phase and preamble are visible) instead of printing 24 zeros.
      f_l<=frames;w_l<=accepted_words;a_l<=last_write_addr;n_l<=magic_now?{header0,header1,header2}:raw_nibbles;c_l<=raw_nibble_count;x_l<=raw_now;i_l<=ipv4_now;u_l<=udp_now;p_l<=port_now;m_l<=magic_now;r_l<=model_ready;e_l<=pending_error|parser_error;
      x_seen<=raw_now;f_seen<=frame_now;i_seen<=ipv4_now;u_seen<=udp_now;p_seen<=port_now;m_seen<=magic_now;k_seen<=raw_nibble_count[4];t_seen<=raw_nibble_count[3];w_seen<=accepted_words;r_seen<=model_ready;
     end
    end else timer<=timer+1'b1;
   end else if(!tx_busy&&!tx_start)begin
    tx_data<=byte_at(char_index);tx_start<=1;
    if(char_index==LINE_BYTES-1)active<=0;else char_index<=char_index+1'b1;
   end
  end
 end
 wire unused_diagnostics=&{1'b0,raw_nibbles,last_write_low,tx_done};
endmodule
