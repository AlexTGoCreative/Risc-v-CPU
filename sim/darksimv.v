`timescale 1ns / 1ps
`include "../rtl/config.vh"

// clock and reset logic

module darksimv;

    reg CLK = 0;
    
    reg RES = 1;

    initial while(1) #(500e6/`BOARD_CK) CLK = !CLK; // clock generator w/ freq defined by config.vh

    integer i;

    initial
    begin
`ifdef __ICARUS__
        $dumpfile("darksocv.vcd");
        $dumpvars();

    `ifdef __REGDUMP__
        for(i=0;i!=`RLEN;i=i+1)
        begin
            $dumpvars(0,soc0.bridge0.core0.REGS[i]);
        end
    `endif
`endif
        $display("reset (startup)");
        #1e3    RES = 0;            // wait 1us in reset state
        //#1000e3 RES = 1;            // run  1ms
        //$display("reset (restart)");
        //#1e3    RES = 0;            // wait 1us in reset state
        //#1000e3 $finish();          // run  1ms
    end

    wire TX;
    wire RX = 1;

`ifdef __SDRAM__

    // sdram sim model!

    wire        S_NWE,S_CLK;
    wire  [1:0] S_DQM;
    reg  [15:0] S_DBFF = 0;  
    wire [15:0] S_DB = S_NWE ? S_DBFF : 16'hzzzz;

    always@(negedge S_CLK)
    begin
        if(S_NWE==0 && S_DQM[1]==0) S_DBFF[15:8] <= S_DB[15:8];
        if(S_NWE==0 && S_DQM[0]==0) S_DBFF[ 7:0] <= S_DB[ 7:0];
    end

`endif

    darksocv
`ifdef SPI
    #(.SPI_DIV_COEF(1))
`endif
    soc0
    (
        .XCLK(CLK),
        .XRES(|RES),
`ifdef __SDRAM__
        .S_CLK(S_CLK),
        .S_NWE(S_NWE),
        .S_DQM(S_DQM),
        .S_DB (S_DB),
`endif
        .IPORT(0),
        .UART_RXD(RX),
        .UART_TXD(TX)
    );

endmodule
