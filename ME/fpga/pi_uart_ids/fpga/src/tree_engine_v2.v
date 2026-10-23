`timescale 1ns/1ps
module tree_engine_v2 #(parameter NODE_COUNT=1273,parameter MAX_STEPS=64)(
 input wire clk,input wire rst_n,input wire start,input wire [615:0] features_flat,
 input wire model_write_en,input wire [11:0] model_write_addr,input wire [63:0] model_write_data,input wire model_commit,input wire [15:0] commit_version,
 output wire ready,output wire busy,output reg result_valid,output reg [5:0] class_id,output reg [11:0] leaf_node,output reg [2:0] error_code,output reg [7:0] step_count,output wire [15:0] model_version
);
 localparam IDLE=0,WAIT=1,EVAL=2;reg [1:0] state;reg [11:0] node_address;wire [63:0] node_word;wire [1:0] op;wire [5:0] fid,decoded_class;wire [21:0] operand,feature_value;wire [11:0] tc,fc;wire take=(op==1)?(feature_value<=operand):(op==2)?(feature_value==operand):0;wire [11:0] child=take?tc:fc;
 tree_model_dual_bram_v2 #(.NODE_COUNT(NODE_COUNT)) model(.clk(clk),.rst_n(rst_n),.read_addr(node_address),.read_data(node_word),.write_en(model_write_en),.write_addr(model_write_addr),.write_data(model_write_data),.commit(model_commit),.commit_version(commit_version),.model_version(model_version));
 ids_node_decoder dec(.node_word(node_word),.operation(op),.feature_id(fid),.operand(operand),.true_child(tc),.false_child(fc),.class_id(decoded_class),.flags());
 ids_feature_regfile #(.FEATURE_COUNT(28),.FEATURE_WIDTH(22)) regs(.clk(clk),.load(state==IDLE&&start),.features_in(features_flat),.select_id(fid),.selected_value(feature_value));
 assign ready=(state==IDLE);assign busy=(state!=IDLE);
 always @(posedge clk or negedge rst_n)begin if(!rst_n)begin state<=IDLE;node_address<=0;result_valid<=0;class_id<=0;leaf_node<=0;error_code<=0;step_count<=0;end else begin result_valid<=0;case(state)
  IDLE:if(start)begin node_address<=0;step_count<=0;error_code<=0;state<=WAIT;end
  WAIT:state<=EVAL;
  EVAL:if(op==0)begin class_id<=decoded_class;leaf_node<=node_address;result_valid<=1;state<=IDLE;end
   else if(op==3)begin error_code<=2;result_valid<=1;state<=IDLE;end
   else if(fid>=28)begin error_code<=3;result_valid<=1;state<=IDLE;end
   else if(child>=NODE_COUNT)begin error_code<=4;result_valid<=1;state<=IDLE;end
   else if(step_count>=MAX_STEPS-1)begin error_code<=5;result_valid<=1;state<=IDLE;end
   else begin node_address<=child;step_count<=step_count+1'b1;state<=WAIT;end
  default:state<=IDLE;endcase end end
endmodule
