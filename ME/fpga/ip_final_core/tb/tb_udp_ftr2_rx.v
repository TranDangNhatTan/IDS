`timescale 1ns/1ps
// Protocol regression independent of the Ethernet PHY DDR layer.
// Checks: Ethernet/IPv4/UDP offsets, FTR2 magic, sequence and 28 u32 values.
module tb_udp_ftr2_rx;
 reg clk=0,rst_n=0,rx_valid=0,rx_sop=0;
 reg [7:0] rx_data=0;
 wire raw_valid; wire [28*32-1:0] raw_features_flat;
 wire [31:0] record_seq,accepted,dropped; wire frame_error,udp_seen;
 always #5 clk=~clk;
 ids_udp_feature_rx dut(
  .clk(clk),.rst_n(rst_n),.rx_data(rx_data),.rx_valid(rx_valid),.rx_sop(rx_sop),.engine_busy(1'b0),.raw_ready(1'b1),
  .raw_valid(raw_valid),.raw_features_flat(raw_features_flat),.record_sequence(record_seq),.accepted_records(accepted),.dropped_records(dropped),.frame_error(frame_error),.udp_seen(udp_seen));
 task emit_byte; input [7:0] d; input first; begin
  @(negedge clk); rx_data=d;rx_valid=1;rx_sop=first;
 end endtask
 task u32le; input [31:0] w; begin emit_byte(w[7:0],0);emit_byte(w[15:8],0);emit_byte(w[23:16],0);emit_byte(w[31:24],0);end endtask
 integer i;
 initial begin
  repeat(3) @(posedge clk);rst_n=1;
  // Ethernet header: destination then a learned source MAC, then IPv4.
  for(i=0;i<6;i=i+1) emit_byte(8'hff,i==0);
  emit_byte(8'h02,0);emit_byte(8'h50,0);emit_byte(8'h47,0);emit_byte(8'h41,0);emit_byte(8'h49,0);emit_byte(8'h01,0);
  emit_byte(8'h08,0);emit_byte(8'h00,0);
  emit_byte(8'h45,0);emit_byte(0,0);emit_byte(0,0);emit_byte(8'h90,0);emit_byte(0,0);emit_byte(0,0);emit_byte(0,0);emit_byte(0,0);emit_byte(64,0);emit_byte(17,0);
  emit_byte(0,0);emit_byte(0,0);emit_byte(192,0);emit_byte(168,0);emit_byte(50,0);emit_byte(22,0);emit_byte(192,0);emit_byte(168,0);emit_byte(50,0);emit_byte(50,0);
  emit_byte(8'hc3,0);emit_byte(8'h50,0);emit_byte(8'hd6,0);emit_byte(8'hda,0);emit_byte(0,0);emit_byte(124,0);emit_byte(0,0);emit_byte(0,0);
  emit_byte("F",0);emit_byte("T",0);emit_byte("R",0);emit_byte("2",0);u32le(32'h12345678);
  for(i=0;i<28;i=i+1) u32le(32'h10000000+i);
  @(negedge clk);rx_valid=0;rx_sop=0;rx_data=0;
  repeat(5) @(posedge clk);
  if(accepted!==1 || dropped!==0 || !udp_seen || record_seq!==32'h12345678 || raw_features_flat[31:0]!==32'h10000000 || raw_features_flat[895:864]!==32'h1000001b) begin
   $display("FTR2_RX_FAIL acc=%0d drop=%0d seq=%h first=%h last=%h idx=%0d ipudp=%b port=%b magic=%0d",accepted,dropped,record_seq,raw_features_flat[31:0],raw_features_flat[895:864],dut.byte_index,dut.ip_is_udp,dut.port_ok,dut.protocol_magic);
   $finish_and_return(1);
  end
  $display("FTR2_RX_PASS seq=%h accepted=%0d",record_seq,accepted);
  $finish;
 end
endmodule
