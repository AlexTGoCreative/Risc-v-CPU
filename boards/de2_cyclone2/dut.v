// DarkRISCV - DUT wrapper for Terasic DE2
// Connects darksocv SoC to board-level signals

`timescale 1ns / 1ps
`include "../../rtl/config.vh"

module dut (
    input        clk,
    input        reset,      // KEY[0], active low; INVRES in config.vh handles polarity
    input        rx,         // UART RX
    output       tx,         // UART TX
    output [31:0] leds       // LED output bus
);

    darksocv soc0 (
        .XCLK     (clk),
        .XRES     (reset),
        .UART_RXD (rx),
        .UART_TXD (tx),
        .LED      (leds)
    );

endmodule
