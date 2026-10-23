`timescale 1ns/1ps
// Protocol-v2 transactional model loader. Pi sends writes in file order;
// retries of an already accepted index are acknowledged idempotently.
module model_manager_v2 #(parameter NODE_COUNT=1273)(
 input wire clk,input wire rst_n,input wire frame_valid,input wire [7:0] frame_type,input wire [15:0] frame_seq,input wire [7:0] payload_len,input wire [615:0] payload,input wire engine_busy,input wire [15:0] current_version,
 output reg write_en,output reg [11:0] write_addr,output reg [63:0] write_data,output reg commit,output reg [15:0] commit_version,
 output reg model_valid,output reg upload_open,output reg [15:0] accepted_count,output reg [31:0] upload_error_count,
 output reg response_valid,output reg [7:0] response_type,output reg [15:0] response_seq,output reg [7:0] response_len,output reg [615:0] response_payload
);
 localparam OK=0,BAD_STATE=1,BAD_INDEX=2,BAD_COUNT=3,IMAGE_CRC=4,BUSY=5,UNSUPPORTED=6;
 reg [31:0] expected_crc,crc_work;reg [15:0] requested_version;reg [7:0] status;reg [15:0] idx;reg [63:0] word;reg [31:0] commit_crc;
 function [31:0] crc32_byte;input [31:0] c;input [7:0] d;integer i;reg [31:0] t;begin t=c^d;for(i=0;i<8;i=i+1)t=t[0]?((t>>1)^32'hEDB88320):(t>>1);crc32_byte=t;end endfunction
 function [31:0] crc32_word_le;input [31:0] c;input [63:0] w;integer j;reg [31:0] t;begin t=c;for(j=0;j<8;j=j+1)t=crc32_byte(t,w[j*8 +:8]);crc32_word_le=t;end endfunction
 task respond;input [7:0] typ;input [15:0] sq;input [7:0] st;begin response_valid<=1;response_type<=typ;response_seq<=sq;response_len<=5;response_payload<=0;response_payload[7:0]<=st;response_payload[23:8]<=accepted_count;response_payload[39:24]<=current_version;end endtask
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin write_en<=0;write_addr<=0;write_data<=0;commit<=0;commit_version<=0;model_valid<=0;upload_open<=0;accepted_count<=0;upload_error_count<=0;response_valid<=0;response_type<=0;response_seq<=0;response_len<=0;response_payload<=0;expected_crc<=0;crc_work<=0;requested_version<=0;end
  else begin write_en<=0;commit<=0;response_valid<=0;
   if(frame_valid)case(frame_type)
    8'h01:begin // MODEL_BEGIN
     if(payload_len!=8)begin upload_error_count<=upload_error_count+1;respond(8'h81,frame_seq,BAD_COUNT);end
     else if({payload[15:0]}!=NODE_COUNT)begin upload_error_count<=upload_error_count+1;respond(8'h81,frame_seq,BAD_COUNT);end
     else if(engine_busy)respond(8'h81,frame_seq,BUSY);
     else begin
      upload_open<=1;accepted_count<=0;crc_work<=32'hffff_ffff;expected_crc<=payload[47:16];requested_version<=payload[63:48];
      respond(8'h81,frame_seq,OK);
      // ACK acknowledges the newly opened staging image, not the previous one.
      response_payload[23:8] <= 16'd0;
      response_payload[39:24] <= payload[63:48];
     end
    end
    8'h02:begin // MODEL_WRITE
     idx=payload[15:0];word=payload[79:16];
     if(payload_len!=10)begin upload_error_count<=upload_error_count+1;respond(8'h82,frame_seq,BAD_COUNT);end
     else if(!upload_open)respond(8'h82,frame_seq,BAD_STATE);
     else if(idx>=NODE_COUNT)begin upload_error_count<=upload_error_count+1;respond(8'h82,frame_seq,BAD_INDEX);end
     else if(idx<accepted_count)respond(8'h82,frame_seq,OK);
     else if(idx!=accepted_count)begin upload_error_count<=upload_error_count+1;respond(8'h82,frame_seq,BAD_INDEX);end
     else begin
      write_en<=1;write_addr<=idx[11:0];write_data<=word;accepted_count<=accepted_count+1'b1;crc_work<=crc32_word_le(crc_work,word);
      respond(8'h82,frame_seq,OK);
      // Non-blocking state update occurs after this edge; return the count just accepted.
      response_payload[23:8] <= accepted_count + 1'b1;
      response_payload[39:24] <= requested_version;
     end
    end
    8'h03:begin // MODEL_COMMIT
     commit_crc=payload[31:0];
     if(payload_len!=6)begin upload_error_count<=upload_error_count+1;respond(8'h83,frame_seq,BAD_COUNT);end
     else if(!upload_open)respond(8'h83,frame_seq,BAD_STATE);
     else if(accepted_count!=NODE_COUNT)begin upload_error_count<=upload_error_count+1;respond(8'h83,frame_seq,BAD_COUNT);end
     else if(commit_crc!=expected_crc || commit_crc!=(crc_work^32'hffff_ffff))begin upload_error_count<=upload_error_count+1;respond(8'h83,frame_seq,IMAGE_CRC);end
     else begin
      commit<=1;commit_version<=payload[47:32];model_valid<=1;upload_open<=0;
      respond(8'h83,frame_seq,OK);
      // The model bank changes on the next clock; report the requested committed version now.
      response_payload[39:24] <= payload[47:32];
     end
    end
    8'h04:begin respond(8'h84,frame_seq,model_valid?OK:BAD_STATE);end
    default:;
   endcase
  end
 end
endmodule
