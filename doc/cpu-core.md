# The CPU Core — darkriscv.v

This document explains how the DarkRISCV processor works, step by step,
for readers who may not be familiar with CPU design.

---

## What Is a CPU?

A CPU (Central Processing Unit) is the "brain" of a computer. It does three
things over and over, billions of times per second:

1. **Fetch** — read the next instruction from memory
2. **Decode** — figure out what the instruction means
3. **Execute** — carry out the operation (add, subtract, load, store, jump…)

Each instruction is a 32-bit binary number. The CPU reads these numbers one
after another from memory, starting at address 0.

---

## RISC-V and RV32I

**RISC-V** is an open-standard instruction set — a public "language" that
defines what binary numbers mean what operations. DarkRISCV implements the
**RV32I** base variant:

- **RV** = RISC-V
- **32** = 32-bit addresses and registers
- **I** = Integer base instructions only

The RV32I instruction set includes:

| Category | Examples | What they do |
|---|---|---|
| Arithmetic | `ADD`, `SUB`, `AND`, `OR`, `XOR` | Math and logic on two registers |
| Immediate | `ADDI`, `ANDI`, `ORI` | Math with a constant embedded in the instruction |
| Load/Store | `LW`, `SW`, `LB`, `SB` | Move data between registers and memory |
| Branch | `BEQ`, `BNE`, `BLT`, `BGE` | If condition is true, jump to a different address |
| Jump | `JAL`, `JALR` | Unconditional jump (function call / return) |
| Upper immediate | `LUI`, `AUIPC` | Load large constants into registers |
| System | `ECALL`, `EBREAK`, `CSR*` | Interact with the operating environment |

The CPU has **32 general-purpose registers** (`x0`–`x31`), each 32 bits wide.
Register `x0` is hardwired to zero — reading it always gives 0, writing to it
does nothing.

---

## Pipeline: How Instructions Flow

DarkRISCV uses a **3-stage pipeline** (configured by `__3STAGE__` in config.vh).
Think of it like a 3-person assembly line:

```
Clock 1:  [FETCH instr1] [           ] [           ]
Clock 2:  [FETCH instr2] [DECODE instr1] [           ]
Clock 3:  [FETCH instr3] [DECODE instr2] [EXECUTE instr1]  ← instr1 result ready
Clock 4:  [FETCH instr4] [DECODE instr3] [EXECUTE instr2]  ← instr2 result ready
  ...
```

### Stage 1 — Instruction Fetch (IF)

```verilog
assign IADDR = IFPC;   // send PC to memory
// memory returns IDATA (the 32-bit instruction)
```

The **program counter** (`IFPC`) holds the address of the next instruction.
It sends this address to memory, which returns the 32-bit instruction word.
Normally, `IFPC` increments by 4 each clock (each instruction is 4 bytes).

### Stage 2 — Instruction Decode (ID)

The 32-bit instruction is split apart according to the RISC-V specification:

```
Bits [6:0]    → opcode   (what kind of instruction?)
Bits [11:7]   → rd       (destination register number)
Bits [14:12]  → funct3   (sub-type of instruction)
Bits [19:15]  → rs1      (source register 1 number)
Bits [24:20]  → rs2      (source register 2 number)
Bits [31:25]  → funct7   (further sub-type)
```

The decoder also extracts the **immediate value** — a constant number embedded
inside the instruction. RISC-V encodes immediates differently depending on the
instruction type (I-type, S-type, B-type, U-type, J-type), so the decoder
rearranges the bits and sign-extends them.

In the code, `XSIMM` is the sign-extended immediate and `XUIMM` is the
unsigned version. The opcode is decoded into one-hot signals:

```verilog
XLUI   <= IDATAX[6:0] == 7'b0110111;   // Load Upper Immediate
XJAL   <= IDATAX[6:0] == 7'b1101111;   // Jump And Link
XBCC   <= IDATAX[6:0] == 7'b1100011;   // Branch Conditional
XLCC   <= IDATAX[6:0] == 7'b0000011;   // Load from memory
XSCC   <= IDATAX[6:0] == 7'b0100011;   // Store to memory
XMCC   <= IDATAX[6:0] == 7'b0010011;   // ALU with immediate
XRCC   <= IDATAX[6:0] == 7'b0110011;   // ALU register-to-register
```

### Stage 3 — Execute (EX)

This is where the actual work happens. The main components are:

#### The ALU (Arithmetic Logic Unit)

The ALU is a single combinational expression that selects the operation based
on `funct3`:

```verilog
wire [31:0] RMDATA =
    FCT3==7 ? U1REG & S2REGX :        // AND
    FCT3==6 ? U1REG | S2REGX :        // OR
    FCT3==4 ? U1REG ^ S2REGX :        // XOR
    FCT3==3 ? U1REG < U2REGX :        // Set Less Than (unsigned)
    FCT3==2 ? S1REG < S2REGX :        // Set Less Than (signed)
    FCT3==0 ? (XRCC && FCT7[5] ?
               U1REG - S2REGX :       // SUB  (when funct7 bit 5 = 1)
               U1REG + S2REGX) :      // ADD  (when funct7 bit 5 = 0)
    FCT3==1 ? S1REG << U2REGX[4:0] :  // Shift Left
              FCT7[5] ?
               S1REG >>> U2REGX[4:0]: // Shift Right Arithmetic
               S1REG >>  U2REGX[4:0]; // Shift Right Logical
```

`U1REG` and `U2REG` are the values read from the register file (source
registers rs1 and rs2). `S2REGX` is either rs2 (for register-register ops)
or the immediate value (for register-immediate ops).

#### The Branch Unit

For conditional branches, the branch unit compares two registers:

```verilog
wire BMUX =
    FCT3==0 && U1REG == U2REGX ||  // BEQ  (branch if equal)
    FCT3==1 && U1REG != U2REGX ||  // BNE  (branch if not equal)
    FCT3==4 && S1REG <  S2REGX ||  // BLT  (branch if less than, signed)
    FCT3==5 && S1REG >= S2REG  ||  // BGE  (branch if greater or equal, signed)
    FCT3==6 && U1REG <  U2REGX ||  // BLTU (unsigned)
    FCT3==7 && U1REG >= U2REG;     // BGEU (unsigned)
```

If `BMUX` is true and the instruction is a branch, the pipeline jumps to the
target address (`PC + immediate`).

#### Register Write-Back

At the end of the execute stage, the result is written into the destination
register. The source of the result depends on the instruction type:

```verilog
REGS[DPTR] <=
    LCC          ? LDATA :     // Load: data from memory
    AUIPC        ? PC + SIMM : // AUIPC: PC + upper immediate
    JAL || JALR  ? IDPC :      // Jump: save return address
    LUI          ? SIMM :      // LUI: the immediate itself
    MCC || RCC   ? RMDATA :    // ALU result
    CSRX         ? CRDATA :    // CSR read
                   DREG;       // Default: keep current value
```

---

## Pipeline Flush (the penalty for jumping)

When the CPU takes a branch or jump, the instructions already in the pipeline
(fetched after the branch) are wrong — they came from the "not taken" path.
The CPU must **flush** the pipeline: discard those instructions and re-fetch
from the new address.

```verilog
FLUSH <= JREQ ? 2 : 0;  // flush 2 stages when a jump is taken
```

In a 3-stage pipeline, a flush costs **2 clock cycles**. This is why the
simulation reports a CPI (Clocks Per Instruction) of about 1.7 instead of the
ideal 1.0 — roughly 37% of cycles are wasted on flushes.

---

## Pipeline Stall (waiting for memory)

When the CPU reads from or writes to memory, the memory may not respond
immediately. The `HLT` (halt) signal freezes the entire pipeline until the
memory acknowledges:

```verilog
wire HLT = (DDREQ ? !DDACK : 0) ||   // data bus request pending
           (IDREQ ? !IDACK : 0);      // instruction bus request pending
```

When `HLT` is high, no register is updated, no PC changes — everything waits.

---

## Memory Interface

The CPU has two buses:

- **Instruction bus** (I-bus): `IADDR` → memory → `IDATA`
  - Read-only, fetches one 32-bit instruction per cycle
- **Data bus** (D-bus): `DADDR`, `DATAO` ↔ `DATAI`
  - Read/write, supports byte (8-bit), halfword (16-bit), and word (32-bit)
  - Byte enable signals (`DBE`) select which bytes within a 32-bit word

The data address is always computed as: `DADDR = rs1 + immediate`

---

## Load and Store: Byte/Halfword/Word

RISC-V supports accessing memory in different widths. The `LDATA` logic
extracts the correct bytes from the 32-bit memory word and sign-extends them:

- `LB` / `LBU`: load 1 byte (signed / unsigned)
- `LH` / `LHU`: load 2 bytes
- `LW`: load full 4-byte word

For stores, `SDATA` places the register value into the correct byte lanes,
and `DBE` (Data Byte Enable) tells the memory which bytes to actually write.

---

## CSR Registers (Control and Status)

When `__CSR__` is enabled, the CPU supports special registers for system
control:

| CSR | Address | Purpose |
|---|---|---|
| `mstatus` | 0x300 | Machine status (interrupt enable bits) |
| `mtvec` | 0x305 | Trap vector — where to jump on interrupt |
| `mepc` | 0x341 | Exception PC — return address after interrupt |
| `mcause` | 0x342 | Cause of the last exception |
| `mie` | 0x304 | Interrupt enable mask |
| `mip` | 0x344 | Interrupt pending flags |
| `mcycle` | 0xC00 | Clock cycle counter (64-bit, low half) |
| `minstret` | 0xC02 | Instructions retired counter (64-bit, low half) |

These are read/written with `CSRRW`, `CSRRS`, `CSRRC` instructions.

---

## Interrupts

When `__INTERRUPT__` is enabled:

1. An external `IRQ` signal arrives
2. If interrupts are enabled (`mstatus[3]` = 1) and the specific interrupt is
   enabled (`mie[11]` = 1), the CPU:
   - Saves the next PC into `mepc`
   - Jumps to `mtvec` (the interrupt handler address)
   - Clears `mstatus[3]` to prevent nested interrupts
3. The handler does its work, then executes `MRET`
4. `MRET` restores `mstatus[3]` and jumps back to `mepc`

---

## Simulation Support

In simulation (`ifdef SIMULATION`), the CPU includes:

- **Performance meter** (`__PERFMETER__`): counts clocks spent running,
  halted, and flushed; prints a report when simulation ends
- **Instruction trace** (`__TRACE__`): prints every instruction as it executes
- **End-of-simulation**: when `ESIMREQ` is asserted (by darkuart detecting the
  `>` prompt character), the CPU prints the pipeline report and calls `$finish()`
- **Safety checks**: detects invalid instructions and undefined data reads

---

## Optional Extensions

| Feature | Config define | What it adds |
|---|---|---|
| M-extension | `__MEXT__` | Hardware multiply (`MUL`, `MULH`, `MULHSU`, `MULHU`) |
| MAC coprocessor | `__MAC16X16__` | 16×16 multiply-accumulate via custom instruction |
| RV32E | `__RV32E__` | Reduced register file (16 registers instead of 32) |
| Multi-threading | `__THREADS__` | Multiple hardware thread contexts sharing the pipeline |
| DBNZ | `__DBNZ__` | Custom decrement-and-branch-if-not-zero instruction |

---

## Key Signals Summary

| Signal | Direction | Width | Purpose |
|---|---|---|---|
| `CLK` | input | 1 | System clock (100 MHz) |
| `RES` | input | 1 | Reset (active high) |
| `IADDR` | output | 32 | Instruction fetch address |
| `IDATA` | input | 32 | Instruction data from memory |
| `DADDR` | output | 32 | Data access address |
| `DATAO` | output | 32 | Data to write to memory |
| `DATAI` | input | 32 | Data read from memory |
| `DBE` | output | 4 | Byte enable (which bytes in the 32-bit word) |
| `DRD` | output | 1 | Data read request |
| `DWR` | output | 1 | Data write request |
| `HLT` | internal | 1 | Pipeline stall (waiting for memory) |
| `FLUSH` | internal | 2 | Pipeline flush counter (0 = running, 1-2 = flushing) |
