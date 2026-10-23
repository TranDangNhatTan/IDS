`timescale 1ns/1ps
// Full 1,273-word transactional upload into the simulation BRAM model.
module tb_full_model_bram;
 localparam NODE_COUNT=1273;
 reg clk=0,rst_n=0,valid=0,sop=0;reg [7:0] data=0;reg [11:0] read_addr=0;
 wire write_en,activate,ready,ack,peer_valid;wire [11:0] write_addr;wire [63:0] write_data,read_data;
 wire [15:0] words,version;wire active_bank;wire [47:0] peer_mac;wire [31:0] peer_ip;wire [15:0] peer_port;
 reg [63:0] expected[0:NODE_COUNT-1];integer i,j;integer writes=0;
 always #5 clk=~clk;
 ids_udp_feature_rx #(.NODE_COUNT(NODE_COUNT)) parser(.clk(clk),.rst_n(rst_n),.rx_data(data),.rx_valid(valid),.rx_sop(sop),.engine_busy(1'b0),.raw_ready(1'b1),
  .model_write_en(write_en),.model_write_addr(write_addr),.model_write_data(write_data),.model_activate(activate),.model_ready(ready),.accepted_words(words),.model_ack(ack),
  .peer_mac(peer_mac),.peer_ip(peer_ip),.peer_port(peer_port),.peer_valid(peer_valid));
 ids_tree_rom_banked #(.NODE_COUNT(NODE_COUNT)) ram(.clk(clk),.address(read_addr),.data(read_data),.write_en(write_en),.write_addr(write_addr),.write_data(write_data),.activate_pulse(activate),.engine_busy(1'b0),.active_bank(active_bank),.model_version(version));
 always @(posedge clk)if(write_en)writes=writes+1;
 task put;input [7:0] x;input first;begin @(negedge clk);data=x;valid=1;sop=first;@(negedge clk);valid=0;sop=0;end endtask
 task mod_packet;input [7:0] op;input [15:0] addr;input [63:0] word;integer n;reg [7:0] x;begin
  for(n=0;n<=56;n=n+1)begin
   x=0;case(n)
    0,1,2,3,4,5:x=8'hFF;6:x=8'hC4;7:x=8'hC6;8:x=8'hE6;9:x=8'h18;10:x=8'h5D;11:x=8'h9E;
    12:x=8'h08;13:x=0;14:x=8'h45;23:x=17;26:x=192;27:x=168;28:x=50;29:x=22;
    30:x=192;31:x=168;32:x=50;33:x=50;34:x=8'hD6;35:x=8'hDB;36:x=8'hD6;37:x=8'hDA;
    42:x="M";43:x="O";44:x="D";45:x="1";46:x=op;47:x=addr[7:0];48:x=addr[15:8];
    49:x=word[7:0];50:x=word[15:8];51:x=word[23:16];52:x=word[31:24];53:x=word[39:32];54:x=word[47:40];55:x=word[55:48];56:x=word[63:56];
   endcase
   put(x,n==0);
  end
 end endtask
 task check_word;input [11:0] addr;begin
  read_addr=addr;repeat(2)@(posedge clk);#1;
  if(read_data!==expected[addr])$fatal(1,"BRAM mismatch addr=%0d expected=%h got=%h",addr,expected[addr],read_data);
 end endtask
 initial begin
  $readmemh("model/node_rom.mem",expected);
  repeat(3)@(posedge clk);rst_n=1;
  // Match the dashboard exactly: three init copies then two full addressed
  // passes.  Only the first arrival of each address may increase `words`.
  for(j=0;j<3;j=j+1)mod_packet(1,0,0);
  for(j=0;j<2;j=j+1)for(i=0;i<NODE_COUNT;i=i+1)mod_packet(2,i[15:0],expected[i]);
  mod_packet(2,16'd10,expected[10]);repeat(2)@(posedge clk);
  if(words!==NODE_COUNT||writes!==2*NODE_COUNT+1)$fatal(1,"full upload count failed words=%0d writes=%0d",words,writes);
  mod_packet(3,0,0);repeat(2)@(posedge clk);
  if(!ready||version!==1)$fatal(1,"commit failed ready=%b version=%0d",ready,version);
  mod_packet(3,0,0);repeat(2)@(posedge clk);
  if(!ready||version!==1)$fatal(1,"repeated commit was not idempotent version=%0d",version);
  check_word(0);check_word(1023);check_word(1024);check_word(1272);
  $display("FULL_MODEL_BRAM_PASS words=%0d writes=%0d version=%0d last=%h",words,writes,version,read_data);
  $finish;
 end
endmodule
