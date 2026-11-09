#=============================================================================
# run_u55c_hls.tcl
#=============================================================================

set hls_prj mlp_u55c.prj

open_project ${hls_prj} -reset
set_top mlp_u55c

add_files mlp_u55c_kernel.cpp
add_files mlp.cpp
add_files layer.cpp
add_files -tb mlp_u55c_tb.cpp

open_solution "solution1"
set_part {xcu55c-fsvh2892-2L-e}
create_clock -period 3.333

csim_design -O
csynth_design

exit
