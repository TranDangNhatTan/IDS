`timescale 1ns/1ps
module top_final_sys(input wire clk,input wire rst_n,input wire uart_feature_rx,input wire uart_usb_rx,output wire uart_usb_tx,output wire [3:0] led);
 wire [7:0] feat_byte,usb_byte;wire feat_valid,usb_valid,feat_ferr,usb_ferr;
 wire frame_valid;wire [15:0] frame_seq;wire [615:0] frame_features;wire bad_cobs,bad_crc,bad_len;
 reg [615:0] fifo[0:3];reg [15:0] fifo_seq[0:3];reg [2:0] wr,rd;wire fifo_full=(wr[2]!=rd[2])&&(wr[1:0]==rd[1:0]);wire fifo_empty=(wr==rd);reg overflow;reg [31:0] accepted;
 wire write_en,activate,checksum_error,update_open,model_ready;wire [11:0] write_addr;wire [63:0] write_data;wire [15:0] accepted_words;
 reg launch;reg [615:0] active_features;reg [15:0] active_seq;wire engine_ready,engine_busy,done,result_valid;wire [5:0] class_id;wire [11:0] leaf_node;wire [2:0] error_code;wire [7:0] step_count;wire active_bank;wire [15:0] model_version;
 reg result_start;wire result_busy,result_done;
 uart_rx_sync rx_features(.clk(clk),.rst_n(rst_n),.rx(uart_feature_rx),.data(feat_byte),.valid(feat_valid),.framing_error(feat_ferr));
 uart_rx_sync rx_usb(.clk(clk),.rst_n(rst_n),.rx(uart_usb_rx),.data(usb_byte),.valid(usb_valid),.framing_error(usb_ferr));
 feature_frame_rx frames(.clk(clk),.rst_n(rst_n),.rx_data(feat_byte),.rx_valid(feat_valid),.frame_valid(frame_valid),.seq_id(frame_seq),.features(frame_features),.bad_cobs(bad_cobs),.bad_crc(bad_crc),.bad_length(bad_len));
 model_update_uart updater(.clk(clk),.rst_n(rst_n),.rx_data(usb_byte),.rx_valid(usb_valid),.engine_busy(engine_busy),.write_en(write_en),.write_addr(write_addr),.write_data(write_data),.activate_pulse(activate),.checksum_error(checksum_error),.accepted_words(accepted_words),.update_open(update_open),.model_ready(model_ready));
 ids_tree_engine_live engine(.clk(clk),.rst_n(rst_n),.start(launch),.feature_valid(launch),.features_flat(active_features),.model_write_en(write_en),.model_write_addr(write_addr),.model_write_data(write_data),.model_activate(activate),.ready(engine_ready),.busy(engine_busy),.done(done),.result_valid(result_valid),.class_id(class_id),.leaf_node(leaf_node),.error_code(error_code),.step_count(step_count),.active_bank(active_bank),.model_version(model_version));
 result_frame_tx results(.clk(clk),.rst_n(rst_n),.start(result_start),.seq_id(active_seq),.class_id(class_id),.leaf_node(leaf_node),.step_count(step_count),.error_code(error_code),.model_version(model_version),.uart_tx(uart_usb_tx),.busy(result_busy),.done(result_done));
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n)begin wr<=0;rd<=0;overflow<=0;accepted<=0;launch<=0;active_features<=0;active_seq<=0;result_start<=0;end else begin launch<=0;result_start<=0;
   if(frame_valid)begin if(fifo_full)overflow<=1;else begin fifo[wr[1:0]]<=frame_features;fifo_seq[wr[1:0]]<=frame_seq;wr<=wr+1'b1;accepted<=accepted+1'b1;end end
   if(engine_ready&&model_ready&&!fifo_empty)begin active_features<=fifo[rd[1:0]];active_seq<=fifo_seq[rd[1:0]];rd<=rd+1'b1;launch<=1;end
   if(result_valid&&!result_busy)result_start<=1;
  end
 end
 assign led[0]=rst_n;assign led[1]=model_ready;assign led[2]=accepted!=0;assign led[3]=bad_cobs|bad_crc|bad_len|overflow|checksum_error|feat_ferr|usb_ferr;
endmodule
