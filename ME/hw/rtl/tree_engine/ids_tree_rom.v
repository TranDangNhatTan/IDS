module ids_tree_rom #(
    parameter NODE_COUNT = 1273,
    parameter ROM_FILE = "ME/hw/model_export/dt_fpga_flow28_fixed/node_rom.mem"
) (
    input wire clk,
    input wire [11:0] address,
    output reg [63:0] data
);
    reg [63:0] memory [0:NODE_COUNT-1];

    initial begin
        $readmemh(ROM_FILE, memory);
    end

    always @(posedge clk) begin
        if (address < NODE_COUNT)
            data <= memory[address];
        else
            data <= 64'hC000000000000000;
    end
endmodule
