`timescale 1ns/1ps

module tb_ethernet_passthrough;
    reg        clk;
    reg        ext_rst_n;
    reg  [1:0] phy1_rxd;
    reg        phy1_crs_dv;
    wire [1:0] phy1_txd;
    wire       phy1_tx_en;
    wire       phy1_rst_n;
    reg  [1:0] phy2_rxd;
    reg        phy2_crs_dv;
    wire [1:0] phy2_txd;
    wire       phy2_tx_en;
    wire       phy2_rst_n;
    wire [5:0] status;

    reg [7:0] capture_1_to_2 [0:63];
    reg [7:0] capture_2_to_1 [0:63];
    integer count_1_to_2;
    integer count_2_to_1;
    reg [1:0] dibit_1_to_2;
    reg [1:0] dibit_2_to_1;
    reg [7:0] byte_1_to_2;
    reg [7:0] byte_2_to_1;
    integer errors;
    integer i;

    top_ethernet_passthrough #(
        .RESET_CYCLES(8)
    ) dut (
        .rmii_ref_clk(clk),
        .ext_rst_n(ext_rst_n),
        .phy1_rxd(phy1_rxd),
        .phy1_crs_dv(phy1_crs_dv),
        .phy1_txd(phy1_txd),
        .phy1_tx_en(phy1_tx_en),
        .phy1_rst_n(phy1_rst_n),
        .phy2_rxd(phy2_rxd),
        .phy2_crs_dv(phy2_crs_dv),
        .phy2_txd(phy2_txd),
        .phy2_tx_en(phy2_tx_en),
        .phy2_rst_n(phy2_rst_n),
        .status(status)
    );

    always #10 clk = ~clk;

    function [7:0] frame1_byte;
        input integer index;
        begin
            case (index)
                0: frame1_byte = 8'h55;
                1: frame1_byte = 8'h55;
                2: frame1_byte = 8'h55;
                3: frame1_byte = 8'h55;
                4: frame1_byte = 8'h55;
                5: frame1_byte = 8'h55;
                6: frame1_byte = 8'h55;
                7: frame1_byte = 8'hD5;
                8: frame1_byte = 8'h01;
                9: frame1_byte = 8'h23;
                10: frame1_byte = 8'h45;
                11: frame1_byte = 8'h67;
                12: frame1_byte = 8'h89;
                13: frame1_byte = 8'hAB;
                14: frame1_byte = 8'hCD;
                default: frame1_byte = 8'hEF;
            endcase
        end
    endfunction

    function [7:0] frame2_byte;
        input integer index;
        begin
            case (index)
                0: frame2_byte = 8'h55;
                1: frame2_byte = 8'h55;
                2: frame2_byte = 8'h55;
                3: frame2_byte = 8'h55;
                4: frame2_byte = 8'h55;
                5: frame2_byte = 8'h55;
                6: frame2_byte = 8'h55;
                7: frame2_byte = 8'hD5;
                8: frame2_byte = 8'hDE;
                9: frame2_byte = 8'hAD;
                default: frame2_byte = 8'hBE;
            endcase
        end
    endfunction

    task send_phy1_frame;
        integer n;
        reg [7:0] value;
        begin
            @(negedge clk);
            phy1_crs_dv = 1'b1;
            for (n = 0; n < 16; n = n + 1) begin
                value = frame1_byte(n);
                phy1_rxd = value[1:0]; @(negedge clk);
                phy1_rxd = value[3:2]; @(negedge clk);
                phy1_rxd = value[5:4]; @(negedge clk);
                phy1_rxd = value[7:6]; @(negedge clk);
            end
            phy1_crs_dv = 1'b0;
            phy1_rxd = 2'b00;
        end
    endtask

    task send_phy2_frame;
        integer n;
        reg [7:0] value;
        begin
            @(negedge clk);
            phy2_crs_dv = 1'b1;
            for (n = 0; n < 11; n = n + 1) begin
                value = frame2_byte(n);
                phy2_rxd = value[1:0]; @(negedge clk);
                phy2_rxd = value[3:2]; @(negedge clk);
                phy2_rxd = value[5:4]; @(negedge clk);
                phy2_rxd = value[7:6]; @(negedge clk);
            end
            phy2_crs_dv = 1'b0;
            phy2_rxd = 2'b00;
        end
    endtask

    always @(posedge clk) begin
        if (phy2_tx_en) begin
            case (dibit_1_to_2)
                0: byte_1_to_2[1:0] <= phy2_txd;
                1: byte_1_to_2[3:2] <= phy2_txd;
                2: byte_1_to_2[5:4] <= phy2_txd;
                3: begin
                    capture_1_to_2[count_1_to_2] <= {phy2_txd, byte_1_to_2[5:0]};
                    count_1_to_2 <= count_1_to_2 + 1;
                end
            endcase
            dibit_1_to_2 <= dibit_1_to_2 + 1'b1;
        end else begin
            dibit_1_to_2 <= 0;
        end

        if (phy1_tx_en) begin
            case (dibit_2_to_1)
                0: byte_2_to_1[1:0] <= phy1_txd;
                1: byte_2_to_1[3:2] <= phy1_txd;
                2: byte_2_to_1[5:4] <= phy1_txd;
                3: begin
                    capture_2_to_1[count_2_to_1] <= {phy1_txd, byte_2_to_1[5:0]};
                    count_2_to_1 <= count_2_to_1 + 1;
                end
            endcase
            dibit_2_to_1 <= dibit_2_to_1 + 1'b1;
        end else begin
            dibit_2_to_1 <= 0;
        end
    end

    initial begin
        clk = 1'b0;
        ext_rst_n = 1'b0;
        phy1_rxd = 2'b00;
        phy1_crs_dv = 1'b0;
        phy2_rxd = 2'b00;
        phy2_crs_dv = 1'b0;
        count_1_to_2 = 0;
        count_2_to_1 = 0;
        dibit_1_to_2 = 0;
        dibit_2_to_1 = 0;
        byte_1_to_2 = 0;
        byte_2_to_1 = 0;
        errors = 0;

        repeat (3) @(negedge clk);
        ext_rst_n = 1'b1;
        wait (phy1_rst_n && phy2_rst_n);
        repeat (3) @(negedge clk);

        fork
            send_phy1_frame;
            send_phy2_frame;
        join

        wait (count_1_to_2 == 16 && count_2_to_1 == 11);
        repeat (3) @(posedge clk);

        for (i = 0; i < 16; i = i + 1)
            if (capture_1_to_2[i] !== frame1_byte(i)) begin
                $display("ERROR 1->2 byte %0d expected=%02x actual=%02x",
                         i, frame1_byte(i), capture_1_to_2[i]);
                errors = errors + 1;
            end

        for (i = 0; i < 11; i = i + 1)
            if (capture_2_to_1[i] !== frame2_byte(i)) begin
                $display("ERROR 2->1 byte %0d expected=%02x actual=%02x",
                         i, frame2_byte(i), capture_2_to_1[i]);
                errors = errors + 1;
            end

        if (status !== 6'b000000) begin
            $display("ERROR status=%b", status);
            errors = errors + 1;
        end

        if (errors == 0)
            $display("ETHERNET_PASSTHROUGH_PASS frames=2 bytes=27");
        else
            $display("ETHERNET_PASSTHROUGH_FAIL errors=%0d", errors);
        $finish;
    end

    initial begin
        #100000;
        $display("ETHERNET_PASSTHROUGH_TIMEOUT");
        $finish;
    end
endmodule
