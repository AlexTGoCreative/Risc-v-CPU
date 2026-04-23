# System-on-Chip Architecture — `darksocv.v`

This document explains how all the individual hardware modules are wired
together to form a complete, functional computer system. For a visual overview,
see the SoC diagram explained in [diagrams.md § darksocv.png](diagrams.md#3-darksocvpng--soc-architecture-block-diagram).

---

## 1. What Is a System-on-Chip?

A CPU alone cannot do anything useful. It needs:
- **Memory** to read instructions from and store data in
- **Peripheral interfaces** to communicate with the outside world (UART,
  LEDs, buttons)
- **A clock source** to drive its timing
- **A reset mechanism** to start from a known state

A **System-on-Chip** (SoC) integrates all of these components into a single
design. In the DarkRISCV project, `darksocv.v` is the top-level Verilog module
that instantiates and interconnects every sub-module. When synthesised onto the
DE2 FPGA, this entire design becomes a working computer.

---

## 2. Official SoC Block Diagram

![DarkSoCV SoC block diagram](darksocv.png)

The dotted vertical line divides the system into two architectural zones. This
is the fundamental architectural distinction of the design:

**Left half — Synchronous Harvard Architecture**

The CPU operates at full speed with predictable, deterministic latency. Data
and instructions travel on separate, independent buses simultaneously.

**Right half — Asynchronous Von Neumann Architecture**

Memory and peripherals share a single bus (X-BUS). All communication is
request/acknowledge (handshaked), tolerating variable latency. The CPU never
sees this latency directly because the DarkBridge and caches absorb it.

---

## 3. Simplified Block Diagram

```
                            FPGA Package
                 ┌──────────────────────────────────────┐
  50 MHz ───────>│ XCLK                                 │
  KEY[0] ───────>│ XRES                                 │
                 │                                      │
                 │   ┌───────────┐                      │
                 │   │  darkpll  │──> 100 MHz CLK       │
                 │   └───────────┘──> RES (sync reset)  │
                 │                                      │
                 │   ┌────────────────────────────────┐ │
                 │   │         darkbridge             │ │
                 │   │  ┌──────────────────────────┐  │ │
                 │   │  │      darkriscv (CPU)      │  │ │
                 │   │  │  IADDR─────>  DADDR────>  │  │ │
                 │   │  │  IDATA<─────  DATAI<────  │  │ │
                 │   │  └──────────────────────────┘  │ │
                 │   │  ┌────────┐    ┌────────┐       │ │
                 │   │  │  I$    │    │  D$    │       │ │
                 │   │  └────────┘    └────────┘       │ │
                 │   └────────────────┬───────────────┘ │
                 │                   │ X-BUS            │
                 │     ┌─────────────┼─────────────┐    │
                 │     │             │             │    │
                 │  ┌──┴──────┐ ┌───┴────┐ ┌──────┴──┐ │
                 │  │ darkram │ │ darkio │ │  SDRAM  │ │
                 │  │  [00]   │ │  [01]  │ │  [10]   │ │
                 │  └─────────┘ └───┬────┘ └─────────┘ │
                 │                  │                   │
                 │          ┌───────┴──────┐            │
                 │          │              │            │
                 │      ┌───┴──────┐   ┌──┴──────┐     │
                 │      │ darkuart │   │  Timer  │     │
                 │      └───┬──────┘   └─────────┘     │
                 │          │                           │
  RS-232 <───── │── TXD    │   LEDR[17:0]─────────────>│──> Red LEDs
  RS-232 ──────>│── RXD    │   SW[17:0] ──────────────>│(via IPORT)
                 └──────────────────────────────────────┘

  Numbers in brackets [ ] are XADDR[31:30] routing bits
```

---

## 4. Module-by-Module Walkthrough

### 4.1 `darkpll` — Clock Generator

**Source file:** `rtl/darkpll.v`  
**Purpose:** Multiply the 50 MHz board clock to 100 MHz; synchronise reset.

The Terasic DE2 board provides a 50 MHz oscillator. The CPU requires 100 MHz
for maximum performance. A **PLL (Phase-Locked Loop)** achieves this by:

1. Comparing the output clock to a reference phase
2. Using a feedback loop to lock the output frequency to exactly `N × input`
3. For DE2: `N = 2`, so `50 MHz × 2 = 100 MHz`

The reset signal (`XRES`) is also synchronised through the PLL: the module
holds `RES` high for at least 128 clock cycles after power-up or button press.
This ensures every flip-flop in the design captures its reset value before the
CPU starts executing.

**In simulation:** The testbench (`darksimv.v`) bypasses the PLL:

```verilog
// darksimv.v: simple clock toggle, no real PLL needed
always #5 XCLK = ~XCLK;   // 10 ns period = 100 MHz
```

**On the DE2 board:** The `pll.v` file in `boards/de2_cyclone2/` uses the
Altera `altpll` megafunction — a pre-built, silicon-tested PLL block.

---

### 4.2 `darkbridge` — Bus Bridge

**Source file:** `rtl/darkbridge.v`  
**Purpose:** Translate the CPU's two-bus Harvard interface to the SoC's
single-bus X-BUS interface.

#### The Fundamental Problem

The CPU (`darkriscv.v`) has two buses:
- **I-bus**: always reading instructions (every cycle)
- **D-bus**: occasionally reading/writing data (loads/stores)

The memory system (`darkram.v`, `darkio.v`) can potentially receive requests
from both simultaneously. `darkbridge.v` coordinates this.

#### Harvard Mode (Default: `__HARVARD__` defined)

In Harvard mode, DarkRAM operates as a **dual-port** memory:
- Port A handles instruction fetches exclusively (I-bus)
- Port B handles data accesses (D-bus → X-BUS)

DarkBridge maps these without any time-multiplexing — both can operate in the
same clock cycle. This gives maximum throughput:

```
I-bus  ─────────────────────────→  BRAM Port A (always reads, every cycle)
D-bus  ──→  Address Decoder ────→  BRAM Port B (or DarkIO, SDRAM)
```

Instruction fetches never interfere with data accesses.

#### Von Neumann Mode (`__HARVARD__` not defined)

In Von Neumann mode, both buses must share a single memory port. DarkBridge
uses a simple priority scheme:

1. If a **data request** is pending, serve it on the X-BUS; assert `HLT` to
   the CPU for the instruction bus simultaneously.
2. If only an **instruction request** is pending, serve it on the X-BUS.

This halves the available instruction bandwidth compared to Harvard mode,
which is why caches (`__ICACHE__`, `__DCACHE__`) are automatically enabled
in Von Neumann mode.

#### L1 Cache Integration

DarkBridge also instantiates the two optional L1 caches:

```verilog
`ifdef __ICACHE__
    darkcache icache0 (CLK, ..., IADDR, IDATA, ICACHE_HIT, ...);
`endif

`ifdef __DCACHE__
    darkcache dcache0 (CLK, ..., DADDR, DATAI, DCACHE_HIT, ...);
`endif
```

Cache hits are returned immediately; misses are forwarded to the X-BUS with
`HLT` asserted until the response arrives.

---

### 4.3 `darkram` — Block RAM

**Source file:** `rtl/darkram.v`  
**Purpose:** On-chip memory for firmware (instructions) and data.

#### FPGA Block RAM

FPGAs contain dedicated memory cells called **Block RAM (BRAM)** — large arrays
of flip-flops organised as addressable memories. On the Cyclone II, each BRAM
block holds 4096 bits (4 Kb). Multiple blocks are chained to form larger
memories.

DarkRAM uses BRAM configured as a 32-bit wide, \(2^{\text{MLEN}-2}\) entry
array. With `MLEN = 15`:

\[
\text{entries} = 2^{15-2} = 2^{13} = 8192 \text{ words} = 32768 \text{ bytes} = 32 \text{ KB}
\]

#### Firmware Loading

At simulation start:
```verilog
initial $readmemh("../src/darksocv.mem", MEM);
```

At synthesis time (FPGA), the Quartus tool reads the `.mif` file produced by
`mem2mif.py` and bakes the firmware data into the FPGA bitstream. When the
FPGA is programmed, the BRAM cells are pre-loaded with the firmware — the CPU
begins executing immediately after reset without any boot loader.

#### Byte Write Support

RISC-V store instructions (`SB`, `SH`, `SW`) write 1, 2, or 4 bytes. Since
BRAM is 32 bits wide, writing fewer than 4 bytes requires selecting which byte
lanes to update:

```verilog
// Each byte lane has an independent write enable
always @(posedge CLK) begin
    if (DWR) begin
        if (DBE[3]) MEM[word_addr][31:24] <= DATAO[31:24];  // byte 3
        if (DBE[2]) MEM[word_addr][23:16] <= DATAO[23:16];  // byte 2
        if (DBE[1]) MEM[word_addr][15: 8] <= DATAO[15: 8];  // byte 1
        if (DBE[0]) MEM[word_addr][ 7: 0] <= DATAO[ 7: 0];  // byte 0
    end
end
```

On FPGAs that do not support individual byte write enables, `__RMW_CYCLE__`
can be enabled. This performs a **Read-Modify-Write**: the full word is read,
the target byte is updated in a register, and the modified word is written
back. This costs 1 extra wait state per sub-word store.

#### Memory Read Latency

BRAM is **synchronous** — data is available one clock cycle after the address
is presented. This is why load instructions incur a 1-cycle stall:

```
Clock N:   DADDR presented to BRAM, DRD = 1
Clock N+1: BRAM returns data on DATAI (HLT was high during N)
Clock N+1: CPU captures DATAI, writes to rd, resumes (HLT goes low)
```

---

### 4.4 `darkio` — I/O Controller

**Source file:** `rtl/darkio.v`  
**Purpose:** All peripheral registers accessible to firmware.

#### Memory-Mapped I/O

DarkIO responds to any address with `[31:30] = 01` (the `0x40000000` range).
Within that range, bits `[4:2]` select which of the 8 registers to access:

| `XADDR[4:2]` | Offset | Register | R/W | Description |
|---|---|---|---|---|
| `000` | `+0x00` | Board Info | R | `{IRQ_flags, core_id, clock_MHz, board_id}` |
| `001` | `+0x04` | UART | R/W | UART data byte and status flags |
| `010` | `+0x08` | LED | R/W | LED output register |
| `011` | `+0x0C` | Timer | R/W | Timer reload value |
| `100` | `+0x10` | Microseconds | R | Free-running µs counter |
| `101` | `+0x14` | IPORT | R | General-purpose input (switches) |
| `110` | `+0x18` | OPORT | R/W | General-purpose output |
| `111` | `+0x1C` | SPI | R/W | SPI data (optional) |

From firmware (C code), these registers are accessed as an array:

```c
volatile unsigned int *io = (volatile unsigned int *)0x40000000;
// io[0] = board info, io[1] = UART, io[2] = LEDs, etc.
```

The `volatile` qualifier is essential: it prevents the C compiler from caching
the register value in a CPU register. Every read or write must generate an
actual memory instruction.

#### Timer Operation

The timer is a **countdown register**:

```
Firmware writes io[3] = 99999    (reload value for 1 kHz at 100 MHz)
Hardware: TIMER = 99999
Clock 1: TIMER = 99998
Clock 2: TIMER = 99997
...
Clock 99999: TIMER = 0 → interrupt! TIMER reloads to 99999 → repeat
```

The interrupt rate:

\[
f_{\text{timer}} = \frac{f_{\text{clock}}}{\text{reload} + 1} = \frac{100{,}000{,}000}{99{,}999 + 1} = 1000 \text{ Hz}
\]

#### Microsecond Counter

The free-running microsecond counter provides a wall-clock reference for
firmware timing:

```c
unsigned int start = io[4];           // record start time
do_some_work();
unsigned int elapsed = io[4] - start; // time elapsed in microseconds
```

Since the counter is 32 bits, it overflows every \(2^{32} / 10^6 ≈ 4295\)
seconds (~71 minutes). For longer measurements, firmware must handle rollover.

---

### 4.5 `darkuart` — Serial Port

**Source file:** `rtl/darkuart.v`  
**Purpose:** Transmit and receive bytes over a serial (RS-232) connection.

#### What Is a UART?

A **UART (Universal Asynchronous Receiver/Transmitter)** converts:
- **Parallel → Serial** (transmit): takes an 8-bit byte from a register and
  shifts it out one bit at a time on the `TXD` pin
- **Serial → Parallel** (receive): samples the `RXD` pin one bit at a time
  and assembles them into an 8-bit byte in a register

"Asynchronous" means there is no separate clock wire — the receiver must infer
timing from the data transitions themselves.

#### Serial Protocol

```
TXD line state:
  Idle:  ─────────────────────────────
  Byte:  ─────┐   ┌───┐   ┌──┐   ┌───
              └───┘   └───┘  └───┘
              Start D0   D1  ...  Stop
              (LOW) (LSB first)   (HIGH)
```

Frame format: **8N1** (8 data bits, No parity, 1 stop bit):
1. **Start bit**: TXD goes LOW for one bit period
2. **8 data bits**: LSB first, each held for one bit period
3. **Stop bit**: TXD goes HIGH for one bit period
4. **Idle**: TXD remains HIGH until next transmission

At 115200 baud, each bit period is:

\[
T_{\text{bit}} = \frac{1}{115200} \approx 8.68 \text{ µs}
\]

A complete byte takes \(10 \times 8.68 \text{ µs} \approx 86.8 \text{ µs}\)
(start + 8 data + stop = 10 bit periods).

#### Baud Rate Generation

The UART counts `__BAUD__` clock cycles per bit period:

\[
\text{__BAUD__} = \left\lfloor \frac{f_{\text{clock}}}{f_{\text{baud}}} \right\rfloor = \left\lfloor \frac{100{,}000{,}000}{115{,}200} \right\rfloor = 868
\]

The transmitter decrements a counter from 868 to 0, shifts one bit of the
shift register, and reloads — repeating for each of the 10 bit periods.

#### UART Status Register Format

When firmware reads `io[1]`:

```
Bit 31 (RXIRQ): 1 = a received byte is waiting to be read
Bit 30 (TXIRQ): 1 = transmitter is idle (ready for next byte)
Bits [7:0]:     the received data byte (valid when RXIRQ = 1)
```

When firmware writes `io[1]`:
- Bits `[7:0]` load the byte to transmit
- The UART begins serialising immediately

#### Simulation Shortcut

In simulation, the serial waveform would take 869 clock cycles per bit ×
10 bits = 8680 cycles per character — extremely slow. Instead, the UART
module detects that it is running in simulation and uses a shortcut:

```verilog
`ifdef SIMULATION
    always @(posedge CLK) begin
        if (TXWR) $write("%c", TXDATA);   // print immediately
        if (TXDATA == ">") ESIMREQ <= 1; // signal end of simulation
    end
`endif
```

This makes simulation output appear instantly, rather than after thousands of
simulated clock cycles per character.

---

### 4.6 `darkcache` — L1 Cache

**Source file:** `rtl/darkcache.v`  
**Purpose:** Optional cache to reduce effective memory latency.

#### Cache Fundamentals

A **cache** is a small, fast memory that stores copies of recently accessed
data. When the CPU requests an address:

- **Hit**: the address is in the cache → data returned immediately (0 wait states)
- **Miss**: the address is not in the cache → forward to slow memory, store
  a copy on return

The goal is that the **hit rate** is high enough that the effective average
latency is close to 0 wait states, even when the underlying memory is slow.

#### Direct-Mapped Structure

DarkCache uses a **direct-mapped** organisation: each memory address maps to
exactly one cache slot, determined by the lower address bits.

```
Address [31:0]:
  [31 ... DEPTH+2]  →  TAG    (identifies which memory block occupies this slot)
  [DEPTH+1 ... 2]   →  INDEX  (selects which cache slot)
  [1:0]             →  (byte offset, ignored — cache stores 32-bit words)
```

With `__CDEPTH__ = 6`: 2^6 = 64 cache entries.

Each entry:

| Field | Bits | Purpose |
|---|---|---|
| `CVALID` | 1 | Is this entry populated? |
| `CTAG` | 32 − DEPTH − 2 | Which memory address is stored here? |
| `CDATA` | 32 | The cached 32-bit word |

**Hit detection:**
```verilog
wire CHIT = CVALID[INDEX] && (CTAG[INDEX] == TAG);
```

If `CHIT = 1`: return `CDATA[INDEX]` without accessing main memory.
If `CHIT = 0`: access main memory, update `CDATA[INDEX]`, `CTAG[INDEX]`,
`CVALID[INDEX]`.

#### Why Direct-Mapped?

A **fully associative** cache can store any address in any slot (maximum
flexibility, maximum hit rate) but requires comparing all `N` tags
simultaneously — expensive in hardware.

A **direct-mapped** cache is the simplest: each address has exactly one
possible slot. The logic is a single comparator rather than N comparators.
The downside is **conflict misses**: two frequently used addresses that map
to the same slot will evict each other repeatedly.

The instruction cache typically achieves >90% hit rate for sequential code
(loops), where the same instructions are fetched repeatedly. The data cache
is less effective (typically 60–70%) because data access patterns are less
predictable.

---

### 4.7 SDRAM Controller (Optional)

**Source file:** `rtl/lib/sdram/mt48lc16m16a2_ctrl.v`  
**Purpose:** Interface to off-chip SDRAM for larger memory capacity.

SDRAM (Synchronous Dynamic RAM) provides megabytes of storage, but with
significantly higher latency than BRAM:
- **BRAM**: 1 clock cycle (10 ns at 100 MHz)
- **SDRAM**: 3–7 clock cycles for CAS latency, plus refresh overhead

Without caches, SDRAM would dramatically reduce CPU performance. With I$ and
D$ caches, most accesses are cache hits, and the SDRAM latency is only paid
on cache misses.

The SDRAM controller also handles **refresh**: DRAM cells leak charge and
must be refreshed approximately every 64 ms to prevent data loss. The
controller inserts refresh cycles transparently, asserting `HLT` to the CPU
during the brief refresh period.

---

## 5. Address Decoding

The SoC uses the **top 2 bits** of the 32-bit address for memory region
selection. This is the address decoder inside `darksocv.v`:

```verilog
// Route request to the correct peripheral based on address[31:30]
wire XDREQMUX [3:0];
assign XDREQMUX[0] = XDREQ && (XADDR[31:30] == 2'b00);  // BRAM
assign XDREQMUX[1] = XDREQ && (XADDR[31:30] == 2'b01);  // DarkIO
assign XDREQMUX[2] = XDREQ && (XADDR[31:30] == 2'b10);  // SDRAM (optional)
assign XDREQMUX[3] = XDREQ && (XADDR[31:30] == 2'b11);  // unused

// Multiplex the response data from the selected peripheral
assign XXDATAI = XDACKMUX[1] ? XATAIMUX[1] :   // DarkIO response
                 XDACKMUX[2] ? XATAIMUX[2] :   // SDRAM response
                               XATAIMUX[0];    // BRAM response (default)
```

| Address range | `ADDR[31:30]` | Region | Peripheral |
|---|---|---|---|
| `0x00000000 – 0x3FFFFFFF` | `00` | BRAM | DarkRAM (8–32 KB on-chip memory) |
| `0x40000000 – 0x7FFFFFFF` | `01` | I/O | DarkIO (UART, LED, timer, GPIO) |
| `0x80000000 – 0xBFFFFFFF` | `10` | SDRAM | Optional external DRAM |
| `0xC0000000 – 0xFFFFFFFF` | `11` | — | Unused |

Only 2 bits are needed for routing, leaving 30 bits for addressing within
each region. This is more address space than any of the current peripherals
need, so most of each region is "empty" — accessing unmapped addresses returns
undefined data (typically 0).

---

## 6. Reset Sequence

When the FPGA powers up or `KEY[0]` is pressed on the DE2:

1. **PLL acquires lock**: `darkpll.v` waits until the 100 MHz output is stable,
   then counts 128 cycles before deasserting `RES`.

2. **CPU reset**: While `RES = 1`, the CPU's `IFPC` is forced to `__RESETPC__`
   (address `0x00000000`) and `FLUSH` is set to 2. All pipeline registers load
   their reset values.

3. **First fetch**: On the first clock after `RES` goes low, `IFPC = 0` is
   driven onto `IADDR`. BRAM returns the instruction at address 0.

4. **Boot code executes**: The instruction at address 0 is the first word of
   `boot.S`:

   ```asm
   .section .text
   .global _start
   _start:
       la  sp, _stack     # load stack pointer address
       jal ra, main       # jump to C main function
   ```

5. **C firmware runs**: `main()` in `darkshell/main.c` (or whichever
   application is selected) begins executing. It initialises the UART, prints
   the boot banner, and enters the command loop.

---

## 7. Module Hierarchy Summary

```
darksocv.v  (top-level SoC)
│
├── darkpll.v          Clock: 50 MHz in → 100 MHz out + synchronised reset
│
├── darkbridge.v       Bus bridge: CPU Harvard buses → single X-BUS
│    ├── darkriscv.v   THE CPU CORE: 3-stage pipeline, 4 parallel ALUs
│    ├── darkcache.v   Optional I-cache (instruction cache)
│    ├── darkcache.v   Optional D-cache (data cache)
│    └── darkmac.v     Optional MAC coprocessor (16×16 multiply-accumulate)
│
├── darkram.v          On-chip BRAM: dual-port, holds firmware + data
│
├── darkio.v           I/O controller: 8 memory-mapped registers
│    ├── darkuart.v    Serial port (115200 8N1)
│    └── darkspi.v     SPI master (optional, not used on DE2)
│
└── mt48lc16m16a2_ctrl  SDRAM controller (optional, external DRAM)
```

Each sub-module is a separate Verilog file in `rtl/`. They communicate
exclusively through their ports — no shared global variables exist in Verilog.
This strict boundary makes each module independently testable and replaceable.
