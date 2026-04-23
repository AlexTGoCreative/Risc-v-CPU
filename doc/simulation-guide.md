# Simulation Guide

This document explains how to compile the firmware, run the Icarus Verilog
simulation, interpret the output, and explore waveforms. No prior simulation
experience is assumed.

---

## 1. What Is Simulation?

When designing hardware in Verilog, you cannot instantly run your design on a
physical chip — synthesis (converting Verilog to FPGA configuration) takes
5–20 minutes. **Simulation** provides a faster alternative:

A **simulator** is a program that models the behaviour of your Verilog circuit
in software. It evaluates all the logic gates, registers, and module
interactions cycle by cycle, producing the same logical output as real
hardware — but running on your PC in seconds.

**Icarus Verilog** (`iverilog`) is a free, open-source Verilog simulator. It:
1. **Compiles** Verilog source files into an intermediate format
2. **Runs** the compiled simulation using the `vvp` runtime
3. **Generates** a VCD (Value Change Dump) waveform file for post-analysis

**GTKWave** is a free waveform viewer that displays the VCD file as a timeline
of every signal in the design — like a logic analyser recording.

---

## 2. Prerequisites

Before running a simulation, you need the following tools installed and on
your `PATH`:

| Tool | Purpose | How to get it |
|---|---|---|
| **Icarus Verilog** (`iverilog`, `vvp`) | Verilog compiler and simulator | [iverilog.icarus.com](http://iverilog.icarus.com) |
| **RISC-V GCC toolchain** | Compiles C/assembly to RISC-V machine code | [xPack RISC-V GCC](https://xpack.github.io/riscv-none-elf-gcc/) |
| **Python** (≥ 3.8) | Build helper scripts | [python.org](https://python.org) |
| **GNU Make** | Automates the build process | Ships with Linux; [GnuWin32](http://gnuwin32.sourceforge.net/) on Windows |
| **GTKWave** (optional) | Waveform viewer | [gtkwave.sourceforge.net](http://gtkwave.sourceforge.net) |

All paths are configured in `src/config.mk`. Edit this file to match your
installation if the tools are not on your system `PATH`.

---

## 3. The Complete Build Flow

The simulation requires two independent build steps:

```
Step 1: Firmware Build (src/ directory)
────────────────────────────────────────
boot.S  ─────────────────────────────────┐
main.c  ──→  .o files  ──→  darksocv.elf  ──→  darksocv.mem (hex)
io.c    ─────────────────────────────────┘     (firmware image)

Step 2: RTL Compilation + Simulation (sim/ directory)
──────────────────────────────────────────────────────
darksimv.v  ┐
darksocv.v  │
darkriscv.v ├──→  iverilog  ──→  darksocv (simulator executable)
darkram.v   │          ↑
darkio.v    │          │
darkuart.v  ┘     darksocv.mem  (firmware loaded at startup)
...

Simulation Output:
──────────────────
darksocv (executable)  ──→  terminal output  (UART prints → $write)
                       ──→  darksocv.vcd     (waveform file)
                       ──→  darksocv.txt     (instruction trace, if enabled)
```

---

## 4. Step-by-Step: Running a Simulation

### Step 1 — Build the Firmware

```bash
cd src
make clean
make
```

The `src/Makefile` compiles the active application. The application is selected
by the `APPLICATION` variable at the top of `src/Makefile`:

```makefile
APPLICATION = darkshell   # options: darkshell, calc, coremark
```

| Application | What it runs |
|---|---|
| `darkshell` | An interactive command shell (LED control, memory dump, timer) |
| `calc` | A scripted calculator: computes sum, fibonacci, factorial, and primes |
| `coremark` | EEMBC CoreMark benchmark (measures CPU performance in iterations/sec) |

**Output files produced:**
- `src/darksocv.mem` — the firmware in hexadecimal format (one 32-bit word per
  line), ready to load into simulation
- `src/darksocv.lst` — assembly listing (human-readable disassembly)
- `src/darksocv.map` — linker map showing where every function and variable lives
  in memory

### Step 2 — Compile the RTL and Run the Simulation

```bash
cd sim
make clean
make
```

This runs two commands:

**Compilation** (`iverilog`):
```bash
iverilog -I ../rtl -D__ICARUS__ -o darksocv darksimv.v ../rtl/darksocv.v \
         ../rtl/darkriscv.v ../rtl/darkbridge.v ../rtl/darkram.v \
         ../rtl/darkio.v ../rtl/darkuart.v ...
```

- `-D__ICARUS__`: defines the `__ICARUS__` macro, which activates the
  `SIMULATION` mode in all Verilog files
- `-I ../rtl`: adds the `rtl/` directory to the include path so
  `` `include "../rtl/config.vh" `` works

**Simulation** (`vvp` via `run_sim.py`):
```bash
py run_sim.py darksocv darksocv.txt ../rtl/config.vh
```

The `run_sim.py` script:
1. Reads `config.vh` to extract `MLEN` and passes it to `vvp`
2. Invokes `vvp darksocv` to run the simulation
3. Captures `UART` output (printed by `$write`) to the terminal
4. Waits for `$finish()` (triggered by the `>` prompt character)

---

## 5. Understanding the Simulation Output

### 5.1 Boot Screenshot

![Boot output](boot.png)

The terminal shows the firmware's boot messages. A detailed explanation of
every line is in [diagrams.md § boot.png](diagrams.md#1-bootpng--the-simulation-boot-screenshot).

Brief summary of each line:

```
boot0: main@0200 stack@01fb0
```
The `boot.S` startup code placed `main()` at address `0x0200` in BRAM and
set the initial stack pointer to `0x01fb0`.

```
csrxx: not found
stvec: not found
mtvec: not found (polling)
```
CSR support (`__CSR__`) is not enabled in this build. The firmware gracefully
falls back to polling mode — it checks the timer register in a loop rather
than using hardware interrupts.

```
board: simulation only (id=0)
```
`BOARD_ID = 0` is the simulation identifier (set in `config.vh` when no real
board is defined).

```
build: Sun, 27 Apr 2025 15:11:03 -0300 for rv32e_zicsr
```
Build timestamp from the GCC `__DATE__`/`__TIME__` macros.

```
core0: darkriscv@100MHz w/ rv32e
```
CPU running at 100 MHz with the RV32E reduced register file (16 registers).

```
bram0: 352 bytes free
bram0: text@0200+5048 data@15b0+2280 stack@2000
```
Memory layout: code at `0x0200` (5048 bytes), data at `0x15b0` (2280 bytes),
stack at `0x2000`. Only 352 bytes remain unallocated.

```
uart0: 115.2kbps (div=868)
```
UART configured at 115200 baud; divisor = 100 MHz ÷ 115200 ≈ 868.

```
timr0: 1000Hz (div=99999)
```
Timer fires 1000 times per second; reload = 100 MHz ÷ 1000 − 1 = 99999.

```
Welcome to DarkRISCV!
492>
```
The shell is ready. `492` is the instruction count from reset to the prompt.
The `>` character ends the simulation.

---

### 5.2 DarkShell Output

When `APPLICATION = darkshell`, the firmware includes an interactive test shell
(note: in simulation, RX is tied high so you cannot type interactively — the
shell uses a hardcoded command script):

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

The shell banner reports:
- `pipeline=3`: 3-stage pipeline is active
- `ipc=0.6`: measured instructions per clock (approximately)
- `cache=0`: caches not active in Harvard mode
- `rv32i+O1+O2+O3`: instruction set and compiler optimisation flags
- `mass=32KB`: BRAM size (2^MLEN = 2^15 = 32768 bytes)

### 5.3 Calc Output

When `APPLICATION = calc`:

```
darkRISC-V (pipeline=3, ...) built=Jan 14 2025
board: de2 (id=21, clock=100000000)
...
= sum 10 = 55 (formula: 55)
= fib 30 = 832040
= fact 12 = 479001600
= max 1000 = largest prime up to 1000 is 997
>
```

The `calc` application runs a deterministic set of computations:
- `sum 10`: \(1+2+\cdots+10 = 55\), verified against the closed-form formula
  \(\frac{n(n+1)}{2}\)
- `fib 30`: 30th Fibonacci number (832040)
- `fact 12`: 12! = 479001600 (largest factorial that fits in a 32-bit integer)
- `max 1000`: finds the largest prime ≤ 1000 using trial division

These results are deterministic — if the CPU is functioning correctly, the
output is always exactly as shown.

---

### 5.4 Pipeline Performance Report

At the end of simulation, `darkriscv.v` prints (when `__PERFMETER__` is defined):

```
pipeline-report:
  clocks:   101737
  running:  59862
  halted:   0
  flushed:  41875
  CPI:      1.70
```

**Interpreting each field:**

| Field | Meaning | Notes |
|---|---|---|
| `clocks` | Total clock cycles from reset to `$finish()` | Includes all time from boot to prompt |
| `running` | Cycles where an instruction completed | = number of instructions executed |
| `halted` | Cycles spent waiting for memory (`HLT = 1`) | 0 in Harvard mode (BRAM is fast) |
| `flushed` | Cycles wasted on pipeline flushes | = branch penalty cycles |
| `CPI` | Clocks Per Instruction = `clocks / running` | Lower is better; ideal = 1.0 |

**Why CPI = 1.70:**

\[
\text{CPI} = \frac{\text{clocks}}{\text{running}} = \frac{101737}{59862} \approx 1.70
\]

The excess (0.70 above the ideal 1.0) comes entirely from the 41875 flushed
cycles — every taken branch costs 2 wasted cycles. The halted count is 0
because Harvard mode gives the CPU simultaneous access to instruction and data
buses through separate BRAM ports.

**Achieving lower CPI:**
- Compile with `-O1` instead of `-Os` (fewer branches in the generated code)
- Enable branch prediction (not yet implemented in DarkRISCV)
- Use the DBNZ instruction for tight loops (avoids branch flush)

---

## 6. Waveform Viewing with GTKWave

### 6.1 Opening the VCD File

The simulation writes all signal traces to `sim/darksocv.vcd`:

```bash
gtkwave sim/darksocv.vcd
```

### 6.2 What Signals to Add

In the GTKWave hierarchy browser (left panel), navigate to:
- `darksocv` → `darkbridge0` → `darkriscv0` → add:
  - `CLK` — the 100 MHz clock (fast toggling signal)
  - `IFPC` — program counter (staircase incrementing by 4)
  - `IADDR` — instruction fetch address (same as IFPC, one cycle earlier)
  - `IDATA` — instruction word (changes when a new instruction is fetched)
  - `FLUSH` — pipeline flush counter (goes to 2 on branches, counts down)
  - `HLT` — pipeline stall (goes high briefly on load instructions)

### 6.3 How to Read the Waveforms

**Normal sequential execution:**
```
CLK:    ─┐ ┌─┐ ┌─┐ ┌─┐ ┌─┐ ┌─┐ ┌─
         └─┘ └─┘ └─┘ └─┘ └─┘ └─┘

IFPC:   ──000──X──004──X──008──X──00C──X──010──
         (each value held for 1 clock cycle)

FLUSH:  ────────0────────────────────────────────
         (0 = running, pipeline active)

HLT:    ────────0────────────────────────────────
         (0 = running, memory responding in time)
```

**Branch taken (pipeline flush):**
```
CLK:    ─┐ ┌─┐ ┌─┐ ┌─┐ ┌─┐ ┌─┐ ┌─

IFPC:   ──010──X──014──X──018──X──400──X──404──
                           ^ branch detected   ^ correct code continues here
                           IFPC jumps to 0x400

FLUSH:  ─────────────0─────X──2──X──1──X──0────
                           ^ branch  ^ counting down
```

During `FLUSH = 2` and `FLUSH = 1`, the instructions at `0x014` and `0x018`
are discarded (replaced by NOP). The next real instruction executes at `0x400`.

**Load instruction (memory stall):**
```
CLK:    ─┐ ┌─┐ ┌─┐ ┌─┐ ┌─┐ ┌─┐ ┌─

IFPC:   ──020──X──024──X──024──X──028──
                      ^ same address repeated:
                        HLT held the pipeline for 1 cycle

HLT:    ─────────────0──X─1──X──0────
                        ^ load request pending (BRAM not yet ready)
```

The `HLT` signal frozen the pipeline for 1 cycle — `IFPC` did not advance,
allowing the memory to respond and the load result to be captured.

---

## 7. Instruction Trace

When `__TRACE__` is uncommented in `rtl/config.vh`, every instruction execution
is logged to `sim/darksocv.txt`:

```
100ns: [0] pc=00000000 inst=00004197
105ns: [0] pc=00000004 inst=04818193
110ns: [0] pc=00000008 inst=30519073
115ns: [0] pc=0000000c inst=34011073
...
```

**Field meanings:**
| Field | Example | Meaning |
|---|---|---|
| Time | `100ns` | Simulation time (5 ns per clock → 100 MHz) |
| Thread | `[0]` | Thread ID (0 in single-thread mode) |
| `pc=` | `00000000` | Program counter (byte address of this instruction) |
| `inst=` | `00004197` | Raw 32-bit instruction word in hexadecimal |

To decode `0x00004197`:
- Bits `[6:0]` = `010111` → `AUIPC` (Add Upper Immediate to PC)
- Bits `[11:7]` = `00011` → rd = `x3`
- Bits `[31:12]` = `0x00004` → imm = 0x4000

The trace is invaluable for debugging: if the simulation produces wrong output,
you can compare the trace against the disassembly listing (`src/darksocv.lst`)
to find exactly where execution went wrong.

**Note:** When `__TRACE__` is enabled, UART output is suppressed (the two are
mutually exclusive for readability).

---

## 8. The Testbench (`darksimv.v`)

`sim/darksimv.v` is the **simulation-only wrapper** that creates the environment
around the SoC. On real hardware, this functionality comes from the FPGA board
itself (oscillator, reset button, UART connector). In simulation, it must be
modelled in Verilog:

```verilog
module darksimv;

    // 1. Clock generation: 100 MHz = 10 ns period = 5 ns half-period
    reg XCLK = 0;
    always #5 XCLK = ~XCLK;

    // 2. Reset: hold high for a few cycles, then release
    reg XRES = 1;
    initial begin
        #50 XRES = 0;   // release reset after 50 ns (5 clock cycles)
    end

    // 3. UART RX: tied to 1 (idle) — no serial input during simulation
    wire UART_RXD = 1;

    // 4. VCD dump: record all signal changes to a file
    initial begin
        $dumpfile("darksocv.vcd");
        $dumpvars(0, darksimv);   // dump everything
    end

    // 5. Instantiate the full SoC
    darksocv soc0 (
        .XCLK(XCLK), .XRES(XRES),
        .UART_RXD(UART_RXD), .UART_TXD(),
        .LED(), .IPORT(0), .OPORT(), .DEBUG()
    );

endmodule
```

Because `UART_RXD = 1` (idle line), the firmware cannot receive serial input.
This is why:
- `darkshell` uses a hardcoded command array to "type" commands automatically
- `calc` has its computations hardcoded (no user input required)

---

## 9. Common Issues and Fixes

| Problem | Likely Cause | Solution |
|---|---|---|
| `darksocv.mem not found` | Firmware not built | Run `make` in `src/` first |
| `iverilog: command not found` | Icarus not installed | Install Icarus Verilog, add to PATH |
| `riscv-none-elf-gcc: not found` | GCC toolchain missing | Install xPack RISC-V GCC, set CROSS in `src/config.mk` |
| Simulation hangs (no output) | Firmware never prints `>` | Check `main()` reaches the prompt; check MLEN matches linker script |
| `CPI` much higher than 1.7 | Von Neumann mode active | Check that `__HARVARD__` is defined in `config.vh` |
| No output at all | Firmware crashes during boot | Check `boot.S` stack pointer; verify MLEN is consistent |
| `Warning: ... Not enough words` | `darksocv.mem` too small for configured MLEN | Rebuild firmware after changing MLEN; or reduce MLEN |
| Wrong computation results | Firmware bug or RTL bug | Use `__TRACE__` and compare against `darksocv.lst` |

---

## 10. Quick Reference Commands

```bash
# ─── Firmware ────────────────────────────────────────────────────────────────
cd src

# Build the default application (darkshell)
make

# Switch to calc application: edit src/Makefile → APPLICATION = calc, then:
make clean && make

# ─── Simulation ──────────────────────────────────────────────────────────────
cd sim

# Full clean + compile + run (recommended)
make clean && make

# Just run (after previous compilation)
py run_sim.py darksocv darksocv.txt ../rtl/config.vh

# View waveforms (after simulation)
gtkwave darksocv.vcd

# ─── From the project root ───────────────────────────────────────────────────
# Build firmware + run simulation (both steps)
make

# Clean everything
make clean
```

---

## 11. Enabling Optional Simulation Features

Edit `rtl/config.vh` and recompile:

```verilog
// Enable instruction trace (outputs to sim/darksocv.txt)
`define __TRACE__

// Enable performance meter (prints CPI report at end)
`define __PERFMETER__     // (enabled by default)

// Enable register dump in GTKWave (shows register file contents in waveform)
`define __REGDUMP__

// Enable interactive UART input (allows typing commands in the terminal)
// Note: only works with Icarus Verilog
`define __INTERACTIVE__
```

After changing `config.vh`, you must recompile the RTL (`make` in `sim/`)
but you do not need to rebuild the firmware unless you also changed `MLEN`.
