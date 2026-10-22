`timescale 1ns/1ps

module fifo_packet_buffer #(
    parameter DEPTH  = 2048,
    parameter ADDR_W = 11
) (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       wr_en,
    input  wire [7:0] wr_data,
    input  wire       wr_last,
    output wire       full,
    output reg        overflow,
    input  wire       rd_en,
    output reg  [7:0] rd_data,
    output reg        rd_last,
    output reg        rd_valid,
    output wire       empty,
    output wire       packet_available,
    output wire [ADDR_W:0] level
);
    (* syn_ramstyle = "block_ram" *) reg [8:0] memory [0:DEPTH-1];
    reg [ADDR_W-1:0] wr_ptr;
    reg [ADDR_W-1:0] rd_ptr;
    reg [ADDR_W:0]   count;
    reg [ADDR_W:0]   packet_count;

    wire do_write = wr_en && !full;
    wire do_read  = rd_en && !empty;
    wire write_packet = do_write && wr_last;
    wire read_packet  = rd_valid && rd_last;

    assign full             = (count == DEPTH);
    assign empty            = (count == 0);
    assign packet_available = (packet_count != 0);
    assign level            = count;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_ptr       <= {ADDR_W{1'b0}};
            rd_ptr       <= {ADDR_W{1'b0}};
            count        <= {(ADDR_W+1){1'b0}};
            packet_count <= {(ADDR_W+1){1'b0}};
            overflow     <= 1'b0;
            rd_data      <= 8'd0;
            rd_last      <= 1'b0;
            rd_valid     <= 1'b0;
        end else begin
            overflow <= wr_en && full;
            rd_valid <= 1'b0;

            if (do_write) begin
                memory[wr_ptr] <= {wr_last, wr_data};
                wr_ptr <= wr_ptr + {{(ADDR_W-1){1'b0}}, 1'b1};
            end

            if (do_read) begin
                rd_data  <= memory[rd_ptr][7:0];
                rd_last  <= memory[rd_ptr][8];
                rd_valid <= 1'b1;
                rd_ptr <= rd_ptr + {{(ADDR_W-1){1'b0}}, 1'b1};
            end

            case ({do_write, do_read})
                2'b10: count <= count + {{ADDR_W{1'b0}}, 1'b1};
                2'b01: count <= count - {{ADDR_W{1'b0}}, 1'b1};
                default: count <= count;
            endcase

            case ({write_packet, read_packet})
                2'b10: packet_count <= packet_count + {{ADDR_W{1'b0}}, 1'b1};
                2'b01: packet_count <= packet_count - {{ADDR_W{1'b0}}, 1'b1};
                default: packet_count <= packet_count;
            endcase
        end
    end
endmodule
