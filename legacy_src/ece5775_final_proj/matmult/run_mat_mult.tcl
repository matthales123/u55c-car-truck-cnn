#=============================================================================
# run_mult.tcl 
#=============================================================================
# @brief: A Tcl script for synthesizing the mat mult design.
#
# @desc: This script launches a batch of simulation & synthesis runs
# to quickly explore different K parameters.
#
# 1. The user specifies the list of K values.
# 2. Useful simulation & synthesis stats are consolidated into ./result/result.csv

#------------------------------------------------------
# Remove old result file
#------------------------------------------------------
set filename "mat_mult_result.csv"
file delete -force "./result/${filename}"

#------------------------------------------------------
# You can specify a set of parameter K to explore.
#------------------------------------------------------
#set value_k { 1 2 3 4 5 }
set value_k { 1 }
#------------------------------------------------------
# run batch experiments
#------------------------------------------------------
foreach { K } $value_k {

# Define the bitwidth macros from CFLAGs
set CFLAGS "-DK_CONST=${K}"

# Project name
set hls_prj ${K}-mat_mult.prj

# Open/reset the project
open_project ${hls_prj} -reset
# Top function of the design is "matmult"
set_top matmult

# Add design and testbench files
add_files matmult.cpp -cflags $CFLAGS
add_files -tb matmult_test.cpp -cflags $CFLAGS
#add_files -tb data

open_solution "solution1"
# Use Zynq device
set_part {xc7z020clg484-1}

# Target clock period is 10ns
create_clock -period 10

# Do not inline update_knn and knn_vote functions 
#set_directive_inline -off update_knn
#set_directive_inline -off knn_vote
### You can add your own directives here ###


# Pipeline the main loop!
set_directive_pipeline matmult/LOOP_MAT_MULT_2

#array partitions
set_directive_array_partition -type complete  matmult out_vec

#loop unrolls
#set_directive_loop_unroll matmult/LOOP_MAT_MULT_1
#set_directive_loop_unroll matmult/LOOP_MAT_MULT_2
set_directive_loop_unroll matmult/LOOP_MAT_MULT_3

# Simulate the C++ design
csim_design
# Synthesize the design
csynth_design
# Co-simulate the design
#cosim_design

#---------------------------------------------
# Collect & dump out results from HLS reports
#---------------------------------------------
set argv [list $filename $hls_prj]
set argc 2
source "collect_result.tcl"
}
exit
