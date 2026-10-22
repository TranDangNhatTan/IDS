`timescale 1ns/1ps
// Real-PHY regression: 8-byte Ethernet preamble and 4-byte FCS are present.
module tb_rmii_udp_fcs;
 reg clk=0,rst_n=0,crs_dv=0; reg [1:0] rxd=0;
 wire [7:0] rx_byte; wire valid,sop,last,rmii_error;
 wire raw_valid,raw_ready,udp_error; wire [895:0] features;
 wire [31:0] accepted,dropped;
 always #10 clk=~clk;
 assign raw_ready=1'b1;
 rmii_deserializer #(.STRIP_PREAMBLE(1)) dut_rmii(.clk(clk),.rst_n(rst_n),.rxd(rxd),.crs_dv(crs_dv),.rx_byte(rx_byte),.rx_byte_valid(valid),.rx_byte_sop(sop),.rx_byte_last(last),.rx_frame_error(rmii_error));
 ids_udp_feature_rx dut_udp(.clk(clk),.rst_n(rst_n),.rx_data(rx_byte),.rx_valid(valid),.rx_sop(sop),.rx_last(last),.raw_valid(raw_valid),.raw_ready(raw_ready),.raw_features_flat(features),.accepted_records(accepted),.dropped_records(dropped),.frame_error(udp_error));
 task send_byte; input [7:0] b; begin
  rxd=b[1:0]; @(posedge clk); rxd=b[3:2]; @(posedge clk);
  rxd=b[5:4]; @(posedge clk); rxd=b[7:6]; @(posedge clk);
 end endtask
 task send_u32_le; input [31:0] w; begin
  send_byte(w[7:0]); send_byte(w[15:8]); send_byte(w[23:16]); send_byte(w[31:24]);
 end endtask
 integer i;
 initial begin
  repeat(3) @(posedge clk); rst_n=1; crs_dv=1;
  for(i=0;i<7;i=i+1) send_byte(8'h55); send_byte(8'hD5);
  for(i=0;i<6;i=i+1) send_byte(8'hFF); for(i=0;i<6;i=i+1) send_byte(i);
  send_byte(8'h08); send_byte(8'h00);                         // Ethernet type IPv4
  send_byte(8'h45); send_byte(0); send_byte(0); send_byte(8'h90); // IPv4 20-byte header
  send_byte(0); send_byte(0); send_byte(0); send_byte(0); send_byte(64); send_byte(17);
  for(i=0;i<10;i=i+1) send_byte(0);                            // rest of IPv4 header
  send_byte(0); send_byte(1); send_byte(8'hD6); send_byte(8'hDA); // UDP dst = 55002
  send_byte(0); send_byte(124); send_byte(0); send_byte(0);
  send_byte("F"); send_byte("T"); send_byte("R"); send_byte("1");
  for(i=0;i<28;i=i+1) send_u32_le(32'h10000000+i);
  for(i=0;i<4;i=i+1) send_byte(0); // PHY-delivered Ethernet FCS
  crs_dv=0; rxd=0; repeat(20) @(posedge clk);
  if(accepted!=1 || dropped!=0 || features[31:0]!==32'h10000000 || features[895:864]!==32'h1000001B) begin
   $display("RMII_UDP_FCS_FAIL accepted=%0d dropped=%0d first=%h last=%h index=%0d udp=%b port=%b magic=%b",accepted,dropped,features[31:0],features[895:864],dut_udp.byte_index,dut_udp.ip_is_udp,dut_udp.port_hi_ok,dut_udp.magic_ok); $finish_and_return(1);
  end
  $display("RMII_UDP_FCS_PASS accepted=%0d first=%h last=%h",accepted,features[31:0],features[895:864]); $finish;
 end
endmodule
