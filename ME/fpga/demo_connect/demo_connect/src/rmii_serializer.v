`timescale 1ns/1ps

module rmii_serializer (
    input  wire       clk,
    input  wire       rst_n,
    input  wire [7:0] fifo_data,
    input  wire       fifo_last,
    input  wire       fifo_valid,
    input  wire       fifo_empty,
    input  wire       packet_available,
    output wire       fifo_rd_en,
    output reg  [1:0] txd,
    output reg        tx_en,
    output wire       busy,
    output reg        underflow
);
    localparam ST_IDLE = 2'd0;
    localparam ST_WAIT = 2'd1;
    localparam ST_SEND = 2'd2;
    localparam ST_LAST = 2'd3;

    reg [1:0] state;
    reg [1:0] dibit_index;
    reg [7:0] current_byte;
    reg       current_last;
    reg [7:0] next_byte;
    reg       next_last;
    reg       next_valid;

    wire start_frame = (state == ST_IDLE) && packet_available && !fifo_empty;
    wire request_second = (state == ST_WAIT) && fifo_valid &&
                          !fifo_last && !fifo_empty;
    wire request_following = (state == ST_SEND) &&
                             (dibit_index == 2'd3) &&
                             !current_last && next_valid &&
                             !next_last && !fifo_empty;

    assign fifo_rd_en = start_frame || request_second || request_following;
    assign busy = (state != ST_IDLE);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state         <= ST_IDLE;
            dibit_index   <= 2'd0;
            current_byte  <= 8'd0;
            current_last  <= 1'b0;
            next_byte     <= 8'd0;
            next_last     <= 1'b0;
            next_valid    <= 1'b0;
            txd            <= 2'b00;
            tx_en          <= 1'b0;
            underflow      <= 1'b0;
        end else begin
            underflow <= 1'b0;
            case (state)
                ST_IDLE: begin
                    tx_en <= 1'b0;
                    txd   <= 2'b00;
                    if (start_frame) begin
                        state <= ST_WAIT;
                    end
                end

                ST_WAIT: begin
                    tx_en <= 1'b0;
                    if (fifo_valid) begin
                        current_byte <= fifo_data;
                        current_last <= fifo_last;
                        txd          <= fifo_data[1:0];
                        tx_en        <= 1'b1;
                        dibit_index  <= 2'd1;
                        next_valid   <= 1'b0;
                        state        <= ST_SEND;
                    end
                end

                ST_SEND: begin
                    tx_en <= 1'b1;
                    if (fifo_valid) begin
                        next_byte  <= fifo_data;
                        next_last  <= fifo_last;
                        next_valid <= 1'b1;
                    end
                    case (dibit_index)
                        2'd0: begin
                            txd <= current_byte[1:0];
                            dibit_index <= 2'd1;
                        end
                        2'd1: begin
                            txd <= current_byte[3:2];
                            dibit_index <= 2'd2;
                        end
                        2'd2: begin
                            txd <= current_byte[5:4];
                            dibit_index <= 2'd3;
                        end
                        2'd3: begin
                            txd <= current_byte[7:6];
                            if (current_last) begin
                                state <= ST_LAST;
                            end else if (next_valid) begin
                                current_byte <= next_byte;
                                current_last <= next_last;
                                next_valid   <= 1'b0;
                                dibit_index  <= 2'd0;
                            end else begin
                                underflow <= 1'b1;
                                state     <= ST_LAST;
                            end
                        end
                    endcase
                end

                ST_LAST: begin
                    tx_en <= 1'b0;
                    txd   <= 2'b00;
                    state <= ST_IDLE;
                end

                default: state <= ST_IDLE;
            endcase
        end
    end
endmodule
