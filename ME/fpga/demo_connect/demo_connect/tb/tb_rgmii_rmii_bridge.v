`timescale 1ns/1ps

module tb_rgmii_rmii_bridge;
    reg sys_clk_50;
    reg ext_rst_n;
    reg lan_rmii_ref_clk;
    reg [1:0] lan_rxd;
    reg lan_crs_dv;
    wire [1:0] lan_txd;
    wire lan_tx_en;
    reg eth_rgmii_rx_clk;
    reg [3:0] eth_rgmii_rxd;
    reg eth_rgmii_rx_ctl;
    wire eth_rgmii_tx_clk;
    wire [3:0] eth_rgmii_txd;
    wire eth_rgmii_tx_ctl;
    wire eth_rst_n;
    wire eth_mdc;
    tri eth_mdio;
    wire [3:0] led;

    reg [7:0] capture_rmii [0:63];
    reg [7:0] capture_rgmii [0:63];
    integer rmii_count;
    integer rgmii_count;
    reg [1:0] rmii_phase;
    reg [7:0] rmii_work;
    reg       rgmii_high;
    reg [3:0] rgmii_low;
    integer errors;
    integer i;

    top_acg525_rgmii_rmii_bridge #(.RESET_CYCLES(8)) dut (
        .sys_clk_50(sys_clk_50),
        .ext_rst_n(ext_rst_n),
        .lan_rmii_ref_clk(lan_rmii_ref_clk),
        .lan_rxd(lan_rxd),
        .lan_crs_dv(lan_crs_dv),
        .lan_txd(lan_txd),
        .lan_tx_en(lan_tx_en),
        .eth_rgmii_rx_clk(eth_rgmii_rx_clk),
        .eth_rgmii_rxd(eth_rgmii_rxd),
        .eth_rgmii_rx_ctl(eth_rgmii_rx_ctl),
        .eth_rgmii_tx_clk(eth_rgmii_tx_clk),
        .eth_rgmii_txd(eth_rgmii_txd),
        .eth_rgmii_tx_ctl(eth_rgmii_tx_ctl),
        .eth_rst_n(eth_rst_n),
        .eth_mdc(eth_mdc),
        .eth_mdio(eth_mdio),
        .led(led)
    );

    always #10 sys_clk_50 = ~sys_clk_50;
    always #10 lan_rmii_ref_clk = ~lan_rmii_ref_clk;
    always #20 eth_rgmii_rx_clk = ~eth_rgmii_rx_clk;

    function [7:0] onboard_byte;
        input integer n;
        begin
            onboard_byte = 8'h40 + n;
        end
    endfunction

    function [7:0] external_byte;
        input integer n;
        begin
            external_byte = 8'hA0 + n;
        end
    endfunction

    task send_onboard_frame;
        integer n;
        reg [7:0] value;
        begin
            @(negedge eth_rgmii_rx_clk);
            eth_rgmii_rx_ctl = 1'b1;
            for (n = 0; n < 17; n = n + 1) begin
                value = onboard_byte(n);
                eth_rgmii_rxd = value[3:0];
                @(negedge eth_rgmii_rx_clk);
                eth_rgmii_rxd = value[7:4];
                @(negedge eth_rgmii_rx_clk);
            end
            eth_rgmii_rx_ctl = 1'b0;
            eth_rgmii_rxd = 4'd0;
        end
    endtask

    task send_external_frame;
        integer n;
        reg [7:0] value;
        begin
            @(negedge lan_rmii_ref_clk);
            lan_crs_dv = 1'b1;
            for (n = 0; n < 13; n = n + 1) begin
                value = external_byte(n);
                lan_rxd = value[1:0]; @(negedge lan_rmii_ref_clk);
                lan_rxd = value[3:2]; @(negedge lan_rmii_ref_clk);
                lan_rxd = value[5:4]; @(negedge lan_rmii_ref_clk);
                lan_rxd = value[7:6]; @(negedge lan_rmii_ref_clk);
            end
            lan_crs_dv = 1'b0;
            lan_rxd = 2'd0;
        end
    endtask

    always @(posedge lan_rmii_ref_clk) begin
        if (lan_tx_en) begin
            case (rmii_phase)
                0: rmii_work[1:0] <= lan_txd;
                1: rmii_work[3:2] <= lan_txd;
                2: rmii_work[5:4] <= lan_txd;
                3: begin
                    capture_rmii[rmii_count] <= {lan_txd, rmii_work[5:0]};
                    rmii_count <= rmii_count + 1;
                end
            endcase
            rmii_phase <= rmii_phase + 1'b1;
        end else begin
            rmii_phase <= 0;
        end
    end

    always @(posedge eth_rgmii_tx_clk) begin
        if (eth_rgmii_tx_ctl) begin
            if (!rgmii_high) begin
                rgmii_low <= eth_rgmii_txd;
                rgmii_high <= 1'b1;
            end else begin
                capture_rgmii[rgmii_count] <= {eth_rgmii_txd, rgmii_low};
                rgmii_count <= rgmii_count + 1;
                rgmii_high <= 1'b0;
            end
        end else begin
            rgmii_high <= 1'b0;
        end
    end

    initial begin
        sys_clk_50 = 0;
        ext_rst_n = 0;
        lan_rmii_ref_clk = 0;
        lan_rxd = 0;
        lan_crs_dv = 0;
        eth_rgmii_rx_clk = 0;
        eth_rgmii_rxd = 0;
        eth_rgmii_rx_ctl = 0;
        rmii_count = 0;
        rgmii_count = 0;
        rmii_phase = 0;
        rmii_work = 0;
        rgmii_high = 0;
        rgmii_low = 0;
        errors = 0;

        repeat (4) @(negedge sys_clk_50);
        ext_rst_n = 1;
        wait (eth_rst_n);
        repeat (8) @(negedge sys_clk_50);

        fork
            send_onboard_frame;
            send_external_frame;
        join

        wait (rmii_count == 17 && rgmii_count == 13);
        repeat (5) @(posedge sys_clk_50);

        for (i = 0; i < 17; i = i + 1)
            if (capture_rmii[i] !== onboard_byte(i)) begin
                $display("ERROR onboard->external byte=%0d expected=%02x actual=%02x",
                         i, onboard_byte(i), capture_rmii[i]);
                errors = errors + 1;
            end

        for (i = 0; i < 13; i = i + 1)
            if (capture_rgmii[i] !== external_byte(i)) begin
                $display("ERROR external->onboard byte=%0d expected=%02x actual=%02x",
                         i, external_byte(i), capture_rgmii[i]);
                errors = errors + 1;
            end

        // Packet-path LED mapping must show RMII carrier, a complete RMII
        // frame, and RGMII transmit activity after the bidirectional test.
        if (led !== 4'b1111) begin
            $display("ERROR bridge status led=%b", led);
            errors = errors + 1;
        end

        if (errors == 0)
            $display("RGMII_RMII_BRIDGE_PASS frames=2 bytes=30 cdc=async");
        else
            $display("RGMII_RMII_BRIDGE_FAIL errors=%0d", errors);
        $finish;
    end

    initial begin
        #200000;
        $display("RGMII_RMII_BRIDGE_TIMEOUT rmii=%0d rgmii=%0d", rmii_count, rgmii_count);
        $finish;
    end
endmodule
