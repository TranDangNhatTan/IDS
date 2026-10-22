`timescale 1ns/1ps

module async_packet_fifo #(
    parameter DEPTH  = 2048,
    parameter ADDR_W = 11
) (
    input  wire              wr_clk,
    input  wire              wr_rst_n,
    input  wire              wr_en,
    input  wire [7:0]        wr_data,
    input  wire              wr_last,
    output reg               wr_full,
    output reg               wr_overflow,

    input  wire              rd_clk,
    input  wire              rd_rst_n,
    input  wire              rd_en,
    output reg  [7:0]        rd_data,
    output reg               rd_last,
    output reg               rd_valid,
    output wire              rd_empty,
    output wire              packet_available
);
    localparam PTR_W = ADDR_W + 1;

    (* syn_ramstyle = "block_ram" *) reg [8:0] memory [0:DEPTH-1];

    reg [PTR_W-1:0] wr_bin;
    reg [PTR_W-1:0] wr_gray;
    reg [PTR_W-1:0] commit_gray;
    reg [PTR_W-1:0] rd_gray_wr1;
    reg [PTR_W-1:0] rd_gray_wr2;

    reg [PTR_W-1:0] rd_bin;
    reg [PTR_W-1:0] rd_gray;
    reg [PTR_W-1:0] wr_gray_rd1;
    reg [PTR_W-1:0] wr_gray_rd2;
    reg [PTR_W-1:0] commit_gray_rd1;
    reg [PTR_W-1:0] commit_gray_rd2;

    wire do_write = wr_en && !wr_full;
    wire do_read  = rd_en && !rd_empty;

    wire [PTR_W-1:0] wr_bin_next = wr_bin + do_write;
    wire [PTR_W-1:0] wr_gray_next = (wr_bin_next >> 1) ^ wr_bin_next;
    wire [PTR_W-1:0] rd_bin_next = rd_bin + do_read;
    wire [PTR_W-1:0] rd_gray_next = (rd_bin_next >> 1) ^ rd_bin_next;

    wire [PTR_W-1:0] full_compare = {
        ~rd_gray_wr2[PTR_W-1:PTR_W-2],
         rd_gray_wr2[PTR_W-3:0]
    };

    assign rd_empty = (rd_gray == wr_gray_rd2);
    assign packet_available = (rd_gray != commit_gray_rd2);

    always @(posedge wr_clk or negedge wr_rst_n) begin
        if (!wr_rst_n) begin
            wr_bin       <= {PTR_W{1'b0}};
            wr_gray      <= {PTR_W{1'b0}};
            commit_gray  <= {PTR_W{1'b0}};
            rd_gray_wr1  <= {PTR_W{1'b0}};
            rd_gray_wr2  <= {PTR_W{1'b0}};
            wr_full      <= 1'b0;
            wr_overflow  <= 1'b0;
        end else begin
            rd_gray_wr1 <= rd_gray;
            rd_gray_wr2 <= rd_gray_wr1;
            wr_overflow <= wr_en && wr_full;

            if (do_write) begin
                memory[wr_bin[ADDR_W-1:0]] <= {wr_last, wr_data};
                wr_bin  <= wr_bin_next;
                wr_gray <= wr_gray_next;
                if (wr_last)
                    commit_gray <= wr_gray_next;
            end

            wr_full <= (wr_gray_next == full_compare);
        end
    end

    always @(posedge rd_clk or negedge rd_rst_n) begin
        if (!rd_rst_n) begin
            rd_bin          <= {PTR_W{1'b0}};
            rd_gray         <= {PTR_W{1'b0}};
            wr_gray_rd1     <= {PTR_W{1'b0}};
            wr_gray_rd2     <= {PTR_W{1'b0}};
            commit_gray_rd1 <= {PTR_W{1'b0}};
            commit_gray_rd2 <= {PTR_W{1'b0}};
            rd_data         <= 8'd0;
            rd_last         <= 1'b0;
            rd_valid        <= 1'b0;
        end else begin
            wr_gray_rd1     <= wr_gray;
            wr_gray_rd2     <= wr_gray_rd1;
            commit_gray_rd1 <= commit_gray;
            commit_gray_rd2 <= commit_gray_rd1;
            rd_valid        <= 1'b0;

            if (do_read) begin
                rd_data  <= memory[rd_bin[ADDR_W-1:0]][7:0];
                rd_last  <= memory[rd_bin[ADDR_W-1:0]][8];
                rd_valid <= 1'b1;
                rd_bin   <= rd_bin_next;
                rd_gray  <= rd_gray_next;
            end
        end
    end
endmodule

