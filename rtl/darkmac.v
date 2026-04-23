`timescale 1ns / 1ps

// proprietary extension (custom-0)
//`define CUS     7'b00010_11      // cus   rd,rs1,rs2,fc3,fct5

// configuration file

`include "../rtl/config.vh"

module darkmac
(
    input             CLK,   // clock
    input             RES,   // reset
    input             HLT,   // halt

    input             CPR_REQ,      // CPR instr request
    input      [ 2:0] CPR_FCT3,     // fct3 field
    input      [ 6:0] CPR_FCT7,     // fct7 field
    input      [31:0] CPR_RS1,      // operand RS1
    input      [31:0] CPR_RS2,      // operand RS2
    input      [31:0] CPR_RDR,      // operand RD (read)
    output     [31:0] CPR_RDW,      // operand RD (write)
    output            CPR_ACK,      // CPR instr ack (unused)

    output [3:0]  DEBUG       // old-school osciloscope based debug! :)
);

    // MAC instruction template w/ RV32 ABI
    // 
    // based on xor and add:
    // 
    // 0000000 01100 01011 100 01100 0110011 xor a2,a1,a2
    // 0000000 01010 01100 000 01010 0110011 add a0,a2,a0
    // 0000000 01100 01011 000 01010 0001011 mac a0,a1,a2 
    // 
    // aka: int mac(int a0,int a1, int a2);
    //
    // to hex code:
    // 
    // 0000 0000 1100 0101 1000 0101 0000 1011 => 0x00c5850b

    wire signed [15:0] K1TMP = CPR_RS1[15:0];

    wire signed [15:0] K2TMP = CPR_RS2[15:0];

    wire signed [31:0] KDATA = K1TMP*K2TMP;

    assign CPR_RDW = CPR_RDR + KDATA;

    assign CPR_ACK = CPR_REQ; // fully combinational

    assign DEBUG = 0;

endmodule
