module ids_top #(
    parameter FEATURE_COUNT = 28,
    parameter RAW_WIDTH = 32,
    parameter FEATURE_WIDTH = 22,
    parameter NODE_COUNT = 1273,
    parameter MAX_STEPS = 64,
    parameter ROM_FILE = "ME/hw/model_export/dt_fpga_flow28_fixed/node_rom.mem"
) (
    input wire clk,
    input wire rst_n,
    input wire raw_record_valid,
    output wire raw_record_ready,
    input wire [FEATURE_COUNT*RAW_WIDTH-1:0] raw_features_flat,
    output wire busy,
    output wire done,
    output wire result_valid,
    output wire [5:0] class_id,
    output wire [11:0] leaf_node,
    output wire [2:0] error_code,
    output wire [7:0] step_count
);
    wire feature_valid;
    wire feature_ready;
    wire [FEATURE_COUNT*FEATURE_WIDTH-1:0] features_flat;
    wire engine_ready;
    wire start;

    assign start = feature_valid && engine_ready;
    assign feature_ready = start;

    ids_feature_ingest #(.FEATURE_COUNT(FEATURE_COUNT), .RAW_WIDTH(RAW_WIDTH), .FEATURE_WIDTH(FEATURE_WIDTH)) ingest (
        .clk(clk), .rst_n(rst_n), .raw_valid(raw_record_valid), .raw_ready(raw_record_ready),
        .raw_features_flat(raw_features_flat), .feature_valid(feature_valid),
        .feature_ready(feature_ready), .features_flat(features_flat)
    );

    ids_tree_engine #(.FEATURE_COUNT(FEATURE_COUNT), .FEATURE_WIDTH(FEATURE_WIDTH),
                      .NODE_COUNT(NODE_COUNT), .MAX_STEPS(MAX_STEPS), .ROM_FILE(ROM_FILE)) engine (
        .clk(clk), .rst_n(rst_n), .start(start), .feature_valid(feature_valid),
        .features_flat(features_flat), .ready(engine_ready), .busy(busy), .done(done),
        .result_valid(result_valid), .class_id(class_id), .leaf_node(leaf_node),
        .error_code(error_code), .step_count(step_count)
    );
endmodule
