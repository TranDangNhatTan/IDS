module ids_feature_ingest #(
    parameter FEATURE_COUNT = 28,
    parameter RAW_WIDTH = 32,
    parameter FEATURE_WIDTH = 22
) (
    input wire clk,
    input wire rst_n,
    input wire raw_valid,
    output wire raw_ready,
    input wire [FEATURE_COUNT*RAW_WIDTH-1:0] raw_features_flat,
    output reg feature_valid,
    input wire feature_ready,
    output reg [FEATURE_COUNT*FEATURE_WIDTH-1:0] features_flat
);
    wire [FEATURE_COUNT*FEATURE_WIDTH-1:0] quantized;
    wire accept_raw;

    assign raw_ready = !feature_valid || feature_ready;
    assign accept_raw = raw_valid && raw_ready;

    ids_feature_quantizer #(.FEATURE_COUNT(FEATURE_COUNT), .RAW_WIDTH(RAW_WIDTH), .FEATURE_WIDTH(FEATURE_WIDTH)) quantizer (
        .raw_features_flat(raw_features_flat), .encoded_features_flat(quantized)
    );

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            feature_valid <= 1'b0;
            features_flat <= {FEATURE_COUNT*FEATURE_WIDTH{1'b0}};
        end else begin
            if (accept_raw) begin
                features_flat <= quantized;
                feature_valid <= 1'b1;
            end else if (feature_ready) begin
                feature_valid <= 1'b0;
            end
        end
    end
endmodule

