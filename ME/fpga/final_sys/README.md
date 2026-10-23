# final_sys

FPGA-only Pi UART IDS accelerator. C17 receives COBS/CRC FEATURE frames from
Pi GPIO14. V7 is the onboard USB-UART receive path for the existing model
update protocol. V8 sends COBS/CRC RESULT frames to the Pi through CH9102F.

Program `release/final_sys.fs`. The model BRAM is empty after configuration;
upload and activate the 1273-node image through USB UART V7 before inference.
LED0=reset released, LED1=model ready, LED2=feature accepted, LED3=sticky error.

Run `scripts/build_gowin.ps1` for synthesis/P&R and bitstream generation.
