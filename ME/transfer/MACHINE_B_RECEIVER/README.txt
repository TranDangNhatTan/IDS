MACHINE B - NHAN DATA TU CONG ETHERNET ONBOARD ACG525
====================================================

Ket noi:
  May A -> LAN8720 ngoai -> FPGA -> RJ45 onboard ACG525 -> May B

Yeu cau:
  - Windows va Python 3.
  - May B dat IPv4: 192.168.50.2
  - Subnet mask: 255.255.255.0
  - May A dat IPv4: 192.168.50.1
  - Cho phep Python qua Windows Firewall (Private network).

Thu tu chay:
  1. Double-click 01_check_network.bat.
  2. Dam bao physical link connected va IPv4 dung.
  3. Double-click 02_run_receiver.bat.
  4. Sau do moi chay tool gui tren may A.

Lenh dat IP bang PowerShell Administrator:
  netsh interface ipv4 set address name="Ethernet" static 192.168.50.2 255.255.255.0

Mac dinh receiver:
  IP: 192.168.50.2
  UDP port: 55001
  So goi cho doi: 1000

Ket qua dung:
  Missing packets   : 0
  CRC errors        : 0
  Pattern errors    : 0
  TEST PASS

Neu ten card mang khong phai Ethernet:
  py -3 check_machine_b.py --adapter "Ten card mang"

Neu muon doi so goi:
  py -3 machine_b_receiver.py --expected 10000
