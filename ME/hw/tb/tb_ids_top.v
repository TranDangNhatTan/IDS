`timescale 1ns/1ps
`include "ME/hw/tb/data/vector_count.vh"

module tb_ids_top;
    localparam FEATURE_COUNT = 28;
    localparam RAW_WIDTH = 32;
    localparam VECTOR_COUNT = `RTL_VECTOR_COUNT;

    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg raw_record_valid = 1'b0;
    wire raw_record_ready;
    reg [FEATURE_COUNT*RAW_WIDTH-1:0] raw_features_flat = 0;
    wire busy, done, result_valid;
    wire [5:0] class_id;
    wire [11:0] leaf_node;
    wire [2:0] error_code;
    wire [7:0] step_count;
    reg [FEATURE_COUNT*RAW_WIDTH-1:0] vectors [0:VECTOR_COUNT-1];
    reg [17:0] expected [0:VECTOR_COUNT-1];
    integer i;
    integer failures = 0;

    always #5 clk = ~clk;

    ids_top #(
        .ROM_FILE("ME/hw/model_export/dt_fpga_flow28_fixed/node_rom.mem")
    ) dut (
        .clk(clk), .rst_n(rst_n), .raw_record_valid(raw_record_valid),
        .raw_record_ready(raw_record_ready), .raw_features_flat(raw_features_flat),
        .busy(busy), .done(done), .result_valid(result_valid), .class_id(class_id),
        .leaf_node(leaf_node), .error_code(error_code), .step_count(step_count)
    );

    initial begin
        $readmemh("ME/hw/tb/data/raw_features.mem", vectors);
        $readmemh("ME/hw/tb/data/expected_results.mem", expected);
        repeat (4) @(posedge clk);
        rst_n <= 1'b1;
        repeat (2) @(posedge clk);
        for (i = 0; i < VECTOR_COUNT; i = i + 1) begin
            wait (raw_record_ready);
            @(negedge clk);
            raw_features_flat = vectors[i];
            raw_record_valid = 1'b1;
            @(negedge clk);
            while (!raw_record_ready) @(negedge clk);
            raw_record_valid = 1'b0;
            wait (done);
            #1;
            if (!result_valid || error_code != 0 || class_id != expected[i][5:0] || leaf_node != expected[i][17:6]) begin
                $display("TOP_FAIL vector=%0d class=%0d/%0d leaf=%0d/%0d err=%0d", i,
                         class_id, expected[i][5:0], leaf_node, expected[i][17:6], error_code);
                failures = failures + 1;
            end
            @(posedge clk);
        end
        if (failures == 0)
            $display("IDS_TOP_PASS vectors=%0d", VECTOR_COUNT);
        else
            $display("IDS_TOP_FAIL failures=%0d", failures);
        $finish;
    end

    initial begin
        #(VECTOR_COUNT * 2500);
        $display("IDS_TOP_TIMEOUT");
        $finish;
    end
endmodule
