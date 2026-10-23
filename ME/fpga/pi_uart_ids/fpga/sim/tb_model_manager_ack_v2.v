`timescale 1ns/1ps
// ABI regression for v2 MODEL_WRITE_ACK: status | node_index | accepted_count.
module tb_model_manager_ack_v2;
 reg clk=0,rst_n=0,frame_valid=0,engine_busy=0; reg [7:0] frame_type=0,payload_len=0;
 reg [15:0] frame_seq=0,current_version=16'h0037; reg [615:0] payload=0;
 wire write_en,commit,model_valid,upload_open,response_valid;wire [11:0] write_addr;wire [63:0] write_data;wire [15:0] commit_version,accepted_count,response_seq;wire [31:0] upload_error_count;wire [7:0] response_type,response_len;wire [615:0] response_payload;
 always #10 clk=~clk;
 model_manager_v2 dut(.clk(clk),.rst_n(rst_n),.frame_valid(frame_valid),.frame_type(frame_type),.frame_seq(frame_seq),.payload_len(payload_len),.payload(payload),.engine_busy(engine_busy),.current_version(current_version),.write_en(write_en),.write_addr(write_addr),.write_data(write_data),.commit(commit),.commit_version(commit_version),.model_valid(model_valid),.upload_open(upload_open),.accepted_count(accepted_count),.upload_error_count(upload_error_count),.response_valid(response_valid),.response_type(response_type),.response_seq(response_seq),.response_len(response_len),.response_payload(response_payload));
 task send;input [7:0] typ;input [15:0] seq;input [7:0] len;input [615:0] p;begin @(negedge clk);frame_type=typ;frame_seq=seq;payload_len=len;payload=p;frame_valid=1;@(negedge clk);frame_valid=0;end endtask
 initial begin
  #1; rst_n=0; #25; rst_n=1;
  // BEGIN: count=1273, arbitrary CRC, requested version=9.
  payload=0;payload[15:0]=1273;payload[47:16]=32'h12345678;payload[63:48]=16'd9;send(8'h01,16'h10,8,payload);
  if(!response_valid||response_type!=8'h81||response_payload[7:0]!=0||response_payload[23:8]!=0||response_payload[39:24]!=16'h0037)$fatal(1,"BEGIN ACK ABI mismatch");
  // WRITE node 0 must ACK node 0 and count 1.
  payload=0;payload[15:0]=0;payload[79:16]=64'h0123456789abcdef;send(8'h02,16'h11,10,payload);
  if(!response_valid||response_type!=8'h82||response_payload[7:0]!=0||response_payload[23:8]!=0||response_payload[39:24]!=1||!write_en)$fatal(1,"WRITE0 ACK ABI mismatch node=%0d count=%0d",response_payload[23:8],response_payload[39:24]);
  // Retry is idempotent: same node and current count.
  send(8'h02,16'h12,10,payload);
  if(!response_valid||response_type!=8'h82||response_payload[23:8]!=0||response_payload[39:24]!=1||write_en)$fatal(1,"WRITE retry ACK ABI mismatch");
  $display("MODEL_MANAGER_ACK_V2_PASS node0=%0d accepted=%0d",response_payload[23:8],response_payload[39:24]);$finish;
 end
endmodule
