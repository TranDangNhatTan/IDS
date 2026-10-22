`timescale 1ns/1ps

module rgmii_100_serializer (
    input  wire       clk,
    input  wire       nibble_ce,
    input  wire       rst_n,
    input  wire [7:0] fifo_data,
    input  wire       fifo_last,
    input  wire       fifo_valid,
    input  wire       fifo_empty,
    input  wire       packet_available,
    output wire       fifo_rd_en,
    output reg  [3:0] txd,
    output reg        tx_ctl,
    output reg        underflow
);
    localparam ST_IDLE = 2'd0;
    localparam ST_HIGH = 2'd1;
    localparam ST_NEXT = 2'd2;

    reg [1:0] state;
    reg [7:0] current_byte;
    reg       current_last;
    reg [7:0] buffered_byte;
    reg       buffered_last;
    reg       buffered_valid;
    reg       read_pending;

    assign fifo_rd_en = rst_n && !read_pending && !buffered_valid &&
                        packet_available && !fifo_empty;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state        <= ST_IDLE;
            current_byte <= 8'd0;
            current_last <= 1'b0;
            buffered_byte  <= 8'd0;
            buffered_last  <= 1'b0;
            buffered_valid <= 1'b0;
            read_pending   <= 1'b0;
            txd          <= 4'd0;
            tx_ctl       <= 1'b0;
            underflow    <= 1'b0;
        end else begin
            underflow <= 1'b0;
            if (fifo_rd_en)
                read_pending <= 1'b1;

            if (fifo_valid) begin
                buffered_byte  <= fifo_data;
                buffered_last  <= fifo_last;
                buffered_valid <= 1'b1;
                read_pending   <= 1'b0;
            end

            // nibble_ce is high immediately before TX_CLK changes high->low.
            // Outputs then have half a TX clock period to settle before the
            // RTL8211F samples them on the next rising edge.
            if (nibble_ce) begin
                case (state)
                    ST_IDLE: begin
                        txd    <= 4'd0;
                        tx_ctl <= 1'b0;
                        if (buffered_valid) begin
                            current_byte  <= buffered_byte;
                            current_last  <= buffered_last;
                            buffered_valid <= 1'b0;
                            txd           <= buffered_byte[3:0];
                            tx_ctl        <= 1'b1;
                            state         <= ST_HIGH;
                        end
                    end

                    ST_HIGH: begin
                        txd    <= current_byte[7:4];
                        tx_ctl <= 1'b1;
                        state  <= ST_NEXT;
                    end

                    ST_NEXT: begin
                        if (current_last) begin
                            txd    <= 4'd0;
                            tx_ctl <= 1'b0;
                            state  <= ST_IDLE;
                        end else if (buffered_valid) begin
                            current_byte  <= buffered_byte;
                            current_last  <= buffered_last;
                            buffered_valid <= 1'b0;
                            txd           <= buffered_byte[3:0];
                            tx_ctl        <= 1'b1;
                            state         <= ST_HIGH;
                        end else begin
                            txd       <= 4'd0;
                            tx_ctl    <= 1'b0;
                            underflow <= 1'b1;
                            state     <= ST_IDLE;
                        end
                    end

                    default: state <= ST_IDLE;
                endcase
            end
        end
    end
endmodule
