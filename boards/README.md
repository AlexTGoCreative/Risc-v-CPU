## Supported Board

**Terasic DE2 — Altera Cyclone II EP2C35F672C6**

All project files are in `boards/de2_cyclone2/`.

| File | Purpose |
|---|---|
| `darksocv.qpf` | Quartus project file |
| `darksocv.qsf` | Pin assignments and device settings |
| `darksocv.sdc` | Timing constraints (50 MHz in → 100 MHz via PLL) |
| `top.v` | Top-level Verilog wrapper |
| `dut.v` | SoC instantiation |
| `pll.v` | altpll megafunction (50 → 100 MHz) |
| `_darkram.v` | Altera altsyncram BRAM (8 KB) |
| `mem2mif.py` | Converts `darksocv.mem` to Altera MIF format |

---

## Step-by-Step: Build and Program the DE2

### Prerequisites
- **Quartus Prime** 20.1 Lite Edition (free) with Cyclone II device support installed
- **USB Blaster** driver installed (comes with Quartus)
- A **USB-A to USB-B** cable (for JTAG programming via the USB Blaster port on the DE2)
- A **DB9 RS-232 cable** or **USB-to-RS232 adapter** (for UART communication)
- A serial terminal — **PuTTY** or **TeraTerm** on Windows

---

### Step 1 — Build the firmware

From the project root:

    cd src
    # Make sure src/Makefile has APPLICATION = darkshell (or calc)
    make all

This produces `src/darksocv.mem` (the firmware image).

---

### Step 2 — Convert firmware to MIF format

    cd boards/de2_cyclone2
    py mem2mif.py ..\..\src\darksocv.mem memory_init.mif 8192

This reads `../../src/darksocv.mem` and writes `memory_init.mif` in the same folder.
The MIF file is referenced by `_darkram.v` and gets compiled into the FPGA bitstream.

---

### Step 3 — Open the project in Quartus

1. Launch **Quartus Prime**
2. **File → Open Project** → navigate to `boards/de2_cyclone2/darksocv.qpf`
3. The project opens with device **EP2C35F672C6** already selected

---

### Step 4 — Compile (synthesise + place & route)

1. Click **Processing → Start Compilation** (or press `Ctrl+L`)
2. Wait for compilation to finish (~5–10 minutes)
3. Check for errors in the Messages pane — warnings about timing on UART/LEDs are expected and safe

---

### Step 5 — Connect the DE2 board

1. Connect the **USB Blaster** cable from the DE2's `USB BLASTER` port to your PC
2. Power the DE2 via its DC adapter (5V)
3. The board should power on — all LEDs and 7-segment displays will light up with the factory demo

---

### Step 6 — Program the FPGA

1. In Quartus: **Tools → Programmer**
2. Click **Hardware Setup** → select **USB-Blaster**
3. Click **Auto Detect** — the EP2C35 should appear
4. Add the file `output_files/darksocv.sof` if not already listed
5. Check the **Program/Configure** box
6. Click **Start**
7. Progress bar reaches 100% → FPGA is programmed (not persistent — lost on power cycle)

> To make it persistent, program the `.pof` file into the serial flash using **Active Serial** mode instead.

---

### Step 7 — Connect the serial terminal

The UART is on the **DB9 RS-232** connector (via MAX232 level shifter) on the DE2.

1. Connect a DB9 cable or USB-to-RS232 adapter between the DE2 and your PC
2. Open **PuTTY** → Connection type: **Serial**
3. Set:
   - **Port**: your COM port (check Device Manager)
   - **Speed**: `115200`
   - **Data bits**: `8`, **Stop bits**: `1`, **Parity**: `None`, **Flow control**: `None`
4. Click **Open**

---

### Step 8 — Interact with the shell

After programming, press **KEY[0]** (the rightmost push button) to reset the CPU.
You should see the boot banner followed by the shell prompt:

    board: de2 (id=21)
    build: Thu, 23 Apr 2026 ...
    core0: darkriscv@100MHz rv32i little-endian
    ...
    Welcome to DarkRISCV!

    497>

Type any command and press Enter. See `src/darkshell/README.md` for the full command list.
