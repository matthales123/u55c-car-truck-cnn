#==========================================================================
# Makefile
#==========================================================================
# @brief: A makefile the compiles and runs the matmult program
#
# @desc: 1. Enter "make" to compile & execute the digitrec program
#        2. Enter "make clean" to clean up the directory (before submission)


# Extract Vivado HLS include path
VHLS_PATH := $(dir $(shell which vivado_hls))/..
VHLS_INC ?= ${VHLS_PATH}/include

# Specify compilation flags
CFLAGS = -g -I${VHLS_INC} -DK_CONST=3

# Compile & run digitrec implementation
all: matmult.cpp matmult_test.cpp
	@echo "Compiling & executing the matrix multiplication program ..."
	g++ ${CFLAGS} matmult.cpp matmult_test.cpp -o matmult
	./matmult

# Clean up the directory before submission
clean:
	@echo "Clean up output files"
	rm -rf matmult vivado_hls.log *nn.prj result out.dat *~
