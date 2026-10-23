`timescale 1ns/1ps
module tb_perf;
  reg clk=0,rst_n=0,start=0,feature_valid=0; reg [615:0] features=0;
  wire ready,busy,done,result_valid; wire [5:0] class_id; wire [11:0] leaf_node; wire [2:0] error_code; wire [7:0] step_count; wire active_bank; wire [15:0] model_version;
  reg tx_start=0; reg [15:0] tx_seq=16'h1234; wire tx,btx,tx_done;
  integer engine_cycles,i; time t0,t1;
  ids_tree_engine_live engine(.clk(clk),.rst_n(rst_n),.start(start),.feature_valid(feature_valid),.features_flat(features),.model_write_en(1'b0),.model_write_addr(12'd0),.model_write_data(64'd0),.model_activate(1'b0),.ready(ready),.busy(busy),.done(done),.result_valid(result_valid),.class_id(class_id),.leaf_node(leaf_node),.error_code(error_code),.step_count(step_count),.active_bank(active_bank),.model_version(model_version));
  result_frame_tx result_tx(.clk(clk),.rst_n(rst_n),.start(tx_start),.seq_id(tx_seq),.class_id(6'd2),.leaf_node(12'd0),.step_count(8'd0),.error_code(3'd0),.model_version(16'd1),.uart_tx(tx),.busy(btx),.done(tx_done));
  always #10 clk=~clk;
  initial begin
    $dumpfile("tb_perf.vcd");
    $dumpvars(0,tb_perf);
    repeat(3) @(negedge clk); rst_n=1;
    // A known one-node leaf model: operation=LEAF, class=2.
    engine.rom.sim_memory[0]=64'h0000000000000020;
    @(negedge clk);t0=$time;start=1;feature_valid=1;
    @(negedge clk);start=0;feature_valid=0;
    wait(result_valid);t1=$time;engine_cycles=(t1-t0)/20;
    if(class_id!==6'd2 || leaf_node!==0 || error_code!==0) $fatal(1,"engine result mismatch");
    $display("PERF_ENGINE_LEAF cycles=%0d latency_ns=%0t",engine_cycles,t1-t0);
    // Worst permitted path: 63 decision nodes followed by one leaf (64 nodes).
    for(i=0;i<63;i=i+1) engine.rom.sim_memory[i]=64'h40FFFFFC00000000 | ((i+1)<<22);
    engine.rom.sim_memory[63]=64'h0000000000000030;
    wait(ready); @(negedge clk); t0=$time; start=1;feature_valid=1;
    @(negedge clk);start=0;feature_valid=0;wait(result_valid);t1=$time;engine_cycles=(t1-t0)/20;
    if(class_id!==6'd3 || leaf_node!==12'd63 || error_code!==0) $fatal(1,"long-path result mismatch");
    $display("PERF_ENGINE_64_NODE cycles=%0d latency_ns=%0t",engine_cycles,t1-t0);
    @(negedge clk);t0=$time;tx_start=1;@(negedge clk);tx_start=0;wait(tx_done);t1=$time;
    $display("PERF_RESULT_UART encoded_bytes=%0d latency_ns=%0t",result_tx.enc_len,t1-t0);
    if((t1-t0)>2000000) $fatal(1,"result UART exceeds 2ms");
    $display("FINAL_SYS_PERF_TB_PASS");$finish;
  end
endmodule
