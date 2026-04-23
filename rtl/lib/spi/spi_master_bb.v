`timescale 1ns / 1ps

/*
    Simple bit-banging SPI master
    Early 3/4-wire support
*/

module spi_master_bb (
    input               CLK,    // clock
    input               RES,    // reset

    output [31:0]       IPORT,
    input  [31:0]       OPORT,

    output              CSN,    // SPI CSN output (active LOW)
    output              SCK,    // SPI clock output
    inout               MOSI,   // SPI master data output, slave data input; or m/s i/o (3-wire enabled)
    input               MISO    // SPI master data input, slave data output
);

    wire spibb_ena;
    reg [15:0] out_x_resp = 16'b0;
    reg [31:0] IPORTFF = 32'b0;
    assign spibb_ena = OPORT[3];
    assign IPORT = spibb_ena ? IPORTFF : 32'b0;
    assign CSN = spibb_ena ? OPORT[2] : 1'bz;
    assign SCK = spibb_ena ? OPORT[1] : 1'bz;
`ifdef SPI3WIRE
    wire mosi_tri;
    assign mosi_tri = OPORT[4];
    wire rd;
    assign rd = spibb_ena ? OPORT[5] : 1'b0;
    assign MOSI = !spibb_ena || (rd && mosi_tri) ? 1'bz : OPORT[0];
`else
    reg mosi_tri = 0;           // should remove
    reg rd = 0;                 // should remove
    assign MOSI = spibb_ena ? OPORT[0] : 1'bz;
`endif
    always@(posedge CLK) begin
        if (RES) begin
            out_x_resp <= 16'b0;
        end else if (spibb_ena) begin
            out_x_resp <= OPORT[31:16];
        end
    end
    always@(posedge CLK) begin
        if (RES) begin
            IPORTFF <= 32'b0;
        end else if (spibb_ena & !CSN) begin
`ifdef SPI3WIRE
//            IPORTFF <= {out_x_resp, 11'b0, rd ? MISO : 1'b1, rd, mosi_tri, spibb_ena, CSN, SCK, MOSI};
            IPORTFF <= {out_x_resp, 11'b0, mosi_tri ? 1'b1 : MISO, rd, mosi_tri, spibb_ena, CSN, SCK, MOSI};
//            IPORTFF <= {out_x_resp, 11'b0, MISO, rd, mosi_tri, spibb_ena, CSN, SCK, MOSI};
`else
            IPORTFF <= {out_x_resp, 11'b0, MISO, rd, mosi_tri, spibb_ena, CSN, SCK, MOSI};
`endif
        end
    end
endmodule
