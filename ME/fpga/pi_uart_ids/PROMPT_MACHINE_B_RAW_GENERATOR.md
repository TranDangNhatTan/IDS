# Prompt C — Laptop B labelled raw Ethernet generator

You are a Windows networking/Python test engineer. Create
`ME/fpga/pi_uart_ids/laptop_b_generator/`. Read `../PROTOCOL_CONTRACT.md`
first. Laptop B is only an Ethernet test source and dashboard browser: never
opens, proxies, or configures the Pi–FPGA UART.

## Network and goal

Laptop B Ethernet is `192.168.10.1/24`; Pi eth0 is `192.168.10.2/24`. Generate
deterministic Ethernet/IPv4/UDP frames addressed to Pi MAC/IP, destination UDP
40000, with exact payload:

```text
IDSRAW1 | sequence:u32-le | deterministic test bytes
```

The generator can offer normal/attack **labelled test profiles** for a controlled
evaluation run. Labels are test metadata sent to the Pi dashboard/API by a
documented HTTP endpoint or run manifest; they do not change the IDSRAW1 wire
payload or UART protocol. No rate/payload CLI tuning is required beyond the
fixed test profiles and configuration file.

## Deliverables

* `config.json`: Npcap adapter, Pi MAC/IP, source IP/MAC, UDP port 40000,
  selected profile, fixed count/rate/payload/start sequence, and optional label.
* Python/Scapy sender, PowerShell launcher, requirements, README.
* Deterministic normal and attack profile data, each with labels and expected
  sequence range. State clearly that a label is test metadata, not proof that
  an individual FPGA prediction is correct.
* Preflight checks for Npcap, Administrator rights, selected adapter, local
  IPv4 `192.168.10.1`, reachable Pi `192.168.10.2`, destination MAC/IP and
  packet construction.
* `--dry-run`, `--verify-network`, and `--profile` are sufficient CLI options.
  Print actual adapter, MAC/IP, profile, every transmitted sequence and errors.

## Acceptance

Default run sends 10 deterministic packets at 5 packets/s. It must not report
end-to-end pass merely after sending. A test run passes only when Pi dashboard
or API reports the same sequences, a committed FPGA model, and received RESULT
frames. Dashboard URL is `http://192.168.10.2:8080`.
