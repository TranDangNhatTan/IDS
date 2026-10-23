# Model lifecycle on the single Pi–FPGA UART

The Pi–FPGA connection has exactly one full-duplex UART port. It is not
permitted to add a USB UART, second UART, Ethernet port, or another FPGA pin
for model data.

The deployed decision-tree BRAM therefore has two mutually exclusive operating
modes on the **same C17 RX wire**:

1. **Model maintenance mode:** no FEATURE frames are in flight. The Pi sends
   the existing `model_update_uart` byte protocol, then sends its activation
   command. LED1 must turn on before inference is enabled.
2. **Inference mode:** the Pi uses only the COBS FEATURE and RESULT frames in
   `PROTOCOL_CONTRACT.md`. It must not send maintenance bytes while a FEATURE
   transaction is pending.

This preserves the supplied model word format and its activation behavior.
It is a deployment prerequisite, not an optional diagnostic: a new FPGA
configuration has no valid runtime model until a model is loaded and activated.

For a production revision, the maintenance protocol should be formally added
to a versioned management-frame section of `PROTOCOL_CONTRACT.md`, or the model
should be converted to a verified synthesizable read-only preload image. Neither
change may be made unilaterally because it changes the Pi–FPGA integration ABI.
