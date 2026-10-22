`timescale 1ns/1ps

module tb_uart_debug_reporter;
    reg clk;
    reg rst_n;
    reg [15:0] status;
    wire uart_tx;
    reg [7:0] received [0:9];
    integer i;
    integer errors;

    uart_debug_reporter #(
        .CLKS_PER_BIT(4),
        .REPORT_CYCLES(200)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .status(status),
        .uart_tx(uart_tx)
    );

    always #5 clk = ~clk;

    task receive_byte;
        output [7:0] value;
        integer bit_number;
        begin
            @(negedge uart_tx);
            repeat (2) @(posedge clk);
            if (uart_tx !== 1'b0)
                errors = errors + 1;
            for (bit_number = 0; bit_number < 8; bit_number = bit_number + 1) begin
                repeat (4) @(posedge clk);
                value[bit_number] = uart_tx;
            end
            repeat (4) @(posedge clk);
            if (uart_tx !== 1'b1)
                errors = errors + 1;
        end
    endtask

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        status = 16'hA53C;
        errors = 0;
        repeat (4) @(posedge clk);
        rst_n = 1'b1;

        for (i = 0; i < 10; i = i + 1)
            receive_byte(received[i]);

        if (received[0] != "D" || received[1] != "B" ||
            received[2] != "G" || received[3] != "=" ||
            received[4] != "A" || received[5] != "5" ||
            received[6] != "3" || received[7] != "C" ||
            received[8] != 8'h0D || received[9] != 8'h0A)
            errors = errors + 1;

        if (errors == 0)
            $display("UART_DEBUG_PASS message=DBG=A53C");
        else
            $display("UART_DEBUG_FAIL errors=%0d", errors);
        $finish;
    end

    initial begin
        #100000;
        $display("UART_DEBUG_TIMEOUT");
        $finish;
    end
endmodule
