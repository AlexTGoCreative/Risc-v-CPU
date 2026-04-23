# Understanding the Architecture Diagrams

This document provides an in-depth, academic explanation of the three PNG
images found in this `doc/` folder. Each image captures a different level of
abstraction of the DarkRISCV system:

| Image | Abstraction level | What it shows |
|---|---|---|
| `boot.png` | Behavioural / software | The processor running firmware and printing output |
| `darkriscv.png` | Micro-architecture | The internal structure of the CPU core |
| `darksocv.png` | System architecture | How the CPU integrates with memory and peripherals |

Reading them in the order above — from observable behaviour down to
implementation detail — gives a natural top-down introduction to the design.

---

## 1. `boot.png` — The Simulation Boot Screenshot

![DarkRISCV boot screenshot](boot.png)

### 1.1 What This Image Is

This screenshot captures the text output printed by the CPU's firmware when it
starts up inside the Icarus Verilog simulator. It is the most direct evidence
that the entire hardware stack — CPU, memory, UART, simulation testbench — is
functioning correctly.

The text appears because the firmware (a C program compiled for RISC-V)
executes `printf()`-like calls that write characters to the UART register.
In simulation, the UART module does not generate real electrical serial
waveforms; instead it calls the Verilog system task `$write("%c", data)`,
which causes the character to appear directly in the simulator terminal.

### 1.2 The ASCII Art Banner

The large "rv" pattern at the top of the screenshot is the RISC-V ASCII logo,
included in the original DarkRISCV firmware. It is composed of the letters
`r` and `v` arranged to form a stylised "RV" emblem. The caption below it
reads:

```
INSTRUCTION SETS WANT TO BE FREE
```

This phrase is a nod to the philosophy behind the RISC-V project: an
instruction set architecture that is openly published, unencumbered by
patents, and free for anyone to implement — a deliberate contrast to
proprietary ISAs such as x86 (Intel/AMD) or ARM.

### 1.3 Line-by-Line Analysis of the Boot Messages

```
boot0: main@0200 stack@01fb0
```

The `boot.S` startup assembly code (`src/boot.S`) has completed its
initialisation. It reports:
- `main@0200`: the compiled `main()` C function was placed at byte address
  `0x0200` (512 decimal) within the Block RAM. This is where the CPU will
  transfer control after the boot stub runs.
- `stack@01fb0`: the stack pointer (`sp` register, which is `x2` in RISC-V)
  was set to `0x01fb0`. In RISC-V calling convention, the stack grows
  **downward** — each function call decrements the stack pointer, and `ret`
  restores it. The boot code places the initial stack pointer near the top of
  the available RAM area.

```
csrxx: not found
stvec: not found
mtvec: not found (polling)
```

The firmware attempted to configure hardware interrupt registers:
- `csrxx`: a probe to detect whether **any** CSR (Control and Status Register)
  support is compiled in. It is "not found" because `__CSR__` is not defined
  in `rtl/config.vh` for this build.
- `stvec`: the supervisor trap vector — not applicable here (no supervisor mode).
- `mtvec`: the machine trap vector — the address the CPU would jump to on an
  interrupt. Because `__INTERRUPT__` is not enabled, the firmware falls back
  to **polling mode**: it checks the timer register in a tight loop rather than
  relying on hardware interrupts.

This graceful fallback demonstrates the firmware's portability: the same C
code runs whether or not the hardware interrupt mechanism is present.

```
board: simulation only (id=0)
```

The board identifier is read from the I/O register `io[0]`, which contains
the `BOARD_ID` value compiled into the Verilog. `BOARD_ID = 0` is the
designated value for the Icarus simulation environment (see `rtl/config.vh`).
When the same firmware runs on the DE2 FPGA, this line would read
`board: de2 (id=21)`.

```
build: Sun, 27 Apr 2025 15:11:03 -0300 for rv32e_zicsr
```

A build timestamp embedded by the C compiler at compile time using
`__DATE__` and `__TIME__` macros. The suffix `rv32e_zicsr` is the GCC
`-march=` string:
- `rv32e`: RISC-V 32-bit, Embedded profile (16 registers instead of 32)
- `zicsr`: the Zicsr extension (CSR read/write instructions — needed even
  for the fallback polling code that attempts CSR reads)

```
core0: darkriscv@100MHz w/ rv32e
```

The firmware reads the clock frequency from the I/O board-info register and
formats it. `rv32e` confirms the reduced register file is active in this build.

```
bram0: 352 bytes free
bram0: text@0200+5048 data@15b0+2280 stack@2000
```

The firmware reports its own memory layout (read from symbols embedded by the
linker):
- `.text@0200+5048`: the program code starts at offset `0x200` and occupies
  5048 bytes of BRAM.
- `.data@15b0+2280`: initialised and zero-initialised data starts at `0x15b0`
  and uses 2280 bytes.
- `stack@2000`: the stack base (top of BRAM, growing down).
- `352 bytes free`: the space between the end of `.data`/`.bss` and the
  bottom of the stack region.

The tight memory usage (352 bytes spare) illustrates why the `-Os` (optimise
for size) compiler flag is the default: the firmware must fit within the
32 KB BRAM.

```
uart0: 115.2kbps (div=868)
```

The UART baud rate and divisor:

\[
\text{divisor} = \left\lfloor \frac{f_{\text{clock}}}{f_{\text{baud}}} \right\rfloor
= \left\lfloor \frac{100{,}000{,}000}{115{,}200} \right\rfloor = 868
\]

The UART module counts 868 system clock cycles per bit period.

```
timr0: 1000Hz (div=99999)
```

The timer is configured to fire 1000 times per second (1 kHz periodic
interrupt or polling event):

\[
\text{reload} = \frac{f_{\text{clock}}}{f_{\text{timer}}} - 1
= \frac{100{,}000{,}000}{1{,}000} - 1 = 99{,}999
\]

```
Welcome to DarkRISCV!
492>
```

The shell is ready. The `492` prefix is the instruction counter — the firmware
counted 492 instructions from reset to reaching the prompt. This is a rough
measure of boot overhead. The `>` character also serves as the simulation
termination signal: when `darkuart.v` detects `>`, it asserts `ESIMREQ`,
which causes the CPU to print the pipeline performance report and then call
`$finish()` to end the simulation.

---

## 2. `darkriscv.png` — CPU Core Block Diagram

![DarkRISCV CPU core block diagram](darkriscv.png)

### 2.1 What This Diagram Shows

This is the micro-architecture block diagram of the `darkriscv.v` module —
the processor core itself. It depicts how data flows through the CPU during
one full instruction cycle, and which internal registers hold state between
clock edges.

Every box in this diagram corresponds to either:
- A **clocked register** (a flip-flop or an array of flip-flops) that holds
  its value until the next rising clock edge, or
- A **combinational circuit** (wires and logic gates) that computes its output
  immediately from its inputs, with no clock dependency.

Understanding this distinction is fundamental to reading RTL: registers break
the combinational path and create the pipeline stages.

### 2.2 The Control Signals: CLK, HLT, RES

Three global signals appear in multiple places on the diagram:

| Signal | Direction | Role |
|---|---|---|
| `CLK` | Input | 100 MHz system clock. Every clocked element latches its value on the **rising edge** of this signal. |
| `HLT` | Input | Pipeline halt. When high, all clocked elements **ignore** the clock edge — they hold their current values. This freezes the pipeline during memory wait-states. |
| `RES` | Input | Synchronous reset. When high, all registers load their reset values (e.g., PC ← 0). |

The `HLT` signal propagates from the memory interface (`darkbridge.v` or
`darkram.v`) back into the CPU. This creates a natural handshake: the memory
asserts `HLT` if it cannot service a request in one cycle, and the CPU waits.

### 2.3 The Instruction Path (Right Side of Diagram)

Reading top-to-bottom down the right column:

#### Program Counter (PC)

The **Program Counter** is the most important register in any processor. It
stores the byte address of the **next instruction to fetch**. At reset it is
loaded with `0x00000000` (configured by `__RESETPC__` in `config.vh`).

On each clock cycle (assuming no halt or flush), the PC is updated to one of:
- `PC + 4` — normal sequential execution (each RISC-V instruction is 4 bytes)
- `PC + immediate` — a taken conditional branch (`BEQ`, `BNE`, etc.)
- `rs1 + immediate` — an indirect jump (`JALR`)
- `mtvec` — interrupt handler address (when `__INTERRUPT__` is enabled)

The PC feeds simultaneously into the instruction cache and the ALU responsible
for computing `NEXT PC` (PC+4 or branch target).

#### INSTRUCTION CACHE / INSTRUCTION BUS

The PC value is driven onto the `INSTRUCTION BUS` (`IADDR` port of the
module), which connects to external memory. The memory returns a 32-bit
instruction word on `IDATA`.

The **Instruction Cache** (`darkcache.v`, when enabled) sits on this path. If
the requested address is already in cache (a **cache hit**), the instruction
is returned in zero additional cycles. On a **cache miss**, the request is
forwarded to the external bus and `HLT` is asserted until the data returns.

In Harvard mode (default), the instruction bus operates independently of the
data bus — instruction fetches and data accesses can happen simultaneously.

#### IDATA (IF) — Instruction Fetch Pipeline Register

The 32-bit instruction returned from memory is captured into the `IDATA (IF)`
pipeline register on the rising clock edge. This register separates the
**Fetch stage** from the **Decode stage**: the next clock cycle can begin
fetching instruction N+1 while instruction N is being decoded.

#### Instruction Decode Logic

The decode stage splits the 32-bit instruction into its constituent fields
according to the RISC-V base ISA encoding:

```
Bits [6:0]   → opcode   (7 bits: what kind of instruction)
Bits [11:7]  → rd       (5 bits: destination register number)
Bits [14:12] → funct3   (3 bits: instruction sub-type)
Bits [19:15] → rs1      (5 bits: source register 1 number)
Bits [24:20] → rs2      (5 bits: source register 2 number)
Bits [31:25] → funct7   (7 bits: further qualification)
```

The decoder also reconstructs the **immediate value** — a constant embedded
within the instruction bits. The encoding differs by instruction type:

| Type | Used by | Immediate reconstruction |
|---|---|---|
| I-type | `LW`, `ADDI`, `JALR` | Bits [31:20], sign-extended to 32 bits |
| S-type | `SW`, `SB`, `SH` | Bits [31:25] ++ [11:7], sign-extended |
| B-type | `BEQ`, `BNE`, `BLT` | Bits [31], [7], [30:25], [11:8], shifted left 1 |
| U-type | `LUI`, `AUIPC` | Bits [31:12], zero-padded to 32 bits |
| J-type | `JAL` | Bits [31], [19:12], [20], [30:21], shifted left 1 |

The immediate reconstruction is entirely combinational — it is computed in the
same clock cycle the instruction is being decoded.

One-hot decode signals (`XLUI`, `XJAL`, `XBCC`, `XLCC`, `XSCC`, `XMCC`,
`XRCC`) are also generated here, one per instruction type. These signals drive
the multiplexers in the Execute stage.

#### IMM (ID) — Immediate / Decode Pipeline Register

The decoded fields (immediate value, register numbers, one-hot signals) are
captured in the `IMM (ID)` pipeline register. This separates the **Decode
stage** from the **Execute stage**.

### 2.4 The Register File (Left Side of Diagram)

The stacked rectangular elements on the left represent the **register file**:
an array of 32 (or 16, in RV32E) general-purpose 32-bit registers, labelled
X0 through X15 (or X31).

Key properties of the register file:

**Multi-port read:** Two source registers (`rs1` and `rs2`) are read
simultaneously in a single cycle. The register file has two read ports, so
both values are available at the same time for the Execute stage.

**Single-port write:** One destination register (`rd`) is written per cycle.
The write happens on the clock edge at the end of the Execute stage.

**Combinational reads:** Unlike writes (which are clocked), reads are
**combinational** — the output is valid as soon as the register number input
is stable, with no clock edge required.

**X0 = 0 permanently:** Register `x0` is hardwired to zero. Writing to it has
no effect; reading it always returns `0`. This simplifies the ISA considerably:
many pseudo-instructions (e.g., `NOP = ADDI x0, x0, 0`) are just aliases.

**Threading:** When `__THREADS__` is enabled, the register file is enlarged to
store multiple thread contexts. A thread identifier selects which "bank" of
registers is active, allowing context switching in just 2 clock cycles.

### 2.5 The Four Parallel ALUs (Execute Stage)

This is the central design insight of DarkRISCV. During the Execute stage,
**four separate arithmetic circuits compute in parallel**, each responsible for
one specific result:

#### ALU 1 — REG/REG and REG/IMM Results (leftmost)

This is the **main arithmetic unit**. It computes the result of arithmetic and
logic instructions:

| Operation | `funct3` | Computation |
|---|---|---|
| ADD | 000 | `rs1 + rs2` or `rs1 + imm` |
| SUB | 000 + funct7[5] | `rs1 - rs2` |
| AND | 111 | `rs1 & rs2` |
| OR | 110 | `rs1 \| rs2` |
| XOR | 100 | `rs1 ^ rs2` |
| SLL | 001 | `rs1 << rs2[4:0]` (shift left logical) |
| SRL | 101 | `rs1 >> rs2[4:0]` (shift right logical) |
| SRA | 101 + funct7[5] | `rs1 >>> rs2[4:0]` (shift right arithmetic) |
| SLT | 010 | `rs1 < rs2` (signed less-than comparison) |
| SLTU | 011 | `rs1 < rs2` (unsigned less-than comparison) |

The result is a single 32-bit value (`RMDATA`) that is written back to
register `rd` at the end of the Execute stage.

#### ALU 2 — Conditional Branch Logic (second from left)

This circuit evaluates the branch condition for `B-type` instructions. It
compares the two source registers and produces a single-bit decision:

| Instruction | `funct3` | Condition |
|---|---|---|
| `BEQ` | 000 | `rs1 == rs2` |
| `BNE` | 001 | `rs1 != rs2` |
| `BLT` | 100 | `rs1 < rs2` (signed) |
| `BGE` | 101 | `rs1 >= rs2` (signed) |
| `BLTU` | 110 | `rs1 < rs2` (unsigned) |
| `BGEU` | 111 | `rs1 >= rs2` (unsigned) |

If the condition is true and the instruction is a branch, the CPU must update
the PC to the branch target (`PC + B-type immediate`) and flush the pipeline
(discard the two instructions already in earlier stages).

#### ALU 3 — NEXT PC Calculation (third from left)

This circuit determines the next Program Counter value:

| Situation | Next PC |
|---|---|
| Normal execution | `PC + 4` |
| Taken conditional branch | `PC + B-type immediate` |
| `JAL` (jump and link) | `PC + J-type immediate` |
| `JALR` (jump and link register) | `(rs1 + I-type immediate) & ~1` |
| Interrupt (if enabled) | `mtvec` |

The computed next PC feeds back to the PC register at the top-right, closing
the main execution loop.

#### ALU 4 — Memory Address (rightmost)

The memory address for load and store instructions is always:

\[
\text{DADDR} = rs1 + \text{immediate}
\]

For load instructions (`LW`, `LH`, `LB`), `DADDR` is the address to read from
memory; the data returns on `DATAI` and is written into `rd`.

For store instructions (`SW`, `SH`, `SB`), `DADDR` is the address to write
to; the value to store comes from `rs2` on the `DATAO` bus.

#### Why Four ALUs?

Traditional in-order processors compute one thing at a time and use **result
forwarding** (passing the output of one stage directly to the input of the
next, bypassing the register file) to handle data dependencies. This requires
complex forwarding multiplexers and hazard detection logic.

DarkRISCV eliminates this complexity by computing everything in parallel: since
ALU 1 (arithmetic), ALU 2 (branch), ALU 3 (next PC), and ALU 4 (address) all
have access to the same register values simultaneously, no forwarding is
needed. Each result is consumed by its own downstream resource, not by the
next instruction.

This is possible because the pipeline is designed so that a result is always
written to the register file **before** it is needed as an input to a
subsequent instruction. When this cannot be guaranteed (e.g., a `LW` followed
immediately by an instruction that uses the loaded value), the memory
acknowledges with `HLT`, stalling the pipeline for one cycle.

### 2.6 The STORE / LOAD Interface

The **DATA CACHE / DATA/IO BUS** on the lower right connects the CPU to
external memory and I/O:

- **STORE path**: `DATAO` carries the value of `rs2`, byte-enabled by `DBE`
  (Data Byte Enable). The `DWR` (Data Write) signal enables the write.
- **LOAD path**: `DATAI` receives the value from memory. The `LDATA` logic
  (inside the CPU) extracts the correct byte or halfword from the 32-bit word
  and sign-extends it before writing it into the destination register `rd`.
- **Byte enable (`DBE`)**: For sub-word stores (`SB`, `SH`), only specific
  byte lanes of the 32-bit bus carry valid data. `DBE[3:0]` indicates which
  bytes to write:
  - `SW`: `DBE = 4'b1111` (all four bytes)
  - `SH` at address ending in `00`: `DBE = 4'b0011`
  - `SB` at address ending in `01`: `DBE = 4'b0010`

### 2.7 The NEXT PC Loop

The bold arrow at the very bottom of the diagram, labelled **NEXT PC**, feeds
the result of ALU 3 all the way back to the PC register at the top-right. This
completes the fetch-decode-execute loop: every clock cycle, the result of the
current Execute stage becomes the address for the next Fetch stage.

In normal operation (no jump or branch), ALU 3 simply outputs `PC + 4`. On a
taken branch or jump, ALU 3 outputs the target address, and a **FLUSH** signal
of 2 is generated to invalidate the two instructions already in the Fetch and
Decode stages.

---

## 3. `darksocv.png` — SoC Architecture Block Diagram

![DarkSoCV SoC architecture block diagram](darksocv.png)

### 3.1 What This Diagram Shows

This diagram depicts the **System-on-Chip** (`darksocv.v`) — the complete
computer that surrounds the CPU core. It shows which modules exist, how they
are connected by buses, and the architectural philosophy governing each half
of the design.

The key feature of the diagram is the **vertical dotted line** that divides it
into two halves. This line is not a physical boundary on the chip; it
represents a **conceptual boundary** between two memory architecture paradigms.

### 3.2 Left Half — Synchronous Harvard Architecture

The left side contains the speed-critical elements that run at the full 100 MHz
clock rate with deterministic (zero-or-fixed) latency.

#### DarkRISCV @100MHz

The CPU core appears as a single box on the far left. It has two ports
connecting it to the rest of the system:

- **I-BUS** (top): the instruction bus. Every clock cycle the CPU sends a
  32-bit address on this bus and expects a 32-bit instruction word in return.
  The bus is **read-only** from the CPU's perspective.

- **D-BUS** (bottom): the data bus. Used for load and store instructions. The
  CPU can read data from an address or write data to an address. It is a
  **read/write** bus.

The two buses are completely independent — they operate simultaneously,
connecting to different destinations. This is the defining characteristic of
a **Harvard architecture**.

#### I$ — Instruction Cache

The **I$** block sits between the I-BUS and DarkBridge. Its purpose is to
eliminate the latency of reading instructions from BRAM on every cycle.

When the CPU requests an address:
- **Cache hit**: the requested address is already stored in the cache →
  `HLT` is not asserted → the CPU receives the instruction in the same cycle.
- **Cache miss**: the address is not in cache → `HLT` is asserted →
  DarkBridge forwards the request to the X-BUS → BRAM responds → the
  instruction is stored in the cache and returned to the CPU.

The cache is configured as a direct-mapped structure with \(2^N\) entries
(`__CDEPTH__` in `config.vh`). Each entry stores the data word, its address
tag, and a valid flag.

In Harvard mode (when `__HARVARD__` is defined), the instruction cache is
less important because BRAM can respond to instruction fetches every cycle via
its dedicated Port A. The cache becomes critical in Von Neumann mode.

#### D$ — Data Cache

The **D$** block serves the same purpose for data bus transactions. It reduces
load latency for frequently accessed data (e.g., loop counters, frequently
called functions' local variables).

Write policy: on a store instruction, the cache either updates the cached entry
(for full-word stores) or invalidates it (for byte/halfword stores, since
read-modify-write is needed at the BRAM level).

#### DarkBridge

**DarkBridge** (`darkbridge.v`) is the most architecturally interesting module
in the SoC. It acts as a **bus bridge** between two fundamentally different bus
structures:

- **Input side**: two independent buses (I-BUS and D-BUS from the CPU)
- **Output side**: one shared bus (X-BUS to all memory and peripherals)

**Harvard mode** (default, `__HARVARD__` defined):
Both buses are mapped to the X-BUS simultaneously. The I-BUS maps to Port A of
BRAM (instruction port), and the D-BUS maps to Port B (data port). Since
DarkRAM is a dual-port memory, both buses can operate in the same clock cycle
without conflict.

**Von Neumann mode** (`__HARVARD__` not defined):
DarkBridge time-multiplexes: it serves the D-BUS in one cycle, then the I-BUS
in the next. This requires the CPU to stall (`HLT`) on instruction fetches
when a data operation just occurred. Caches (I$ and D$) are essential to hide
this penalty.

DarkBridge also instantiates the optional L1 caches (I$ and D$).

### 3.3 The X-BUS

The **X-BUS** (eXternal BUS) is the shared bus that connects DarkBridge to all
right-side components. It carries:

| Signal | Width | Direction | Meaning |
|---|---|---|---|
| `XADDR` | 32 bits | Bridge → peripherals | Memory address |
| `XDATAO` | 32 bits | Bridge → peripherals | Data to write |
| `XDATAI` | 32 bits | peripherals → Bridge | Data read back |
| `XDREQ` | 1 bit | Bridge → peripherals | Request valid |
| `XDACK` | 1 bit | peripherals → Bridge | Response valid (handshake) |
| `XDWR` | 1 bit | Bridge → peripherals | Write (1) or Read (0) |
| `XBE` | 4 bits | Bridge → peripherals | Byte enable |

The **address decoder** (inside `darksocv.v`) uses the top 2 bits of `XADDR`
to route the transaction to the correct peripheral:

| `XADDR[31:30]` | Target | Address range |
|---|---|---|
| `2'b00` | DarkRAM | `0x00000000` – `0x3FFFFFFF` |
| `2'b01` | DarkIO | `0x40000000` – `0x7FFFFFFF` |
| `2'b10` | SDRAM | `0x80000000` – `0xBFFFFFFF` |
| `2'b11` | (unused) | `0xC0000000` – `0xFFFFFFFF` |

Only one peripheral asserts `XDACK` at a time; the SoC multiplexes `XDATAI`
from whichever peripheral responded.

### 3.4 Right Half — Asynchronous Von Neumann Architecture

The right side contains the memory and peripheral modules that the CPU
communicates with via the X-BUS.

#### DarkRAM (boot FW)

**DarkRAM** (`darkram.v`) is the on-chip Block RAM — the primary storage for
both program instructions and data. It is labelled "boot FW" because it is
pre-loaded with the compiled firmware at synthesis time (or simulation startup).

Key properties:
- **Dual-port**: Port A is connected to the instruction bus (read-only); Port B
  is connected to the data/X-bus (read/write).
- **Size**: configured by `MLEN` in `config.vh`. `MLEN = 15` → 32 KB.
- **Initialisation**: loaded from `darksocv.mem` (simulation) or
  `memory_init.mif` (FPGA synthesis via Quartus).
- **Byte-write enables**: Port B supports individual byte writes via `DBE[3:0]`.

On power-up or reset, the CPU begins fetching from address `0x00000000`, which
is the first word in DarkRAM — the entry point of `boot.S`.

#### DarkIO

**DarkIO** (`darkio.v`) is the I/O controller. It is the bridge between the
CPU's memory bus and the physical world:
- **LED**: drives 8–18 LEDs on the FPGA board
- **UART**: routes transmit/receive data to/from `darkuart.v`
- **Timer**: a countdown counter that generates periodic interrupt requests
- **GPIO**: general-purpose input (switches/buttons) and output ports
- **SPI**: optional interface to external serial devices

DarkIO responds to any address in the range `0x40000000 – 0x7FFFFFFF`.
Internally, it uses bits `[4:2]` of the address (an 8-entry register file)
to select the specific register. From the CPU's perspective, writing `0xFF` to
address `0x40000008` is indistinguishable from writing to memory — this is the
essence of **memory-mapped I/O**.

#### SDRAM Controller

The **SDRAM Controller** (`lib/sdram/mt48lc16m16a2_ctrl.v`) provides an
interface to off-chip SDRAM (Synchronous Dynamic RAM). This is optional and
is not populated on the DE2 build by default.

SDRAM is much larger than BRAM (16 MB or more vs 32 KB) but has much higher
access latency (tens of nanoseconds vs 1 clock cycle). The caches (I$ and D$)
are essential to make SDRAM practical for code execution.

### 3.5 Why This Architecture Was Chosen

The split architecture in `darksocv.png` reflects a deliberate trade-off:

**Performance at the CPU boundary**: The CPU must be able to fetch an
instruction and access data every single clock cycle (or nearly so). This
requires the Harvard separation of I-BUS and D-BUS, and optionally L1 caches
to absorb latency.

**Simplicity at the memory boundary**: Having multiple memory types (BRAM,
SDRAM, I/O) each with their own bus interface would be complex and wasteful.
The X-BUS provides a single, simple protocol that all peripherals implement
identically. The address decoder trivially routes transactions using just 2
bits.

**Flexibility**: The DarkBridge layer decouples the CPU from the memory system.
Adding a new peripheral means implementing the X-BUS handshake protocol and
assigning an unused address range — the CPU and its caches require no changes.
Adding a new CPU feature (e.g., threading) only affects `darkriscv.v` and the
`DarkBridge` instantiation — the memory system requires no changes.

This architectural layering is a fundamental principle of good hardware design:
**separate concerns, minimise cross-cutting dependencies**.

---

## 4. Connecting the Diagrams: A Signal-Level Trace

To solidify the connection between the three diagrams, let us trace the path of
one complete instruction: `LW x5, 8(x10)` (Load Word — read the 32-bit word
at address `x10 + 8` and store it in register `x5`).

**Step 1: Fetch (Fetch stage, clock N)**
- `darkriscv.v` drives `IADDR = PC` onto the I-BUS.
- `darksocv.v` routes the I-BUS through DarkBridge to Port A of DarkRAM.
- DarkRAM returns the 32-bit instruction word `0x00852283` (encoding of
  `LW x5, 8(x10)`) on `IDATA`.
- The instruction is captured into `IDATA (IF)` on the rising edge of CLK N.

**Step 2: Decode (Decode stage, clock N+1)**
- The Instruction Decode Logic breaks `0x00852283` apart:
  - opcode `[6:0]` = `0000011` → Load instruction (`XLCC` asserted)
  - `funct3 [14:12]` = `010` → Load Word (`LW`)
  - `rd [11:7]` = `00101` → destination is `x5`
  - `rs1 [19:15]` = `01010` → source base is `x10`
  - immediate `[31:20]` = `000000001000` → sign-extended to `0x00000008` (+8)
- The register file reads `x10` simultaneously (combinational).
- The decoded fields are captured into `IMM (ID)` on the rising edge of CLK N+1.

**Step 3: Execute (Execute stage, clock N+2)**
- ALU 4 computes: `DADDR = x10 + 8`.
- `DWR = 0` (read), `DRD = 1` (data read request).
- `darksocv.v` routes the D-BUS through DarkBridge to the X-BUS.
- Address decoder: `DADDR[31:30] = 00` → DarkRAM Port B.
- DarkRAM requires 1 clock cycle for Port B reads → `HLT` is asserted for 1
  cycle (pipeline stall).
- Clock N+3: DarkRAM returns the 32-bit word on `DATAI`.
- `LDATA` logic extracts all 32 bits (LW) and sign-extends (not needed for LW).
- The value is written into `x5` in the register file.

**In terms of the diagrams:**
- `boot.png` shows the final result: the firmware that uses `LW` instructions
  running and printing its output.
- `darkriscv.png` shows the internal path: PC → INSTRUCTION BUS → IDATA →
  Decode → IMM → ALU 4 → DATA CACHE → register write-back via LOAD arrow.
- `darksocv.png` shows the bus-level path: CPU → I-BUS (step 1) and D-BUS
  (step 3) → DarkBridge → X-BUS → DarkRAM → back.
