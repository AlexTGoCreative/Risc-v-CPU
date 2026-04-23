## Synopsys Design Constraints
## DarkRISCV on Terasic DE2 (Cyclone II EP2C35F672C6)

set_time_format -unit ns -decimal_places 3

#**************************************************************
# Clocks
#**************************************************************

# 50 MHz input clock on XCLK (CLOCK_50, PIN_N2)
create_clock -name {XCLK} -period 20.000 -waveform { 0.000 10.000 } [get_ports { XCLK }]

# 100 MHz PLL output (derived from XCLK via altpll in top.v)
create_generated_clock -name {CLK_100} -source [get_ports {XCLK}] -multiply_by 2 \
    [get_nets {pll_inst|altpll_component|auto_generated|wire_pll1_clk[0]}]

#**************************************************************
# Timing Exceptions
#**************************************************************

set_false_path -from [get_ports {XRES}]
set_false_path -to   [get_ports {LED[*]}]
set_false_path -to   [get_ports {UART_TXD}]
set_false_path -from [get_ports {UART_RXD}]

#**************************************************************
# Cut timing paths across clock domains
#**************************************************************

derive_clock_uncertainty
