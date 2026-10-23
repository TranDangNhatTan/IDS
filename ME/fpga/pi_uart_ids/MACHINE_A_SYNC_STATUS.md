# Machine A FPGA synchronization status

The Pi server and Laptop B prompts use protocol **v2**. The existing root RTL
(`src/`, `constraints/`, `release/pi_uart_ids.fs`) predates it: it uses v1
frames and raw `A5 5A` model commands, not v2 COBS MODEL acknowledgements or
the required image CRC32. Do not program that bitstream with the synchronized
Pi server.

Machine A must implement the v2 design specified by `PROMPT_MACHINE_A_FPGA.md`
under `fpga/`, then build a new `fpga/release/pi_uart_ids.fs`.

```text
Model: ME/hw/model_export/dt_fpga_flow28_fixed/node_rom.hex
Size:  1273 words x 64 bits
Input: 28 features x 22 bits = 77-byte FEATURE payload
```

`ME/hw/tb/data/tree_features.mem` contains 22,156 golden 616-bit test inputs;
it is not a model image.
