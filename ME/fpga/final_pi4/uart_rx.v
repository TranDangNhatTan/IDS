`timescale 1ns/1ps

// UART receiver for the ACG525 / GW5A-LV25UG324C2/I1.
//
// Timing convention: an interval of N clocks completes when baud_count has
// counted from 0 through N-1.  With the default parameters CLKS_PER_BIT=434
// and HALF_CLKS_PER_BIT=217.  The resulting baud is 50 MHz / 434 =
// 115207.37 baud, an error of approximately +0.0064 percent.
module uart_rx #(
    parameter integer CLK_FREQ_HZ = 50_000_000,
    parameter integer BAUD_RATE   = 115_200
) (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       uart_rx,
    output reg  [7:0] rx_data,
    output reg        rx_done,
    output reg        framing_error
);
    localparam integer CLKS_PER_BIT      =
        (CLK_FREQ_HZ + (BAUD_RATE / 2)) / BAUD_RATE;
    localparam integer HALF_CLKS_PER_BIT = CLKS_PER_BIT / 2;

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

    localparam [2:0] ST_IDLE        = 3'd0;
    localparam [2:0] ST_START_CHECK = 3'd1;
    localparam [2:0] ST_DATA        = 3'd2;
    localparam [2:0] ST_STOP        = 3'd3;
    localparam [2:0] ST_WAIT_IDLE   = 3'd4;

    // Asynchronous assertion, synchronous deassertion.  The receiver state
    // cannot leave reset until two clean clk edges have occurred.
    reg [1:0] reset_sync;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            reset_sync <= 2'b00;
        else
            reset_sync <= {reset_sync[0], 1'b1};
    end
    wire core_rst_n = reset_sync[1];

    // uart_rx is asynchronous.  These are exactly two synchronizer stages;
    // rx_history is separate and is used only for falling-edge detection.
    // Resetting all three high represents the UART idle state and prevents a
    // false start when reset is released.
    reg uart_rx_meta;
    reg uart_rx_sync;
    reg rx_history;
    always @(posedge clk or negedge core_rst_n) begin
        if (!core_rst_n) begin
            uart_rx_meta <= 1'b1;
            uart_rx_sync <= 1'b1;
            rx_history   <= 1'b1;
        end else begin
            uart_rx_meta <= uart_rx;
            uart_rx_sync <= uart_rx_meta;
            rx_history   <= uart_rx_sync;
        end
    end
    wire start_falling_edge = rx_history && !uart_rx_sync;

    reg [2:0] state;
    reg [COUNT_WIDTH-1:0] baud_count;
    reg [2:0] bit_index;
    reg [7:0] shift_reg;

    always @(posedge clk or negedge core_rst_n) begin
        if (!core_rst_n) begin
            state         <= ST_IDLE;
            baud_count    <= {COUNT_WIDTH{1'b0}};
            bit_index     <= 3'd0;
            shift_reg     <= 8'h00;
            rx_data       <= 8'h00;
            rx_done       <= 1'b0;
            framing_error <= 1'b0;
        end else begin
            // Event outputs are pulses, never retained status flags.
            rx_done       <= 1'b0;
            framing_error <= 1'b0;

            case (state)
                ST_IDLE: begin
                    baud_count <= {COUNT_WIDTH{1'b0}};
                    bit_index  <= 3'd0;
                    if (start_falling_edge)
                        state <= ST_START_CHECK;
                end

                ST_START_CHECK: begin
                    if (baud_count == HALF_CLKS_PER_BIT - 1) begin
                        baud_count <= {COUNT_WIDTH{1'b0}};
                        if (!uart_rx_sync) begin
                            shift_reg <= 8'h00;
                            bit_index <= 3'd0;
                            state     <= ST_DATA;
                        end else begin
                            // False start: retain rx_data and emit no event.
                            state <= ST_IDLE;
                        end
                    end else begin
                        baud_count <= baud_count + {{(COUNT_WIDTH-1){1'b0}},1'b1};
                    end
                end

                ST_DATA: begin
                    if (baud_count == CLKS_PER_BIT - 1) begin
                        baud_count           <= {COUNT_WIDTH{1'b0}};
                        shift_reg[bit_index] <= uart_rx_sync;
                        if (bit_index == 3'd7) begin
                            bit_index <= 3'd0;
                            state     <= ST_STOP;
                        end else begin
                            bit_index <= bit_index + 3'd1;
                        end
                    end else begin
                        baud_count <= baud_count + {{(COUNT_WIDTH-1){1'b0}},1'b1};
                    end
                end

                ST_STOP: begin
                    if (baud_count == CLKS_PER_BIT - 1) begin
                        baud_count <= {COUNT_WIDTH{1'b0}};
                        if (uart_rx_sync) begin
                            rx_data <= shift_reg;
                            rx_done <= 1'b1;
                            state   <= ST_IDLE;
                        end else begin
                            // Do not publish the corrupt byte.  WAIT_IDLE
                            // suppresses repeated errors during a BREAK.
                            framing_error <= 1'b1;
                            state         <= ST_WAIT_IDLE;
                        end
                    end else begin
                        baud_count <= baud_count + {{(COUNT_WIDTH-1){1'b0}},1'b1};
                    end
                end

                ST_WAIT_IDLE: begin
                    baud_count <= {COUNT_WIDTH{1'b0}};
                    if (uart_rx_sync)
                        state <= ST_IDLE;
                end

                default: begin
                    state      <= ST_IDLE;
                    baud_count <= {COUNT_WIDTH{1'b0}};
                    bit_index  <= 3'd0;
                end
            endcase
        end
    end
endmodule
