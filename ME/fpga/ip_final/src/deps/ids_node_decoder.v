module ids_node_decoder (
    input wire [63:0] node_word,
    output wire [1:0] operation,
    output wire [5:0] feature_id,
    output wire [21:0] operand,
    output wire [11:0] true_child,
    output wire [11:0] false_child,
    output wire [5:0] class_id,
    output wire [3:0] flags
);
    assign operation   = node_word[63:62];
    assign feature_id  = node_word[61:56];
    assign operand     = node_word[55:34];
    assign true_child  = node_word[33:22];
    assign false_child = node_word[21:10];
    assign class_id    = node_word[9:4];
    assign flags       = node_word[3:0];
endmodule

