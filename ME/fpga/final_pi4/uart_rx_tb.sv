`timescale 1ns/1ps

module uart_rx_tb;
    localparam integer CLK_FREQ_HZ = 50_000_000;
    localparam integer BAUD_RATE   = 115_200;
    localparam integer EXPECTED_CLKS_PER_BIT = 434;
    localparam integer EXPECTED_HALF_CLKS    = 217;
    localparam realtime IDEAL_BIT_NS = 1_000_000_000.0 / BAUD_RATE;
    localparam realtime FAST_BIT_NS  = 1_000_000_000.0 / (BAUD_RATE * 1.02);
    localparam realtime SLOW_BIT_NS  = 1_000_000_000.0 / (BAUD_RATE * 0.98);

    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg uart_line = 1'b1;
    wire [7:0] rx_data;
    wire rx_done;
    wire framing_error;

    uart_rx #(
        .CLK_FREQ_HZ(CLK_FREQ_HZ),
        .BAUD_RATE(BAUD_RATE)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .uart_rx(uart_line),
        .rx_data(rx_data),
        .rx_done(rx_done),
        .framing_error(framing_error)
    );

    always #10 clk = ~clk;

    reg [7:0] expected [0:511];
    integer expected_write = 0;
    integer expected_read = 0;
    integer done_count = 0;
    integer error_count = 0;
    reg previous_done = 1'b0;
    reg previous_error = 1'b0;
    reg [7:0] previous_data = 8'h00;

    task queue_expected(input [7:0] value);
        begin
            expected[expected_write] = value;
            expected_write = expected_write + 1;
        end
    endtask

    task wait_for_expected(input integer target);
        integer guard;
        begin
            guard = 0;
            while ((expected_read < target) && (guard < 200000)) begin
                @(posedge clk);
                guard = guard + 1;
            end
            if (expected_read != target)
                $fatal(1, "Timeout waiting for expected byte target=%0d got=%0d", target, expected_read);
        end
    endtask

    task send_uart_frame(
        input [7:0] value,
        input realtime bit_period,
        input bit stop_valid,
        input realtime idle_before
    );
        integer bit_number;
        begin
            uart_line = 1'b1;
            #(idle_before);
            uart_line = 1'b0;
            #(bit_period);
            for (bit_number = 0; bit_number < 8; bit_number = bit_number + 1) begin
                uart_line = value[bit_number];
                #(bit_period);
            end
            uart_line = stop_valid;
            #(bit_period);
            uart_line = 1'b1;
        end
    endtask

    // Central scoreboard and pulse-width assertions.
    always @(posedge clk) begin
        #1;
        if (rx_done && framing_error)
            $fatal(1, "rx_done and framing_error asserted together");
        if (rx_done && previous_done)
            $fatal(1, "rx_done wider than one clock");
        if (framing_error && previous_error)
            $fatal(1, "framing_error wider than one clock");

        if (!rst_n || !dut.core_rst_n) begin
            previous_data = rx_data;
        end else begin
            if ((rx_data !== previous_data) && !rx_done)
                $fatal(1, "rx_data changed without rx_done old=%02x new=%02x", previous_data, rx_data);
            if (rx_done) begin
                if (expected_read >= expected_write)
                    $fatal(1, "Unexpected rx_done data=%02x", rx_data);
                if (rx_data !== expected[expected_read])
                    $fatal(1, "Byte mismatch index=%0d expected=%02x got=%02x", expected_read, expected[expected_read], rx_data);
                expected_read = expected_read + 1;
                done_count = done_count + 1;
            end
            if (framing_error)
                error_count = error_count + 1;
            previous_data = rx_data;
        end
        previous_done = rx_done;
        previous_error = framing_error;
    end

    // Global simulation timeout.
    initial begin
        #80_000_000;
        $fatal(1, "Global UART_RX testbench timeout");
    end

    integer i;
    integer base_done;
    integer base_error;
    integer target;
    reg [7:0] data_before;
    initial begin
        if (dut.CLKS_PER_BIT != EXPECTED_CLKS_PER_BIT)
            $fatal(1, "CLKS_PER_BIT expected %0d got %0d", EXPECTED_CLKS_PER_BIT, dut.CLKS_PER_BIT);
        if (dut.HALF_CLKS_PER_BIT != EXPECTED_HALF_CLKS)
            $fatal(1, "HALF_CLKS_PER_BIT expected %0d got %0d", EXPECTED_HALF_CLKS, dut.HALF_CLKS_PER_BIT);
        if (CLK_FREQ_HZ <= 0 || BAUD_RATE <= 0 || EXPECTED_CLKS_PER_BIT < 4)
            $fatal(1, "Invalid UART parameter set");

        // Reset and idle behavior.
        repeat (6) @(posedge clk);
        if (rx_data !== 8'h00 || rx_done !== 1'b0 || framing_error !== 1'b0)
            $fatal(1, "Outputs incorrect during reset");
        rst_n = 1'b1;
        repeat (8) @(posedge clk);
        if (rx_done || framing_error)
            $fatal(1, "Spurious event after reset release");

        // Basic values.
        queue_expected(8'h00); send_uart_frame(8'h00, IDEAL_BIT_NS, 1'b1, 913.0);
        queue_expected(8'h55); send_uart_frame(8'h55, IDEAL_BIT_NS, 1'b1, 127.0);
        queue_expected(8'hA5); send_uart_frame(8'hA5, IDEAL_BIT_NS, 1'b1, 311.0);
        queue_expected(8'hFF); send_uart_frame(8'hFF, IDEAL_BIT_NS, 1'b1, 503.0);
        wait_for_expected(4);

        // Back-to-back frames: each still includes exactly one stop bit.
        queue_expected(8'h12);
        queue_expected(8'hE7);
        send_uart_frame(8'h12, IDEAL_BIT_NS, 1'b1, 37.0);
        send_uart_frame(8'hE7, IDEAL_BIT_NS, 1'b1, 0.0);
        wait_for_expected(6);

        // False start shorter than half a bit.
        base_done = done_count;
        base_error = error_count;
        data_before = rx_data;
        uart_line = 1'b0;
        repeat (50) @(posedge clk);
        uart_line = 1'b1;
        repeat (300) @(posedge clk);
        if (done_count != base_done || error_count != base_error || rx_data !== data_before)
            $fatal(1, "False start generated an event or changed data");
        queue_expected(8'h3C);
        send_uart_frame(8'h3C, IDEAL_BIT_NS, 1'b1, 73.0);
        wait_for_expected(7);

        // Invalid stop bit emits one error and never publishes the byte.
        base_done = done_count;
        base_error = error_count;
        data_before = rx_data;
        send_uart_frame(8'h96, IDEAL_BIT_NS, 1'b0, 149.0);
        repeat (600) @(posedge clk);
        if (done_count != base_done || error_count != base_error + 1 || rx_data !== data_before)
            $fatal(1, "Framing-error behavior incorrect done=%0d error=%0d", done_count-base_done, error_count-base_error);

        // BREAK produces only one error until a high idle level is observed.
        base_done = done_count;
        base_error = error_count;
        uart_line = 1'b0;
        #(IDEAL_BIT_NS * 14.0);
        if (done_count != base_done || error_count != base_error + 1)
            $fatal(1, "BREAK did not produce exactly one framing error");
        #(IDEAL_BIT_NS * 3.0);
        if (error_count != base_error + 1)
            $fatal(1, "BREAK produced repeated framing errors");
        uart_line = 1'b1;
        #(IDEAL_BIT_NS);
        queue_expected(8'h69);
        send_uart_frame(8'h69, IDEAL_BIT_NS, 1'b1, 41.0);
        wait_for_expected(8);

        // Reset in the middle of a frame cancels it.  Reset contract takes
        // precedence over retained data: rx_data returns to 00 during reset.
        base_done = done_count;
        base_error = error_count;
        uart_line = 1'b0; #(IDEAL_BIT_NS);
        uart_line = 1'b1; #(IDEAL_BIT_NS);
        uart_line = 1'b0; #(IDEAL_BIT_NS * 0.4);
        rst_n = 1'b0;
        repeat (4) @(posedge clk);
        uart_line = 1'b1;
        repeat (3) @(posedge clk);
        if (rx_data !== 8'h00 || rx_done || framing_error)
            $fatal(1, "Mid-frame reset did not restore reset outputs");
        rst_n = 1'b1;
        repeat (8) @(posedge clk);
        if (done_count != base_done || error_count != base_error)
            $fatal(1, "Canceled frame generated an event after reset");
        queue_expected(8'h5A);
        send_uart_frame(8'h5A, IDEAL_BIT_NS, 1'b1, 59.0);
        wait_for_expected(9);

        // Baud tolerance: transmitter +/-2 percent.
        queue_expected(8'hC3); send_uart_frame(8'hC3, FAST_BIT_NS, 1'b1, 83.0);
        queue_expected(8'h3C); send_uart_frame(8'h3C, SLOW_BIT_NS, 1'b1, 197.0);
        wait_for_expected(11);

        // Four distinct asynchronous start phases.
        queue_expected(8'h11); send_uart_frame(8'h11, IDEAL_BIT_NS, 1'b1, 1.0);
        queue_expected(8'h22); send_uart_frame(8'h22, IDEAL_BIT_NS, 1'b1, 6.0);
        queue_expected(8'h44); send_uart_frame(8'h44, IDEAL_BIT_NS, 1'b1, 11.0);
        queue_expected(8'h88); send_uart_frame(8'h88, IDEAL_BIT_NS, 1'b1, 17.0);
        wait_for_expected(15);

        // All 256 raw values followed by the wrapped 00 value.
        base_error = error_count;
        for (i = 0; i < 256; i = i + 1) begin
            queue_expected(i[7:0]);
            send_uart_frame(i[7:0], IDEAL_BIT_NS, 1'b1, 0.0);
        end
        queue_expected(8'h00);
        send_uart_frame(8'h00, IDEAL_BIT_NS, 1'b1, 0.0);
        target = 15 + 257;
        wait_for_expected(target);

        repeat (20) @(posedge clk);
        if (error_count != base_error)
            $fatal(1, "Raw sequence generated framing errors");
        if (done_count != target || expected_read != expected_write)
            $fatal(1, "Final count mismatch done=%0d expected=%0d consumed=%0d", done_count, expected_write, expected_read);

        $display("UART_RX_TB_PASS bytes=%0d framing_errors=%0d clks_per_bit=%0d", done_count, error_count, dut.CLKS_PER_BIT);
        $finish;
    end
endmodule
