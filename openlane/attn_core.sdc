create_clock [get_ports clk] -name core_clk -period 10.000

# Treat the async reset as a false path for this early backend smoke flow.
set_false_path -from [get_ports rst_n]

# Keep I/O unconstrained but explicit so timing reports remain readable.
set_input_delay 0.0 -clock core_clk [all_inputs]
set_output_delay 0.0 -clock core_clk [all_outputs]
