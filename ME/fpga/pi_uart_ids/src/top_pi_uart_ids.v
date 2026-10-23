`timescale 1ns/1ps
// Pi <-> FPGA is one full-duplex UART: C17 is RX and G14 is TX.
module top_pi_uart_ids(
    input wire clk, input wire rst_n,
    input wire uart_pi_rx, output wire uart_pi_tx,
    output wire [3:0] led
);
    // B16 may assert reset asynchronously.  Release the whole design only
    // after two clk edges, matching the known-good UART-RX board image.
    reg [1:0] reset_sync;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            reset_sync <= 2'b00;
        else
            reset_sync <= {reset_sync[0], 1'b1};
    end
    wire core_rst_n = reset_sync[1];

    wire [7:0] rx_byte;
    wire rx_valid, rx_framing_error;
    wire feature_valid;
    wire [15:0] feature_seq;
    wire [615:0] feature_bits;
    wire bad_cobs, bad_crc, bad_length;

    // The existing model-loader is deliberately connected to the same RX
    // stream. It is used only during a maintenance/model-load window; normal
    // FEATURE traffic uses the COBS protocol contract and never needs another
    // UART pin.
    wire model_write_en, model_activate, model_checksum_error;
    wire model_update_open, model_ready;
    wire [11:0] model_write_addr;
    wire [63:0] model_write_data;
    wire [15:0] model_words;

    reg [615:0] fifo_data [0:3];
    reg [15:0] fifo_seq [0:3];
    reg [2:0] wr_ptr, rd_ptr;
    wire fifo_empty = (wr_ptr == rd_ptr);
    wire fifo_full = (wr_ptr[2] != rd_ptr[2]) && (wr_ptr[1:0] == rd_ptr[1:0]);
    reg fifo_overflow;

    reg launch;
    reg [615:0] active_features;
    reg [15:0] active_seq;
    wire engine_ready, engine_busy, result_valid;
    wire [5:0] class_id;
    wire [11:0] leaf_node;
    wire [2:0] error_code;
    wire [7:0] step_count;
    wire active_bank;
    wire [15:0] model_version;

    reg result_start;
    wire result_busy, result_done;

    // Sticky error/counter instrumentation: exported through on-chip probes
    // in a debug build; LEDs remain deliberately quiet and never emit logs.
    reg [31:0] malformed_cobs_count, bad_crc_count, fifo_overflow_count;
    reg [31:0] accepted_count, result_count, classifier_error_count;
    reg prev_bad_cobs, prev_bad_crc, prev_bad_length;

    uart_rx_sync rx0(.clk(clk), .rst_n(core_rst_n), .rx(uart_pi_rx),
                     .data(rx_byte), .valid(rx_valid), .framing_error(rx_framing_error));
    feature_frame_rx feature_rx(.clk(clk), .rst_n(core_rst_n), .rx_data(rx_byte),
                     .rx_valid(rx_valid), .frame_valid(feature_valid),
                     .seq_id(feature_seq), .features(feature_bits),
                     .bad_cobs(bad_cobs), .bad_crc(bad_crc), .bad_length(bad_length));
    model_update_uart model_loader(.clk(clk), .rst_n(core_rst_n), .rx_data(rx_byte),
                     .rx_valid(rx_valid), .engine_busy(engine_busy),
                     .write_en(model_write_en), .write_addr(model_write_addr),
                     .write_data(model_write_data), .activate_pulse(model_activate),
                     .checksum_error(model_checksum_error), .accepted_words(model_words),
                     .update_open(model_update_open), .model_ready(model_ready));
    ids_tree_engine_live classifier(.clk(clk), .rst_n(core_rst_n), .start(launch),
                     .feature_valid(launch), .features_flat(active_features),
                     .model_write_en(model_write_en), .model_write_addr(model_write_addr),
                     .model_write_data(model_write_data), .model_activate(model_activate),
                     .ready(engine_ready), .busy(engine_busy), .done(),
                     .result_valid(result_valid), .class_id(class_id), .leaf_node(leaf_node),
                     .error_code(error_code), .step_count(step_count),
                     .active_bank(active_bank), .model_version(model_version));
    result_frame_tx result_tx(.clk(clk), .rst_n(core_rst_n), .start(result_start),
                     .seq_id(active_seq), .class_id(class_id), .leaf_node(leaf_node),
                     .step_count(step_count), .error_code(error_code),
                     .model_version(model_version), .uart_tx(uart_pi_tx),
                     .busy(result_busy), .done(result_done));

    always @(posedge clk or negedge core_rst_n) begin
        if (!core_rst_n) begin
            wr_ptr <= 0; rd_ptr <= 0; fifo_overflow <= 0;
            launch <= 0; active_features <= 0; active_seq <= 0; result_start <= 0;
            malformed_cobs_count <= 0; bad_crc_count <= 0; fifo_overflow_count <= 0;
            accepted_count <= 0; result_count <= 0; classifier_error_count <= 0;
            prev_bad_cobs <= 0; prev_bad_crc <= 0; prev_bad_length <= 0;
        end else begin
            launch <= 0; result_start <= 0;
            if (bad_cobs && !prev_bad_cobs) malformed_cobs_count <= malformed_cobs_count + 1'b1;
            if (bad_length && !prev_bad_length) malformed_cobs_count <= malformed_cobs_count + 1'b1;
            if (bad_crc && !prev_bad_crc) bad_crc_count <= bad_crc_count + 1'b1;
            prev_bad_cobs <= bad_cobs; prev_bad_length <= bad_length; prev_bad_crc <= bad_crc;
            if (feature_valid) begin
                if (fifo_full) begin
                    fifo_overflow <= 1'b1;
                    fifo_overflow_count <= fifo_overflow_count + 1'b1;
                end else begin
                    fifo_data[wr_ptr[1:0]] <= feature_bits;
                    fifo_seq[wr_ptr[1:0]] <= feature_seq;
                    wr_ptr <= wr_ptr + 1'b1;
                    accepted_count <= accepted_count + 1'b1;
                end
            end
            if (engine_ready && model_ready && !fifo_empty) begin
                active_features <= fifo_data[rd_ptr[1:0]];
                active_seq <= fifo_seq[rd_ptr[1:0]];
                rd_ptr <= rd_ptr + 1'b1;
                launch <= 1'b1;
            end
            if (result_valid && !result_busy) begin
                result_start <= 1'b1;
                result_count <= result_count + 1'b1;
                if (error_code != 0) classifier_error_count <= classifier_error_count + 1'b1;
            end
        end
    end

    assign led[0] = core_rst_n;
    assign led[1] = model_ready;
    assign led[2] = (accepted_count != 0);
    assign led[3] = bad_cobs | bad_crc | bad_length | fifo_overflow |
                    model_checksum_error | rx_framing_error;
endmodule
