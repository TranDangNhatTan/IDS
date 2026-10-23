`timescale 1ns/1ps

module uart_forwarder_tb;
    localparam integer CLK_FREQ_HZ = 50_000_000;
    localparam integer BAUD_RATE   = 115_200;
    localparam realtime BIT_NS = 1_000_000_000.0 / BAUD_RATE;

    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg uart_rx_pi = 1'b1;
    wire uart_tx_pc;

    uart_forwarder #(
        .CLK_FREQ_HZ(CLK_FREQ_HZ),
        .BAUD_RATE(BAUD_RATE)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .uart_rx_pi(uart_rx_pi),
        .uart_tx_pc(uart_tx_pc)
    );

    always #10 clk = ~clk;

    reg [7:0] expected [0:511];
    integer expected_write = 0;
    integer expected_read = 0;
    integer output_count = 0;

    task queue_expected(input [7:0] value);
        begin
            expected[expected_write] = value;
            expected_write = expected_write + 1;
        end
    endtask

    task send_pi_frame(
        input [7:0] value,
        input bit valid_stop,
        input realtime idle_before
    );
        integer bit_number;
        begin
            uart_rx_pi = 1'b1;
            #(idle_before);
            uart_rx_pi = 1'b0;
            #(BIT_NS);
            for (bit_number = 0; bit_number < 8; bit_number = bit_number + 1) begin
                uart_rx_pi = value[bit_number];
                #(BIT_NS);
            end
            uart_rx_pi = valid_stop;
            #(BIT_NS);
            uart_rx_pi = 1'b1;
        end
    endtask

    task wait_for_outputs(input integer target);
        integer guard;
        begin
            guard = 0;
            while ((output_count < target) && (guard < 2_000_000)) begin
                @(posedge clk);
                guard = guard + 1;
            end
            if (output_count != target)
                $fatal(1, "Timeout: expected %0d forwarded bytes, got %0d", target, output_count);
        end
    endtask

    // Independent UART decoder for the FPGA-to-PC output.
    reg [7:0] monitored_byte;
    integer monitor_bit;
    initial begin
        forever begin
            @(negedge uart_tx_pc);
            #(BIT_NS * 1.5);
            monitored_byte = 8'h00;
            for (monitor_bit = 0; monitor_bit < 8; monitor_bit = monitor_bit + 1) begin
                monitored_byte[monitor_bit] = uart_tx_pc;
                #(BIT_NS);
            end
            if (uart_tx_pc !== 1'b1)
                $fatal(1, "Forwarded UART has an invalid stop bit");
            if (expected_read >= expected_write)
                $fatal(1, "Unexpected forwarded byte 0x%02x", monitored_byte);
            if (monitored_byte !== expected[expected_read])
                $fatal(1, "Forward mismatch index=%0d expected=0x%02x got=0x%02x",
                    expected_read, expected[expected_read], monitored_byte);
            expected_read = expected_read + 1;
            output_count = output_count + 1;
        end
    end

    // Global timeout.
    initial begin
        #80_000_000;
        $fatal(1, "UART_FORWARDER_TB timeout");
    end

    integer i;
    integer count_before;
    initial begin
        repeat (8) @(posedge clk);
        if (uart_tx_pc !== 1'b1)
            $fatal(1, "TX must be idle-high during reset");
        rst_n = 1'b1;
        repeat (8) @(posedge clk);

        // Basic byte values.
        queue_expected(8'h00); send_pi_frame(8'h00, 1'b1, 137.0);
        queue_expected(8'h55); send_pi_frame(8'h55, 1'b1, 263.0);
        queue_expected(8'hA5); send_pi_frame(8'hA5, 1'b1, 401.0);
        queue_expected(8'hFF); send_pi_frame(8'hFF, 1'b1, 79.0);
        wait_for_outputs(expected_write);

        // True back-to-back input frames with no extra idle interval.
        queue_expected(8'h12);
        queue_expected(8'hE7);
        send_pi_frame(8'h12, 1'b1, 13.0);
        send_pi_frame(8'hE7, 1'b1, 0.0);
        wait_for_outputs(expected_write);

        // A 50-clock false start must not be forwarded.
        count_before = output_count;
        uart_rx_pi = 1'b0;
        repeat (50) @(posedge clk);
        uart_rx_pi = 1'b1;
        repeat (300) @(posedge clk);
        if (output_count != count_before)
            $fatal(1, "False start was forwarded");
        queue_expected(8'h3C);
        send_pi_frame(8'h3C, 1'b1, 47.0);
        wait_for_outputs(expected_write);

        // Bad stop bit must be rejected, then reception must recover.
        count_before = output_count;
        send_pi_frame(8'h96, 1'b0, 91.0);
        #(BIT_NS * 2.0);
        if (output_count != count_before)
            $fatal(1, "Framing-error byte was forwarded");
        if (!dut.framing_error_seen)
            $fatal(1, "Framing-error diagnostic was not captured");
        queue_expected(8'h69);
        send_pi_frame(8'h69, 1'b1, 113.0);
        wait_for_outputs(expected_write);

        // Reset in the middle of a frame cancels that frame.
        count_before = output_count;
        uart_rx_pi = 1'b0; #(BIT_NS);
        uart_rx_pi = 1'b1; #(BIT_NS * 0.4);
        rst_n = 1'b0;
        repeat (5) @(posedge clk);
        uart_rx_pi = 1'b1;
        rst_n = 1'b1;
        repeat (10) @(posedge clk);
        if (output_count != count_before || uart_tx_pc !== 1'b1)
            $fatal(1, "Mid-frame reset generated output");

        // Sustained back-to-back binary stream exercises FIFO/handshake.
        for (i = 0; i < 256; i = i + 1) begin
            queue_expected(i[7:0]);
            send_pi_frame(i[7:0], 1'b1, 0.0);
        end
        wait_for_outputs(expected_write);
        repeat (20) @(posedge clk);

        if (dut.overflow_seen)
            $fatal(1, "Forwarder FIFO overflowed during supported stream");
        if (expected_read != expected_write)
            $fatal(1, "Scoreboard not empty expected=%0d read=%0d", expected_write, expected_read);

        $display("UART_FORWARDER_TB_PASS bytes=%0d framing_rejected=1 overflow=0", output_count);
        $finish;
    end
endmodule
