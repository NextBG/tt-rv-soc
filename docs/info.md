## How it works

TinyRV-E is a small RISC-V microcontroller that fits in a few Tiny Tapeout tiles. It was designed end-to-end with an AI assistant (RTL, firmware, testbench and instruction-set simulator).

- **CPU**: multi-cycle RV32E (16 registers, base integer ISA). FENCE / ECALL / EBREAK / CSR instructions execute as NOPs. Misaligned accesses are not supported. Reset vector is `0x0000_0000`.
- **Memory**: everything lives off-chip on the standard Tiny Tapeout QSPI Pmod, used in single-bit SPI mode 0 with SCK = clk/4.
  - SPI flash, execute-in-place (read command `0x03`). Sequential instruction fetches keep CS low and just clock out the next 32 bits.
  - SPI PSRAM (RAM A) for data and stack (read `0x03`, write `0x02`, byte/half/word writes).
- **Peripherals**: UART (8N1, programmable divider), 8 GPIO outputs, 8 GPIO inputs, 2 x 8-bit PWM, 32-bit cycle counter, chip ID.

### Memory map

| Address | Region |
|---|---|
| `0x0000_0000` | SPI flash (read only, XIP, 16 MB) |
| `0x0100_0000` | SPI PSRAM A (read/write, 8 MB) |
| `0x8000_0000` | Peripherals |

### Peripheral registers (base `0x8000_0000`)

| Offset | Name | Description |
|---|---|---|
| `0x00` | GPIO_OUT | bits [7:0] drive `uo_out` (bit 4 is replaced by UART TX, bits 6/7 by PWM when enabled) |
| `0x04` | GPIO_IN | reads `ui_in[7:0]` |
| `0x08` | UART_DATA | write: transmit byte. read: received byte (clears RX valid) |
| `0x0C` | UART_STAT | bit0 = TX busy, bit1 = RX valid |
| `0x10` | UART_DIV | clocks per bit, reset value 434 (115200 baud @ 50 MHz) |
| `0x14` | PWM | [7:0] duty0, [15:8] duty1, [23:16] prescaler, bit24 enable PWM0 on uo[6], bit25 enable PWM1 on uo[7] |
| `0x18` | MTIME | free-running clock cycle counter |
| `0x1C` | ID | `0x52563345` ("RV3E") |

During reset all `uio` pins are inputs, so the RP2040 on the demo board can program the flash while the design is held in reset.

### Limitations

Every memory access is a complete SPI transaction (~70-100 clocks for random accesses), so the CPU runs at a few hundred thousand instructions per second at 50 MHz. At very low clock frequencies a PSRAM transaction can exceed the PSRAM maximum CS-low time (tCEM, 8 us); use at least ~25 MHz when using the PSRAM.

## How to test

1. Build the firmware: `cd firmware && make` (needs `riscv64-unknown-elf-gcc` with rv32e multilib). `hello.bin` is prebuilt in the repository.
2. Program `hello.bin` to the flash at offset 0 of the QSPI Pmod (e.g. with the Tiny Tapeout demo board's RP2040 while the design is in reset).
3. Set the clock to 50 MHz, release reset.
4. Connect a 115200 8N1 UART to `uo[4]` (TX) and `ui[3]` (RX). The chip prints `Hello from TinyRV-E!` followed by a self-test result `OK 00000000`, then echoes every received character.
5. GPIO outputs `uo[3:0]` follow inputs `ui[3:0]`; PWM0/PWM1 are active on `uo[6]` / `uo[7]`.

Simulation: `cd test && make` runs the firmware test and a random-instruction test that compares the CPU against a Python instruction-set simulator. `make GATES=yes` runs them on the gate-level netlist.

## External hardware

- Tiny Tapeout QSPI Pmod (SPI flash + PSRAM) on the bidirectional Pmod header.
- USB-UART adapter (or the demo board's RP2040 UART bridge).
