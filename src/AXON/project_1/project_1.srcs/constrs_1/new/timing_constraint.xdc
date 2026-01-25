####################################################################################
# Timing Constraints for onedconv module
####################################################################################

# Clock Definition - ADJUST THIS PERIOD BASED ON YOUR TARGET FREQUENCY
# Current: 100 MHz (10 ns period)
create_clock -period 10.000 -name sys_clk -waveform {0.000 5.000} [get_ports clk]

# Clock Uncertainty (accounts for jitter, skew)
set_clock_uncertainty -setup 0.200 [get_clocks sys_clk]
set_clock_uncertainty -hold 0.100 [get_clocks sys_clk]

# Input Delays - 30% of clock period
set input_delay_max [expr {10.000 * 0.3}]
set input_delay_min [expr {10.000 * 0.1}]

set_input_delay -clock sys_clk -max $input_delay_max [get_ports {rst start_whole}]
set_input_delay -clock sys_clk -min $input_delay_min [get_ports {rst start_whole}]

set_input_delay -clock sys_clk -max $input_delay_max [get_ports {stride* padding* kernel_size*}]
set_input_delay -clock sys_clk -min $input_delay_min [get_ports {stride* padding* kernel_size*}]

set_input_delay -clock sys_clk -max $input_delay_max [get_ports {input_channels* temporal_length* filter_number*}]
set_input_delay -clock sys_clk -min $input_delay_min [get_ports {input_channels* temporal_length* filter_number*}]

# Output Delays - 30% of clock period
set output_delay_max [expr {10.000 * 0.3}]
set output_delay_min [expr {10.000 * 0.1}]

set_output_delay -clock sys_clk -max $output_delay_max [get_ports {done_all}]
set_output_delay -clock sys_clk -min $output_delay_min [get_ports {done_all}]

set_output_delay -clock sys_clk -max $output_delay_max [get_ports {output_result*}]
set_output_delay -clock sys_clk -min $output_delay_min [get_ports {output_result*}]

# False Paths (if rst is async)
# Uncomment if your reset is asynchronous
# set_false_path -from [get_ports rst]

####################################################################################