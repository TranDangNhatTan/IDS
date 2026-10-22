module ids_rate_quantizer (
    input wire [31:0] numerator,
    input wire [31:0] denominator,
    output reg [15:0] rate_q016,
    output reg divide_by_zero
);
    reg [63:0] scaled;
    reg [63:0] quotient;
    reg [63:0] remainder;

    always @* begin
        rate_q016 = 16'd0;
        divide_by_zero = 1'b0;
        scaled = 64'd0;
        quotient = 64'd0;
        remainder = 64'd0;
        if (denominator == 0) begin
            divide_by_zero = 1'b1;
        end else if (numerator >= denominator) begin
            rate_q016 = 16'hFFFF;
        end else begin
            scaled = numerator * 64'd65535;
            quotient = scaled / denominator;
            remainder = scaled % denominator;
            // Round-to-nearest, ties-to-even, matching numpy.rint.
            if ((remainder * 2 > denominator) ||
                ((remainder * 2 == denominator) && quotient[0]))
                quotient = quotient + 1'b1;
            if (quotient > 65535)
                rate_q016 = 16'hFFFF;
            else
                rate_q016 = quotient[15:0];
        end
    end
endmodule


