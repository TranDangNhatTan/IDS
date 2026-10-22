FPGA ETHERNET TEST - MACHINE A AND MACHINE B
============================================

Network:
  Machine A Ethernet  = 192.168.50.1 / 255.255.255.0
  Machine B Ethernet  = 192.168.50.2 / 255.255.255.0
  UDP port            = 55001

Order:
  1. Load release/demo_connect_uart_debug.fs into ACG525 SRAM.
  2. On machine B, run MACHINE_B_RECEIVER\RUN_MACHINE_B.bat.
  3. On machine A, run RUN_MACHINE_A.bat from this repository.
  4. Machine B should report TEST PASS, missing=0, CRC errors=0.

Default test:
  100 packets, 1400-byte payload, 1 Mbps.

Important:
  Both Ethernet links must show Up at 100 Mbps.
  Sender reporting Done does not prove reception; use machine B result.
  If no packet arrives, inspect UART DBG status and ARP neighbor state.
