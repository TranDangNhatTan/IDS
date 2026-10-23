`timescale 1ns/1ps
module top_pi_uart_ids(input wire clk,input wire rst_n,input wire uart_pi_rx,output wire uart_pi_tx,output wire [3:0] led);
 // B16 is an unverified board-level input, not a trusted reset source.  A
 // configuration-time initialized counter provides a deterministic 20.97 ms
 // power-on reset and cannot leave the UART core held reset by B16.
 reg [19:0] por_count = 20'd0;
 wire core_rst_n = &por_count;
 reg [25:0] heartbeat;
 always @(posedge clk) begin
  if(!core_rst_n) por_count <= por_count + 1'b1;
  if(!core_rst_n) heartbeat <= 26'd0; else heartbeat <= heartbeat + 1'b1;
 end
 wire [7:0] rx_byte;wire rx_valid,rx_ferr;uart_rx_sync rx(.clk(clk),.rst_n(core_rst_n),.rx(uart_pi_rx),.data(rx_byte),.valid(rx_valid),.framing_error(rx_ferr));
 wire frame_valid;wire [7:0] frame_type,frame_len;wire [15:0] frame_seq;wire [615:0] frame_payload;wire bad_cobs,bad_crc,bad_len,bad_ver;
 cobs_frame_rx_v2 frx(.clk(clk),.rst_n(core_rst_n),.rx_data(rx_byte),.rx_valid(rx_valid),.frame_valid(frame_valid),.frame_type(frame_type),.frame_seq(frame_seq),.payload_len(frame_len),.payload(frame_payload),.bad_cobs(bad_cobs),.bad_crc(bad_crc),.bad_length(bad_len),.bad_version(bad_ver));
 wire mw_en,model_commit,model_valid,upload_open,mgr_resp;wire [11:0] mw_addr;wire [63:0] mw_data;wire [15:0] commit_ver,accepted_nodes,current_version,mgr_resp_seq;wire [7:0] mgr_resp_type,mgr_resp_len;wire [615:0] mgr_resp_payload;wire [31:0] upload_errors;
 wire engine_ready,engine_busy,result_valid;wire [5:0] class_id;wire [11:0] leaf_node;wire [2:0] error_code;wire [7:0] steps;
 model_manager_v2 mgr(.clk(clk),.rst_n(core_rst_n),.frame_valid(frame_valid),.frame_type(frame_type),.frame_seq(frame_seq),.payload_len(frame_len),.payload(frame_payload),.engine_busy(engine_busy),.current_version(current_version),.write_en(mw_en),.write_addr(mw_addr),.write_data(mw_data),.commit(model_commit),.commit_version(commit_ver),.model_valid(model_valid),.upload_open(upload_open),.accepted_count(accepted_nodes),.upload_error_count(upload_errors),.response_valid(mgr_resp),.response_type(mgr_resp_type),.response_seq(mgr_resp_seq),.response_len(mgr_resp_len),.response_payload(mgr_resp_payload));
 reg [615:0] fifo[0:3];reg [15:0] fifo_seq[0:3];reg [2:0] wr,rd;wire fifo_empty=(wr==rd);wire fifo_full=(wr[2]!=rd[2])&&(wr[1:0]==rd[1:0]);reg overflow;reg launch;reg [615:0] active_features;reg [15:0] active_seq;reg [31:0] accepted_features,result_count;
 // Diagnostic trace is deliberately independent of a valid host request.
 // It lets Pi distinguish no RX bytes, bad COBS/CRC, and a model-loader error.
 reg [31:0] rx_byte_count,valid_frame_count;reg [7:0] last_frame_type;reg [22:0] trace_timer;reg trace_due;
 tree_engine_v2 eng(.clk(clk),.rst_n(core_rst_n),.start(launch),.features_flat(active_features),.model_write_en(mw_en),.model_write_addr(mw_addr),.model_write_data(mw_data),.model_commit(model_commit),.commit_version(commit_ver),.ready(engine_ready),.busy(engine_busy),.result_valid(result_valid),.class_id(class_id),.leaf_node(leaf_node),.error_code(error_code),.step_count(steps),.model_version(current_version));
 reg tx_start;reg [7:0] tx_type,tx_len;reg [15:0] tx_seq;reg [615:0] tx_payload;wire tx_busy,tx_done;
 cobs_frame_tx_v2 ftx(.clk(clk),.rst_n(core_rst_n),.start(tx_start),.frame_type(tx_type),.frame_seq(tx_seq),.payload_len(tx_len),.payload(tx_payload),.uart_tx(uart_pi_tx),.busy(tx_busy),.done(tx_done));
 always @(posedge clk or negedge core_rst_n)begin
  if(!core_rst_n)begin wr<=0;rd<=0;overflow<=0;launch<=0;active_features<=0;active_seq<=0;accepted_features<=0;result_count<=0;rx_byte_count<=0;valid_frame_count<=0;last_frame_type<=0;trace_timer<=0;trace_due<=0;tx_start<=0;tx_type<=0;tx_seq<=0;tx_len<=0;tx_payload<=0;end
  else begin launch<=0;tx_start<=0;
   if(rx_valid)rx_byte_count<=rx_byte_count+1'b1;
   if(frame_valid)begin valid_frame_count<=valid_frame_count+1'b1;last_frame_type<=frame_type;end
   if(trace_timer==23'd4_999_999)begin trace_timer<=0;trace_due<=1;end else trace_timer<=trace_timer+1'b1;
   if(frame_valid&&frame_type==8'h10&&frame_len==77&&model_valid&&!upload_open)begin if(fifo_full)overflow<=1;else begin fifo[wr[1:0]]<=frame_payload;fifo_seq[wr[1:0]]<=frame_seq;wr<=wr+1'b1;accepted_features<=accepted_features+1'b1;end end
   if(engine_ready&&!fifo_empty&&model_valid&&!upload_open)begin active_features<=fifo[rd[1:0]];active_seq<=fifo_seq[rd[1:0]];rd<=rd+1'b1;launch<=1;end
   if(!tx_busy)begin
    if(mgr_resp)begin tx_start<=1;tx_type<=mgr_resp_type;tx_seq<=mgr_resp_seq;tx_len<=mgr_resp_len;tx_payload<=mgr_resp_payload;end
    else if(result_valid)begin tx_start<=1;tx_type<=8'h20;tx_seq<=active_seq;tx_len<=7;tx_payload<=0;tx_payload[7:0]<=class_id;tx_payload[23:8]<=leaf_node;tx_payload[31:24]<=steps;tx_payload[39:32]<=error_code;tx_payload[55:40]<=current_version;result_count<=result_count+1'b1;end
    else if(trace_due)begin tx_start<=1;tx_type<=8'h90;tx_seq<=0;tx_len<=16;tx_payload<=0;tx_payload[31:0]<=rx_byte_count;tx_payload[63:32]<=valid_frame_count;tx_payload[95:64]<=upload_errors;tx_payload[111:96]<=accepted_nodes;tx_payload[119:112]<={2'b00,overflow,rx_ferr,bad_ver,bad_len,bad_crc,bad_cobs};tx_payload[127:120]<=last_frame_type;trace_due<=0;end
   end
  end
 end
 // LED0 must visibly blink after configuration regardless of UART traffic.
 // LED1 exposes the raw B16 level; it is no longer allowed to reset the core.
 assign led[0]=heartbeat[24];assign led[1]=rst_n;assign led[2]=model_valid|(accepted_features!=0);assign led[3]=bad_cobs|bad_crc|bad_len|bad_ver|rx_ferr|overflow|(upload_errors!=0);
endmodule
