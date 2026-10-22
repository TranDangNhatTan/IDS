`timescale 1ns/1ps

module top_acg525_rgmii_rmii_bridge #(
    parameter RESET_CYCLES = 500000
) (
    input  wire       sys_clk_50,
    input  wire       ext_rst_n,

    input  wire       lan_rmii_ref_clk,
    input  wire [1:0] lan_rxd,
    input  wire       lan_crs_dv,
    output wire [1:0] lan_txd,
    output wire       lan_tx_en,

    input  wire       eth_rgmii_rx_clk,
    input  wire [3:0] eth_rgmii_rxd,
    input  wire       eth_rgmii_rx_ctl,
    output wire       eth_rgmii_tx_clk,
    output wire [3:0] eth_rgmii_txd,
    output wire       eth_rgmii_tx_ctl,
    output wire       eth_rst_n,
    output wire       eth_mdc,
    inout  wire       eth_mdio,

    output wire       uart_tx,
    output wire [3:0] led
);
    reg [19:0] reset_counter;
    reg        phy_reset_done;
    reg        rgmii_tx_clk_reg;

    wire async_logic_rst_n = ext_rst_n && phy_reset_done;
    wire rst_sys_n;
    wire rst_rmii_n;
    wire rst_rgmii_rx_n;

    wire [7:0] rgmii_rx_byte;
    wire       rgmii_rx_valid;
    wire       rgmii_rx_last;
    wire       rgmii_rx_error;
    wire       rgmii_to_rmii_full;
    wire       rgmii_to_rmii_overflow;
    wire [7:0] rgmii_to_rmii_data;
    wire       rgmii_to_rmii_last;
    wire       rgmii_to_rmii_valid;
    wire       rgmii_to_rmii_empty;
    wire       rgmii_to_rmii_packet;
    wire       rgmii_to_rmii_rd_en;
    wire       rmii_tx_underflow;

    wire [7:0] rmii_rx_byte;
    wire       rmii_rx_valid;
    wire       rmii_rx_last;
    wire       rmii_rx_error;
    wire       rmii_to_rgmii_full;
    wire       rmii_to_rgmii_overflow;
    wire [7:0] rmii_to_rgmii_data;
    wire       rmii_to_rgmii_last;
    wire       rmii_to_rgmii_valid;
    wire       rmii_to_rgmii_empty;
    wire       rmii_to_rgmii_packet;
    wire       rmii_to_rgmii_rd_en;
    wire       rgmii_tx_underflow;

    wire mdio_out;
    wire mdio_oe;
    wire mdio_init_done;

    // Sticky debug flags live in their source clock domains. They are safe to
    // synchronize as levels because they remain asserted until reset.
    reg [20:0] rmii_clock_counter;
    reg [6:0]  rmii_debug_sticky;
    reg [4:0]  rgmii_debug_sticky;
    reg [6:0]  rmii_debug_sync1;
    reg [6:0]  rmii_debug_sync2;
    reg [4:0]  rgmii_debug_sync1;
    reg [4:0]  rgmii_debug_sync2;
    reg         rmii_clock_sync1;
    reg         rmii_clock_sync2;
    reg         rmii_clock_previous;
    reg         rmii_clock_seen;
    reg         rgmii_tx_seen;
    reg         rgmii_tx_underflow_seen;
    wire [15:0] uart_debug_status;

    assign eth_rgmii_tx_clk = rgmii_tx_clk_reg;
    assign eth_rst_n = phy_reset_done && ext_rst_n;
    assign eth_mdio = mdio_oe ? mdio_out : 1'bz;
    // Machine A -> Machine B packet-path display. Activity bits are sticky.
    //   LED0: constant one (bitstream/LED baseline)
    //   LED1: external RMII CRS_DV was asserted
    //   LED2: a complete external RMII frame was received
    //   LED3: onboard RGMII TX_CTL was asserted
    assign led = {
        rgmii_tx_seen,
        rmii_debug_sync2[2],
        rmii_debug_sync2[0],
        1'b1
    };

    assign uart_debug_status = {
        1'b0,                                      // 15 reserved
        rgmii_tx_underflow_seen | rmii_debug_sync2[6], // 14 TX underflow
        rgmii_debug_sync2[4] | rmii_debug_sync2[5],    // 13 FIFO overflow
        rgmii_debug_sync2[3],                     // 12 RGMII RX error
        rmii_debug_sync2[4],                      // 11 RMII RX error
        rmii_debug_sync2[3],                      // 10 LAN8720 RMII TX active
        rgmii_debug_sync2[2],                     // 9 onboard RGMII frame RX
        rgmii_debug_sync2[1],                     // 8 onboard RGMII byte RX
        rgmii_debug_sync2[0],                     // 7 onboard RGMII RX_CTL
        rgmii_tx_seen,                            // 6 onboard RGMII TX active
        rmii_debug_sync2[2],                      // 5 LAN8720 frame RX
        rmii_debug_sync2[1],                      // 4 LAN8720 byte RX
        rmii_debug_sync2[0],                      // 3 LAN8720 CRS_DV
        rmii_clock_seen,                          // 2 LAN8720 REF_CLK observed
        mdio_init_done,                           // 1 MDIO sequence sent
        phy_reset_done                            // 0 onboard PHY out of reset
    };

    always @(posedge sys_clk_50 or negedge ext_rst_n) begin
        if (!ext_rst_n) begin
            reset_counter  <= 20'd0;
            phy_reset_done <= 1'b0;
        end else if (!phy_reset_done) begin
            if (reset_counter == RESET_CYCLES - 1)
                phy_reset_done <= 1'b1;
            else
                reset_counter <= reset_counter + 20'd1;
        end
    end

    // The 25 MHz clock is forwarded only to the PHY.  All transmit logic stays
    // in the 50 MHz system domain; rgmii_tx_clk_reg acts only as a clock-enable
    // phase indicator, so no fabric-generated clock drives internal registers.
    always @(posedge sys_clk_50 or negedge async_logic_rst_n) begin
        if (!async_logic_rst_n)
            rgmii_tx_clk_reg <= 1'b0;
        else
            rgmii_tx_clk_reg <= ~rgmii_tx_clk_reg;
    end

    always @(posedge lan_rmii_ref_clk or negedge async_logic_rst_n) begin
        if (!async_logic_rst_n) begin
            rmii_clock_counter <= 21'd0;
            rmii_debug_sticky  <= 7'd0;
        end else begin
            rmii_clock_counter <= rmii_clock_counter + 1'b1;
            if (lan_crs_dv)
                rmii_debug_sticky[0] <= 1'b1;
            if (rmii_rx_valid)
                rmii_debug_sticky[1] <= 1'b1;
            if (rmii_rx_last)
                rmii_debug_sticky[2] <= 1'b1;
            if (lan_tx_en)
                rmii_debug_sticky[3] <= 1'b1;
            if (rmii_rx_error)
                rmii_debug_sticky[4] <= 1'b1;
            if (rmii_to_rgmii_overflow)
                rmii_debug_sticky[5] <= 1'b1;
            if (rmii_tx_underflow)
                rmii_debug_sticky[6] <= 1'b1;
        end
    end

    always @(posedge eth_rgmii_rx_clk or negedge async_logic_rst_n) begin
        if (!async_logic_rst_n) begin
            rgmii_debug_sticky <= 5'd0;
        end else begin
            if (eth_rgmii_rx_ctl)
                rgmii_debug_sticky[0] <= 1'b1;
            if (rgmii_rx_valid)
                rgmii_debug_sticky[1] <= 1'b1;
            if (rgmii_rx_last)
                rgmii_debug_sticky[2] <= 1'b1;
            if (rgmii_rx_error)
                rgmii_debug_sticky[3] <= 1'b1;
            if (rgmii_to_rmii_overflow)
                rgmii_debug_sticky[4] <= 1'b1;
        end
    end

    always @(posedge sys_clk_50 or negedge async_logic_rst_n) begin
        if (!async_logic_rst_n) begin
            rmii_debug_sync1        <= 7'd0;
            rmii_debug_sync2        <= 7'd0;
            rgmii_debug_sync1       <= 5'd0;
            rgmii_debug_sync2       <= 5'd0;
            rmii_clock_sync1        <= 1'b0;
            rmii_clock_sync2        <= 1'b0;
            rmii_clock_previous     <= 1'b0;
            rmii_clock_seen         <= 1'b0;
            rgmii_tx_seen           <= 1'b0;
            rgmii_tx_underflow_seen <= 1'b0;
        end else begin
            rmii_debug_sync1    <= rmii_debug_sticky;
            rmii_debug_sync2    <= rmii_debug_sync1;
            rgmii_debug_sync1   <= rgmii_debug_sticky;
            rgmii_debug_sync2   <= rgmii_debug_sync1;
            rmii_clock_sync1    <= rmii_clock_counter[20];
            rmii_clock_sync2    <= rmii_clock_sync1;
            rmii_clock_previous <= rmii_clock_sync2;
            if (rmii_clock_sync2 != rmii_clock_previous)
                rmii_clock_seen <= 1'b1;
            if (eth_rgmii_tx_ctl)
                rgmii_tx_seen <= 1'b1;
            if (rgmii_tx_underflow)
                rgmii_tx_underflow_seen <= 1'b1;
        end
    end

    reset_sync u_reset_sys (
        .clk(sys_clk_50), .async_rst_n(async_logic_rst_n), .sync_rst_n(rst_sys_n)
    );
    reset_sync u_reset_rmii (
        .clk(lan_rmii_ref_clk), .async_rst_n(async_logic_rst_n), .sync_rst_n(rst_rmii_n)
    );
    reset_sync u_reset_rgmii_rx (
        .clk(eth_rgmii_rx_clk), .async_rst_n(async_logic_rst_n), .sync_rst_n(rst_rgmii_rx_n)
    );
    rtl8211f_mdio_init u_mdio_init (
        .clk(sys_clk_50),
        .rst_n(rst_sys_n),
        .mdc(eth_mdc),
        .mdio_out(mdio_out),
        .mdio_oe(mdio_oe),
        .init_done(mdio_init_done)
    );

    uart_debug_reporter u_uart_debug_reporter (
        .clk(sys_clk_50),
        .rst_n(rst_sys_n),
        .status(uart_debug_status),
        .uart_tx(uart_tx)
    );

    rgmii_100_deserializer u_rgmii_rx (
        .rx_clk(eth_rgmii_rx_clk),
        .rst_n(rst_rgmii_rx_n),
        .rxd(eth_rgmii_rxd),
        .rx_ctl(eth_rgmii_rx_ctl),
        .rx_byte(rgmii_rx_byte),
        .rx_byte_valid(rgmii_rx_valid),
        .rx_byte_last(rgmii_rx_last),
        .rx_frame_error(rgmii_rx_error)
    );

    async_packet_fifo u_rgmii_to_rmii_fifo (
        .wr_clk(eth_rgmii_rx_clk),
        .wr_rst_n(rst_rgmii_rx_n),
        .wr_en(rgmii_rx_valid),
        .wr_data(rgmii_rx_byte),
        .wr_last(rgmii_rx_last),
        .wr_full(rgmii_to_rmii_full),
        .wr_overflow(rgmii_to_rmii_overflow),
        .rd_clk(lan_rmii_ref_clk),
        .rd_rst_n(rst_rmii_n),
        .rd_en(rgmii_to_rmii_rd_en),
        .rd_data(rgmii_to_rmii_data),
        .rd_last(rgmii_to_rmii_last),
        .rd_valid(rgmii_to_rmii_valid),
        .rd_empty(rgmii_to_rmii_empty),
        .packet_available(rgmii_to_rmii_packet)
    );

    rmii_serializer u_rmii_tx (
        .clk(lan_rmii_ref_clk),
        .rst_n(rst_rmii_n),
        .fifo_data(rgmii_to_rmii_data),
        .fifo_last(rgmii_to_rmii_last),
        .fifo_valid(rgmii_to_rmii_valid),
        .fifo_empty(rgmii_to_rmii_empty),
        .packet_available(rgmii_to_rmii_packet),
        .fifo_rd_en(rgmii_to_rmii_rd_en),
        .txd(lan_txd),
        .tx_en(lan_tx_en),
        .busy(),
        .underflow(rmii_tx_underflow)
    );

    rmii_deserializer u_rmii_rx (
        .clk(lan_rmii_ref_clk),
        .rst_n(rst_rmii_n),
        .rxd(lan_rxd),
        .crs_dv(lan_crs_dv),
        .rx_byte(rmii_rx_byte),
        .rx_byte_valid(rmii_rx_valid),
        .rx_byte_last(rmii_rx_last),
        .rx_frame_error(rmii_rx_error)
    );

    async_packet_fifo u_rmii_to_rgmii_fifo (
        .wr_clk(lan_rmii_ref_clk),
        .wr_rst_n(rst_rmii_n),
        .wr_en(rmii_rx_valid),
        .wr_data(rmii_rx_byte),
        .wr_last(rmii_rx_last),
        .wr_full(rmii_to_rgmii_full),
        .wr_overflow(rmii_to_rgmii_overflow),
        .rd_clk(sys_clk_50),
        .rd_rst_n(rst_sys_n),
        .rd_en(rmii_to_rgmii_rd_en),
        .rd_data(rmii_to_rgmii_data),
        .rd_last(rmii_to_rgmii_last),
        .rd_valid(rmii_to_rgmii_valid),
        .rd_empty(rmii_to_rgmii_empty),
        .packet_available(rmii_to_rgmii_packet)
    );

    rgmii_100_serializer u_rgmii_tx (
        .clk(sys_clk_50),
        .nibble_ce(rgmii_tx_clk_reg),
        .rst_n(rst_sys_n),
        .fifo_data(rmii_to_rgmii_data),
        .fifo_last(rmii_to_rgmii_last),
        .fifo_valid(rmii_to_rgmii_valid),
        .fifo_empty(rmii_to_rgmii_empty),
        .packet_available(rmii_to_rgmii_packet),
        .fifo_rd_en(rmii_to_rgmii_rd_en),
        .txd(eth_rgmii_txd),
        .tx_ctl(eth_rgmii_tx_ctl),
        .underflow(rgmii_tx_underflow)
    );
endmodule
