# The CPU Core — `darkriscv.v`

This document explains how the DarkRISCV processor works, step by step, for
readers who may not be familiar with CPU design. It complements the visual
explanation in [diagrams.md](diagrams.md) and the Verilog walkthrough in
[rtl-implementation.md](rtl-implementation.md).

---

## 1. What Is a CPU?

A CPU (Central Processing Unit) is the "brain" of a computer. It executes a
continuous loop:

1. **Fetch** — read the next instruction from memory
2. **Decode** — determine what the instruction means
3. **Execute** — perform the operation (arithmetic, memory access, jump…)
4. **Repeat** — update the program counter and go back to step 1

Every instruction is a **32-bit binary number** — a pattern of 32 zeros and
ones that encodes both what operation to perform and which data to use.
Instructions are stored in memory (in DarkRISCV, inside the Block RAM) and the
CPU reads them sequentially, one per fetch cycle, starting at address 0.

At 100 MHz, DarkRISCV can complete this loop approximately 60–70 million times
per second (accounting for overhead from branches and memory latency).

---

## 2. RISC-V and the RV32I Instruction Set

### 2.1 What Is RISC-V?

**RISC-V** (pronounced "risk five") is an open instruction set architecture
(ISA) — a publicly available specification that defines what binary patterns
correspond to what CPU operations. Unlike ARM or x86, RISC-V is unencumbered
by patents and royalties, so any engineer can implement it freely.

The name comes from:
- **RISC**: Reduced Instruction Set Computer — a design philosophy favouring a
  small number of simple, fast instructions over many complex ones
- **V**: the fifth RISC architecture developed at UC Berkeley

### 2.2 RV32I: The Base Integer ISA

DarkRISCV implements **RV32I** — the base 32-bit integer instruction set:
- **32-bit**: addresses and registers are 32 bits wide
- **I**: integer base — arithmetic, logic, loads, stores, and control flow

The full RV32I specification defines 47 instructions, grouped into 7 types
based on their encoding format. All instructions are exactly 32 bits long.

### 2.3 Instruction Categories

| Category | Mnemonic examples | What they do |
|---|---|---|
| Arithmetic | `ADD`, `SUB`, `AND`, `OR`, `XOR` | Integer math on two registers |
| Immediate arithmetic | `ADDI`, `ANDI`, `ORI`, `XORI` | Math with a constant embedded in the instruction |
| Shifts | `SLL`, `SRL`, `SRA`, `SLLI`, `SRLI`, `SRAI` | Bit shifts (left, right logical, right arithmetic) |
| Comparisons | `SLT`, `SLTU`, `SLTI`, `SLTIU` | Set register to 1 if less-than condition is true |
| Loads | `LW`, `LH`, `LB`, `LHU`, `LBU` | Copy data from memory into a register |
| Stores | `SW`, `SH`, `SB` | Copy a register's value into memory |
| Branches | `BEQ`, `BNE`, `BLT`, `BGE`, `BLTU`, `BGEU` | Conditional jumps based on register comparison |
| Jumps | `JAL`, `JALR` | Unconditional jumps (function calls and returns) |
| Upper immediate | `LUI`, `AUIPC` | Load large constants (upper 20 bits) into registers |
| System | `ECALL`, `EBREAK`, `CSR*` | Interact with the execution environment |

### 2.4 The Register File

The CPU has **32 general-purpose registers** (`x0` through `x31`), each 32
bits wide. By convention, registers are assigned roles:

| Registers | ABI Name | Role |
|---|---|---|
| `x0` | `zero` | Hardwired to 0; writes are discarded |
| `x1` | `ra` | Return address (written by `JAL`/`JALR`) |
| `x2` | `sp` | Stack pointer (initialised by `boot.S`) |
| `x5`–`x7` | `t0`–`t2` | Temporary registers (caller-saved) |
| `x8`–`x9` | `s0`–`s1` | Saved registers (callee-saved) |
| `x10`–`x17` | `a0`–`a7` | Function arguments and return values |
| `x18`–`x27` | `s2`–`s11` | Additional saved registers |
| `x28`–`x31` | `t3`–`t6` | Additional temporaries |

When `__RV32E__` is defined (Embedded profile), only `x0`–`x15` exist.

**The hardwired-zero property of `x0`:** This register always reads as 0 and
ignores writes. This eliminates the need for a dedicated "move to zero"
instruction; `AND x5, x5, x0` effectively zeroes `x5`, and
`BEQ x5, x0, label` branches if `x5 == 0`.

---

## 3. Instruction Encoding: How 32 Bits Encode an Operation

### 3.1 The Six Instruction Formats

RISC-V uses six canonical instruction formats, each placing the opcode,
register numbers, and immediate value in fixed positions:

```
R-type (register-to-register):
  [31:25] funct7 | [24:20] rs2 | [19:15] rs1 | [14:12] funct3 | [11:7] rd | [6:0] opcode

I-type (immediate):
  [31:20] imm[11:0]  | [19:15] rs1 | [14:12] funct3 | [11:7] rd | [6:0] opcode

S-type (store):
  [31:25] imm[11:5] | [24:20] rs2 | [19:15] rs1 | [14:12] funct3 | [11:7] imm[4:0] | [6:0] opcode

B-type (branch):
  [31] imm[12] | [30:25] imm[10:5] | [24:20] rs2 | [19:15] rs1 | [14:12] funct3 | [11:8] imm[4:1] | [7] imm[11] | [6:0] opcode

U-type (upper immediate):
  [31:12] imm[31:12] | [11:7] rd | [6:0] opcode

J-type (jump):
  [31] imm[20] | [30:21] imm[10:1] | [20] imm[11] | [19:12] imm[19:12] | [11:7] rd | [6:0] opcode
```

The scrambled bit ordering of branch and jump immediates is intentional: it
maximises the overlap between formats so that the hardware to extract `rs1`,
`rs2`, and `rd` is shared across formats, minimising total logic.

### 3.2 Worked Example: Decoding `ADD x5, x3, x4`

`ADD` is an R-type instruction:
- opcode = `0110011` (RCC)
- funct3 = `000`
- funct7 = `0000000`
- rd = `00101` (x5)
- rs1 = `00011` (x3)
- rs2 = `00100` (x4)

Assembled into 32 bits:
```
0000000  00100  00011  000  00101  0110011
funct7   rs2    rs1   f3    rd    opcode
= 0x00418133
```

When the CPU decodes `0x00418133`, it extracts all these fields, reads the
values of `x3` and `x4`, adds them, and writes the result to `x5`.

---

## 4. The 3-Stage Pipeline

### 4.1 Why Pipelines?

A non-pipelined (sequential) processor would:
1. Complete Fetch fully
2. Then complete Decode fully
3. Then complete Execute fully
4. Then start over

This wastes the Fetch and Decode hardware during step 3 (they sit idle while
Execute runs). A **pipelined** processor keeps all stages busy simultaneously:

```
Clock:    1    2    3    4    5    6    7
Fetch:   I1   I2   I3   I4   I5   I6   I7
Decode:       I1   I2   I3   I4   I5   I6
Execute:           I1   I2   I3   I4   I5
```

In steady state, one instruction completes per clock cycle — a 3× throughput
improvement over sequential execution (for a 3-stage pipeline).

### 4.2 Stage 1 — Instruction Fetch (IF)

```verilog
assign IADDR = IFPC;   // drive the instruction address onto the bus
// IDATA returns the 32-bit instruction from memory (next clock)
```

The **Program Counter** (`IFPC`) holds the byte address of the next instruction.
It is sent to memory via the instruction bus. Memory returns the 32-bit
instruction word, which is captured into the `IDATAX` pipeline register on
the next rising clock edge.

Under normal operation, `IFPC` advances by 4 each clock:
```verilog
IFPC <= IFPC + 4;   // each instruction is 4 bytes
```

On a taken branch or jump, `IFPC` loads the target address instead:
```verilog
IFPC <= JADDR;   // JADDR = branch target or jump target
```

### 4.3 Stage 2 — Instruction Decode (ID)

The 32-bit instruction word captured in `IDATAX` is split into its fields:

```
Bits [6:0]   → opcode   → decoded into one-hot signals (XLUI, XJAL, XBCC…)
Bits [11:7]  → rd       → destination register number (0–31)
Bits [14:12] → funct3   → instruction sub-type
Bits [19:15] → rs1      → source register 1 number
Bits [24:20] → rs2      → source register 2 number
Bits [31:25] → funct7   → further qualification (e.g., SUB vs ADD)
```

Simultaneously, the register file is read:
- `U1REG` ← value of register `rs1`
- `U2REG` ← value of register `rs2`

And the immediate value is sign-extended from whichever bit fields are relevant
to the instruction format (I/S/B/U/J).

All of this happens **combinationally** — no clock edge is required between
`IDATAX` being valid and the decoded fields being available.

At the end of this stage, decoded fields are captured in the ID pipeline
register (`XIMM`, `XRD`, `XRS1`, `XRS2`, one-hot signals) on the rising clock
edge.

### 4.4 Stage 3 — Execute (EX)

The Execute stage performs the actual work. The four ALUs compute in parallel:

```
ALU 1: RMDATA = rs1 OP rs2  (or rs1 OP imm)   → write to rd
ALU 2: BMUX   = (rs1 CMP rs2)                  → decide if branch is taken
ALU 3: JADDR  = next PC value                  → feed back to IFPC
ALU 4: DADDR  = rs1 + imm                      → memory address for LD/ST
```

For a load instruction (`LW`, `LH`, `LB`), the result depends on data returned
from memory, which is not available until one clock later. This introduces a
**1-cycle stall** (`HLT = 1`) after every load — the pipeline freezes until
BRAM returns the data.

---

## 5. Pipeline Flush — The Cost of Branches

### 5.1 The Problem

In the 3-stage pipeline, when the CPU is executing instruction N (a branch)
in stage 3, instructions N+1 and N+2 are already in stages 2 and 1
respectively:

```
Clock k:   [N+2 in Fetch]  [N+1 in Decode]  [N in Execute ← branch detected here]
```

If the branch is taken, instructions N+1 and N+2 should **not** execute —
they are on the wrong path. But they are already part-way through the pipeline.

### 5.2 The Solution: Pipeline Flush

```verilog
reg [1:0] FLUSH = 0;

always @(posedge CLK) begin
    if (!HLT) FLUSH <= JREQ ? 2 : FLUSH ? FLUSH - 1 : 0;
end
```

When `JREQ` (jump/branch taken) is asserted:
1. `FLUSH` is set to 2
2. For the next 2 clock cycles, the outputs of the Fetch and Decode stages are
   replaced with `NOP` instructions (`ADDI x0, x0, 0` = `0x00000013`)
3. The correct instruction at the branch target enters Fetch as `FLUSH` counts
   down to 0

This costs **2 cycles per taken branch** — the principal overhead in the
3-stage pipeline.

### 5.3 Impact on IPC

Empirically, DarkRISCV achieves approximately CPI = 1.7 (IPC ≈ 0.6) for
typical C firmware. The breakdown:

```
pipeline-report:
  clocks:   101737   (total simulation cycles)
  running:  59862    (instructions completing = 59862 instructions)
  halted:   0        (wait states from memory = 0 cycles in Harvard mode)
  flushed:  41875    (cycles wasted on branch penalties)
  CPI:      1.70     (101737 / 59862 ≈ 1.70)
```

The 41875 flushed cycles arise from the ~37% of instructions that are branches
or jumps in typical code (function calls, loops, if/else blocks).

---

## 6. Memory Interface

### 6.1 Two Buses

DarkRISCV exports two fully independent buses:

**Instruction bus (I-bus):**
- `IADDR [31:0]` — the address to fetch from
- `IDATA [31:0]` — the instruction word returned
- `IDREQ` — request asserted (CPU wants to fetch)
- `IDACK` — acknowledge from memory (data is valid)
- Always read-only

**Data bus (D-bus):**
- `DADDR [31:0]` — the load/store address (= rs1 + immediate)
- `DATAO [31:0]` — data to write (for stores)
- `DATAI [31:0]` — data read back (for loads)
- `DBE [3:0]` — byte enable (which of the 4 bytes to access)
- `DRD` — data read request (load)
- `DWR` — data write request (store)
- `DDREQ` — request asserted
- `DDACK` — acknowledge from memory

### 6.2 Byte Enables

RISC-V supports accessing memory in three widths:

| Instruction | Width | `DBE` |
|---|---|---|
| `LW` / `SW` | 32 bits (4 bytes) | `4'b1111` |
| `LH` / `SH` | 16 bits (2 bytes) | `4'b0011` or `4'b1100` |
| `LB` / `SB` | 8 bits (1 byte) | `4'b0001`, `4'b0010`, `4'b0100`, or `4'b1000` |

The specific `DBE` pattern depends on `DADDR[1:0]` (the byte alignment within
the 32-bit word). For example, `SB` at address 5 (`DADDR[1:0] = 01`) uses
`DBE = 4'b0010` — only byte lane 1 of the word at address 4 is written.

### 6.3 Load Data Sign Extension

After a load, the CPU must extract the correct bytes from the 32-bit word and
sign-extend them:

| Instruction | Operation | Example (`DATAI = 0x12345678`) |
|---|---|---|
| `LW` | all 32 bits | result = `0x12345678` |
| `LH` at byte 0 | lower 16 bits, sign-extend | result = `0x00005678` |
| `LH` at byte 2 | upper 16 bits, sign-extend | result = `0x00001234` |
| `LBU` at byte 0 | lower 8 bits, zero-extend | result = `0x00000078` |
| `LB` at byte 0 | lower 8 bits, sign-extend | result = `0x00000078` (positive) |
| `LB` at byte 1 | second byte, sign-extend | result = `0x00000056` |

The `{sign{msb}, data}` Verilog pattern handles sign extension:
`{24{DATAI[7]}, DATAI[7:0]}` replicates the MSB of the byte 24 times to fill
the upper 24 bits.

---

## 7. Control and Status Registers (CSRs)

When `__CSR__` is enabled in `config.vh`, the CPU supports a set of special
registers accessed via `CSRRW`, `CSRRS`, and `CSRRC` instructions.

### 7.1 Machine-Level CSRs

| CSR name | Address | Purpose |
|---|---|---|
| `mstatus` | `0x300` | Machine status: global interrupt enable (`mstatus[3]` = MIE) |
| `mie` | `0x304` | Machine interrupt enable: which interrupt sources are enabled |
| `mtvec` | `0x305` | Machine trap vector: jump address on interrupt |
| `mepc` | `0x341` | Machine exception PC: return address saved on interrupt |
| `mcause` | `0x342` | Machine cause: reason for the last exception |
| `mip` | `0x344` | Machine interrupt pending: which interrupts are currently pending |
| `mcycle` | `0xC00` | Cycle counter (lower 32 bits of a 64-bit counter) |
| `minstret` | `0xC02` | Instructions-retired counter (lower 32 bits) |

### 7.2 CSR Instructions

| Instruction | Effect |
|---|---|
| `CSRRW rd, csr, rs1` | rd = CSR; CSR = rs1 (atomic read-write) |
| `CSRRS rd, csr, rs1` | rd = CSR; CSR = CSR OR rs1 (set bits) |
| `CSRRC rd, csr, rs1` | rd = CSR; CSR = CSR AND NOT rs1 (clear bits) |

These instructions enable firmware to:
- Read the cycle counter for benchmarking (`CSRRW a0, mcycle, x0`)
- Set the interrupt handler address (`CSRRW x0, mtvec, a0`)
- Enable/disable interrupts (`CSRRS x0, mstatus, MIE_BIT`)

---

## 8. Interrupt Handling

When `__INTERRUPT__` is enabled:

### 8.1 Interrupt Entry

An external `IRQ` pulse triggers the following sequence (if
`mstatus[3]` = 1 and `mie[11]` = 1):

1. The CPU saves the current `IFPC` (the instruction that would have executed
   next) into `mepc`
2. `mstatus[3]` is cleared to 0 (prevents nested interrupts)
3. `IFPC` is loaded with the value of `mtvec` (the interrupt handler address)
4. The pipeline is flushed (FLUSH = 2)

The interrupt handler can now run at address `mtvec`. It should save any
registers it modifies and call `MRET` when done.

### 8.2 Interrupt Return (`MRET`)

The `MRET` instruction reverses the entry sequence:

1. `IFPC` is loaded from `mepc` (returning to the interrupted instruction)
2. `mstatus[3]` is restored to 1 (re-enabling interrupts)
3. The pipeline is flushed

This mechanism is used by the DarkRISCV timer interrupt to implement a simple
1 kHz periodic task (e.g., toggling the OPORT register).

---

## 9. Optional Extensions

### 9.1 M-Extension (Hardware Multiply)

When `__MEXT__` is enabled, the CPU can execute `MUL`, `MULH`, `MULHSU`, and
`MULHU` instructions (the signed and unsigned variants of 32×32 multiplication).
Division and remainder (`DIV`, `REM`) are not implemented in hardware; they are
emulated in software via the `darklibc` math library.

Without hardware multiply:
- `a * b` compiles to a software loop calling `__mulsi3` from `darklibc`
- Each 32×32 multiply takes dozens of instructions

With `__MEXT__`:
- `MUL a0, a1, a2` produces the lower 32 bits in a single clock cycle

### 9.2 Multi-Threading

When `__THREADS__ N` is defined, the CPU maintains \(2^N\) thread contexts
(register files and program counters). The hardware switches between threads
every time a jump instruction occurs — specifically, every time the pipeline
would otherwise be flushed.

This transforms wasted flush cycles into useful work for another thread. The
overhead is minimal: the thread pointer requires just `N` additional bits, and
the register file grows by a factor of \(2^N\). At `N = 1` (2 threads), the
register file doubles in size, requiring roughly 20% more FPGA resources for
the CPU core.

Thread switching rate is directly tied to jump frequency. In code with many
function calls and loops, threads can switch millions of times per second.

### 9.3 DBNZ — Decrement and Branch if Not Zero

When `__DBNZ__` is enabled, a custom loop instruction is added:

```
DBNZ rd, rs1, offset    →    rd = rs1 - 1; if (rd != 0) PC = PC + offset
```

Unlike a branch, DBNZ is **non-flushing** — the 2 instructions following the
DBNZ act as **delay slots** and execute before the branch takes effect. This
is borrowed from MIPS and DSP architectures; it allows the loop body to
contribute 2 more instructions "for free" every iteration.

---

## 10. Simulation-Only Features

### 10.1 Performance Meter

When `__PERFMETER__` is defined, the CPU counts clock cycles into four
categories and prints a report at simulation end:

```
pipeline-report:
  clocks:   101737   (total clock cycles)
  running:  59862    (instructions completing)
  halted:   0        (stall cycles — 0 in Harvard mode)
  flushed:  41875    (branch penalty cycles)
  CPI:      1.70     (clocks / running)
```

### 10.2 Instruction Trace

When `__TRACE__` is defined, every instruction execution is logged with its
timestamp, PC, and instruction word to `sim/darksocv.txt`:

```
100ns: [0] pc=00000000 inst=00004197
105ns: [0] pc=00000004 inst=04818193
110ns: [0] pc=00000008 inst=30519073
```

This is invaluable for debugging: comparing the trace from a known-good run
against a failing run immediately reveals where execution diverges.

### 10.3 End-of-Simulation

When the UART detects the `>` character (the shell prompt), it asserts
`ESIMREQ`. The CPU responds by printing the pipeline report and calling
`$finish()`. This prevents the simulation from running indefinitely.

---

## 11. Key Signal Reference

| Signal | Dir | Width | Stage | Description |
|---|---|---|---|---|
| `CLK` | in | 1 | — | 100 MHz system clock |
| `RES` | in | 1 | — | Synchronous reset (active high) |
| `IFPC` | internal | 32 | IF | Instruction Fetch Program Counter |
| `IADDR` | out | 32 | IF | Instruction address sent to memory |
| `IDATA` | in | 32 | IF | Instruction word returned from memory |
| `IDATAX` | internal | 32 | ID | Pipeline register: instruction in Decode stage |
| `XSIMM` | internal | 32 | ID | Sign-extended immediate value |
| `U1REG` | internal | 32 | ID/EX | Value of source register `rs1` |
| `U2REG` | internal | 32 | ID/EX | Value of source register `rs2` |
| `RMDATA` | internal | 32 | EX | ALU result (arithmetic/logic) |
| `BMUX` | internal | 1 | EX | Branch condition result |
| `JADDR` | internal | 32 | EX | Next PC (branch target or PC+4) |
| `DADDR` | out | 32 | EX | Memory address for load/store |
| `DATAO` | out | 32 | EX | Data to write (store) |
| `DATAI` | in | 32 | EX | Data read from memory (load) |
| `DBE` | out | 4 | EX | Byte enable for memory access |
| `DRD` | out | 1 | EX | Data read request |
| `DWR` | out | 1 | EX | Data write request |
| `HLT` | internal | 1 | — | Pipeline stall (memory not ready) |
| `FLUSH` | internal | 2 | — | Pipeline flush counter (0 = running) |
| `JREQ` | internal | 1 | EX | Jump/branch taken this cycle |
