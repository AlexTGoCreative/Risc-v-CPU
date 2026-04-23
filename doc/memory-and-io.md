# Memory and I/O — How Software Talks to Hardware

This document explains how the firmware (C code running on the CPU)
communicates with memory and with peripheral devices such as the UART, LEDs,
and timer. It bridges the conceptual gap between the hardware description in
[soc-architecture.md](soc-architecture.md) and the firmware code in `src/`.

---

## 1. The Core Concept: Memory-Mapped I/O

In most microprocessors, the CPU communicates with peripherals through a
mechanism called **memory-mapped I/O**. The idea is beautifully simple:

> Peripheral hardware registers are placed at specific memory addresses. To
> communicate with a peripheral, the CPU reads or writes those addresses using
> the same `LW`/`SW` instructions it uses for ordinary memory.

There is **no special I/O instruction** in RISC-V. The same instruction that
reads a variable from RAM can also read the UART status register — the
address determines the destination.

### 1.1 How It Works in Hardware

When the CPU executes `SW a0, 4(a1)` (store word at address `a1 + 4`):

1. The CPU puts the address on the **D-bus** (`DADDR`) and the data on `DATAO`
2. The **address decoder** in `darksocv.v` inspects the top 2 bits of `DADDR`
3. If they are `01`, the transaction is routed to `darkio.v` (the I/O controller)
4. `darkio.v` inspects the lower address bits to identify which register
5. It updates the corresponding hardware register

From the CPU's perspective, this is indistinguishable from writing to RAM.

---

## 2. Memory Map

The 32-bit address space is divided into four regions using the top 2 bits
(`ADDR[31:30]`):

| Address range | Bits [31:30] | Size | Description |
|---|---|---|---|
| `0x00000000` – `0x3FFFFFFF` | `00` | 1 GB | Block RAM (program + data) |
| `0x40000000` – `0x7FFFFFFF` | `01` | 1 GB | I/O registers (DarkIO) |
| `0x80000000` – `0xBFFFFFFF` | `10` | 1 GB | External SDRAM (optional) |
| `0xC0000000` – `0xFFFFFFFF` | `11` | 1 GB | (unused) |

Only a small portion of each region is actually populated:
- BRAM: `MLEN = 15` → 32 KB (addresses `0x0000` – `0x7FFF` are valid)
- I/O: 8 registers at `0x40000000` – `0x4000001F`
- SDRAM: up to 16 MB (if the controller is instantiated)

Accessing an unmapped address returns undefined data (typically `0`) and does
not cause a hardware exception in the base DarkRISCV configuration.

### 2.1 The Linker Script and Memory Layout

The compiler toolchain needs to know where to place code and data. This is
specified in `src/darksocv.lds` (the **linker script**), which defines:

```
MEMORY {
    ROM (rx)  : ORIGIN = 0x00000000, LENGTH = 32K   /* .text goes here */
    RAM (rwx) : ORIGIN = 0x00001000, LENGTH = 28K   /* .data/.bss/stack */
}

SECTIONS {
    .text  : { *(.text*)  } > ROM        /* program code */
    .rodata: { *(.rodata*)} > ROM        /* read-only constants */
    .data  : { *(.data*)  } > RAM AT>ROM /* initialised variables */
    .bss   : { *(.bss*)   } > RAM        /* zero-initialised variables */
    _stack = ORIGIN(RAM) + LENGTH(RAM);  /* stack starts at top of RAM */
}
```

The stack grows **downward** from `_stack`. The startup code in `boot.S`
loads `_stack` into the stack pointer register (`sp = x2`).

**Important:** The `LENGTH` in the linker script must match `MLEN` in
`rtl/config.vh`. If they disagree, the firmware may attempt to access
addresses beyond the physical BRAM, producing garbage results.

---

## 3. Block RAM (BRAM) — `darkram.v`

### 3.1 Organisation

The BRAM is organised as a 32-bit wide array of `2^(MLEN-2)` words. Each
word is 4 bytes (32 bits). The byte address is converted to a word address
by dropping the bottom 2 bits:

\[
\text{word\_index} = \frac{\text{byte\_address}}{4} = \text{byte\_address}[MLEN-1:2]
\]

Both the instruction fetch (Port A) and the data access (Port B) use this
same array, so instructions and data share the same physical memory.

### 3.2 Firmware Loading

**In simulation**, `$readmemh` loads the compiled firmware:

```verilog
initial $readmemh("../src/darksocv.mem", MEM);
```

Each line of `darksocv.mem` contains one 32-bit word in hexadecimal (8 hex
digits). The first line is the instruction at address `0x00000000`.

**On the FPGA**, the Quartus synthesis tool reads `memory_init.mif`
(produced by `mem2mif.py`) and pre-loads the BRAM cells with the firmware
at synthesis time. No boot loader is needed.

### 3.3 Byte Write Granularity

RISC-V store instructions can write 1, 2, or 4 bytes:

| Instruction | Bytes written | `DBE` value |
|---|---|---|
| `SW` (store word) | 4 | `4'b1111` |
| `SH` at offset 0 | 2 (bytes 0–1) | `4'b0011` |
| `SH` at offset 2 | 2 (bytes 2–3) | `4'b1100` |
| `SB` at offset 0 | 1 (byte 0) | `4'b0001` |
| `SB` at offset 1 | 1 (byte 1) | `4'b0010` |
| `SB` at offset 2 | 1 (byte 2) | `4'b0100` |
| `SB` at offset 3 | 1 (byte 3) | `4'b1000` |

The `DBE` (Data Byte Enable) signals tell BRAM exactly which bytes to update.
Bytes with `DBE = 0` are left unchanged — this implements partial writes
without read-modify-write cycles.

---

## 4. I/O Registers — `darkio.v`

All I/O registers live at base address `0x40000000`. The lower bits of the
address select the specific register:

| Offset | Byte address | C index | Register | R/W | Description |
|---|---|---|---|---|---|
| `+0x00` | `0x40000000` | `io[0]` | Board Info | R | `{irq_flags, core_id, clock_mhz, board_id}` |
| `+0x04` | `0x40000004` | `io[1]` | UART | R/W | UART data + status flags |
| `+0x08` | `0x40000008` | `io[2]` | LED | R/W | LED output register |
| `+0x0C` | `0x4000000C` | `io[3]` | Timer | R/W | Timer reload value |
| `+0x10` | `0x40000010` | `io[4]` | Microseconds | R | Free-running µs counter |
| `+0x14` | `0x40000014` | `io[5]` | IPORT | R | General-purpose inputs |
| `+0x18` | `0x40000018` | `io[6]` | OPORT | R/W | General-purpose outputs |
| `+0x1C` | `0x4000001C` | `io[7]` | SPI | R/W | SPI data (optional) |

### 4.1 Accessing I/O from C Code

```c
// Declare a pointer to the I/O base address
volatile unsigned int *io = (volatile unsigned int *)0x40000000;

// Read board info
unsigned int board_id = io[0] & 0xFF;

// Control LEDs
io[2] = 0xFF;       // turn on 8 LEDs (bits 7:0)
io[2] = 0x00;       // turn off all LEDs
io[2] ^= 0x01;      // toggle LED 0

// Send a character over UART
io[1] = 'A';        // transmit the ASCII character 'A' (0x41)

// Read UART status
unsigned int uart = io[1];
if (uart & (1 << 31)) {              // RXIRQ set: received byte available
    char ch = (char)(uart & 0xFF);   // extract the received byte
}

// Set timer to fire at 1 kHz (100 MHz / 1000 = 100000 cycles)
io[3] = 100000 - 1;   // reload value = (clock / frequency) - 1

// Read elapsed time in microseconds
unsigned int t_start = io[4];
// ... do work ...
unsigned int elapsed_us = io[4] - t_start;
```

The `volatile` qualifier is critical. Without it, the C compiler may:
- Cache a register's value in a CPU register and never re-read it (even though
  hardware may have changed it)
- Elide a write entirely (thinking "nothing reads this variable")

`volatile` prevents both optimisations: every read and write generates an
actual memory instruction.

---

## 5. UART in Detail — `darkuart.v`

### 5.1 What Is a UART?

A **UART** (Universal Asynchronous Receiver/Transmitter) converts an 8-bit
parallel byte (living inside the CPU's register) into a serial waveform
(a single wire that changes between HIGH and LOW) and vice versa.

This is how the CPU communicates with a terminal program (PuTTY, TeraTerm,
or minicom) over a serial cable (RS-232 or USB-to-serial adapter).

### 5.2 The Serial Protocol (8N1)

```
      Idle         Start  D0   D1   D2   D3   D4   D5   D6   D7   Stop  Idle
TXD: ─────────────┐     ┌────┐    ┌────┐    ┌────┐    ┌────┐    ┌──────────
                  └─────┘    └────┘    └────┘    └────┘    └────┘
                  HIGH   LOW  (8 data bits, LSB first)          HIGH
```

**Frame structure (8N1):**
1. **Idle**: line is HIGH (logical 1)
2. **Start bit**: line drops to LOW for exactly 1 bit period
3. **8 data bits**: transmitted LSB (bit 0) first
4. **Stop bit**: line returns to HIGH for 1 bit period
5. **Idle**: line remains HIGH until the next byte

"Asynchronous" means there is no clock wire. The receiver must detect the
start bit edge and then sample each subsequent bit at intervals of exactly
one bit period. Any frequency error between sender and receiver clocks must
be small enough that the sampling point stays within the valid bit window.

### 5.3 Timing Calculations

At 115200 baud (the DarkRISCV default):

\[
T_{\text{bit}} = \frac{1}{115200 \text{ bps}} \approx 8.68 \text{ µs}
\]

\[
T_{\text{byte}} = 10 \times T_{\text{bit}} = \frac{10}{115200} \approx 86.8 \text{ µs}
\]

Maximum throughput:

\[
\text{throughput} = \frac{8 \text{ bits}}{10 \text{ bits}} \times 115200 \text{ bps} = 92{,}160 \text{ bytes/s} \approx 90 \text{ KB/s}
\]

The hardware divisor:

\[
\text{divisor} = \left\lfloor \frac{f_{\text{clock}}}{f_{\text{baud}}} \right\rfloor = \left\lfloor \frac{100{,}000{,}000}{115{,}200} \right\rfloor = 868
\]

The UART counts 868 system clock cycles between bit transitions.

### 5.4 UART Register Bit Fields

**Reading `io[1]`:**

```
Bit 31 [RXIRQ]: 1 = a received byte is waiting to be read
Bit 30 [TXIRQ]: 1 = the transmitter is idle (ready for next byte)
Bits [7:0]:     the received byte (valid only when RXIRQ = 1)
Bits [29:8]:    reserved / status (implementation-specific)
```

**Writing `io[1]`:**

```
Bits [7:0]: the byte to transmit
            → the byte is loaded into the TX shift register
            → TXIRQ goes LOW (transmitter busy)
            → after ~86.8 µs, TXIRQ goes HIGH again (transmitter idle)
```

### 5.5 A Complete Transmit Sequence

Here is the full path for sending the character `'A'` (ASCII 0x41):

```
1. Firmware: io[1] = 0x41;
             → CPU: DADDR = 0x40000004, DATAO = 0x00000041, DWR = 1

2. darksocv: DADDR[31:30] = 01 → route to darkio

3. darkio:   DADDR[4:2] = 001 → UART register selected
             → writes 0x41 to UART transmit register

4. darkuart: Loads 0x41 into TX shift register [TXSR = 10'b1_01000001_0]
             (start=0, data=01000001, stop=1, idle=1)

5. darkuart: For each of 10 bit periods (868 clock cycles each):
             - Shift TXSR right by 1
             - Drive TXD = TXSR[0]
             → produces the serial waveform on the TXD pin

6. After all 10 bits: TXSR is all 1s, TXIRQ goes HIGH
   → firmware can send the next byte
```

**In simulation**, step 5 is replaced by:
```verilog
$write("%c", 0x41);   // prints 'A' directly to the terminal
```

### 5.6 Receiving Data

The receiver works by sampling the `RXD` line:

1. **Start bit detection**: the receiver waits for `RXD` to go LOW
2. **Centre alignment**: it waits half a bit period to align the sampling
   point to the centre of each bit (maximum noise margin)
3. **Bit sampling**: it samples `RXD` once every bit period for 8 bits
4. **Stop bit**: it verifies `RXD` returns HIGH (framing check)
5. **Byte assembly**: the 8 sampled bits form the received byte
6. **Interrupt flag**: `RXIRQ` is set; firmware reads `io[1]`

---

## 6. Timer

### 6.1 How the Timer Works

The timer is a **countdown register** that reloads automatically:

```
io[3] = N          (set reload value to N)

Hardware:
  TIMER = N
  every clock: TIMER = TIMER - 1
  when TIMER = 0:
      TIMER = N             (auto-reload)
      IREQ[7] = 1           (interrupt flag)
      (if interrupts enabled: jump to mtvec)
```

### 6.2 Calculating the Reload Value

To generate an interrupt at frequency \(f_{\text{irq}}\):

\[
N = \frac{f_{\text{clock}}}{f_{\text{irq}}} - 1
\]

Examples at 100 MHz:

| Desired frequency | Reload value | Calculation |
|---|---|---|
| 1 Hz | 99,999,999 | 100,000,000 ÷ 1 − 1 |
| 1 kHz | 99,999 | 100,000,000 ÷ 1000 − 1 |
| 10 kHz | 9,999 | 100,000,000 ÷ 10,000 − 1 |
| 1 MHz | 99 | 100,000,000 ÷ 1,000,000 − 1 |

```c
// Set timer to 1 kHz
io[3] = (100000000 / 1000) - 1;   // = 99999
```

### 6.3 Timer Polling vs Interrupts

**Without interrupts** (default when `__INTERRUPT__` is not defined):

The firmware checks the timer by examining `io[0]` (the board info register
contains interrupt flags):

```c
// Poll the timer interrupt flag
while (!(io[0] >> 24) & 0x80) {}  // wait until timer fires
```

**With interrupts** (when `__CSR__` and `__INTERRUPT__` are defined):

```c
// Set interrupt handler address
extern void timer_handler(void);
asm("csrw mtvec, %0" :: "r"(&timer_handler));

// Enable timer interrupt
asm("csrs mstatus, 8");    // MIE bit: global interrupt enable
asm("csrs mie, 0x880");    // MTIE bit: enable machine timer interrupt
```

The CPU automatically jumps to `timer_handler` whenever the timer fires,
without any polling loop needed in firmware.

### 6.4 Microsecond Counter

`io[4]` is a **free-running counter** that increments once per microsecond,
independent of the timer reload value:

```c
// Measure elapsed time
unsigned int t0 = io[4];
do_work();
unsigned int elapsed = io[4] - t0;   // elapsed time in microseconds
```

The counter is 32 bits, so it overflows after \(2^{32}\) microseconds ≈
4295 seconds (≈ 71 minutes). For timing intervals shorter than this, no
special overflow handling is needed.

---

## 7. LED and GPIO

### 7.1 LEDs

`io[2]` directly drives the FPGA board's LEDs. Each bit controls one LED:

```c
io[2] = 0x01;   // LED 0 on, all others off  →  binary: 00000001
io[2] = 0xFF;   // LEDs 0–7 all on           →  binary: 11111111
io[2] = 0x55;   // every other LED on        →  binary: 01010101
io[2] = 0x00;   // all LEDs off
io[2] ^= 0x01;  // toggle LED 0
```

On the DE2 board, there are 18 red LEDs (`LEDR[17:0]`). The bottom 18 bits of
`io[2]` control them. Writing `0xFF` lights up the lower 8 LEDs.

### 7.2 General-Purpose Input (`io[5]` = IPORT)

`io[5]` reads the state of physical input pins — on the DE2, these are the 18
toggle switches (`SW[17:0]`). Each bit reflects one switch:

```c
unsigned int switches = io[5] & 0xFF;    // read lower 8 switches
if (switches & 0x01) {
    // SW[0] is in the ON position
}
```

This is **read-only**: writing to `io[5]` has no effect.

### 7.3 General-Purpose Output (`io[6]` = OPORT)

`io[6]` drives general-purpose output pins. These can be connected to any
external signal — LEDs, motor drivers, digital-to-analog converters, etc.
On the DE2, these typically drive logic analyser probe points or custom
expansion connector pins.

```c
io[6] = 0x01;   // assert output pin 0 (HIGH)
io[6] = 0x00;   // deassert all output pins
```

---

## 8. SPI (Optional) — `darkspi.v`

When `__DARKIO_SPI__` is defined in `config.vh`, `io[7]` provides access to
an SPI master interface:

**SPI** (Serial Peripheral Interface) is a synchronous serial protocol used
to communicate with external ICs (sensors, flash memories, DACs, ADCs, etc.):
- **MOSI**: Master Out Slave In — data from CPU to device
- **MISO**: Master In Slave Out — data from device to CPU
- **SCK**: Serial Clock — generated by the master
- **CS/NSS**: Chip Select — selects which device to communicate with

Writing to `io[7]` initiates an SPI transfer; reading returns the received
data. The SPI module is designed for devices like the LIS3DH accelerometer.
It is not used in the DE2 configuration.

---

## 9. Complete Example: Printing a String

Here is what happens at every level of the hardware/software stack when the
firmware prints `"Hello\n"`:

**Firmware (C code):**
```c
void uart_putchar(char c) {
    while (!(io[1] & (1 << 30))) {}  // wait until TXIRQ is set (idle)
    io[1] = c;                        // write the character to UART
}

void uart_puts(const char *s) {
    while (*s) uart_putchar(*s++);
}

uart_puts("Hello\n");
```

**Instruction sequence (simplified):**
```asm
# uart_putchar('H'):
    lui  a0, 0x40000      # a0 = 0x40000000 (IO base)
.wait:
    lw   t0, 4(a0)        # t0 = io[1] (read UART status)
    andi t0, t0, 0x40000000  # mask TXIRQ bit (bit 30)
    beqz t0, .wait        # loop if transmitter busy
    li   t1, 72           # t1 = 'H' = 72 = 0x48
    sw   t1, 4(a0)        # io[1] = 'H' → transmit
```

**Hardware (signal trace):**
```
CLK:   ... │ ... │ ... │ ... │ ...
DADDR: ... │0x40000004│0x40000004│0x40000004│ ...
DRD:   ... │  1  │  0  │  0  │  0  │  0  │ ...
DWR:   ... │  0  │  0  │  1  │  0  │  0  │ ...
DATAO: ... │     │     │0x48 │     │     │ ...
        ^^^lw (read UART status)   ^^^sw (write 'H' to UART)
```

**UART output (simulation):**
```
H
```

**UART output (real hardware):**
```
TXD: ────┐     ┌──┐        ┌──────────┐       ┌────────
         └─────┘  └──┐  ┌──┘          └───┐ ┌─┘
              Start D0 D1  D2 D3 D4 D5 D6 D7  Stop
              (LOW) (0)(0)(0)(1)(0)(0)(0)(1) (HIGH)
              = 0x48 = 'H', LSB first
```
