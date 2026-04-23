## DarkShell — Interactive Firmware for DarkRISCV

DarkShell is the interactive command-line firmware that runs on the RISC-V CPU.
It is written in C and communicates over UART at **115200 baud**.

> **Note:** DarkShell only works interactively on real FPGA hardware.
> In Icarus Verilog simulation the UART RX line is tied high, so no input
> can be received. Use the `calc` firmware for simulation demos instead.

---

## Boot Sequence and Expected Output

After the FPGA is programmed and reset (press **KEY[0]** on the DE2), the CPU
boots and prints a banner over the serial port:

    board: de2 (id=21)
    build: Thu, 23 Apr 2026 12:00:00 for rv32i_zicsr
    core0: darkriscv@100MHz rv32i little-endian
    bram0: text@0+... data@...+... stack@...
    bram0: XXXX bytes free
    uart0: 115.2kbps (div=54)
    timr0: XXXXHz (div=...)
    csrxx: csr_test=...
    stvec: handler@..., debug enabled...
    mtvec: handler@..., enabling interrupts...
    mtvec: interrupts enabled!

    Welcome to DarkRISCV!

    0>

The prompt `497>` shows the number of **microseconds** elapsed since the last
command was executed. Type a command and press **Enter**.

---

## Command Reference

Arguments in `[brackets]` are optional. All hex values are entered without a
`0x` prefix.

---

### System

| Command | Example | Expected output |
|---|---|---|
| `reboot` | `reboot` | Prints `rebooting...` then restarts the CPU from `_start` |
| `reboot <hex_addr>` | `reboot 80000200` | Jumps to the given address (for SDRAM boot) |
| `stop` | `stop` | Triggers an `ebreak` instruction (CPU breakpoint / halt) |
| `clear` | `clear` | Sends ANSI escape codes to clear the terminal screen |

---

### LEDs and I/O

| Command | Example | Expected output |
|---|---|---|
| `led` | `led` | Prints current LED register value, e.g. `led = ff` |
| `led <hex>` | `led a5` | Sets the 8 red LEDs to the given bitmask and prints the new value |
| `oport <hex>` | `oport 1` | Writes to the output port register, prints new value |
| `iport` | `iport` | Reads and prints the input port (switches/buttons) |
| `timer` | `timer` | Prints current timer reload value |
| `timer <dec>` | `timer 50000` | Sets the timer reload value |

**LED example:**

    0> led ff
    led = ff
    (all 8 red LEDs light up)

    0> led 0
    led = 0
    (all LEDs off)

---

### Arithmetic

All values are decimal integers.

| Command | Example | Expected output |
|---|---|---|
| `mul <a> <b>` | `mul 12 34` | `mul = 408` |
| `div <a> <b>` | `div 100 7` | `div = 14, mod = 2` |
| `mac <acc> <x> <y>` | `mac 0 16 16` | `mac = 256` (computes `acc + x*y`) |

**Notes:**
- `mul` and `div` use software emulation (the RV32I core has no M-extension by default)
- `mac` tests the optional hardware multiply-accumulate unit if present

---

### Memory Access

All addresses and values are **hexadecimal** (no `0x` prefix).

| Command | Reads/Writes | Width |
|---|---|---|
| `rdb <addr>` | Read | 8-bit byte |
| `rdw <addr>` | Read | 16-bit halfword |
| `rdl <addr>` | Read | 32-bit word |
| `rdmb <n> <addr>` | Read N items | 8-bit bytes |
| `rdmw <n> <addr>` | Read N items | 16-bit halfwords |
| `rdml <n> <addr>` | Read N items | 32-bit words |
| `wrb <addr> <val>` | Write | 8-bit byte |
| `wrw <addr> <val>` | Write | 16-bit halfword |
| `wrl <addr> <val>` | Write | 32-bit word |
| `wrmb <n> <addr> <v1> ...` | Write N items | 8-bit bytes |

**Examples:**

    0> rdl 0
    0: 13          (reads the first instruction word from BRAM)

    0> wrl 10000010 deadbeef
    10000010: deadbeef

    0> rdml 4 0
    0: 13 0 0 200013    (reads 4 words starting at address 0)

---

### Hex Dump

    dump [<hex_addr>]

Prints 256 bytes (16 rows × 16 bytes) starting at the given address as both
hex and ASCII, similar to `xxd`. If no address is given, dumps from address 0.

**Example:**

    0> dump 0
    0: 13 0 0 0 13 0 0 0 ...   ................
    10: ...

---

## Unknown Command

If you type something that does not match any command, the shell prints the
list of valid commands:

    0> hello
    command: [hello] not found.
    valid commands: clear, dump [hex], led [hex], timer [dec], oport [hex]
                    mul [dec] [dec], div [dec] [dec], mac [dec] [dec] [dec]
                    reboot, wr[m][bwl] [hex] [hex] [[hex] when m],
                    rd[m][bwl] [hex] [[hex] when m], iport

---

## Tips and Tricks

Check how many instructions each function uses (requires the `.lst` file
produced during build):

    awk '{
            if($0~/>:/) PTR=$2
            else
            if($0~/:/) DB[PTR]++
          } END {
            for(i in DB) print DB[i],i
          }' src/darksocv.lst | sort -nr

Example output:

    456 <main>:
    149 <putdx>:
    95 <printf>:
    62 <strtok>:
    62 <gets>:

---

## TODO

- Add a gdb-stub to support UART debugging
- Add a SREC decoder to support application upload via UART
- Split stdio into separate files
- Add more libc features and optimise existing ones

