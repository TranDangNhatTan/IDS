module ids_feature_regfile #(
    parameter FEATURE_COUNT = 28,
    parameter FEATURE_WIDTH = 22
) (
    input wire clk,
    input wire load,
    input wire [FEATURE_COUNT*FEATURE_WIDTH-1:0] features_in,
    input wire [5:0] select_id,
    output reg [FEATURE_WIDTH-1:0] selected_value
);
    reg [FEATURE_COUNT*FEATURE_WIDTH-1:0] features_reg;

    always @(posedge clk) begin
        if (load)
            features_reg <= features_in;
    end

    always @* begin
        if (select_id < FEATURE_COUNT)
            selected_value = features_reg[select_id*FEATURE_WIDTH +: FEATURE_WIDTH];
        else
            selected_value = {FEATURE_WIDTH{1'b0}};
    end
endmodule

