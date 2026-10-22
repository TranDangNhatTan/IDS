module ids_tree_engine #(
    parameter FEATURE_COUNT = 28,
    parameter FEATURE_WIDTH = 22,
    parameter NODE_COUNT = 1273,
    parameter MAX_STEPS = 64,
    parameter ROM_FILE = "ME/hw/model_export/dt_fpga_flow28_fixed/node_rom.mem"
) (
    input wire clk,
    input wire rst_n,
    input wire start,
    input wire feature_valid,
    input wire [FEATURE_COUNT*FEATURE_WIDTH-1:0] features_flat,
    output wire ready,
    output wire busy,
    output reg done,
    output reg result_valid,
    output reg [5:0] class_id,
    output reg [11:0] leaf_node,
    output reg [2:0] error_code,
    output reg [7:0] step_count
);
    localparam [1:0] OP_LEAF = 2'b00;
    localparam [1:0] OP_NUMERIC_LE = 2'b01;
    localparam [1:0] OP_CATEGORY_EQ = 2'b10;
    localparam [1:0] OP_INVALID = 2'b11;

    localparam [2:0] ERR_NONE = 3'd0;
    localparam [2:0] ERR_FEATURE_INVALID = 3'd1;
    localparam [2:0] ERR_BAD_OPERATION = 3'd2;
    localparam [2:0] ERR_BAD_FEATURE_ID = 3'd3;
    localparam [2:0] ERR_BAD_CHILD = 3'd4;
    localparam [2:0] ERR_STEP_LIMIT = 3'd5;

    localparam [1:0] ST_IDLE = 2'd0;
    localparam [1:0] ST_WAIT = 2'd1;
    localparam [1:0] ST_EVAL = 2'd2;

    reg [1:0] state;
    reg [11:0] node_address;
    wire [63:0] node_word;
    wire [1:0] operation;
    wire [5:0] feature_id;
    wire [21:0] operand;
    wire [11:0] true_child;
    wire [11:0] false_child;
    wire [5:0] decoded_class;
    wire [3:0] flags;
    wire [FEATURE_WIDTH-1:0] feature_value;
    wire take_true;
    wire [11:0] selected_child;

    assign ready = (state == ST_IDLE);
    assign busy = (state != ST_IDLE);
    assign take_true = (operation == OP_NUMERIC_LE) ? (feature_value <= operand) :
                       (operation == OP_CATEGORY_EQ) ? (feature_value == operand) : 1'b0;
    assign selected_child = take_true ? true_child : false_child;

    ids_tree_rom #(.NODE_COUNT(NODE_COUNT), .ROM_FILE(ROM_FILE)) rom (
        .clk(clk), .address(node_address), .data(node_word)
    );

    ids_node_decoder decoder (
        .node_word(node_word), .operation(operation), .feature_id(feature_id),
        .operand(operand), .true_child(true_child), .false_child(false_child),
        .class_id(decoded_class), .flags(flags)
    );

    ids_feature_regfile #(.FEATURE_COUNT(FEATURE_COUNT), .FEATURE_WIDTH(FEATURE_WIDTH)) feature_bank (
        .clk(clk), .load(state == ST_IDLE && start && feature_valid),
        .features_in(features_flat), .select_id(feature_id), .selected_value(feature_value)
    );

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= ST_IDLE;
            node_address <= 12'd0;
            done <= 1'b0;
            result_valid <= 1'b0;
            class_id <= 6'd0;
            leaf_node <= 12'd0;
            error_code <= ERR_NONE;
            step_count <= 8'd0;
        end else begin
            done <= 1'b0;
            result_valid <= 1'b0;
            case (state)
                ST_IDLE: begin
                    if (start) begin
                        error_code <= ERR_NONE;
                        step_count <= 8'd0;
                        node_address <= 12'd0;
                        if (!feature_valid) begin
                            error_code <= ERR_FEATURE_INVALID;
                            done <= 1'b1;
                        end else begin
                            state <= ST_WAIT;
                        end
                    end
                end
                ST_WAIT: state <= ST_EVAL;
                ST_EVAL: begin
                    if (operation == OP_LEAF) begin
                        class_id <= decoded_class;
                        leaf_node <= node_address;
                        result_valid <= 1'b1;
                        done <= 1'b1;
                        state <= ST_IDLE;
                    end else if (operation == OP_INVALID) begin
                        error_code <= ERR_BAD_OPERATION;
                        done <= 1'b1;
                        state <= ST_IDLE;
                    end else if (feature_id >= FEATURE_COUNT) begin
                        error_code <= ERR_BAD_FEATURE_ID;
                        done <= 1'b1;
                        state <= ST_IDLE;
                    end else if (selected_child >= NODE_COUNT) begin
                        error_code <= ERR_BAD_CHILD;
                        done <= 1'b1;
                        state <= ST_IDLE;
                    end else if (step_count >= MAX_STEPS) begin
                        error_code <= ERR_STEP_LIMIT;
                        done <= 1'b1;
                        state <= ST_IDLE;
                    end else begin
                        node_address <= selected_child;
                        step_count <= step_count + 1'b1;
                        state <= ST_WAIT;
                    end
                end
                default: begin
                    error_code <= ERR_BAD_OPERATION;
                    done <= 1'b1;
                    state <= ST_IDLE;
                end
            endcase
        end
    end
endmodule
