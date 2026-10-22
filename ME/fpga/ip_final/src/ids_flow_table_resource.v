// Resource-profile flow table.  State is intentionally only 16 entries: the
// associative lookup remains LUT/FF, while large completed-flow history moves
// to the sequential BRAM engine.  A close event is held until accepted.
module ids_flow_table_resource #(
 parameter FLOW_ENTRIES=16, parameter TICKS_PER_SECOND=50000000,
 parameter FLOW_TIMEOUT_TICKS=250000000
) (
 input wire clk,input wire rst_n,input wire packet_valid,output wire packet_ready,
 input wire [31:0] src_ip,input wire [31:0] dst_ip,input wire [15:0] src_port,input wire [15:0] dst_port,
 input wire [15:0] frame_bytes,input wire [7:0] ip_protocol,input wire [7:0] tcp_flags,
 input wire [1:0] protocol_code,input wire [6:0] service_code,input wire [3:0] flag_code,
 input wire wrong_fragment,input wire urgent,input wire [63:0] packet_timestamp,
 input wire timeout_sweep,input wire [63:0] current_timestamp_ticks,
 output reg event_valid,input wire event_ready,output reg [9*32-1:0] base_features_flat,
 output reg [31:0] event_timestamp_seconds,output reg [31:0] event_dst_ip,
 output reg [15:0] event_src_port,output reg [6:0] event_service_code,output reg [3:0] event_flag_code,
 output reg table_full_error,output reg close_event_overflow
);
 reg valid_mem[0:FLOW_ENTRIES-1]; reg [31:0] src_ip_mem[0:FLOW_ENTRIES-1],dst_ip_mem[0:FLOW_ENTRIES-1];
 reg [15:0] src_port_mem[0:FLOW_ENTRIES-1],dst_port_mem[0:FLOW_ENTRIES-1];
 reg [7:0] protocol_mem[0:FLOW_ENTRIES-1]; reg [1:0] protocol_code_mem[0:FLOW_ENTRIES-1];
 reg [6:0] service_mem[0:FLOW_ENTRIES-1]; reg [3:0] flag_mem[0:FLOW_ENTRIES-1];
 reg [63:0] start_time_mem[0:FLOW_ENTRIES-1],last_time_mem[0:FLOW_ENTRIES-1];
 reg [31:0] src_bytes_mem[0:FLOW_ENTRIES-1],dst_bytes_mem[0:FLOW_ENTRIES-1];
 reg [2:0] fragment_mem[0:FLOW_ENTRIES-1]; reg urgent_mem[0:FLOW_ENTRIES-1];
 integer i,match_index,free_index,scan_pointer; reg match_found,match_reverse,free_found;
 reg close_valid,close_from_packet; integer close_index;
 wire fin_close=packet_valid&&match_found&&ip_protocol==8'd6&&(tcp_flags[0]||tcp_flags[2]);
 wire [63:0] close_time=close_from_packet?packet_timestamp:current_timestamp_ticks;
 wire [63:0] close_seconds=close_time/TICKS_PER_SECOND;
 wire [63:0] duration_seconds=(close_time>=start_time_mem[close_index])?
                               ((close_time-start_time_mem[close_index])/TICKS_PER_SECOND):64'd0;
 wire [31:0] close_src_bytes=src_bytes_mem[close_index]+((close_from_packet&&!match_reverse)?frame_bytes:0);
 wire [31:0] close_dst_bytes=dst_bytes_mem[close_index]+((close_from_packet&&match_reverse)?frame_bytes:0);
 wire [2:0] close_fragments=fragment_mem[close_index]+
                            ((close_from_packet&&wrong_fragment&&fragment_mem[close_index]<7)?1'b1:1'b0);
 wire close_urgent=urgent_mem[close_index]||(close_from_packet&&urgent);
 wire [3:0] close_flag=close_from_packet?flag_code:flag_mem[close_index];
 assign packet_ready=match_found||free_found;
 always @* begin
   match_found=0;match_reverse=0;match_index=0;free_found=0;free_index=0;
   for(i=0;i<FLOW_ENTRIES;i=i+1) begin
     if(!valid_mem[i]&&!free_found) begin free_found=1;free_index=i;end
     if(valid_mem[i]&&!match_found) begin
       if(src_ip==src_ip_mem[i]&&dst_ip==dst_ip_mem[i]&&src_port==src_port_mem[i]&&dst_port==dst_port_mem[i]&&ip_protocol==protocol_mem[i])
         begin match_found=1;match_index=i;match_reverse=0;end
       else if(src_ip==dst_ip_mem[i]&&dst_ip==src_ip_mem[i]&&src_port==dst_port_mem[i]&&dst_port==src_port_mem[i]&&ip_protocol==protocol_mem[i])
         begin match_found=1;match_index=i;match_reverse=1;end
     end
   end
   close_valid=0;close_from_packet=0;close_index=0;
   if(fin_close) begin close_valid=1;close_from_packet=1;close_index=match_index;end
   else if(timeout_sweep&&valid_mem[scan_pointer]&&current_timestamp_ticks>=last_time_mem[scan_pointer]&&
           current_timestamp_ticks-last_time_mem[scan_pointer]>=FLOW_TIMEOUT_TICKS)
     begin close_valid=1;close_index=scan_pointer;end
 end
 always @(posedge clk or negedge rst_n) begin
   if(!rst_n) begin
     event_valid<=0;base_features_flat<=0;event_timestamp_seconds<=0;event_dst_ip<=0;event_src_port<=0;event_service_code<=0;event_flag_code<=0;
     table_full_error<=0;close_event_overflow<=0;scan_pointer<=0;
     for(i=0;i<FLOW_ENTRIES;i=i+1) valid_mem[i]<=0;
   end else begin
     table_full_error<=0;close_event_overflow<=0;
     if(event_valid&&event_ready) event_valid<=0;
     if(timeout_sweep) scan_pointer<=(scan_pointer==FLOW_ENTRIES-1)?0:scan_pointer+1;
     if(close_valid) begin
       if(!event_valid||event_ready) begin
         base_features_flat<=0;
         base_features_flat[0*32 +:32]<=duration_seconds[31:0];
         base_features_flat[1*32 +:32]<=protocol_code_mem[close_index];
         base_features_flat[2*32 +:32]<=service_mem[close_index];
         base_features_flat[3*32 +:32]<=close_flag;
         base_features_flat[4*32 +:32]<=close_src_bytes;
         base_features_flat[5*32 +:32]<=close_dst_bytes;
         base_features_flat[6*32 +:32]<=src_ip_mem[close_index]==dst_ip_mem[close_index]&&src_port_mem[close_index]==dst_port_mem[close_index];
         base_features_flat[7*32 +:32]<=close_fragments;
         base_features_flat[8*32 +:32]<=close_urgent;
         event_timestamp_seconds<=close_seconds[31:0];event_dst_ip<=dst_ip_mem[close_index];event_src_port<=src_port_mem[close_index];
         event_service_code<=service_mem[close_index];event_flag_code<=close_flag;event_valid<=1;valid_mem[close_index]<=0;
       end else close_event_overflow<=1;
     end else if(packet_valid) begin
       if(match_found) begin
         last_time_mem[match_index]<=packet_timestamp;flag_mem[match_index]<=flag_code;
         if(match_reverse) dst_bytes_mem[match_index]<=dst_bytes_mem[match_index]+frame_bytes;
         else src_bytes_mem[match_index]<=src_bytes_mem[match_index]+frame_bytes;
         if(wrong_fragment&&fragment_mem[match_index]<7) fragment_mem[match_index]<=fragment_mem[match_index]+1'b1;
         urgent_mem[match_index]<=urgent_mem[match_index]||urgent;
       end else if(free_found) begin
         valid_mem[free_index]<=1;src_ip_mem[free_index]<=src_ip;dst_ip_mem[free_index]<=dst_ip;src_port_mem[free_index]<=src_port;dst_port_mem[free_index]<=dst_port;
         protocol_mem[free_index]<=ip_protocol;protocol_code_mem[free_index]<=protocol_code;service_mem[free_index]<=service_code;flag_mem[free_index]<=flag_code;
         start_time_mem[free_index]<=packet_timestamp;last_time_mem[free_index]<=packet_timestamp;src_bytes_mem[free_index]<=frame_bytes;dst_bytes_mem[free_index]<=0;
         fragment_mem[free_index]<=wrong_fragment?1:0;urgent_mem[free_index]<=urgent;
       end else table_full_error<=1;
     end
   end
 end
endmodule

