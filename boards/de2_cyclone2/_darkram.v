// Altera altsyncram-based BRAM replacement for darkram.v
// DarkRISCV DE2 board (Cyclone II EP2C35F672C6)
//
// Uses the altsyncram megafunction with MIF initialization.
// Memory size: 2048 x 32-bit = 8 KB (matches MLEN=13 in config.vh)
// Initialize with: boards/de2_cyclone2/memory_init.mif
//   generated from: src/darksocv.mem via scripts/helpers.py mem2mif

`timescale 1ns / 1ps
`include "../../rtl/config.vh"

module darkram #(parameter INIT_FILE = "memory_init.mif")
(
    input           CLK,
    input           RES,
    input           HLT,

    // Instruction fetch port
    input           IDREQ,
    input  [31:0]   IADDR,
    output [31:0]   IDATA,
    output          IDACK,

    // Data read/write port
    input           XDREQ,
    input           XRD,
    input           XWR,
    input  [3:0]    XBE,
    input  [31:0]   XADDR,
    input  [31:0]   XATAI,
    output [31:0]   XATAO,
    output          XDACK,

    output [3:0]    DEBUG
);

    wire [31:0] ram_q_a;
    wire [31:0] ram_q_b;
    wire        write_enable;

    // Dual-port Block RAM using altsyncram
    altsyncram #(
        .operation_mode         ("BIDIR_DUAL_PORT"),
        .width_a                (32),
        .widthad_a              (13),       // 2^13 = 8192 words = 32KB (MLEN=15)
        .numwords_a             (8192),
        .width_b                (32),
        .widthad_b              (13),
        .numwords_b             (8192),
        .lpm_type               ("altsyncram"),
        .ram_block_type         ("AUTO"),
        .init_file              (INIT_FILE),
        .outdata_reg_a          ("UNREGISTERED"),
        .outdata_reg_b          ("UNREGISTERED"),
        .indata_reg_b           ("CLOCK0"),
        .address_reg_b          ("CLOCK0"),
        .wrcontrol_wraddress_reg_b ("CLOCK0"),
        .byte_size              (8),
        .width_byteena_a        (4),
        .width_byteena_b        (4),
        .byteena_reg_b          ("CLOCK0"),
        .intended_device_family ("Cyclone II")
    ) ram_inst (
        .clock0     (CLK),
        // Port A: instruction fetch (read-only)
        .address_a  (IADDR[14:2]),
        .q_a        (ram_q_a),
        // Port B: data read/write
        .address_b  (XADDR[14:2]),
        .wren_b     (write_enable),
        .byteena_b  (XBE),
        .data_b     (XATAI),
        .q_b        (ram_q_b)
    );

    assign write_enable = XDREQ & XWR;

    // Instruction port outputs
    assign IDATA = ram_q_a;
    assign IDACK = IDREQ;

    // Data port outputs
    assign XATAO = ram_q_b;

    // Data ACK: writes complete immediately; reads need 1 cycle
    assign XDACK = (DTACK == 1) || (XDREQ && XWR);

    reg [3:0] DTACK = 0;
    always @(posedge CLK)
    begin
        DTACK <= RES ? 0 : DTACK ? DTACK - 1 : (XDREQ && XRD) ? 1 : 0;
    end

    // Note: mem2mif.py must be re-run with depth=8192 when MLEN=15

    assign DEBUG = { XDREQ, XRD, XWR, XDACK };

endmodule
