# Memory and I/O — How Software Talks to Hardware

This document explains how firmware (C code) running on the CPU communicates
with memory and peripheral devices.

---

## What Is Memory-Mapped I/O?

When the CPU executes a `store` instruction, it sends an address and data to
the bus. If the address falls in the BRAM range, the data goes to memory. But
if the address falls in the I/O range, the data goes to a hardware register —
an LED lights up, a character is sent over the serial port, or a timer starts.

From the CPU's perspective, **everything looks like memory**. There is no
special "I/O instruction" — the same `LW` (load word) and `SW` (store word)
instructions work for both memory and peripherals. The address determines
where the data goes.

---

## Memory Map

| Address Range | Size | Description |
|---|---|---|
| `0x00000000` – `0x00007FFF` | 32 KB | Block RAM (program + data) |
| `0x40000000` – `0x7FFFFFFF` | 1 GB | I/O registers (darkio) |
| `0x80000000` – `0xBFFFFFFF` | 1 GB | External SDRAM (optional) |
| `0xC0000000` – `0xFFFFFFFF` | 1 GB | (unused) |

The top 2 bits of the address (`[31:30]`) select the region. Within the BRAM
region, the usable addresses depend on `MLEN`:

- `MLEN = 13` → addresses `0x0000` to `0x1FFF` (8 KB)
- `MLEN = 14` → addresses `0x0000` to `0x3FFF` (16 KB)
- `MLEN = 15` → addresses `0x0000` to `0x7FFF` (32 KB)

---

## Block RAM (darkram.v)

### How It Works

The BRAM is organized as an array of 32-bit words. Each clock cycle, both
ports can access the memory simultaneously:

```
Port A (Instruction Fetch)           Port B (Data Access)
─────────────────────────           ───────────────────────
Address → IADDR[MLEN-1:2]          Address → DADDR[MLEN-1:2]
Output  → IDATA (32 bits)          Input   → DATAO (32 bits)
Always read                         Output  → DATAI (32 bits)
                                    Control → DWR (write), DRD (read)
                                    Byte enable → DBE[3:0]
```

The `[MLEN-1:2]` indexing divides the byte address by 4 (since each entry is
4 bytes / 32 bits).

### Firmware Loading

At simulation start, the memory contents are loaded from a hex file:

```verilog
$readmemh("../src/darksocv.mem", MEM);
```

This file is produced by the build system:
1. `riscv-none-elf-gcc` compiles C code to RISC-V machine code (`.o` files)
2. `riscv-none-elf-ld` links them into a flat binary
3. `riscv-none-elf-objcopy` extracts raw bytes
4. `helpers.py bin2hex` converts the binary into hex format for `$readmemh`

On real hardware, the FPGA synthesis tool reads the same data and initialises
the BRAM contents at configuration time.

### Byte Writes

RISC-V supports writing individual bytes (`SB`), halfwords (`SH`, 2 bytes),
or full words (`SW`, 4 bytes). Since BRAM is 32 bits wide, writing less than
a full word requires byte-enable signals:

```
SW (store word):    DBE = 4'b1111   →  all 4 bytes written
SH (store half):    DBE = 4'b0011   or  4'b1100  (depending on address[1])
SB (store byte):    DBE = 4'b0001   or  4'b0010  or  4'b0100  or  4'b1000
```

---

## I/O Registers (darkio.v)

### Register Map

All I/O registers are at base address `0x40000000`. The lower 5 bits of the
address select the register:

| Offset | C Address | Name | R/W | Description |
|---|---|---|---|---|
| `0x00` | `io[0]` | Board Info | R | Board ID, clock speed, IRQ flags |
| `0x04` | `io[1]` | UART Data | R/W | Read: received byte + status; Write: transmit byte |
| `0x08` | `io[2]` | LED | R/W | Each bit controls one LED on the board |
| `0x0C` | `io[3]` | Timer | R/W | Timer reload value (counts down to zero) |
| `0x10` | `io[4]` | Microsecond | R | Free-running microsecond counter |
| `0x14` | `io[5]` | IPORT | R | General-purpose input port (switches, buttons) |
| `0x18` | `io[6]` | OPORT | R/W | General-purpose output port |
| `0x1C` | `io[7]` | SPI | R/W | SPI data register (optional) |

### How Firmware Accesses I/O

In C, the I/O registers are accessed through a pointer to the I/O base address:

```c
volatile unsigned int *io = (volatile unsigned int *)0x40000000;

// Write to LEDs
io[2] = 0xFF;          // turn on 8 LEDs

// Read the timer
unsigned int t = io[4]; // read microsecond counter

// Send a character over UART
io[1] = 'A';           // transmit 'A'

// Read a character from UART (if available)
unsigned int rx = io[1]; // read UART status + data
```

The `volatile` keyword tells the C compiler not to optimise away reads/writes
to these addresses — each access must actually happen, because the hardware
state may change between reads.

---

## UART in Detail (darkuart.v)

### What Is a UART?

A **UART** (Universal Asynchronous Receiver/Transmitter) converts parallel
data (8-bit bytes inside the CPU) into serial data (a single wire toggling
high and low) and vice versa. This is how the CPU communicates with a
terminal (PuTTY, minicom, etc.) over a serial cable.

### Serial Protocol

```
  Idle    Start   D0   D1   D2   D3   D4   D5   D6   D7   Stop   Idle
────────┐     ┌────┐    ┌────┐    ┌────┐    ┌────┐    ┌─────────────────
        └─────┘    └────┘    └────┘    └────┘    └────┘

  HIGH    LOW   data bits (LSB first)              HIGH
```

- **Idle**: line is HIGH
- **Start bit**: line goes LOW for one bit period
- **Data bits**: 8 bits, LSB (least significant bit) first
- **Stop bit**: line goes HIGH for one bit period

At 115200 baud, each bit period is 1/115200 ≈ 8.68 microseconds. A full
byte takes approximately 86.8 µs (start + 8 data + stop = 10 bit periods).

### UART Status Register

When firmware reads the UART register (`io[1]`):

```
Bit 31 (UART_RXIRQ) : 1 if a byte has been received and is waiting
Bit 30 (UART_TXIRQ) : 1 if the transmitter is done (ready for next byte)
Bits [7:0]           : The received data byte (valid if RXIRQ=1)
```

When firmware writes to the UART register:
- Bits [7:0] are loaded into the transmit shift register
- The UART begins shifting them out as a serial waveform

### UART in Simulation

In simulation, the UART skips the serial waveform entirely:

```verilog
// Transmit: just print the character
$write("%c", UART_TX_DATA);

// Detect '>' character → end simulation
if (UART_TX_DATA == ">") ESIMREQ <= 1;
```

This means simulation output appears directly in the terminal, making it easy
to test firmware without a real serial port.

---

## Timer

The timer works by counting down:

1. Firmware writes a reload value to `io[3]` (e.g., `io[3] = 100000` for a
   1 ms interval at 100 MHz)
2. The counter decrements each clock cycle
3. When it reaches zero:
   - It reloads the original value automatically
   - It sets an interrupt flag (`IREQ[7]`)
   - If the CPU has interrupts enabled, it jumps to the interrupt handler

### Microsecond Counter

`io[4]` is a separate free-running counter that increments once per
microsecond. Firmware uses it for timing:

```c
unsigned int start = io[4];
// ... do some work ...
unsigned int elapsed_us = io[4] - start;
```

---

## LEDs

`io[2]` directly controls the FPGA board's LEDs:

```c
io[2] = 0x01;  // LED 0 on, all others off
io[2] = 0xFF;  // all 8 LEDs on
io[2] = 0x00;  // all LEDs off
```

Each bit corresponds to one LED. Writing a `1` turns the LED on; writing `0`
turns it off.

---

## General-Purpose I/O

- **IPORT** (`io[5]`): reads the state of switches or buttons on the FPGA board.
  Each bit corresponds to one input pin. This is read-only.

- **OPORT** (`io[6]`): general-purpose output register. Each bit drives an
  FPGA output pin. Can be used for custom hardware signals.

---

## SPI (Optional)

When `__DARKIO_SPI__` is enabled, `io[7]` provides a simple SPI master
interface through `darkspi.v`. Writing triggers an SPI transfer; reading
returns the received data.

---

## Putting It All Together: A Complete I/O Example

Here is what happens when firmware prints the letter `A` over the UART:

```
1. CPU executes:  SW x5, 4(x10)    — store register x5 to address io[1]
                  (x5 = 0x41 = 'A', x10 = 0x40000000)

2. darkriscv.v:   DADDR = 0x40000004, DATAO = 0x00000041, DWR = 1

3. darksocv.v:    DADDR[31:30] = 01 → route to darkio

4. darkio.v:      DADDR[4:2] = 001 → UART register selected
                  Writes 0x41 to the UART transmit register

5. darkuart.v:    Loads 0x41 into shift register
                  [Simulation: $write("%c", 0x41) → prints 'A']
                  [Hardware: starts shifting out start + 01000001 + stop]

6. darkuart.v:    After transmission, sets UART_TXIRQ = 1
                  (firmware can poll this to know when to send the next byte)
```
