`timescale 1ns/1ps
`include "ME/hw/tb/data/vector_count.vh"

module tb_ids_tree_engine;
    localparam FEATURE_COUNT = 28;
    localparam FEATURE_WIDTH = 22;
    localparam NODE_COUNT = 1273;
    localparam VECTOR_COUNT = `RTL_VECTOR_COUNT;

    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg start = 1'b0;
    reg feature_valid = 1'b0;
    reg [FEATURE_COUNT*FEATURE_WIDTH-1:0] features_flat = 0;
    wire ready, busy, done, result_valid;
    wire [5:0] class_id;
    wire [11:0] leaf_node;
    wire [2:0] error_code;
    wire [7:0] step_count;
    reg [FEATURE_COUNT*FEATURE_WIDTH-1:0] vectors [0:VECTOR_COUNT-1];
    reg [17:0] expected [0:VECTOR_COUNT-1];
    integer i;
    integer failures = 0;
    integer max_steps = 0;

    always #5 clk = ~clk;

    ids_tree_engine #(
        .NODE_COUNT(NODE_COUNT),
        .ROM_FILE("ME/hw/model_export/dt_fpga_flow28_fixed/node_rom.mem")
    ) dut (
        .clk(clk), .rst_n(rst_n), .start(start), .feature_valid(feature_valid),
        .features_flat(features_flat), .ready(ready), .busy(busy), .done(done),
        .result_valid(result_valid), .class_id(class_id), .leaf_node(leaf_node),
        .error_code(error_code), .step_count(step_count)
    );

    initial begin
        $readmemh("ME/hw/tb/data/tree_features.mem", vectors);
        $readmemh("ME/hw/tb/data/expected_results.mem", expected);
        repeat (4) @(posedge clk);
        rst_n <= 1'b1;
        repeat (2) @(posedge clk);

        for (i = 0; i < VECTOR_COUNT; i = i + 1) begin
            wait (ready);
            @(negedge clk);
            features_flat = vectors[i];
            feature_valid = 1'b1;
            start = 1'b1;
            @(negedge clk);
            start = 1'b0;
            feature_valid = 1'b0;
            wait (done);
            #1;
            if (!result_valid || error_code != 0 || class_id != expected[i][5:0] || leaf_node != expected[i][17:6]) begin
                $display("TREE_FAIL vector=%0d class=%0d/%0d leaf=%0d/%0d err=%0d", i,
                         class_id, expected[i][5:0], leaf_node, expected[i][17:6], error_code);
                failures = failures + 1;
            end
            if (step_count > max_steps)
                max_steps = step_count;
            @(posedge clk);
        end

        // Invalid feature record must terminate with an explicit error.
        wait (ready);
        @(negedge clk);
        start = 1'b1;
        feature_valid = 1'b0;
        @(negedge clk);
        start = 1'b0;
        wait (done);
        #1;
        if (error_code != 3'd1 || result_valid)
            failures = failures + 1;

        if (failures == 0)
            $display("TREE_ENGINE_PASS vectors=%0d max_steps=%0d", VECTOR_COUNT, max_steps);
        else
            $display("TREE_ENGINE_FAIL failures=%0d", failures);
        $finish;
    end

    initial begin
        #(VECTOR_COUNT * 2000);
        $display("TREE_ENGINE_TIMEOUT");
        $finish;
    end
endmodule
