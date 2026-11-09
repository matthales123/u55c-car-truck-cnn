# Primary accelerator clock constraint (300 MHz target).
create_clock -name clk -period 3.333 [get_ports clk]

# Mild uncertainty margin for realistic closure gating.
set_clock_uncertainty 0.050 [get_clocks clk]
