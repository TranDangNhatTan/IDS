`timescale 1ns/1ps
module ids_tree_engine_live #(
 parameter FEATURE_COUNT=28, parameter FEATURE_WIDTH=22, parameter NODE_COUNT=1273, parameter MAX_STEPS=64,
 parameter ROM_FILE="model/node_rom.mem"
) (
 input wire clk,input wire rst_n,input wire start,input wire feature_valid,
 input wire [FEATURE_COUNT*FEATURE_WIDTH-1:0] features_flat,
 input wire model_write_en,input wire [11:0] model_write_addr,input wire [63:0] model_write_data,input wire model_activate,
 output wire ready,output wire busy,output reg done,output reg result_valid,output reg [5:0] class_id,
 output reg [11:0] leaf_node,output reg [2:0] error_code,output reg [7:0] step_count,
 output wire active_bank,output wire [15:0] model_version
);
 localparam OP_LEAF=2'b00, OP_NUMERIC_LE=2'b01, OP_CATEGORY_EQ=2'b10;
 localparam ST_IDLE=0, ST_WAIT=1, ST_EVAL=2;
 reg [1:0] state; reg [11:0] node_address;
 wire [63:0] node_word; wire [1:0] operation; wire [5:0] feature_id, decoded_class; wire [21:0] operand;
 wire [11:0] true_child,false_child; wire [3:0] flags; wire [FEATURE_WIDTH-1:0] feature_value;
 wire take_true=(operation==OP_NUMERIC_LE)?(feature_value<=operand):(operation==OP_CATEGORY_EQ)?(feature_value==operand):1'b0;
 wire [11:0] selected_child=take_true?true_child:false_child;
 assign ready=(state==ST_IDLE); assign busy=(state!=ST_IDLE);
 ids_tree_rom_banked #(.NODE_COUNT(NODE_COUNT),.ROM_FILE(ROM_FILE)) rom(
   .clk(clk),.address(node_address),.data(node_word),.write_en(model_write_en),.write_addr(model_write_addr),.write_data(model_write_data),.activate_pulse(model_activate),.engine_busy(busy),.active_bank(active_bank),.model_version(model_version));
 ids_node_decoder decoder(.node_word(node_word),.operation(operation),.feature_id(feature_id),.operand(operand),.true_child(true_child),.false_child(false_child),.class_id(decoded_class),.flags(flags));
 ids_feature_regfile #(.FEATURE_COUNT(FEATURE_COUNT),.FEATURE_WIDTH(FEATURE_WIDTH)) feature_bank(.clk(clk),.load(state==ST_IDLE&&start&&feature_valid),.features_in(features_flat),.select_id(feature_id),.selected_value(feature_value));
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin state<=ST_IDLE;node_address<=0;done<=0;result_valid<=0;class_id<=0;leaf_node<=0;error_code<=0;step_count<=0;end
  else begin done<=0;result_valid<=0;case(state)
   ST_IDLE: if(start) begin error_code<=0;step_count<=0;node_address<=0;if(!feature_valid)begin error_code<=1;done<=1;end else state<=ST_WAIT;end
   ST_WAIT: state<=ST_EVAL;
   ST_EVAL: if(operation==OP_LEAF)begin class_id<=decoded_class;leaf_node<=node_address;done<=1;result_valid<=1;state<=ST_IDLE;end
    else if(operation==2'b11)begin error_code<=2;done<=1;state<=ST_IDLE;end
    else if(feature_id>=FEATURE_COUNT)begin error_code<=3;done<=1;state<=ST_IDLE;end
    else if(selected_child>=NODE_COUNT)begin error_code<=4;done<=1;state<=ST_IDLE;end
    else if(step_count>=MAX_STEPS-1)begin error_code<=5;done<=1;state<=ST_IDLE;end
    else begin node_address<=selected_child;step_count<=step_count+1'b1;state<=ST_WAIT;end
   default: state<=ST_IDLE;
  endcase end
 end
endmodule


