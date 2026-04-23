# RTL Implementation Guide — Reading the Verilog Source

This document is a guided tour of the Verilog source files in the `rtl/`
directory. Its goal is to bridge the gap between the abstract architecture
concepts (explained in [cpu-core.md](cpu-core.md) and
[soc-architecture.md](soc-architecture.md)) and the actual code that
implements them.

> **Prerequisites:** You should be familiar with the concepts in
> [cpu-core.md](cpu-core.md) and [soc-architecture.md](soc-architecture.md)
> before reading this document. No prior Verilog experience is assumed — the
> basics are introduced here as needed.

---

## 1. A Brief Introduction to Verilog

**Verilog** is a *Hardware Description Language* (HDL). Unlike C or Python —
where you write instructions that execute sequentially — Verilog describes
*circuits* that operate in parallel and are driven by a clock signal.

### 1.1 Two Kinds of Logic

**Combinational logic** (`assign` statements, `always @(*)` blocks):
- Has no memory — output depends only on current inputs
- Changes instantly when inputs change (subject to propagation delay)
- Examples: an adder, a multiplexer, a decoder

```verilog
// Combinational: output is always the bitwise AND of a and b
assign y = a & b;
```

**Sequential logic** (`always @(posedge CLK)` blocks):
- Has memory — output is stored in a flip-flop (register)
- Output only changes on the rising edge of the clock
- Examples: a counter, a shift register, a pipeline stage register

```verilog
// Sequential: on every rising clock edge, capture the input
always @(posedge CLK) begin
    if (RES) q <= 0;       // synchronous reset
    else     q <= d;       // latch input
end
```

### 1.2 Key Verilog Constructs You Will Encounter

| Construct | Meaning |
|---|---|
| `wire` | A signal (no storage) — like a wire in a real circuit |
| `reg` | A variable that can hold a value across clock cycles (stored in a flip-flop) |
| `assign` | Continuous assignment — combinational logic |
| `always @(posedge CLK)` | Sequential block — runs on every rising clock edge |
| `always @(*)` | Combinational block — runs whenever any input changes |
| `module ... endmodule` | Definition of a hardware block (like a class) |
| `parameter` | A compile-time constant (like a template parameter) |
| `` `define `` | A preprocessor macro (like `#define` in C) |
| `` `ifdef ... `endif `` | Conditional compilation (like `#ifdef` in C) |
| `$readmemh(file, array)` | Simulation only: load a hex file into a memory array |

### 1.3 Module Ports

Every Verilog module has **ports** — the signals that connect it to other
modules. Ports have a direction:
- `input`: driven from outside; read inside
- `output`: driven from inside; read outside
- `inout`: bidirectional (e.g., a tri-state bus)

---

## 2. `config.vh` — The Master Configuration File

**Location:** `rtl/config.vh`  
**Type:** Header file (included in every other RTL file via `` `include "../rtl/config.vh" ``)

This file contains all the compile-time switches that control the
feature set of the processor. Think of it as the "settings panel" for
the entire design.

### 2.1 Pipeline Configuration

```verilog
`define __3STAGE__
```

This is the single most important switch. When defined, the CPU uses a
**3-stage pipeline** (Fetch → Decode → Execute). When commented out, it falls
back to a **2-stage pipeline** (Fetch+Decode → Execute), which has lower
maximum clock frequency but fewer pipeline flush cycles on branches.

The trade-off:

| Mode | Max clock (Spartan-6) | Branch penalty | Load penalty |
|---|---|---|---|
| 3-stage | ~100 MHz | 2 cycles | 1 cycle |
| 2-stage | ~56 MHz | 1 cycle | 1 cycle |

The 3-stage pipeline achieves higher clock frequency by distributing the logic
more evenly between stages, at the cost of more cycles wasted on branches.

### 2.2 ISA Variant

```verilog
//`define __RV32E__
```

Commented out by default — the CPU implements **RV32I** (32 registers). When
uncommented, it switches to **RV32E** (16 registers), halving the register file
size and saving FPGA area. Useful for very small FPGAs.

### 2.3 Memory Size

```verilog
`define MLEN 15   // 15 → 2^15 = 32768 bytes = 32 KB
```

This is the address width of the on-chip BRAM. The actual memory size is
\(2^{\text{MLEN}}\) bytes. Common values:

| `MLEN` | Size | Suitable for |
|---|---|---|
| 13 | 8 KB | `darkshell` application |
| 14 | 16 KB | Most applications |
| 15 | 32 KB | CoreMark benchmark |

**Warning:** `MLEN` must be consistent between `rtl/config.vh` and the linker
script `src/darksocv.lds`. If they disagree, the firmware will write beyond
the BRAM boundary, causing unpredictable behaviour.

### 2.4 Bus Architecture

```verilog
`define __HARVARD__
```

When defined, the SoC uses separate instruction and data buses (Harvard mode).
When commented out, the buses are time-multiplexed (Von Neumann mode), and the
cache configuration below is automatically activated:

```verilog
`ifndef __HARVARD__
    `define __LUTCACHE__
    `define __CDEPTH__ 6      // cache depth: 2^6 = 64 entries
    `define __ICACHE__        // enable instruction cache
    `define __DCACHE__        // enable data cache
    `define __RMW_CYCLE__     // read-modify-write for sub-word stores
`endif
```

### 2.5 Board Definition

The board is identified by a `BOARD_ID` compile-time constant. Each board
section defines the clock configuration:

```verilog
`ifdef DE2_CYCLONE2
    `define BOARD_ID 21
    `define BOARD_CK 100000000  // clock frequency in Hz
    `define INVRES 1            // active-low reset (KEY[0] on DE2)
`endif
```

When no board is defined (e.g., in simulation), `BOARD_ID` defaults to 0 and
`BOARD_CK` defaults to 100 MHz.

### 2.6 UART Baud Rate

```verilog
`define __UARTSPEED__ 115200
`define __BAUD__ ((`BOARD_CK / `__UARTSPEED__))
```

The baud divisor is computed automatically from the clock frequency. At 100 MHz
this evaluates to 868, meaning the UART module counts 868 clock cycles per bit.

### 2.7 Optional Features

| Define | What it enables |
|---|---|
| `__CSR__` | Control and Status Registers (required for interrupts) |
| `__INTERRUPT__` | Hardware interrupt support (`IRQ` input, `mtvec`, `mepc`) |
| `__MEXT__` | Hardware multiply extension (`MUL`, `MULH`, etc.) |
| `__THREADS__` N | Hardware multi-threading (2^N thread contexts) |
| `__COPROCESSOR__` | Custom instruction interface (coprocessor port) |
| `__MAC16X16__` | 16×16 multiply-accumulate instruction via coprocessor |
| `__DBNZ__` | Decrement-and-branch-if-not-zero custom instruction |
| `__TRACE__` | Instruction-level trace output during simulation |
| `__PERFMETER__` | Pipeline performance counter report at end of simulation |

---

## 3. `darkriscv.v` — The CPU Core

**Location:** `rtl/darkriscv.v`  
**Instantiated by:** `darkbridge.v` (which is instantiated by `darksocv.v`)

This is the heart of the entire project — approximately 800 lines of Verilog
that implement a complete RISC-V processor.

### 3.1 Module Ports

```verilog
module darkriscv (
    input        CLK,      // 100 MHz system clock
    input        RES,      // synchronous reset (active high)
    input        IRQ,      // interrupt request (if __INTERRUPT__ enabled)

    // Instruction bus (read-only)
    output        IDREQ,   // instruction fetch request
    output [31:0] IADDR,   // instruction address
    input  [31:0] IDATA,   // instruction data returned from memory
    input         IDACK,   // instruction acknowledge (data is valid)

    // Data bus (read/write)
    output        DDREQ,   // data access request
    output [31:0] DADDR,   // data address (load/store)
    output [ 3:0] DBE,     // byte enable (which bytes to read/write)
    output        DRD,     // data read enable
    output        DWR,     // data write enable
    output [31:0] DATAO,   // data to write (store)
    input  [31:0] DATAI,   // data received (load)
    input         DDACK,   // data acknowledge

    output [3:0]  DEBUG    // debug output signals
);
```

The CPU communicates with the outside world through exactly these signals.
Everything else — the pipeline registers, the ALU, the decoder — is internal.

### 3.2 Instruction Opcodes

At the top of the file, the seven RV32I opcodes are defined as constants:

```verilog
`define LUI     7'b01101_11  // Load Upper Immediate
`define AUIPC   7'b00101_11  // Add Upper Immediate to PC
`define JAL     7'b11011_11  // Jump and Link
`define JALR    7'b11001_11  // Jump and Link Register
`define BCC     7'b11000_11  // Branch (BEQ, BNE, BLT, BGE, BLTU, BGEU)
`define LCC     7'b00000_11  // Load (LB, LH, LW, LBU, LHU)
`define SCC     7'b01000_11  // Store (SB, SH, SW)
`define MCC     7'b00100_11  // ALU with Immediate (ADDI, ANDI, ORI…)
`define RCC     7'b01100_11  // ALU Register-Register (ADD, SUB, AND…)
`define SYS     7'b11100_11  // System (ECALL, EBREAK, CSR*)
`define CUS     7'b00010_11  // Custom-0 (MAC instruction)
```

The bottom 2 bits of every RISC-V base instruction are always `11` — this is
part of the encoding scheme to distinguish 32-bit instructions from compressed
(16-bit) RVC instructions, which this implementation does not support.

### 3.3 The Pipeline Halt Signal

```verilog
wire HLT = (DDREQ ? !DDACK : 0) ||   // data bus waiting for acknowledge
           (IDREQ ? !IDACK : 0);      // instruction bus waiting
```

`HLT` is a combinational signal. It is `1` whenever the CPU has made a request
that has not yet been acknowledged. When `HLT = 1`, every clocked element in
the CPU skips its update — the entire pipeline freezes until memory responds.

This is the **flow control mechanism** of the memory interface. The memory
controller asserts `DDACK`/`IDACK` when data is ready, which deasserts `HLT`,
allowing the pipeline to advance.

### 3.4 The Fetch Stage: Program Counter

```verilog
reg [31:0] IFPC;   // Instruction Fetch Program Counter

always @(posedge CLK) begin
    if (XRES)      IFPC <= `__RESETPC__;   // on reset: go to address 0
    else if (!HLT) IFPC <= JADDR;          // on normal clock: next PC
end
```

`IFPC` is a 32-bit register that holds the address of the instruction
currently being **fetched** (the IF stage of the pipeline). `JADDR` is a
combinational wire computed by the Execute stage: it is either `IFPC + 4`
(sequential execution) or a branch/jump target.

The CPU drives `IADDR = IFPC`, which sends the address to the instruction bus.

### 3.5 The Decode Stage: Instruction Register and Decoder

```verilog
reg [31:0] IDATAX;   // pipeline register: holds instruction in decode stage
reg [31:0] XIMM;     // decoded immediate value (sign-extended)
```

The instruction captured in `IDATAX` is decoded using combinational logic. The
opcode and format determine how the immediate value is reconstructed:

```verilog
// Instruction decode: one-hot signals, one per instruction type
wire XLUI  = (IDATAX[6:0] == `LUI);   // Load Upper Immediate
wire XJAL  = (IDATAX[6:0] == `JAL);   // Jump And Link
wire XBCC  = (IDATAX[6:0] == `BCC);   // Branch Conditional
wire XLCC  = (IDATAX[6:0] == `LCC);   // Load from memory
wire XSCC  = (IDATAX[6:0] == `SCC);   // Store to memory
wire XMCC  = (IDATAX[6:0] == `MCC);   // ALU with immediate
wire XRCC  = (IDATAX[6:0] == `RCC);   // ALU register-to-register

// Immediate reconstruction (format-specific bit reordering)
wire [31:0] XSIMM =                    // sign-extended immediate
    XSCC ? { {21{IDATAX[31]}}, IDATAX[30:25], IDATAX[11:7]  } :  // S-type
    XBCC ? { {20{IDATAX[31]}}, IDATAX[7], IDATAX[30:25], IDATAX[11:8], 1'b0 } :  // B-type
    XLUI ||
    XAUIPC? { IDATAX[31:12], 12'b0 } :  // U-type (upper immediate)
    XJAL  ? { {12{IDATAX[31]}}, IDATAX[19:12], IDATAX[20], IDATAX[30:21], 1'b0 } : // J-type
             { {21{IDATAX[31]}}, IDATAX[30:20] };                  // I-type (default)
```

The sign-extension operation (e.g., `{21{IDATAX[31]}}`) replicates the most
significant bit of the immediate field 21 times to fill the upper 32 bits.
This ensures that negative numbers represented in fewer bits are correctly
extended to the full 32-bit signed representation.

### 3.6 The Register File

```verilog
reg [31:0] REGS [`RLEN-1:0];   // register file: 32 (or 16 for RV32E) entries
```

The `RLEN` macro is computed in `config.vh` based on whether `__RV32E__` and
`__THREADS__` are defined. For a basic RV32I build, `RLEN = 32`.

**Combinational reads** (two simultaneous read ports):

```verilog
wire [31:0] U1REG = REGS[RS1];    // value of source register 1
wire [31:0] U2REG = REGS[RS2];    // value of source register 2
```

`RS1` and `RS2` are 5-bit register indices extracted from the instruction.
Since these are plain `wire` assignments (not registered), the values are
available combinationally — the register file effectively has infinite read
bandwidth with zero latency.

**Clocked write** (one write port):

```verilog
always @(posedge CLK) begin
    if (!HLT && !XRES) begin
        if (WDREQ && RD != 0)       // write to rd, but never to x0
            REGS[RD] <= WDATA;
    end
end
```

`WDREQ` (write data request) is asserted when the Execute stage has a result
ready. `RD` is the 5-bit destination register number. `WDATA` is the 32-bit
result (from the ALU, a load, or a jump return address). The `RD != 0` guard
enforces the hardwired-zero property of `x0`.

### 3.7 The Execute Stage: Four ALUs

The Execute stage computes four results in parallel every clock cycle.

**ALU 1 — Arithmetic/Logic:**

```verilog
wire [31:0] RMDATA =
    FCT3==7 ? U1REG &  S2REGX :         // AND
    FCT3==6 ? U1REG |  S2REGX :         // OR
    FCT3==4 ? U1REG ^  S2REGX :         // XOR
    FCT3==3 ? U1REG <  U2REGX :         // SLTU (unsigned comparison)
    FCT3==2 ? S1REG <  S2REGX :         // SLT  (signed comparison)
    FCT3==0 ? (XRCC && FCT7[5] ?
               U1REG -  S2REGX :        // SUB (register only)
               U1REG +  S2REGX) :       // ADD
    FCT3==1 ? S1REG << U2REGX[4:0] :   // SLL (shift left logical)
              FCT7[5]  ?
               S1REG >>> U2REGX[4:0]:  // SRA (shift right arithmetic)
               S1REG >>  U2REGX[4:0];  // SRL (shift right logical)
```

`S2REGX` is either `U2REG` (register-to-register) or `XSIMM` (immediate),
selected by whether the instruction is `XRCC` or `XMCC`.

**ALU 2 — Branch Condition:**

```verilog
wire BMUX =
    (FCT3==0 && U1REG == U2REGX) ||   // BEQ
    (FCT3==1 && U1REG != U2REGX) ||   // BNE
    (FCT3==4 && S1REG <  S2REGX) ||   // BLT  (signed)
    (FCT3==5 && S1REG >= S2REG)  ||   // BGE  (signed)
    (FCT3==6 && U1REG <  U2REGX) ||   // BLTU (unsigned)
    (FCT3==7 && U1REG >= U2REG);      // BGEU (unsigned)

wire JREQ = (XBCC && BMUX) || XJAL || XJALR;  // is a jump/branch taken?
```

**ALU 3 — Next PC:**

```verilog
wire [31:0] JADDR =
    XJAL  ? XIDPC + XSIMM :         // JAL: PC + J-type immediate
    XJALR ? U1REG + XSIMM :         // JALR: rs1 + I-type immediate
    XBCC  ? XIDPC + XSIMM :         // BCC: PC + B-type immediate (if taken)
            IFPC  + 4;              // default: next sequential instruction
```

`XIDPC` is the PC value of the instruction currently in the Execute stage
(the `IDPC` pipeline register, which holds the PC captured in Decode).

**ALU 4 — Memory Address:**

```verilog
assign DADDR = U1REG + XSIMM;    // rs1 + immediate (I-type for LW, S-type for SW)
```

This is a single combinational addition. It is always computed, even when the
instruction is not a load or store — the result is simply ignored when
`DDREQ = 0`.

### 3.8 Register Write-Back

The final step in each instruction cycle: write the result back to the
destination register.

```verilog
wire [31:0] WDATA =
    XLCC         ? LDATA :         // Load: data from memory
    XAUIPC       ? XIDPC + XSIMM :// AUIPC: PC + upper immediate
    XJAL || XJALR? XIDPC + 4 :    // JAL/JALR: return address = PC+4
    XLUI         ? XSIMM :         // LUI: the immediate value itself
    XMCC || XRCC ? RMDATA :        // ALU result
    XCSRX        ? CRDATA :        // CSR read
                   DREG;           // keep current value (NOP)
```

`LDATA` contains the result of the load — the 32-bit word from memory, with
the appropriate bytes extracted and sign-extended:

```verilog
wire [31:0] LDATA =
    FCT3==0 ? { {24{DATAI[ 7]}}, DATAI[ 7:0] } :  // LB  (byte, signed)
    FCT3==4 ? {  24'b0,          DATAI[ 7:0] } :  // LBU (byte, unsigned)
    FCT3==1 ? { {16{DATAI[15]}}, DATAI[15:0] } :  // LH  (halfword, signed)
    FCT3==5 ? {  16'b0,          DATAI[15:0] } :  // LHU (halfword, unsigned)
              DATAI;                               // LW  (full word)
```

### 3.9 Pipeline Flush

When a jump or taken branch is detected (`JREQ = 1`), the two instructions
already in the Fetch and Decode stages are wrong — they were fetched from the
sequential path, not the jump target. They must be discarded:

```verilog
reg [1:0] FLUSH;    // flush counter: counts down from 2 to 0

always @(posedge CLK) begin
    if (!HLT) FLUSH <= JREQ ? 2 : FLUSH ? FLUSH - 1 : 0;
end
```

When `FLUSH > 0`, the pipeline stage outputs are replaced with `NOP` (a null
operation — specifically `ADDI x0, x0, 0`), so that the instructions in the
wrong stages are effectively discarded without causing side effects.

### 3.10 Performance Counters (Simulation Only)

When `__PERFMETER__` is defined, additional registers count events:

```verilog
`ifdef __PERFMETER__
    integer TCLK   = 0;   // total clocks
    integer THLT   = 0;   // clocks spent halted (memory wait)
    integer TFLUSH = 0;   // clocks spent flushing (branch penalty)
    integer TRUN   = 0;   // clocks spent executing
`endif
```

These are incremented in simulation-only `always` blocks and printed at the
end of simulation:

```
pipeline-report:
  clocks:   101737
  running:  59862
  halted:   0
  flushed:  41875
  CPI:      1.70
```

---

## 4. `darksocv.v` — The SoC Top Level

**Location:** `rtl/darksocv.v`  
**Role:** The outermost module; wires together all sub-modules

This file is the "glue" — it has relatively little logic of its own, but it
instantiates and connects all the other modules.

### 4.1 Module Ports

```verilog
module darksocv (
    input        XCLK,      // 50 MHz external clock (from crystal)
    input        XRES,      // external reset (KEY[0] on DE2, active low)
    input        UART_RXD,  // UART receive pin
    output       UART_TXD,  // UART transmit pin
    output [31:0] LED,      // LED outputs
    input  [31:0] IPORT,    // general-purpose inputs (switches)
    output [31:0] OPORT,    // general-purpose outputs
    output [ 3:0] DEBUG     // debug pins (oscilloscope)
);
```

These are the FPGA pin-level signals. The `XCLK` input is 50 MHz from the
DE2's on-board oscillator; the PLL multiplies it to 100 MHz internally.

### 4.2 Clock and Reset Generation

```verilog
darkpll darkpll0 (
    .XCLK(XCLK),   // 50 MHz in
    .XRES(XRES),   // external reset
    .CLK(CLK),     // 100 MHz out
    .RES(RES)      // synchronised reset out
);
```

The PLL converts 50 MHz to 100 MHz and synchronises the reset signal. In
simulation (no real PLL), this is replaced by a simple clock toggle in the
testbench (`darksimv.v`).

### 4.3 The Bus Bridge and CPU Instantiation

```verilog
darkbridge darkbridge0 (
    .CLK(CLK), .RES(RES),
    // External (X-BUS) side
    .XIREQ(XIREQ), .XADDR(XADDR), .XATAI(XXATAI), .XDREQ(XDREQ),
    .XDATAO(XDATAO), .XDATAI(XXDATAI), .XDACK(XXDACK), ...
    // CPU (I-BUS + D-BUS) side — these connect to darkriscv internally
    ...
);
```

`darkbridge.v` internally instantiates `darkriscv.v`. From `darksocv.v`'s
perspective, the bridge is a black box with a CPU inside; it presents a single
unified external bus (X-BUS) to the rest of the SoC.

### 4.4 Address Decoder

The address decoder is the routing logic that directs each bus transaction to
the correct peripheral:

```verilog
wire XDREQMUX [3:0];   // one request line per peripheral

assign XDREQMUX[0] = XDREQ && (XADDR[31:30] == 2'b00);  // BRAM
assign XDREQMUX[1] = XDREQ && (XADDR[31:30] == 2'b01);  // DarkIO
assign XDREQMUX[2] = XDREQ && (XADDR[31:30] == 2'b10);  // SDRAM
assign XDREQMUX[3] = XDREQ && (XADDR[31:30] == 2'b11);  // unused
```

The response multiplexer selects which peripheral's data to return:

```verilog
assign XXDATAI = XDACKMUX[0] ? XATAIMUX[0] :   // data from BRAM
                 XDACKMUX[1] ? XATAIMUX[1] :   // data from DarkIO
                 XDACKMUX[2] ? XATAIMUX[2] :   // data from SDRAM
                               32'h00000000;    // default (unused)

assign XXDACK  = |XDACKMUX;   // transaction complete when any peripheral acks
```

---

## 5. `darkbridge.v` — Bus Bridge

**Location:** `rtl/darkbridge.v`  
**Instantiated by:** `darksocv.v`  
**Internally instantiates:** `darkriscv.v`, `darkcache.v` (×2)

DarkBridge solves the impedance mismatch between the CPU (two independent buses)
and the SoC memory system (one shared bus).

### 5.1 Harvard Mode (default)

In Harvard mode, the instruction bus (`IADDR`/`IDATA`) maps directly to Port A
of DarkRAM, while the data bus (`DADDR`/`DATAO`/`DATAI`) maps to the X-BUS.
The key point: both ports of DarkRAM can be active **simultaneously**, so
instruction fetches and data accesses never conflict.

```
CPU I-BUS  ──────────────────────────────────────→  BRAM Port A
CPU D-BUS  ──→  Address Decoder  ──→  BRAM Port B  (or DarkIO, SDRAM)
```

### 5.2 Von Neumann Mode

When `__HARVARD__` is not defined, a single physical port must serve both
buses. DarkBridge implements a priority scheme: data requests take priority
over instruction fetches (since load/store results are needed immediately;
instruction fetches can tolerate one cycle of extra latency).

```
CPU I-BUS ─┐
           ├→  Multiplexer  ──→  X-BUS  ──→  BRAM / DarkIO / SDRAM
CPU D-BUS ─┘
```

When a data request wins the arbitration, an instruction stall (`HLT`) is
asserted to the CPU until the data transaction completes.

---

## 6. `darkram.v` — Block RAM

**Location:** `rtl/darkram.v`  
**Instantiated by:** `darksocv.v`

### 6.1 Memory Organisation

```verilog
reg [31:0] MEM [0:(2**`MLEN)/4 - 1];  // word-addressed array
```

The memory is declared as an array of 32-bit words. The number of entries is
\(2^{\text{MLEN}} / 4\) because each entry is 4 bytes.

At simulation startup:

```verilog
initial $readmemh("../src/darksocv.mem", MEM);
```

This Verilog system task loads the compiled firmware (in hexadecimal format)
into the `MEM` array. Each line of `darksocv.mem` contains one 32-bit word in
hexadecimal, corresponding to four bytes of the firmware binary.

### 6.2 Dual-Port Behaviour

Port A (instruction port) — always reads, never writes:

```verilog
// Port A: synchronous read (result available next cycle)
always @(posedge CLK) begin
    IDATA_reg <= MEM[IADDR[`MLEN-1:2]];  // word-addressed
end
```

Port B (data port) — reads and writes with byte enable:

```verilog
// Port B: write with byte enables
always @(posedge CLK) begin
    if (DWR) begin
        if (DBE[3]) MEM[DADDR[`MLEN-1:2]][31:24] <= DATAO[31:24];
        if (DBE[2]) MEM[DADDR[`MLEN-1:2]][23:16] <= DATAO[23:16];
        if (DBE[1]) MEM[DADDR[`MLEN-1:2]][15: 8] <= DATAO[15: 8];
        if (DBE[0]) MEM[DADDR[`MLEN-1:2]][ 7: 0] <= DATAO[ 7: 0];
    end
end

// Port B: read
always @(posedge CLK) begin
    if (DRD) DATAI_reg <= MEM[DADDR[`MLEN-1:2]];
end
```

The `[`MLEN-1:2]` indexing converts a byte address to a word address by
dropping the bottom 2 bits (equivalent to dividing by 4).

---

## 7. `darkio.v` — I/O Controller

**Location:** `rtl/darkio.v`  
**Instantiated by:** `darksocv.v`

DarkIO is an 8-register memory-mapped peripheral. It decodes the lower address
bits to select which register to access:

```verilog
// Register selection: bits [4:2] of the address
wire [2:0] IOSEL = XADDR[4:2];

always @(posedge CLK) begin
    case (IOSEL)
        3'd0: XDATAI <= { IRQ_FLAGS, CORE_ID, CLOCK_MHZ, BOARD_ID };
        3'd1: XDATAI <= UART_DATA;     // UART status + received byte
        3'd2: XDATAI <= LED_REG;       // LED register (readback)
        3'd3: XDATAI <= TIMER_REG;     // timer reload value
        3'd4: XDATAI <= TIMEUS;        // microsecond counter
        3'd5: XDATAI <= IPORT;         // general-purpose inputs
        3'd6: XDATAI <= OPORT_REG;     // general-purpose outputs
        3'd7: XDATAI <= SPI_DATA;      // SPI register (optional)
    endcase
end
```

Write handling follows the same pattern but updates internal registers instead
of reading them.

### 7.1 The Timer

```verilog
reg [31:0] TIMER   = 0;    // current countdown value
reg [31:0] TRELOAD = 0;    // reload value (set by firmware)

always @(posedge CLK) begin
    if (TIMER == 0) begin
        TIMER   <= TRELOAD;        // reload
        IREQ[7] <= 1;              // set interrupt flag
    end else begin
        TIMER   <= TIMER - 1;      // count down
        IREQ[7] <= 0;
    end
end
```

Every time `TIMER` reaches zero, it reloads from `TRELOAD` and pulses
`IREQ[7]`. The CPU (if interrupts are enabled) detects this and jumps to the
interrupt handler.

### 7.2 The Microsecond Counter

```verilog
reg [31:0] TIMEUS = 0;
reg [6:0]  USCLK  = 0;     // counts clock cycles within each microsecond

always @(posedge CLK) begin
    if (USCLK == (BOARD_CK/1000000 - 1)) begin
        USCLK  <= 0;
        TIMEUS <= TIMEUS + 1;   // increment once per microsecond
    end else begin
        USCLK <= USCLK + 1;
    end
end
```

At 100 MHz, `BOARD_CK/1000000 = 100`, so `USCLK` counts from 0 to 99 (100
clock cycles = 1 µs), then increments `TIMEUS`.

---

## 8. `darkuart.v` — Serial Port

**Location:** `rtl/darkuart.v`  
**Instantiated by:** `darkio.v`

### 8.1 UART Transmitter

The transmitter is a **shift register** that serialises parallel data:

```verilog
reg [9:0] TXSR = 0;   // shift register: [start + 8 data + stop]
reg [9:0] TXDIV;      // baud rate counter

always @(posedge CLK) begin
    if (TXDIV == 0) begin
        TXSR  <= { 1'b1, TXSR[9:1] };    // shift right: output LSB first
        TXDIV <= `__BAUD__;               // reload baud divisor
    end else begin
        TXDIV <= TXDIV - 1;
    end
    TXD <= TXSR[0];                       // output current bit
end
```

In simulation, the transmitter is replaced by:

```verilog
`ifdef SIMULATION
    always @(posedge CLK) begin
        if (TXWR) $write("%c", TXDATA);   // print character directly
        if (TXDATA == ">") ESIMREQ <= 1; // trigger simulation end
    end
`endif
```

### 8.2 UART Receiver

The receiver samples the incoming `RXD` line at the centre of each bit period
(offset by half a bit period from the start bit edge, to maximise noise margin):

```verilog
reg [3:0] RXDIV;    // counts half-bit periods to find centre
reg [8:0] RXSR;     // receive shift register

always @(posedge CLK) begin
    if (!RXD_SYNC && !RXBUSY) begin
        RXBUSY <= 1;           // start bit detected (RXD went low)
        RXDIV  <= `__BAUD__ / 2;  // wait half a bit period
    end else if (RXBUSY) begin
        if (RXDIV == 0) begin
            RXSR  <= { RXD_SYNC, RXSR[8:1] };  // sample and shift
            RXCNT <= RXCNT + 1;
            RXDIV <= `__BAUD__;
            if (RXCNT == 8) begin  // all 8 data bits received
                RXDATA  <= RXSR[8:1];
                RXBUSY  <= 0;
                RXIRQ   <= 1;      // notify firmware: new byte available
            end
        end else RXDIV <= RXDIV - 1;
    end
end
```

---

## 9. `darkcache.v` — L1 Cache

**Location:** `rtl/darkcache.v`  
**Instantiated by:** `darkbridge.v` (optional, controlled by `__ICACHE__`/`__DCACHE__`)

### 9.1 Direct-Mapped Cache Structure

```verilog
parameter DEPTH = `__CDEPTH__;    // cache depth: 2^DEPTH entries

reg [31:0]           CDATA [0:(2**DEPTH)-1];  // cached data
reg [31-DEPTH-2:0]   CTAG  [0:(2**DEPTH)-1];  // address tags
reg                  CVALID[0:(2**DEPTH)-1];  // valid flags
```

Each entry stores:
- `CDATA`: the 32-bit data word
- `CTAG`: the upper address bits that identify which memory location is cached
- `CVALID`: whether this entry contains valid data

### 9.2 Hit/Miss Detection

```verilog
wire [DEPTH-1:0] CIDX = ADDR[DEPTH+1:2];   // cache index (lower bits)
wire [31-DEPTH-2:0] CTAG_IN = ADDR[31:DEPTH+2];  // tag (upper bits)

wire CHIT = CVALID[CIDX] && (CTAG[CIDX] == CTAG_IN);
```

On every request:
- **Hit** (`CHIT = 1`): return `CDATA[CIDX]` immediately; no memory access
- **Miss** (`CHIT = 0`): forward to memory, store the response in the cache,
  assert `HLT` for the required number of wait cycles

---

## 10. `darkpll.v` — Clock Generator

**Location:** `rtl/darkpll.v`  
**Instantiated by:** `darksocv.v`

`darkpll.v` is a thin wrapper around the FPGA vendor's PLL primitive. For the
DE2 (Cyclone II / Altera), it instantiates the `altpll` megafunction:

```verilog
altpll altpll0 (
    .inclk0(XCLK),    // 50 MHz reference
    .c0(CLK),         // 100 MHz output
    .locked(LOCKED)
);
```

The PLL also generates the synchronised reset: `RES` is held high until the
PLL achieves lock (`LOCKED` goes high) and a counter has expired (to allow
all flip-flops to reach their reset state).

In simulation, `darkpll.v` is bypassed: the testbench (`darksimv.v`) drives
`CLK` directly using a simple `always #5 XCLK = ~XCLK;` statement, generating
a 100 MHz clock with 5 ns half-period.

---

## 11. `darkmac.v` — Multiply-Accumulate Coprocessor

**Location:** `rtl/darkmac.v`  
**Instantiated by:** `darkbridge.v` (when `__COPROCESSOR__` and `__MAC16X16__` are defined)

The MAC unit adds a custom instruction to the ISA:

```
mac rd, rs1, rs2    →    rd = rd + (rs1[15:0] × rs2[15:0])
```

It uses the RISC-V **custom-0** opcode space (`7'b0001011`), which is reserved
by the specification for non-standard extensions without conflicting with any
standard instruction.

The implementation is purely combinational:

```verilog
wire [31:0] CPR_RDW = CPR_RDR + (CPR_RS1[15:0] * CPR_RS2[15:0]);
```

`CPR_RDR` is the current value of the destination register (fed back from the
CPU via the coprocessor port), and the result `CPR_RDW` is written back in
the same cycle. This makes the MAC instruction single-cycle, with no extra
latency over a standard ALU instruction.

---

## 12. Module Dependency Map

The following diagram shows which module instantiates which:

```
darksocv.v  (top-level SoC)
 │
 ├── darkpll.v        (clock: 50 MHz → 100 MHz, reset synchronisation)
 │
 ├── darkbridge.v     (bus bridge: I-BUS + D-BUS → X-BUS)
 │    ├── darkriscv.v (THE CPU: fetch, decode, execute)
 │    ├── darkcache.v (optional I$ instruction cache)
 │    ├── darkcache.v (optional D$ data cache)
 │    └── darkmac.v   (optional MAC coprocessor)
 │
 ├── darkram.v        (on-chip BRAM: dual-port, 8–32 KB)
 │
 ├── darkio.v         (I/O controller)
 │    ├── darkuart.v  (UART serial port: 115200 baud)
 │    └── darkspi.v   (optional SPI master)
 │
 └── mt48lc16m16a2_ctrl.v   (optional SDRAM controller)
```

Each `include "../rtl/config.vh"` at the top of every file ensures that all
modules share the same feature configuration.

---

## 13. Synthesis vs Simulation

The same Verilog source files serve two distinct purposes:

**Synthesis** (FPGA):
- Run through Quartus (Altera) or Vivado/ISE (Xilinx)
- Translates Verilog into FPGA primitives (LUTs, flip-flops, BRAM, PLL)
- Produces a bitstream (`.sof` or `.bit` file) to program the FPGA
- Real hardware: signals change at true 100 MHz

**Simulation** (PC):
- Run through Icarus Verilog (`iverilog`)
- Simulates the circuit behaviour in software
- `ifdef SIMULATION` blocks substitute simplified models for hardware
  primitives (PLL → simple toggle, UART TX → `$write`, BRAM → `$readmemh`)
- Produces a VCD waveform file for viewing in GTKWave

The `SIMULATION` macro (automatically set when `__ICARUS__` is detected) is
the mechanism that switches between these modes without any manual code changes.
