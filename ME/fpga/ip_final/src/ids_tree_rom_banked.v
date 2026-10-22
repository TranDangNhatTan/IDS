`timescale 1ns/1ps
// GW5A explicit-BRAM store for the UART-updatable Decision Tree.
// 1273 x 64 bits needs two 1024 x 64 banks. Each 64-bit bank is built from
// four native 16K-bit DPB macros (1024 x 16); total = 8 physical BSRAMs.
module ids_tree_rom_banked #(
    parameter NODE_COUNT=1273,
    parameter ROM_FILE="model/node_rom.mem"
) (
    input wire clk, input wire [11:0] address, output reg [63:0] data,
    input wire write_en, input wire [11:0] write_addr, input wire [63:0] write_data,
    input wire activate_pulse, input wire engine_busy,
    output wire active_bank, output reg [15:0] model_version
);
`ifdef SIMULATION
    // Cycle-accurate interface model for Icarus regression. Synthesis selects
    // the DPB primitive branch below.
    reg [63:0] sim_memory [0:NODE_COUNT-1];
    always @(posedge clk) begin
        if (write_en && write_addr < NODE_COUNT && !engine_busy)
            sim_memory[write_addr] <= write_data;
        if (address < NODE_COUNT)
            data <= sim_memory[address];
        else
            data <= 64'hC000000000000000;
        if (activate_pulse && !engine_busy)
            model_version <= model_version + 1'b1;
    end
`else
    wire [63:0] read_bank0, read_bank1, unused_bank0, unused_bank1;
    wire read_select_bank0 = (address < 12'd1024);
    wire read_select_bank1 = (address >= 12'd1024) && (address < NODE_COUNT);
    wire write_select_bank0 = write_en && !engine_busy && (write_addr < 12'd1024);
    wire write_select_bank1 = write_en && !engine_busy &&
                              (write_addr >= 12'd1024) && (write_addr < NODE_COUNT);
    // A 16-bit DPB port uses address bits [13:4] as its 1024-word address.
    wire [13:0] read_addr0  = {address[9:0], 4'b0000};
    wire [13:0] read_addr1  = {address[9:0], 4'b0000};
    wire [13:0] write_addr0 = {write_addr[9:0], 4'b0000};
    wire [13:0] write_addr1 = {write_addr[9:0], 4'b0000};
    genvar lane;
    generate
        for (lane=0; lane<4; lane=lane+1) begin : g_tree_bram_lane
            DPB #(
                .READ_MODE0(1'b0), .READ_MODE1(1'b0),
                .WRITE_MODE0(2'b00), .WRITE_MODE1(2'b00),
                .BIT_WIDTH_0(16), .BIT_WIDTH_1(16),
                .BLK_SEL_0(3'b000), .BLK_SEL_1(3'b000), .RESET_MODE("SYNC")
            ) tree_bank0 (
                .DOA(unused_bank0[lane*16 +: 16]), .DOB(read_bank0[lane*16 +: 16]),
                .DIA(write_data[lane*16 +: 16]), .DIB(16'd0),
                .BLKSELA(3'b000), .BLKSELB(3'b000),
                .ADA(write_addr0), .ADB(read_addr0),
                .WREA(write_select_bank0), .WREB(1'b0),
                .CLKA(clk), .CLKB(clk), .CEA(write_select_bank0), .CEB(1'b1),
                .OCEA(1'b0), .OCEB(1'b0), .RESETA(1'b0), .RESETB(1'b0)
            );
            DPB #(
                .READ_MODE0(1'b0), .READ_MODE1(1'b0),
                .WRITE_MODE0(2'b00), .WRITE_MODE1(2'b00),
                .BIT_WIDTH_0(16), .BIT_WIDTH_1(16),
                .BLK_SEL_0(3'b000), .BLK_SEL_1(3'b000), .RESET_MODE("SYNC")
            ) tree_bank1 (
                .DOA(unused_bank1[lane*16 +: 16]), .DOB(read_bank1[lane*16 +: 16]),
                .DIA(write_data[lane*16 +: 16]), .DIB(16'd0),
                .BLKSELA(3'b000), .BLKSELB(3'b000),
                .ADA(write_addr1), .ADB(read_addr1),
                .WREA(write_select_bank1), .WREB(1'b0),
                .CLKA(clk), .CLKB(clk), .CEA(write_select_bank1), .CEB(1'b1),
                .OCEA(1'b0), .OCEB(1'b0), .RESETA(1'b0), .RESETB(1'b0)
            );
        end
    endgenerate
    always @(posedge clk) begin
        if (read_select_bank0)
            data <= read_bank0;
        else if (read_select_bank1)
            data <= read_bank1;
        else
            data <= 64'hC000000000000000;
        if (activate_pulse && !engine_busy)
            model_version <= model_version + 1'b1;
    end
`endif
    assign active_bank = 1'b0;
    initial model_version = 16'd0;
endmodule
