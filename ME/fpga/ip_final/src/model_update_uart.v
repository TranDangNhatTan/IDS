`timescale 1ns/1ps
// Runtime model protocol, little-endian fields:
// A5 5A 12 12                                     -> begin a 1273-word image
// A5 5A 10 addr_lo addr_hi word[7:0] checksum  -> write inactive bank
// A5 5A 11 checksum                             -> activate at safe boundary
// checksum is XOR of CMD and all payload bytes.  Bad frames never modify RAM.
module model_update_uart (
    input wire clk, input wire rst_n, input wire [7:0] rx_data, input wire rx_valid,
    input wire engine_busy,
    output reg write_en, output reg [11:0] write_addr, output reg [63:0] write_data,
    output reg activate_pulse, output reg checksum_error, output reg [15:0] accepted_words,
    output reg update_open, output reg model_ready
);
    localparam WAIT_A5=0, WAIT_5A=1, CMD=2, PAYLOAD=3, CHECK=4;
    reg [2:0] state; reg [7:0] command, checksum, received_checksum;
    reg [3:0] payload_index, payload_needed;
    reg [11:0] address_latched; reg [63:0] word_latched;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state<=WAIT_A5; write_en<=0; write_addr<=0; write_data<=0; activate_pulse<=0;
            checksum_error<=0; accepted_words<=0; command<=0; checksum<=0; received_checksum<=0;
            payload_index<=0; payload_needed<=0; address_latched<=0; word_latched<=0; update_open<=0; model_ready<=0;
        end else begin
            write_en<=0; activate_pulse<=0;
            if (rx_valid) case (state)
                WAIT_A5: if (rx_data==8'hA5) state<=WAIT_5A;
                WAIT_5A: state <= (rx_data==8'h5A) ? CMD : WAIT_A5;
                CMD: begin
                    command<=rx_data; checksum<=rx_data; payload_index<=0;
                    if (rx_data==8'h10) begin payload_needed<=10; state<=PAYLOAD; end
                    else if (rx_data==8'h11 || rx_data==8'h12) begin payload_needed<=0; state<=CHECK; end
                    else state<=WAIT_A5;
                end
                PAYLOAD: begin
                    checksum <= checksum ^ rx_data;
                    case (payload_index)
                        0: address_latched[7:0] <= rx_data;
                        1: address_latched[11:8] <= rx_data[3:0];
                        2: word_latched[7:0] <= rx_data;
                        3: word_latched[15:8] <= rx_data;
                        4: word_latched[23:16] <= rx_data;
                        5: word_latched[31:24] <= rx_data;
                        6: word_latched[39:32] <= rx_data;
                        7: word_latched[47:40] <= rx_data;
                        8: word_latched[55:48] <= rx_data;
                        default: word_latched[63:56] <= rx_data;
                    endcase
                    if (payload_index == payload_needed-1) state<=CHECK;
                    else payload_index<=payload_index+1'b1;
                end
                CHECK: begin
                    received_checksum<=rx_data;
                    if (rx_data == checksum) begin
                        if (command==8'h12) begin
                            accepted_words<=0; update_open<=1'b1;
                        end else if (command==8'h10 && update_open && accepted_words < 16'd1273) begin
                            write_en<=1; write_addr<=address_latched; write_data<=word_latched;
                            accepted_words<=accepted_words+1'b1;
                        end else if (command==8'h11 && update_open && accepted_words==16'd1273 && !engine_busy) begin
                            activate_pulse<=1; update_open<=0; model_ready<=1'b1;
                        end else checksum_error<=1'b1;
                    end else checksum_error<=1'b1;
                    state<=WAIT_A5;
                end
                default: state<=WAIT_A5;
            endcase
        end
    end
endmodule
