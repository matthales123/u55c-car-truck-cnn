//===========================================================================
// mlp.h
//===========================================================================
// @brief: This header file defines the interface for the core functions.

#ifndef MLP
#define MLP
#include "layer.h"
#include "typedefs.h"
#include <hls_stream.h>

// Top function for synthesis
void dut (
  hls::stream<bit32_t> &strm_in,
  hls::stream<bit32_t> &strm_out
);

// Top function for mlp accelerator
bit32_t mlp_xcel(float input[MAX_FMAP]);

#endif
