`timescale 1ns/1ps

module tb_ids_packet_top;
    reg clk = 0;
    reg rst_n = 0;
    reg [7:0] rx_data = 0;
    reg rx_valid = 0;
    reg rx_sop = 0;
    reg rx_last = 0;
    reg [63:0] timestamp_ticks = 0;
    reg timeout_close = 0;
    wire parser_error, flow_table_full, busy, done, result_valid;
    wire [5:0] class_id;
    wire [11:0] leaf_node;
    wire [2:0] error_code;
    reg [7:0] packet [0:53];
    integer i;
    integer failures = 0;

    always #5 clk = ~clk;

    ids_packet_top #(
        .TICKS_PER_SECOND(100),
        .ROM_FILE("ME/hw/model_export/dt_fpga_flow28_fixed/node_rom.mem")
    ) dut (
        .clk(clk), .rst_n(rst_n), .rx_data(rx_data), .rx_valid(rx_valid),
        .rx_sop(rx_sop), .rx_last(rx_last), .timestamp_ticks(timestamp_ticks),
        .timeout_close(timeout_close), .parser_error(parser_error),
        .flow_table_full(flow_table_full), .busy(busy), .done(done),
        .result_valid(result_valid), .class_id(class_id), .leaf_node(leaf_node),
        .error_code(error_code)
    );

    task send_packet;
        input reverse_direction;
        input second_flow;
        input [7:0] flags;
        input [63:0] stamp;
        begin
            for (i = 0; i < 54; i = i + 1) packet[i] = 8'h00;
            packet[12] = 8'h08; packet[13] = 8'h00;
            packet[14] = 8'h45; packet[16] = 8'h00; packet[17] = 8'd40;
            packet[22] = 8'd64; packet[23] = 8'd6;
            if (second_flow) begin
                packet[26] = 8'd192; packet[27] = 8'd168; packet[28] = 8'd1; packet[29] = 8'd20;
                packet[30] = 8'd10; packet[31] = 8'd0; packet[32] = 8'd0; packet[33] = 8'd2;
                packet[34] = 8'h5B; packet[35] = 8'hA0;
                packet[36] = 8'h00; packet[37] = 8'h16;
            end else if (!reverse_direction) begin
                packet[26] = 8'd192; packet[27] = 8'd168; packet[28] = 8'd1; packet[29] = 8'd10;
                packet[30] = 8'd10; packet[31] = 8'd0; packet[32] = 8'd0; packet[33] = 8'd1;
                packet[34] = 8'h30; packet[35] = 8'h39;
                packet[36] = 8'h00; packet[37] = 8'h50;
            end else begin
                packet[26] = 8'd10; packet[27] = 8'd0; packet[28] = 8'd0; packet[29] = 8'd1;
                packet[30] = 8'd192; packet[31] = 8'd168; packet[32] = 8'd1; packet[33] = 8'd10;
                packet[34] = 8'h00; packet[35] = 8'h50;
                packet[36] = 8'h30; packet[37] = 8'h39;
            end
            packet[46] = 8'h50; packet[47] = flags;
            timestamp_ticks = stamp;
            for (i = 0; i < 54; i = i + 1) begin
                @(negedge clk);
                rx_data = packet[i]; rx_valid = 1'b1;
                rx_sop = (i == 0); rx_last = (i == 53);
            end
            @(negedge clk);
            rx_valid = 1'b0; rx_sop = 1'b0; rx_last = 1'b0;
            repeat (2) @(posedge clk);
        end
    endtask

    initial begin
        repeat (4) @(posedge clk);
        rst_n <= 1'b1;
        repeat (2) @(posedge clk);
        send_packet(1'b0, 1'b0, 8'h12, 64'd0);   // flow A forward SYN+ACK
        send_packet(1'b0, 1'b1, 8'h12, 64'd20);  // flow B interleaved, proves two entries
        send_packet(1'b1, 1'b0, 8'h11, 64'd100); // flow A reverse FIN+ACK, closes A
        wait (done);
        #1;
        if (!result_valid || error_code != 0 || parser_error || flow_table_full ||
            class_id != 6'd18 || leaf_node != 12'd1087)
            failures = failures + 1;
        if (failures == 0)
            $display("PACKET_TOP_PASS class=%0d leaf=%0d", class_id, leaf_node);
        else
            $display("PACKET_TOP_FAIL class=%0d leaf=%0d err=%0d parser=%0d collision=%0d",
                     class_id, leaf_node, error_code, parser_error, flow_table_full);
        $finish;
    end

    initial begin
        #1000000;
        $display("PACKET_TOP_TIMEOUT");
        $finish;
    end
endmodule
