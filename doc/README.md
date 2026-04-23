# DarkRISCV Documentation

Welcome to the DarkRISCV documentation. This guide explains how a RISC-V
CPU works, from the ground up, for readers with no prior hardware design
experience.

---

## What Is This Project?

DarkRISCV is a **soft-core CPU** — a processor described entirely in code
(Verilog), which can be loaded onto an FPGA chip to become a real, working
processor. It implements the **RISC-V RV32I** instruction set, meaning it
can run C programs compiled with a standard RISC-V compiler.

**Key specs:**

| Feature | Value |
|---|---|
| Instruction set | RISC-V RV32I (32-bit integer) |
| Pipeline | 3 stages (Fetch → Decode → Execute) |
| Clock speed | 100 MHz (on DE2 FPGA board) |
| On-chip memory | 32 KB Block RAM |
| Peripherals | UART, Timer, LEDs, GPIO, SPI |
| Language | Verilog HDL |

---

## Documentation Files

Start with the CPU core document to understand the fundamentals, then work
through the SoC and I/O documents. The simulation guide shows how to run
everything.

| Document | Description |
|---|---|
| [cpu-core.md](cpu-core.md) | **The CPU itself** — what a CPU is, the 3-stage pipeline, instruction fetch/decode/execute, ALU, branches, register file, program counter, interrupts. Start here. |
| [soc-architecture.md](soc-architecture.md) | **The complete system** — how the CPU, memory, UART, LEDs, and timer are wired together on a single chip. Block diagram and module-by-module walkthrough. |
| [memory-and-io.md](memory-and-io.md) | **Memory and peripherals** — how software communicates with hardware via memory-mapped I/O, UART serial protocol, timer, LEDs, and the address map. |
| [simulation-guide.md](simulation-guide.md) | **Running the simulation** — step-by-step instructions for building firmware, running Icarus Verilog, and interpreting the output. |

---

## Project Directory Structure

```
darkriscv/
├── rtl/                    Hardware description (Verilog source)
│   ├── darkriscv.v         CPU core (fetch, decode, execute)
│   ├── darksocv.v          Top-level SoC (wires everything together)
│   ├── darkbridge.v        Bus bridge (CPU ↔ memory/IO)
│   ├── darkram.v           Block RAM (program + data storage)
│   ├── darkio.v            I/O controller (UART, LEDs, timer)
│   ├── darkuart.v          UART serial port
│   ├── darkcache.v         Optional L1 cache
│   ├── darkpll.v           Clock generator (PLL)
│   ├── darkmac.v           Multiply-accumulate coprocessor
│   ├── darkspi.v           SPI master (optional)
│   └── config.vh           All configuration switches
│
├── src/                    Firmware (C and assembly)
│   ├── boot.S              Startup code (sets stack pointer, calls main)
│   ├── darksocv.lds        Linker script (memory layout)
│   ├── config.mk           Compiler paths and flags
│   ├── Makefile             Firmware build rules
│   ├── darkshell/          Interactive shell firmware
│   ├── calc/               Calculator firmware (sum, fib, fact, primes)
│   └── darklibc/           Minimal C library (printf, memcpy, etc.)
│
├── sim/                    Simulation
│   ├── darksimv.v          Testbench (clock, reset, VCD dump)
│   ├── run_sim.py          Simulation runner script
│   ├── Makefile             Simulation build rules
│   └── trace.py            Instruction trace analysis
│
├── boards/                 FPGA board configurations
│   └── de2_cyclone2/       Terasic DE2 (Cyclone II) project files
│
├── scripts/                Build utilities
│   └── helpers.py          Cross-platform Python helper tools
│
└── doc/                    This documentation folder
    ├── README.md           This index file
    ├── cpu-core.md         CPU core deep-dive
    ├── soc-architecture.md SoC architecture guide
    ├── memory-and-io.md    Memory and I/O explanation
    └── simulation-guide.md Simulation instructions
```

---

## Glossary

| Term | Definition |
|---|---|
| **ALU** | Arithmetic Logic Unit — the part of the CPU that does math and logic |
| **BRAM** | Block RAM — fast memory built into the FPGA chip |
| **CPI** | Clocks Per Instruction — how many clock cycles each instruction takes on average |
| **CSR** | Control and Status Register — special registers for interrupts and system control |
| **FPGA** | Field-Programmable Gate Array — a chip whose logic can be configured by loading a design |
| **Harvard** | Architecture where instruction and data memories are separate (two buses) |
| **HDL** | Hardware Description Language — code that describes digital circuits (e.g., Verilog) |
| **I-bus** | Instruction bus — carries instruction fetch addresses and data |
| **D-bus** | Data bus — carries load/store addresses and data |
| **IRQ** | Interrupt Request — a signal that tells the CPU to pause and handle an event |
| **ISA** | Instruction Set Architecture — the specification of what instructions a CPU supports |
| **PLL** | Phase-Locked Loop — converts one clock frequency to another |
| **Pipeline** | A technique where multiple instructions overlap in execution (like an assembly line) |
| **Register** | A tiny, fast storage location inside the CPU (32 bits each, 32 of them) |
| **RISC-V** | An open-standard instruction set architecture |
| **RV32I** | The base 32-bit integer RISC-V instruction set |
| **SoC** | System-on-Chip — a complete computer on one chip (CPU + memory + peripherals) |
| **UART** | Universal Asynchronous Receiver/Transmitter — serial communication interface |
| **VCD** | Value Change Dump — a file format for recording digital signal waveforms |
| **Verilog** | A hardware description language used to design digital circuits |
| **Von Neumann** | Architecture where instruction and data memories share a single bus |

---

## Reading Order (Recommended)

1. **[cpu-core.md](cpu-core.md)** — Understand what a CPU does and how DarkRISCV
   implements fetch, decode, and execute
2. **[soc-architecture.md](soc-architecture.md)** — See how the CPU connects to
   memory and peripherals to form a complete computer
3. **[memory-and-io.md](memory-and-io.md)** — Learn how software communicates with
   hardware through memory-mapped I/O
4. **[simulation-guide.md](simulation-guide.md)** — Run the simulation yourself and
   see the CPU in action
