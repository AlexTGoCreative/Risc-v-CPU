# System-on-Chip Architecture — darksocv.v

This document explains how the individual hardware modules are wired together
to form a complete computer system.

---

## What Is a System-on-Chip (SoC)?

A CPU alone cannot do anything useful — it needs memory to read instructions
from, memory to store data in, and peripherals (UART, LEDs, timers) to
communicate with the outside world.

A **System-on-Chip** (SoC) is a single chip (or in our case, a single FPGA
design) that contains all of these components wired together. The file
`darksocv.v` is the top-level module that instantiates and connects everything.

---

## Official SoC Block Diagram

![DarkSoCV SoC Architecture](darksocv.png)

This diagram shows the two architectural halves of the system:

**Left half — Synchronous Harvard Architecture**

This is the high-speed side where the CPU lives. "Harvard" means instructions and data travel on separate buses simultaneously:

| Element | What it does |
|---|---|
| **DarkRISCV @100MHz** | The CPU core. Sends instruction fetch requests on **I-BUS** and data load/store requests on **D-BUS** at the same time |
| **I$** (Instruction Cache) | Sits between the I-BUS and main memory. Returns recently fetched instructions without going to slow BRAM every time |
| **D$** (Data Cache) | Sits between the D-BUS and main memory. Reduces load/store latency for frequently accessed data |
| **DarkBridge** | The central hub. Multiplexes the CPU's two buses onto the single shared bus (**X-BUS**) used by the right half |

**Right half — Asynchronous Von Neumann Architecture**

This is the memory and peripheral side. "Von Neumann" means instructions and data share the same bus:

| Element | What it does |
|---|---|
| **DarkRAM (boot FW)** | Block RAM containing the firmware. Both instructions and data live here. Loaded at synthesis time from `memory_init.mif` |
| **DarkIO** | I/O controller. Exposes memory-mapped registers for **LED** output and **UART** serial communication |
| **SDRAM Controller** | Optional interface to external SDRAM for larger memory capacity |
| **X-BUS** | The shared bus connecting DarkBridge to all right-side components. Address bits `[31:30]` select which device responds |

**Why two halves?** The CPU needs to fetch instructions and read/write data every cycle without waiting. The cache layer hides the fact that BRAM and SDRAM are slower than the CPU. From the CPU's point of view, it always has fast Harvard-style memory; from the memory's point of view, only one request arrives at a time on the X-BUS.

---

## Simplified Block Diagram

```
                          FPGA Pins
                     ┌──────────────────┐
          50 MHz ───>│ XCLK             │
      KEY[0] ───────>│ XRES             │
                     │                  │
                     │   ┌──────────┐   │
                     │   │ darkpll  │   │──> 100 MHz CLK
                     │   └──────────┘   │──> RES (synchronised reset)
                     │                  │
                     │   ┌──────────────────────────────┐
                     │   │ darkbridge                    │
                     │   │  ┌────────────┐               │
                     │   │  │ darkriscv  │ ← THE CPU     │
                     │   │  │ (RV32I)    │               │
                     │   │  └─────┬──────┘               │
                     │   │    I-bus│  D-bus               │
                     │   └────────┼────────┬─────────────┘
                     │            │        │
                     │    ┌───────┴──┐  ┌──┴──────────┐
                     │    │ darkram  │  │ Address      │
                     │    │ (BRAM)   │  │ Decoder      │
                     │    │ 8-32 KB  │  │ [31:30]      │
                     │    └──────────┘  └──┬──────────┘
                     │                     │
                     │       ┌─────────────┼─────────────┐
                     │       │             │             │
                     │  ┌────┴─────┐ ┌─────┴────┐ ┌─────┴────┐
                     │  │ darkram  │ │ darkio   │ │ SDRAM    │
                     │  │ CS=00   │ │ CS=01    │ │ CS=10    │
                     │  │ (data)  │ │          │ │(optional)│
                     │  └─────────┘ └────┬─────┘ └──────────┘
                     │                   │
                     │          ┌────────┼────────┐
                     │          │        │        │
                     │     ┌────┴───┐ ┌──┴──┐ ┌──┴──┐
                     │     │darkuart│ │Timer│ │GPIO │
                     │     └───┬────┘ └─────┘ └──┬──┘
                     │         │                  │
      DB9 RS232 <────│── TXD   │         LED[7:0]─│──> Red LEDs
      DB9 RS232 ────>│── RXD   │        IPORT <───│── Switches
                     └──────────────────────────────┘
```

---

## Module-by-Module Walkthrough

### 1. darkpll — Clock Generator (`darkpll.v`)

**Purpose:** Convert the board's external clock to the frequency the CPU needs.

The DE2 board provides a 50 MHz oscillator. The CPU is designed to run at
100 MHz. The PLL (Phase-Locked Loop) multiplies the clock by 2:

```
50 MHz input × 2 = 100 MHz output
```

It also synchronises the reset signal: when you press KEY[0], the PLL holds
`RES` high for several clock cycles to ensure every module starts cleanly.

On different FPGA families (Xilinx, Lattice, Altera), the PLL uses the
vendor's specific IP block. In simulation (Icarus Verilog), the PLL is
replaced by a simple clock toggle.

---

### 2. darkbridge — Bus Bridge (`darkbridge.v`)

**Purpose:** Connect the CPU's buses to the rest of the system.

The CPU has two independent buses:
- **I-bus** (instruction bus): read-only, fetches one instruction per cycle
- **D-bus** (data bus): read/write, for load/store operations

DarkBridge has two operating modes:

#### Harvard Mode (default, `__HARVARD__` defined)

Both buses operate independently in parallel. The I-bus goes directly to BRAM
for instructions, while the D-bus goes through the address decoder to access
BRAM, I/O, or SDRAM. This gives the best performance.

#### Von Neumann Mode (for shared memory)

When using a single-port memory (like SDRAM), both buses must share one
physical port. DarkBridge time-multiplexes them: first it serves data
requests, then instruction requests. This is slower but necessary for
external memory. L1 caches help hide the penalty.

DarkBridge also instantiates the optional **L1 caches** (darkcache):
- **I-cache**: caches instruction fetches to avoid re-reading from slow memory
- **D-cache**: caches data reads

---

### 3. darkram — Block RAM (`darkram.v`)

**Purpose:** On-chip memory that stores both the program (instructions) and data.

FPGAs contain built-in memory blocks called **Block RAM** (BRAM). DarkRAM
configures them as a dual-port memory:

- **Port A** (instruction port): read-only, connected to the I-bus
- **Port B** (data port): read/write, connected to the D-bus

The memory size is controlled by `MLEN` in `config.vh`:
- `MLEN = 13` → 2^13 = 8192 bytes = 8 KB
- `MLEN = 15` → 2^15 = 32768 bytes = 32 KB

At startup, the memory is initialised from the file `darksocv.mem`, which
contains the compiled firmware in hexadecimal format.

**Write logic:** Supports individual byte writes using byte-enable signals.
When you write a single byte (e.g., `SB` instruction), only that byte within
the 32-bit word is modified. This is handled either by:
- **Direct byte write** (default): each byte lane has its own write enable
- **Read-Modify-Write** (`__RMW_CYCLE__`): read the word, modify the byte,
  write back — costs 1 extra wait-state

---

### 4. darkio — I/O Controller (`darkio.v`)

**Purpose:** Provide all the peripheral registers that software can read/write.

DarkIO occupies address space `0x40000000 – 0x7FFFFFFF` (the `CS=01` region).
It contains:

| Offset | Register | R/W | Description |
|---|---|---|---|
| `0x00` | Board Info | R | `{IRQ_flags, core_id, clock_MHz, board_id}` |
| `0x04` | UART | R/W | UART data and status (via darkuart) |
| `0x08` | LED | R/W | LED register (directly drives FPGA LEDs) |
| `0x0C` | Timer Reload | R/W | Timer auto-reload value |
| `0x10` | Microseconds | R | Free-running microsecond counter |
| `0x14` | IPORT | R | General-purpose input (switches/buttons) |
| `0x18` | OPORT | R/W | General-purpose output |
| `0x1C` | SPI | R/W | SPI data (optional, via darkspi) |

**Timer and Interrupts:**

The timer counts down from its reload value to zero. When it reaches zero:
1. It reloads automatically
2. It sets an interrupt request flag (`IREQ[7]`)
3. If the CPU has interrupts enabled, it jumps to the interrupt handler

The microsecond counter (`TIMEUS`) increments once per microsecond regardless
of the timer — it is used by firmware to measure elapsed time.

---

### 5. darkuart — Serial Port (`darkuart.v`)

**Purpose:** Transmit and receive bytes over a serial (RS-232) connection.

The UART operates at **115200 baud, 8 data bits, no parity, 1 stop bit**.
The baud rate is derived from the system clock:

```
baud_divisor = BOARD_CK / 115200
```

At 100 MHz, this gives a divisor of ~868.

**In simulation**, the UART has special behavior:
- **TX**: instead of generating serial waveforms, it calls `$write("%c", data)`
  to print characters directly to the terminal
- **RX**: the `RXD` pin is tied high (idle), so no input is possible
- **Termination**: when the CPU prints the `>` character, the UART asserts
  `ESIMREQ`, which triggers the performance report and `$finish()`

**On real hardware**, the UART generates proper serial waveforms on `TXD` and
samples incoming data on `RXD`, using start/stop bit detection and bit
sampling at the center of each bit period.

---

### 6. darkcache — L1 Cache (`darkcache.v`)

**Purpose:** Speed up memory access by remembering recently read data.

The cache is a small, fast memory that sits between the CPU and main memory.
When the CPU reads an address:

1. **Cache hit**: the data is already in the cache → return it immediately
   (0 wait-states)
2. **Cache miss**: the data is not cached → forward the request to main memory,
   wait for the response, store a copy in the cache for next time

The cache uses a **direct-mapped** scheme:
- Cache depth is 2^N entries (configured by `__CDEPTH__`)
- Each entry stores: a **tag** (the upper address bits), the **data** (32 bits),
  and a **valid** flag
- The lower address bits select which cache entry to check

When the CPU writes to a cached address, the cache either **updates** the
entry (if writing a full word) or **invalidates** it (if writing a partial
byte/halfword).

---

### 7. darkmac — Multiply-Accumulate (`darkmac.v`)

**Purpose:** Optional hardware accelerator for multiply-accumulate operations.

When `__COPROCESSOR__` and `__MAC16X16__` are enabled, this module provides a
custom instruction:

```
mac rd, rs1, rs2   →   rd = rd + (rs1[15:0] × rs2[15:0])
```

It multiplies the lower 16 bits of two registers and adds the result to the
destination register. This is useful for DSP (Digital Signal Processing)
applications. The operation is fully combinational (no extra clock cycles).

---

### 8. darkspi — SPI Master (`darkspi.v`)

**Purpose:** Optional SPI interface for communicating with external sensors.

Supports 16-bit and 24-bit SPI transfers, designed for devices like the
STMicroelectronics LIS3DH accelerometer. Not used in the DE2 configuration.

---

## Address Decoder in darksocv.v

The top-level SoC uses the **top 2 bits** of the 32-bit address to route
bus transactions:

```verilog
XDREQMUX[0] = XDREQ && XADDR[31:30] == 2'b00;  // → darkram  (BRAM)
XDREQMUX[1] = XDREQ && XADDR[31:30] == 2'b01;  // → darkio   (peripherals)
XDREQMUX[2] = XDREQ && XADDR[31:30] == 2'b10;  // → SDRAM    (external)
XDREQMUX[3] = XDREQ && XADDR[31:30] == 2'b11;  // → (unused)
```

The data output from the selected peripheral is muxed back:

```verilog
XXATAI = XATAIMUX[XADDR[31:30]];
XXDACK = XDACKMUX[XADDR[31:30]];
```

---

## Reset Sequence

When the FPGA powers up or KEY[0] is pressed:

1. `darkpll` holds `RES` high for 128 clock cycles
2. The CPU's internal `XRES` stays high → `IFPC` is loaded with address `0x00000000`
3. The pipeline `FLUSH` counter is set to 2
4. After reset deasserts, the CPU fetches its first instruction from address 0
5. This is the `boot.S` assembly code, which sets up the stack pointer and
   calls `main()`
