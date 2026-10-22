// Serial history-query pipeline.  One completed flow is accepted only when
// the BRAM engine and classifier output register are available.
module ids_history_pipeline_resource (
 input wire clk,input wire rst_n,
 input wire event_valid,output wire event_ready,input wire [9*32-1:0] base_features_flat,
 input wire [31:0] event_timestamp_seconds,input wire [31:0] event_dst_ip,input wire [15:0] event_src_port,
 input wire [6:0] event_service_code,input wire [3:0] event_flag_code,
 output reg raw_record_valid,input wire raw_record_ready,output reg [28*32-1:0] raw_features_flat
);
 reg active; reg [9*32-1:0] active_base; reg [31:0] active_time,active_dst; reg [15:0] active_port;
 reg [6:0] active_service; reg [3:0] active_flag;
 wire history_busy,history_result_valid,history_commit_ready;
 wire [19*32-1:0] history_features;
 assign event_ready=!active&&!history_busy&&(!raw_record_valid||raw_record_ready);
 ids_history_window_bram history(
   .clk(clk),.rst_n(rst_n),.commit(history_result_valid&&active&&history_commit_ready),
   .commit_timestamp_seconds(active_time),.commit_dst_ip(active_dst),.commit_src_port(active_port),
   .commit_service_code(active_service),.commit_flag_code(active_flag),
   .query_start(event_valid&&event_ready),.query_timestamp_seconds(event_timestamp_seconds),
   .query_dst_ip(event_dst_ip),.query_src_port(event_src_port),.query_service_code(event_service_code),
   .commit_ready(history_commit_ready),.busy(history_busy),.result_valid(history_result_valid),
   .history_features_flat(history_features));
 always @(posedge clk or negedge rst_n) begin
   if(!rst_n) begin active<=0;raw_record_valid<=0;raw_features_flat<=0;active_base<=0;active_time<=0;active_dst<=0;active_port<=0;active_service<=0;active_flag<=0;end
   else begin
     if(raw_record_valid&&raw_record_ready) raw_record_valid<=0;
     if(event_valid&&event_ready) begin
       active<=1;active_base<=base_features_flat;active_time<=event_timestamp_seconds;active_dst<=event_dst_ip;active_port<=event_src_port;active_service<=event_service_code;active_flag<=event_flag_code;
     end
     if(history_result_valid&&active) begin
       raw_features_flat<=0;raw_features_flat[0*32 +:9*32]<=active_base;raw_features_flat[9*32 +:19*32]<=history_features;
       raw_record_valid<=1;active<=0;
     end
   end
 end
endmodule


