#=============================================================================
# run_more.tcl 
#=============================================================================
# @brief: A Tcl script for synthesizing the baseline digit recongnition design.

# Project name
set hls_prj mlp_more.prj

# Open/reset the project
open_project ${hls_prj} -reset

# Top function of the design is "dut"
set_top dut

# Add design and testbench files
add_files mlp.cpp
add_files -tb mlp_test.cpp
add_files layer.cpp
add_files -tb data

open_solution "solution1"
# Use Zynq device
set_part {xc7z020clg484-1}

# Target clock period is 10ns
create_clock -period 10

### You can insert your own directives here ###

############################################
# -------------------------------------------------
#array partitions
# -------------------------------------------------
set_directive_array_partition -type block -factor 8 max_pool input
set_directive_array_partition -type block -factor 8 max_pool output
set_directive_array_partition -type block -factor 8 conv1 input
set_directive_array_partition -type block -factor 8 conv1 output

# Unrolling DENSE function ------------------------
# set_directive_loop_unroll dense_mlp/LOOP_DENSE_MLP_1
# set_directive_pipeline dense_mlp/LOOP_DENSE_MLP_0

# Unrolling RESHAPE function ----------------------
# set_directive_loop_unroll reshape/LOOP_RESHAPE_0
set_directive_loop_unroll reshape/LOOP_RESHAPE_1
set_directive_loop_unroll reshape/LOOP_RESHAPE_2

# Unrolling CONV function --------------------------
set_directive_loop_unroll conv1/LOOP_N
set_directive_loop_unroll conv1/LOOP_X
set_directive_loop_unroll conv1/LOOP_Y
set_directive_loop_unroll conv1/LOOP_M
set_directive_loop_unroll conv1/LOOP_C
set_directive_loop_unroll conv1/LOOP_R

# -------------------------------------------------
#Pipeline
# -------------------------------------------------
set_directive_pipeline conv1/LOOP_N

# -------------------------------------------------
# Array Reshape
# -------------------------------------------------
# CONV
set_directive_array_reshape -type block -factor 4 conv1 input
set_directive_array_reshape -type block -factor 4 conv1 output
#DENSE_MLP
set_directive_array_reshape -type block -factor 4 dense_mlp input
set_directive_array_reshape -type block -factor 4 dense_mlp output
#MAX_POOL
set_directive_array_reshape -type block -factor 4 max_pool input
set_directive_array_reshape -type block -factor 4 max_pool output

# -------------------------------------------------
# LOOP MERGE
# -------------------------------------------------
set_directive_loop_merge conv1
set_directive_loop_merge dense_mlp

# -------------------------------------------------
# EXPRESSION BALANCE
# -------------------------------------------------
set_directive_expression_balance conv1
set_directive_expression_balance dense_mlp
set_directive_expression_balance max_pool

# -------------------------------------------------
# LATENCY
# -------------------------------------------------
set_directive_latency -max=10 conv1/LOOP_N
set_directive_latency -max=10 conv1/LOOP_X
set_directive_latency -max=10 conv1/LOOP_Y
set_directive_latency -max=10 conv1/LOOP_M
set_directive_latency -max=10 conv1/LOOP_C
set_directive_latency -max=10 conv1/LOOP_R

# -------------------------------------------------
# INLINE
# -------------------------------------------------
set_directive_inline -recursive conv1
set_directive_inline -recursive dense_mlp
set_directive_inline -recursive max_pool





# Simulate the C++ design
csim_design -O
# Synthesize the design
csynth_design
# Co-simulate the design
#cosim_design
exit
