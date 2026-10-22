    // Hardware-oriented history engine. Unlike ids_history_window (the reference
// model), this reads one packed history entry per clock, allowing Gowin to
// infer block RAM instead of expanding a 256-way combinational read mux.
module ids_history_window_bram #(
    parameter HISTORY_DEPTH = 256
) (
    input wire clk, input wire rst_n,
    input wire commit, input wire [31:0] commit_timestamp_seconds,
    input wire [31:0] commit_dst_ip, input wire [15:0] commit_src_port,
    input wire [6:0] commit_service_code, input wire [3:0] commit_flag_code,
    input wire query_start, input wire [31:0] query_timestamp_seconds,
    input wire [31:0] query_dst_ip, input wire [15:0] query_src_port,
    input wire [6:0] query_service_code,
    output wire commit_ready, output wire busy, output reg result_valid,
    output reg [19*32-1:0] history_features_flat
);
    // valid, timestamp, destination IP, source port, service, flag = 92 bits.
    (* ram_style = "block" *) reg [91:0] history_mem [0:HISTORY_DEPTH-1];
    reg [91:0] read_entry;
    reg [7:0] write_pointer, scan_pointer;
    reg [1:0] state;
    localparam ST_IDLE = 2'd0, ST_READ = 2'd1, ST_EVAL = 2'd2, ST_FINISH = 2'd3;
    reg [31:0] q_time, q_dst_ip; reg [15:0] q_src_port; reg [6:0] q_service;
    integer time_count, time_srv_count, time_serror, time_srv_serror, time_rerror, time_srv_rerror;
    integer time_same_srv, time_diff_srv, time_srv_diff_host, host_count, host_srv_count, host_same_src_port;
    integer host_serror, host_srv_serror, host_rerror, host_srv_rerror, all_srv_count, all_srv_diff_host;
    wire entry_valid = read_entry[91]; wire [31:0] entry_time = read_entry[90:59];
    wire [31:0] entry_dst = read_entry[58:27]; wire [15:0] entry_src_port = read_entry[26:11];
    wire [6:0] entry_service = read_entry[10:4]; wire [3:0] entry_flag = read_entry[3:0];
    assign busy = state != ST_IDLE;
    assign commit_ready = !busy;
    function is_serror; input [3:0] flag; begin is_serror=(flag==6)||(flag==7)||(flag==8)||(flag==9)||(flag==11); end endfunction
    function is_rerror; input [3:0] flag; begin is_rerror=(flag==2)||(flag==3)||(flag==4)||(flag==5); end endfunction
    function [31:0] ratio_q016; input integer n; input integer d; reg [63:0] scaled,q,r; begin
        if(d<=0) ratio_q016=0; else if(n>=d) ratio_q016=65535; else begin
            scaled=n*65535; q=scaled/d; r=scaled%d;
            if((r*2>d)||((r*2==d)&&q[0])) q=q+1;
            ratio_q016=q[31:0];
        end
    end endfunction
    task emit_result; begin
        history_features_flat = {19*32{1'b0}};
        history_features_flat[0*32 +: 32] = time_count > 511 ? 511 : time_count;
        history_features_flat[1*32 +: 32] = time_srv_count > 100 ? 100 : time_srv_count;
        history_features_flat[2*32 +: 32] = ratio_q016(time_serror,time_count);
        history_features_flat[3*32 +: 32] = ratio_q016(time_srv_serror,time_srv_count);
        history_features_flat[4*32 +: 32] = ratio_q016(time_rerror,time_count);
        history_features_flat[5*32 +: 32] = ratio_q016(time_srv_rerror,time_srv_count);
        history_features_flat[6*32 +: 32] = ratio_q016(time_same_srv,time_count);
        history_features_flat[7*32 +: 32] = ratio_q016(time_diff_srv,time_count);
        history_features_flat[8*32 +: 32] = ratio_q016(time_srv_diff_host,time_srv_count);
        history_features_flat[9*32 +: 32] = host_count > 253 ? 253 : host_count;
        history_features_flat[10*32 +: 32] = host_srv_count > 255 ? 255 : host_srv_count;
        history_features_flat[11*32 +: 32] = ratio_q016(host_srv_count,host_count);
        history_features_flat[12*32 +: 32] = ratio_q016(host_count-host_srv_count,host_count);
        history_features_flat[13*32 +: 32] = ratio_q016(host_same_src_port,host_count);
        history_features_flat[14*32 +: 32] = ratio_q016(all_srv_diff_host,all_srv_count);
        history_features_flat[15*32 +: 32] = ratio_q016(host_serror,host_count);
        history_features_flat[16*32 +: 32] = ratio_q016(host_srv_serror,host_srv_count);
        history_features_flat[17*32 +: 32] = ratio_q016(host_rerror,host_count);
        history_features_flat[18*32 +: 32] = ratio_q016(host_srv_rerror,host_srv_count);
    end endtask
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            state<=ST_IDLE; write_pointer<=0; scan_pointer<=0; result_valid<=0; history_features_flat<=0;
            time_count<=0;time_srv_count<=0;time_serror<=0;time_srv_serror<=0;time_rerror<=0;time_srv_rerror<=0;
            time_same_srv<=0;time_diff_srv<=0;time_srv_diff_host<=0;host_count<=0;host_srv_count<=0;host_same_src_port<=0;
            host_serror<=0;host_srv_serror<=0;host_rerror<=0;host_srv_rerror<=0;all_srv_count<=0;all_srv_diff_host<=0;
        end else begin
            result_valid<=0;
            if(commit && commit_ready) begin
                history_mem[write_pointer] <= {1'b1,commit_timestamp_seconds,commit_dst_ip,commit_src_port,commit_service_code,commit_flag_code};
                write_pointer <= write_pointer + 1'b1;
            end
            case(state)
                ST_IDLE: if(query_start) begin
                    q_time<=query_timestamp_seconds; q_dst_ip<=query_dst_ip; q_src_port<=query_src_port; q_service<=query_service_code;
                    scan_pointer<=0; time_count<=0;time_srv_count<=0;time_serror<=0;time_srv_serror<=0;time_rerror<=0;time_srv_rerror<=0;
                    time_same_srv<=0;time_diff_srv<=0;time_srv_diff_host<=0;host_count<=0;host_srv_count<=0;host_same_src_port<=0;
                    host_serror<=0;host_srv_serror<=0;host_rerror<=0;host_srv_rerror<=0;all_srv_count<=0;all_srv_diff_host<=0; state<=ST_READ;
                end
                ST_READ: begin read_entry<=history_mem[scan_pointer]; state<=ST_EVAL; end
                ST_EVAL: begin
                    if(entry_valid) begin
                        if(entry_service==q_service) begin all_srv_count<=all_srv_count+1; if(entry_dst!=q_dst_ip) all_srv_diff_host<=all_srv_diff_host+1; end
                        if(entry_dst==q_dst_ip) begin
                            host_count<=host_count+1; if(entry_src_port==q_src_port) host_same_src_port<=host_same_src_port+1;
                            if(is_serror(entry_flag)) host_serror<=host_serror+1; if(is_rerror(entry_flag)) host_rerror<=host_rerror+1;
                            if(entry_service==q_service) begin host_srv_count<=host_srv_count+1; if(is_serror(entry_flag)) host_srv_serror<=host_srv_serror+1; if(is_rerror(entry_flag)) host_srv_rerror<=host_srv_rerror+1; end
                        end
                        if(q_time>=entry_time && q_time-entry_time<=2) begin
                            if(entry_dst==q_dst_ip) begin time_count<=time_count+1; if(entry_service==q_service) time_same_srv<=time_same_srv+1; else time_diff_srv<=time_diff_srv+1; if(is_serror(entry_flag)) time_serror<=time_serror+1; if(is_rerror(entry_flag)) time_rerror<=time_rerror+1; end
                            if(entry_service==q_service) begin time_srv_count<=time_srv_count+1; if(entry_dst!=q_dst_ip) time_srv_diff_host<=time_srv_diff_host+1; if(is_serror(entry_flag)) time_srv_serror<=time_srv_serror+1; if(is_rerror(entry_flag)) time_srv_rerror<=time_srv_rerror+1; end
                        end
                    end
                    if(scan_pointer==HISTORY_DEPTH-1) state<=ST_FINISH; else begin scan_pointer<=scan_pointer+1'b1; state<=ST_READ; end
                end
                ST_FINISH: begin emit_result; result_valid<=1; state<=ST_IDLE; end
            endcase
        end
    end
endmodule


