`timescale 1ns/1ps
module tb_uart_trace;
 reg clk=0,rst_n=0; wire tx;
 reg [31:0] frames=32'h0000059A,ipv4=32'hD2,ip_udp=32'hCA,dst_port=32'hC0,magic=32'hC0;
 reg [15:0] words=16'h00C0,last_data=16'h1A2B; reg [11:0] last_addr=12'h07F; reg ready=0,err=0;
 reg [7:0] chars[0:3]; integer n;
 ids_uart_trace #(.REPORT_CYCLES(1)) dut(.clk(clk),.rst_n(rst_n),.frames(frames),.ipv4(ipv4),.ip_udp(ip_udp),.dst_port(dst_port),.magic(magic),.header0(32'hC4C6E618),.header1(32'h5D9E0800),.header2(32'h00004500),.raw_rx_ctl_cycles(32'h1234),.raw_nibbles(96'h555555555555555DFFFFFFFF),.raw_nibble_count(5'd24),.accepted_words(words),.last_write_addr(last_addr),.last_write_low(last_data),.model_ready(ready),.parser_error(err),.uart_tx(tx));
 always #10 clk=~clk;
 task recv_char; output [7:0] c; integer k; begin
  @(negedge tx); repeat(651) @(posedge clk);
  for(k=0;k<8;k=k+1) begin c[k]=tx; repeat(434) @(posedge clk); end
  if(tx!==1'b1) $fatal(1,"UART stop bit missing");
 end endtask
 initial begin
  repeat(3) @(posedge clk);rst_n=1;
  for(n=0;n<4;n=n+1) recv_char(chars[n]);
  if(chars[0]!="I"||chars[1]!="D"||chars[2]!="S"||chars[3]!=" ") $fatal(1,"UART prefix failed %h %h %h %h",chars[0],chars[1],chars[2],chars[3]);
  wait(!dut.active);repeat(4)@(posedge clk);
  // Background frames and monotonically increasing packet counters must not
  // continuously retrigger UART after their first non-zero stage was logged.
  frames=frames+32'd100;ipv4=ipv4+1;ip_udp=ip_udp+1;dst_port=dst_port+1;magic=magic+1;
  repeat(8)@(posedge clk);
  if(dut.active||dut.pending_change)$fatal(1,"background traffic retriggered UART");
  // Crossing a 256-word model milestone must produce the next line.
  words=16'h0100;wait(dut.active);
  $display("UART_TRACE_PASS prefix=%c%c%c background_suppressed=1 milestone_triggered=1",chars[0],chars[1],chars[2]);$finish;
 end
endmodule
