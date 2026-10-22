`timescale 1ns/1ps

module rtl8211f_mdio_init #(
    parameter MDC_HALF_PERIOD = 25,
    parameter START_DELAY     = 100000,
    parameter FRAME_GAP       = 500,
    parameter [4:0] PHY_ADDR  = 5'b00001
) (
    input  wire clk,
    input  wire rst_n,
    output reg  mdc,
    output reg  mdio_out,
    output reg  mdio_oe,
    output reg  init_done
);
    reg [31:0] delay_count;
    reg [15:0] divider;
    reg [15:0] gap_count;
    reg [63:0] frame;
    reg [6:0]  bit_index;
    reg [1:0]  transaction;
    reg        active;

    function [63:0] mdio_write_frame;
        input [4:0] reg_addr;
        input [15:0] data;
        begin
            mdio_write_frame = {
                32'hFFFFFFFF,
                2'b01,
                2'b01,
                PHY_ADDR,
                reg_addr,
                2'b10,
                data
            };
        end
    endfunction

    function [63:0] selected_frame;
        input [1:0] index;
        begin
            case (index)
                2'd0: selected_frame = mdio_write_frame(5'h09, 16'h0000);
                2'd1: selected_frame = mdio_write_frame(5'h04, 16'h0101);
                default: selected_frame = mdio_write_frame(5'h00, 16'h1200);
            endcase
        end
    endfunction

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            delay_count <= 32'd0;
            divider     <= 16'd0;
            gap_count   <= 16'd0;
            frame       <= 64'd0;
            bit_index   <= 7'd0;
            transaction <= 2'd0;
            active      <= 1'b0;
            mdc         <= 1'b0;
            mdio_out    <= 1'b1;
            mdio_oe     <= 1'b0;
            init_done   <= 1'b0;
        end else if (!init_done) begin
            if (delay_count < START_DELAY) begin
                delay_count <= delay_count + 32'd1;
            end else if (!active) begin
                if (gap_count < FRAME_GAP) begin
                    gap_count <= gap_count + 16'd1;
                end else begin
                    frame       <= selected_frame(transaction);
                    bit_index   <= 7'd63;
                    mdio_out    <= 1'b1;
                    mdio_oe     <= 1'b1;
                    mdc         <= 1'b0;
                    divider     <= 16'd0;
                    gap_count   <= 16'd0;
                    active      <= 1'b1;
                end
            end else if (divider == MDC_HALF_PERIOD - 1) begin
                divider <= 16'd0;
                if (!mdc) begin
                    mdc <= 1'b1;
                end else begin
                    mdc <= 1'b0;
                    if (bit_index == 0) begin
                        active  <= 1'b0;
                        mdio_oe <= 1'b0;
                        if (transaction == 2'd2)
                            init_done <= 1'b1;
                        else
                            transaction <= transaction + 2'd1;
                    end else begin
                        bit_index <= bit_index - 7'd1;
                        mdio_out  <= frame[bit_index-1];
                    end
                end
            end else begin
                divider <= divider + 16'd1;
            end
        end
    end
endmodule

