#==========================================================================
# Makefile
#==========================================================================
# @brief: A makefile the compiles and runs the digitrec program
#
# @desc: 1. "make" or "make sw" runs software execution by default
#        2. "make fpga" invokes the HW accelerator
#        3. "make clean" cleans up the directory


INC_PATH=/usr/include/vivado_hls
CFLAGS = -I${INC_PATH} -DHLS_NO_XIL_FPO_LIB

all: sw

sw: mlp.cpp mlp_test.cpp layer.cpp
	@echo "Compiling & executing cnn software program on ARM ..."
	g++ ${CFLAGS} $^ -o mlp-arm
	./mlp-arm

fpga: host.cpp 
	@echo "Compiling host program & running cnn accelerator ..."
	g++ ${CFLAGS} $^ -o mlp-fpga
	./mlp-fpga

# Clean up the directory before submission
clean:
	@echo "Clean up output files"
	rm -rf mlp-arm vivado_hls.log *.prj result out.dat *~
	rm -rf mlp-fpga
