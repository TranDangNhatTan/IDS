# Raspberry Pi FPGA IDS server

On the Pi 4:

```bash
source /home/vdas/Desktop/projects/pjs-env/bin/activate
pip install -r requirements.txt
python run_server.py
```

Edit only `config.json` for interface/IP/UART/timeouts.  The dashboard listens
on `pi_data_ip:dashboard_port`; visit `http://<pi-ip>:8080`. Raw packet capture
requires root or `CAP_NET_RAW`; UART requires `sudo usermod -aG dialout $USER`
and a new login. Run `sudo raspi-config`, disable the serial login shell and
enable serial hardware. Wiring: GPIO14/pin 8 to FPGA P6.1/C17, GPIO15/pin 10
from FPGA P6.4/G14, and pin 6 common GND. Use 3.3-V TTL only.

## First-run network and permissions

`pi_data_ip` must be an IPv4 address actually assigned to the Pi. For the
default direct-cable test network, assign the configured `192.168.10.2/24` to
`eth0` (this is temporary until made persistent through your network manager):

```bash
sudo ip addr add 192.168.10.2/24 dev eth0
ip -4 addr show dev eth0
```

Give the laptop's Ethernet adapter another address in that subnet, such as
`192.168.10.1/24`. Do not put the Pi's Wi-Fi address in `pi_data_ip` if Laptop
B sends its raw test frames through `eth0`.

For a quick diagnostic run, raw capture can be granted by running the launcher
as root:

```bash
sudo /home/vdas/Desktop/projects/pjs-env/bin/python run_server.py
```

For ordinary runs, grant only the raw-socket capability to the venv interpreter
(re-run this after recreating the venv):

```bash
sudo setcap cap_net_raw+ep "$(readlink -f /home/vdas/Desktop/projects/pjs-env/bin/python)"
getcap "$(readlink -f /home/vdas/Desktop/projects/pjs-env/bin/python)"
```

`features.py` is the one canonical packet mapping. It directly applies the
caps/order from `ids_feature_quantizer.v`; features 4 and 5 are shifted by 2
and 6 exactly once. It has no labels, so the dashboard never reports accuracy.

Run tests with `PYTHONPATH=. python -m unittest discover -s tests -v`.

Example `/etc/systemd/system/pi-fpga-ids.service` (do not enable automatically):

```ini
[Unit]
Description=Pi FPGA IDS server
After=network-online.target
[Service]
User=pi
WorkingDirectory=/home/vdas/Desktop/projects/IDS/ME/fpga/pi_uart_ids/pi_server
ExecStart=/home/vdas/Desktop/projects/pjs-env/bin/python run_server.py
Restart=on-failure
AmbientCapabilities=CAP_NET_RAW
[Install]
WantedBy=multi-user.target
```
