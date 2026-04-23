# Simulation Guide

This document explains how to compile firmware, run the Icarus Verilog
simulation, and interpret the output.

---

## Prerequisites

Before running a simulation, you need:

1. **Icarus Verilog** — the open-source Verilog simulator (`iverilog` and `vvp`)
2. **RISC-V cross-compiler** — `riscv-none-elf-gcc` toolchain (xPacks distribution)
3. **Python** — invoked as `py` on Windows
4. **GNU Make** — for automating the build

All paths are configured in `src/config.mk`.

---

## Project Build Flow

The complete flow from C source code to simulation output:

```
  ┌──────────────────────────────────────────────────────────┐
  │  FIRMWARE BUILD  (src/ directory)                        │
  │                                                          │
  │  main.c  ──gcc──>  main.o  ──ld──>  darksocv.bin        │
  │  boot.S  ──as──>   boot.o ─┘                             │
  │                                                          │
  │  darksocv.bin ──objcopy + bin2hex──> darksocv.mem        │
  └──────────────────────────────────┬───────────────────────┘
                                     │ (hex file)
  ┌──────────────────────────────────┼───────────────────────┐
  │  RTL COMPILATION  (sim/ dir)     │                       │
  │                                  ▼                       │
  │  darksimv.v ─┐                darksocv.mem               │
  │  darksocv.v  ├── iverilog ──> darksocv (executable)      │
  │  darkriscv.v ├─┘                                         │
  │  darkram.v   │                                           │
  │  darkio.v    │                                           │
  │  darkuart.v  │                                           │
  │  ...         │                                           │
  └──────────────┼───────────────────────────────────────────┘
                 │
  ┌──────────────┼───────────────────────────────────────────┐
  │  SIMULATION  │                                           │
  │              ▼                                           │
  │  vvp darksocv ──> terminal output (UART prints)          │
  │                ──> darksocv.vcd (waveform file)           │
  │                ──> darksocv.txt (instruction trace)       │
  └──────────────────────────────────────────────────────────┘
```

---

## Step-by-Step: Running a Simulation

### Step 1: Build the firmware

```bash
cd src
make clean
make
```

This compiles the active application (set by `APPLICATION` in `src/Makefile`).
The available applications are:

| Application | Description |
|---|---|
| `darkshell` | Interactive shell with LED, timer, memory commands |
| `calc` | Scripted calculator (sum, fibonacci, factorial, prime search) |

The build produces `darksocv.mem` — a hex file containing the compiled
firmware.

### Step 2: Compile the Verilog

```bash
cd sim
make darksocv
```

This runs `iverilog` to compile all RTL files plus the testbench
(`darksimv.v`) into a simulator executable called `darksocv`.

### Step 3: Run the simulation

```bash
make
```

Or equivalently:
```bash
py run_sim.py darksocv darksocv.txt ../rtl/config.vh
```

This invokes `vvp darksocv` (the Icarus Verilog runtime), which:
1. Initialises BRAM from `darksocv.mem`
2. Starts the clock toggling
3. Releases reset after 128 cycles
4. The CPU begins executing firmware
5. UART prints appear directly in the terminal
6. When the firmware outputs `>`, the simulation ends automatically

---

## Understanding the Output

### Boot Screenshot

![DarkRISCV simulation boot output](boot.png)

This screenshot shows a real simulation run. Here is what every line means:

```
boot0: main@0200 stack@01fb0
```
The boot assembler (`boot.S`) finished. `main` function is at address `0x0200` in BRAM. The stack pointer starts at `0x01fb0` (top of the stack, growing downward).

```
csrxx: not found
stvec: not found
mtvec: not found (polling)
```
The firmware tried to configure CSR registers for interrupts. They are not enabled in this build (`config.vh` does not define `__CSR__`), so the firmware falls back to polling mode (checking the timer register in a loop instead of using hardware interrupts).

```
board: simulation only (id=0)
```
The `BOARD_ID` configured in `config.vh` is 0, which the firmware recognises as "simulation only" mode.

```
build: Sun, 27 Apr 2025 15:11:03 -0300 for rv32e_zicsr
```
Timestamp when the firmware was compiled. `rv32e_zicsr` is the GCC march string: RV32E (reduced register file) plus the Zicsr extension.

```
core0: darkriscv@100MHz w/ rv32e
```
The CPU core is running at 100 MHz using the RV32E instruction set (16 registers instead of 32).

```
bram0: 352 bytes free
bram0: text@0200+5048 data@15b0+2280 stack@2000
```
Memory layout report from the firmware: code (`.text`) starts at `0x0200` and is 5048 bytes long; data (`.data` + `.bss`) starts at `0x15b0` and uses 2280 bytes; stack top is at `0x2000`. Only 352 bytes of BRAM are unused.

```
uart0: 115.2kbps (div=868)
```
UART configured at 115200 baud. The divider value 868 = 100,000,000 Hz ÷ 115200.

```
timr0: 1000Hz (div=99999)
```
Timer interrupt set to fire 1000 times per second. Divider = 100,000,000 ÷ 1000 − 1 = 99999.

```
Welcome to DarkRISCV!
492>
```
The shell is running. `492` is the instruction counter from the boot sequence (how many instructions executed to reach the prompt). `>` is the shell prompt — in simulation, this character also triggers `$finish()` to end the simulation.

---

### DarkShell output

```
darkRISC-V (pipeline=3, ipc=0.6, cache=0, rv32i+O1+O2+O3+MAC) built=Jan 14 2025
board: de2 (id=21, clock=100000000)
core0: darkriscv@100MHz with mass=32KB
uart0: 115200 bps (active)
timr0: 1000000 Hz (active)

> led 0xff
led = ff
> timer
timer = 1000000 (irq=1)
>
```

The banner shows:
- **pipeline=3**: 3-stage pipeline
- **ipc=0.6**: instructions per clock (inverse of CPI ≈ 1.7)
- **rv32i+O1+O2+O3**: RISC-V base + compiler optimizations
- **mass=32KB**: BRAM size (2^MLEN bytes)

### Calc output

```
darkRISC-V (pipeline=3, ipc=0.6, cache=0, rv32i+O1+O2+O3+MAC) built=Jan 14 2025
board: de2 (id=21, clock=100000000)
...
= sum 10 = 55 (formula: 55)
= fib 30 = 832040
= fact 12 = 479001600
= max 1000 = largest prime up to 1000 is 997
>
```

### Pipeline Performance Report

At the end of simulation, the CPU prints:

```
pipeline-report:
  clocks:   101737
  running:  59862
  halted:   0
  flushed:  41875
  CPI:      1.70
```

- **clocks**: total clock cycles elapsed
- **running**: cycles where an instruction was completing
- **halted**: cycles spent waiting for memory (HLT signal)
- **flushed**: cycles wasted due to pipeline flushes after jumps/branches
- **CPI**: Clocks Per Instruction (lower is better; ideal = 1.0)

A CPI of 1.70 means the CPU takes on average 1.7 clocks per instruction.
The overhead comes from the 2-cycle flush penalty after every taken branch.

---

## Waveform Viewing

The simulation writes signal traces to `darksocv.vcd` (Value Change Dump).
This file can be opened with [GTKWave](http://gtkwave.sourceforge.net/) to
visualise all signals over time:

```bash
gtkwave darksocv.vcd
```

In the waveform viewer, you can see:
- **CLK** toggling at 100 MHz
- **IADDR** incrementing by 4 each cycle (instruction fetch addresses)
- **IDATA** showing the fetched instruction words
- **DADDR / DATAO / DATAI** showing load/store transactions
- **FLUSH** going to 2 after every jump, then counting down to 0

This is invaluable for debugging: if the CPU executes the wrong instruction
or reads garbage data, the waveforms show exactly what happened and when.

---

## Instruction Trace

When `__TRACE__` is enabled in `config.vh`, every instruction is logged:

```
100ns: [0] pc=00000000 inst=00004197
105ns: [0] pc=00000004 inst=04818193
110ns: [0] pc=00000008 inst=30519073
```

Each line shows: simulation time, core ID, program counter, and the
instruction word. The trace is saved to `darksocv.txt`.

---

## The Testbench (darksimv.v)

The testbench is the simulation-only wrapper that creates the environment:

1. **Clock generation**: toggles `XCLK` every 5ns (100 MHz)
2. **Reset**: asserts `XRES` for the first few cycles, then deasserts
3. **UART RX**: tied to HIGH (idle) — `wire RX = 1;`
4. **VCD dumping**: calls `$dumpfile` / `$dumpvars` to generate waveforms
5. **Instantiates**: the full `darksocv` top-level module

Because `RX = 1` (idle), the firmware cannot receive serial input during
simulation. DarkShell uses a built-in script array to provide commands;
the calc application has its computations hardcoded.

---

## Common Issues

| Problem | Cause | Fix |
|---|---|---|
| `darksocv.mem not found` | Firmware not built | Run `make` in `src/` first |
| Simulation hangs | Firmware never prints `>` | Check your `main()` always reaches the prompt |
| CPI much higher than 1.7 | Wait states from cache misses or slow memory | Expected in Von Neumann mode |
| No output at all | Firmware crashes at boot | Check `boot.S` stack pointer and `MLEN` alignment |
| `iverilog` errors | Missing RTL files | Check `sim/Makefile` RTLS list matches your files |

---

## Quick Reference

```bash
# Build firmware
cd src && make clean && make

# Build + run simulation
cd sim && make clean && make

# Just run (after previous compilation)
cd sim && py run_sim.py darksocv darksocv.txt ../rtl/config.vh

# Switch application (edit src/Makefile)
APPLICATION = darkshell    # or calc
```
