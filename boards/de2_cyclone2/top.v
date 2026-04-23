// DarkRISCV - Terasic DE2 Top-Level Module
// Cyclone II EP2C35F672C6, 50 MHz input clock -> 100 MHz via PLL

`timescale 1ns / 1ps
`include "../../rtl/config.vh"

module top (
    input        XCLK,      // 50 MHz clock (CLOCK_50, PIN_N2)
    input        XRES,      // KEY[0] reset, active low (PIN_G26)
    input        UART_RXD,  // UART receive  (PIN_G13, via MAX232)
    output       UART_TXD,  // UART transmit (PIN_G12, via MAX232)
    output [7:0] LED        // Red LEDs LEDR[7:0]
);

    // PLL: 50 MHz -> 100 MHz
    wire clk_100;

    pll pll_inst (
        .inclk0 (XCLK),
        .c0     (clk_100)
    );

    wire [31:0] leds;
    assign LED = leds[7:0];

    dut dut_inst (
        .clk   (clk_100),
        .reset (XRES),          // KEY[0] is active-low; INVRES is set in config.vh
        .rx    (UART_RXD),
        .tx    (UART_TXD),
        .leds  (leds)
    );

endmodule
