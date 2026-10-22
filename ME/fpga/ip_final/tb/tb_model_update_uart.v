`timescale 1ns/1ps
module tb_model_update_uart;
 reg clk=0,rst_n=0,engine_busy=0,rx_valid=0; reg [7:0] rx_data=0;
 wire write_en,activate_pulse,checksum_error; wire [11:0] write_addr; wire [63:0] write_data; wire [15:0] accepted_words;
 model_update_uart dut(.clk(clk),.rst_n(rst_n),.rx_data(rx_data),.rx_valid(rx_valid),.engine_busy(engine_busy),.write_en(write_en),.write_addr(write_addr),.write_data(write_data),.activate_pulse(activate_pulse),.checksum_error(checksum_error),.accepted_words(accepted_words));
 always #5 clk=~clk;
 task send_byte; input [7:0] b; begin @(negedge clk);rx_data=b;rx_valid=1;@(negedge clk);rx_valid=0;end endtask
 task command; input [7:0] cmd; input [11:0] addr; integer i; reg [7:0] c; begin
  c=cmd; send_byte(8'hA5);send_byte(8'h5A);send_byte(cmd);
  if(cmd==8'h10) begin send_byte(addr[7:0]);c=c^addr[7:0];send_byte({4'b0,addr[11:8]});c=c^{4'b0,addr[11:8]}; for(i=0;i<8;i=i+1)begin send_byte(i);c=c^i;end end
  send_byte(c);
 end endtask
 integer n;
 initial begin
  repeat(3) @(negedge clk);rst_n=1;
  command(8'h12,0);
  for(n=0;n<1273;n=n+1) command(8'h10,n);
  if(accepted_words!==16'd1273) $fatal(1,"word count %0d",accepted_words);
  command(8'h11,0); @(posedge clk); if(!activate_pulse) $fatal(1,"activation rejected");
  $display("MODEL_UPDATE_UART_PASS words=%0d",accepted_words); $finish;
 end
endmodule
