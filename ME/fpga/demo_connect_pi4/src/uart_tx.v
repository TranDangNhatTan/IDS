`timescale 1ns/1ps

module uart_tx #(
    parameter integer CLK_FREQ_HZ = 50_000_000,
    parameter integer BAUD_RATE   = 115_200
) (
    input  wire       clk,
    input  wire       rst_n,
    input  wire [7:0] tx_data,
    input  wire       tx_en,
    output reg        uart_tx,
    output reg        tx_busy,
    output reg        tx_done
);
    localparam integer CLKS_PER_BIT =
        (CLK_FREQ_HZ + (BAUD_RATE / 2)) / BAUD_RATE;

    function integer clog2;
        input integer value;
        integer work;
        begin
            work = value - 1;
            for (clog2 = 0; work > 0; clog2 = clog2 + 1)
                work = work >> 1;
        end
    endfunction

    localparam integer COUNT_WIDTH =
        (clog2(CLKS_PER_BIT) < 1) ? 1 : clog2(CLKS_PER_BIT);
    localparam [1:0] IDLE  = 2'd0;
    localparam [1:0] START = 2'd1;
    localparam [1:0] DATA  = 2'd2;
    localparam [1:0] STOP  = 2'd3;

    reg [1:0] state;
    reg [COUNT_WIDTH-1:0] baud_count;
    reg [2:0] bit_index;
    reg [7:0] shift_reg;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state      <= IDLE;
            baud_count <= {COUNT_WIDTH{1'b0}};
            bit_index  <= 3'd0;
            shift_reg  <= 8'h00;
            uart_tx    <= 1'b1;
            tx_busy    <= 1'b0;
            tx_done    <= 1'b0;
        end else begin
            tx_done <= 1'b0;
            case (state)
                IDLE: begin
                    uart_tx    <= 1'b1;
                    tx_busy    <= 1'b0;
                    baud_count <= {COUNT_WIDTH{1'b0}};
                    bit_index  <= 3'd0;
                    if (tx_en) begin
                        shift_reg <= tx_data;
                        uart_tx   <= 1'b0;
                        tx_busy   <= 1'b1;
                        state     <= START;
                    end
                end

                START: begin
                    if (baud_count == CLKS_PER_BIT - 1) begin
                        baud_count <= {COUNT_WIDTH{1'b0}};
                        uart_tx    <= shift_reg[0];
                        state      <= DATA;
                    end else begin
                        baud_count <= baud_count + 1'b1;
                    end
                end

                DATA: begin
                    if (baud_count == CLKS_PER_BIT - 1) begin
                        baud_count <= {COUNT_WIDTH{1'b0}};
                        if (bit_index == 3'd7) begin
                            bit_index <= 3'd0;
                            uart_tx   <= 1'b1;
                            state     <= STOP;
                        end else begin
                            bit_index <= bit_index + 1'b1;
                            uart_tx   <= shift_reg[bit_index + 1'b1];
                        end
                    end else begin
                        baud_count <= baud_count + 1'b1;
                    end
                end

                STOP: begin
                    if (baud_count == CLKS_PER_BIT - 1) begin
                        baud_count <= {COUNT_WIDTH{1'b0}};
                        uart_tx    <= 1'b1;
                        tx_busy    <= 1'b0;
                        tx_done    <= 1'b1;
                        state      <= IDLE;
                    end else begin
                        baud_count <= baud_count + 1'b1;
                    end
                end

                default: begin
                    state   <= IDLE;
                    uart_tx <= 1'b1;
                    tx_busy <= 1'b0;
                end
            endcase
        end
    end
endmodule
