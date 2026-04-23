# RTL — Hardware Description (Verilog)

This directory contains all the Verilog source files that describe the DarkRISCV
system-on-chip (SoC). When synthesised onto an FPGA, these files become real
hardware — a working RISC-V computer.

For in-depth documentation aimed at beginners, see the [doc/](../doc/) folder.

## File Map

| File | What it is |
|---|---|
| `config.vh` | Master configuration — pipeline, ISA, memory size, board, features |
| `darkriscv.v` | **The CPU core** — fetches, decodes and executes RISC-V instructions |
| `darkbridge.v` | Bus bridge — connects the CPU to caches and the external bus |
| `darkcache.v` | Optional L1 instruction/data cache |
| `darkram.v` | On-chip BRAM — dual-port memory for instructions and data |
| `darksocv.v` | **Top-level SoC** — wires together CPU, memory, I/O, SDRAM |
| `darkio.v` | I/O controller — LEDs, timer, interrupt controller, UART/SPI routing |
| `darkuart.v` | UART transmitter/receiver (115200 baud serial port) |
| `darkpll.v` | Clock generator (PLL) — multiplies the board clock to the target frequency |
| `darkmac.v` | Optional 16×16 multiply-accumulate coprocessor |
| `darkspi.v` | Optional SPI master peripheral |
| `lib/sdram/` | SDRAM controller (external DRAM interface) |
| `lib/spi/` | SPI master IP core and simulation stubs |

## Module Hierarchy

```
darksocv (top-level SoC)
 ├── darkpll          (clock: 50 MHz → 100 MHz)
 ├── darkbridge       (bus bridge)
 │    ├── darkriscv   (THE CPU CORE)
 │    ├── darkcache   (optional L1 i-cache)
 │    └── darkcache   (optional L1 d-cache)
 ├── darkram          (on-chip BRAM, 8-32 KB)
 ├── darkio           (I/O subsystem)
 │    ├── darkuart    (serial port)
 │    └── darkspi     (SPI, optional)
 └── sdram controller (external DRAM, optional)
```

## Address Map

The top 2 bits of the 32-bit address select which peripheral is accessed:

| Address range | Bits [31:30] | Target |
|---|---|---|
| `0x00000000 – 0x3FFFFFFF` | `00` | BRAM (on-chip memory) |
| `0x40000000 – 0x7FFFFFFF` | `01` | I/O (UART, LEDs, timer, GPIO) |
| `0x80000000 – 0xBFFFFFFF` | `10` | SDRAM (optional external memory) |
| `0xC0000000 – 0xFFFFFFFF` | `11` | Unused |

## Bus Architecture

DarkBridge supports two modes controlled by `__HARVARD__` in `config.vh`:

- **Harvard mode** (default): separate instruction and data buses operate in
  parallel — best performance (CPI ≈ 1.7)
- **Von Neumann mode**: a single shared bus multiplexes instruction fetches and
  data accesses — slower, but required for single-port memories like SDRAM.
  L1 caches (`__ICACHE__` / `__DCACHE__`) mitigate the performance penalty.
