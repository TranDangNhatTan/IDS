module ids_feature_quantizer #(
    parameter FEATURE_COUNT = 28,
    parameter RAW_WIDTH = 32,
    parameter FEATURE_WIDTH = 22
) (
    input wire [FEATURE_COUNT*RAW_WIDTH-1:0] raw_features_flat,
    output reg [FEATURE_COUNT*FEATURE_WIDTH-1:0] encoded_features_flat
);
    integer index;
    reg [31:0] raw_value;
    reg [31:0] scaled_value;
    reg [21:0] encoded_value;

    function [21:0] saturate;
        input [31:0] value;
        input [21:0] maximum;
        begin
            if (value > maximum)
                saturate = maximum;
            else
                saturate = value[21:0];
        end
    endfunction

    always @* begin
        encoded_features_flat = {FEATURE_COUNT*FEATURE_WIDTH{1'b0}};
        raw_value = 32'd0;
        scaled_value = 32'd0;
        encoded_value = 22'd0;
        for (index = 0; index < FEATURE_COUNT; index = index + 1) begin
            raw_value = raw_features_flat[index*RAW_WIDTH +: RAW_WIDTH];
            scaled_value = raw_value;
            case (index)
                0:  encoded_value = saturate(raw_value, 22'd16744); // duration
                1:  encoded_value = saturate(raw_value, 22'd3);     // protocol_type
                2:  encoded_value = saturate(raw_value, 22'd70);    // service
                3:  encoded_value = saturate(raw_value, 22'd11);    // flag
                4: begin                                           // src_bytes / 4
                    scaled_value = raw_value >> 2;
                    encoded_value = saturate(scaled_value, 22'd240748);
                end
                5: begin                                           // dst_bytes / 64
                    scaled_value = raw_value >> 6;
                    encoded_value = saturate(scaled_value, 22'd3309);
                end
                6:  encoded_value = saturate(raw_value, 22'd1);
                7:  encoded_value = saturate(raw_value, 22'd3);
                8:  encoded_value = saturate(raw_value, 22'd1);
                9:  encoded_value = saturate(raw_value, 22'd511);
                10: encoded_value = saturate(raw_value, 22'd100);
                11,12,13,14,15,16,17:
                    encoded_value = saturate(raw_value, 22'd65535);
                18: encoded_value = saturate(raw_value, 22'd253);
                19: encoded_value = saturate(raw_value, 22'd255);
                20,21,22,23,24,25,26,27:
                    encoded_value = saturate(raw_value, 22'd65535);
                default: encoded_value = 22'd0;
            endcase
            encoded_features_flat[index*FEATURE_WIDTH +: FEATURE_WIDTH] = encoded_value;
        end
    end
endmodule
