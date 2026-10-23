`timescale 1ns/1ps
module tb_udp_echo_rgmii;
 reg sys_clk=0,rx_clk=0;reg [3:0] rxd=0;reg rx_ctl=0;
 wire tx_clk;wire [3:0] txd;wire tx_ctl,eth_rst_n,mdc;tri mdio;wire [3:0] led;
 integer nibbles=0,bytes=0,i;reg [3:0] low_nibble;reg [7:0] captured[0:100];reg [7:0] frame[0:100];reg [31:0] crc;
 top_acg525_udp_echo #(.POR_CYCLES(8),.RX_CLOCK_PROBE_BIT(2),.HEARTBEAT_BIT(2),.MDIO_START_DELAY(4)) dut(
  .sys_clk_50(sys_clk),.eth_rgmii_rx_clk(rx_clk),.eth_rgmii_rxd(rxd),.eth_rgmii_rx_ctl(rx_ctl),
  .eth_rgmii_tx_clk(tx_clk),.eth_rgmii_txd(txd),.eth_rgmii_tx_ctl(tx_ctl),.eth_rst_n(eth_rst_n),.eth_mdc(mdc),.eth_mdio(mdio),.led(led));
 always #10 sys_clk=~sys_clk;
 always #20 rx_clk=~rx_clk;
 always @(posedge tx_clk) #1 if(tx_ctl) begin
  if(nibbles[0]==0) low_nibble=txd;
  else begin captured[bytes]={txd,low_nibble};bytes=bytes+1;end
  nibbles=nibbles+1;
 end
 task send_byte;input [7:0] b;begin
  rxd=b[3:0];@(posedge rx_clk);#1;rxd=b[7:4];@(posedge rx_clk);#1;
 end endtask
 task check_fcs;integer k,b;reg [31:0] c;begin
  c=32'hffffffff;
  for(k=8;k<68;k=k+1) for(b=0;b<8;b=b+1) begin if(c[0]^captured[k][b])c=(c>>1)^32'hedb88320;else c=c>>1;end
  crc=~c;
  if({captured[71],captured[70],captured[69],captured[68]}!==crc)$fatal(1,"FCS mismatch expected=%h got=%h",crc,{captured[71],captured[70],captured[69],captured[68]});
 end endtask
 initial begin
  for(i=0;i<101;i=i+1)begin frame[i]=0;captured[i]=0;end
  for(i=0;i<7;i=i+1)frame[i]=8'h55;frame[7]=8'hd5;
  for(i=8;i<14;i=i+1)frame[i]=8'hff;
  frame[14]=8'h00;frame[15]=8'h11;frame[16]=8'h22;frame[17]=8'h33;frame[18]=8'h44;frame[19]=8'h55;frame[20]=8'h08;frame[21]=8'h00;
  frame[22]=8'h45;frame[31]=8'h11;frame[34]=8'hc0;frame[35]=8'ha8;frame[36]=8'h32;frame[37]=8'h16;
  frame[42]=8'hd6;frame[43]=8'hdb;frame[44]=8'hd6;frame[45]=8'hda;
  frame[50]="P";frame[51]="I";frame[52]="N";frame[53]="G";frame[54]=8'h78;frame[55]=8'h56;frame[56]=8'h34;frame[57]=8'h12;
  wait(eth_rst_n);repeat(8)@(posedge rx_clk);@(negedge rx_clk);rx_ctl=1;
  for(i=0;i<62;i=i+1)send_byte(frame[i]);
  @(negedge rx_clk);rx_ctl=0;rxd=0;
  repeat(25000)@(posedge sys_clk);
  if(!dut.por_done||!dut.mdio_done||!dut.rx_clock_seen)$fatal(1,"RGMII bring-up flags failed por=%b mdio=%b rxclk=%b",dut.por_done,dut.mdio_done,dut.rx_clock_seen);
  if(bytes!=72)$fatal(1,"ACK frame length %0d",bytes);
  if(captured[0]!=8'h55||captured[7]!=8'hd5||captured[8]!=8'h00||captured[20]!=8'h08||captured[21]!=8'h00||captured[50]!="A"||captured[53]!="1"||captured[54]!=8'h78||captured[57]!=8'h12)$fatal(1,"ACK fields invalid");
  check_fcs();
  $display("UDP_ECHO_RGMII_PASS bytes=%0d sequence=%h fcs=%h",bytes,{captured[57],captured[56],captured[55],captured[54]},crc);$finish;
 end
endmodule
