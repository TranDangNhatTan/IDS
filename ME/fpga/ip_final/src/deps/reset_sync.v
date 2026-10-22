`timescale 1ns/1ps

module reset_sync (
    input  wire clk,
    input  wire async_rst_n,
    output wire sync_rst_n
);
    reg [1:0] sync_ff;
    always @(posedge clk or negedge async_rst_n) begin
        if (!async_rst_n)
            sync_ff <= 2'b00;
        else
            sync_ff <= {sync_ff[0], 1'b1};
    end
    assign sync_rst_n = sync_ff[1];
endmodule

