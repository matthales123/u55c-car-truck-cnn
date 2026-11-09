//===========================================================================
// mlp_u55c_kernel.cpp
//===========================================================================
// @brief: U55C-friendly HLS top that batches image inference from global memory.

#include "mlp.h"
#include "layer.h"
#include "typedefs.h"

static constexpr int kImageElems = 3072;

extern "C" void mlp_u55c(
    const float *images,
    bit32_t *predictions,
    int num_images)
{
#pragma HLS INTERFACE m_axi     port=images      offset=slave bundle=gmem0 max_read_burst_length=64
#pragma HLS INTERFACE m_axi     port=predictions offset=slave bundle=gmem1 max_write_burst_length=64
#pragma HLS INTERFACE s_axilite port=images      bundle=control
#pragma HLS INTERFACE s_axilite port=predictions bundle=control
#pragma HLS INTERFACE s_axilite port=num_images  bundle=control
#pragma HLS INTERFACE s_axilite port=return      bundle=control

  IMG_LOOP:
  for (int img = 0; img < num_images; ++img)
  {
#pragma HLS LOOP_TRIPCOUNT min=1 max=256
    float input[MAX_FMAP];

    LOAD_LOOP:
    for (int i = 0; i < kImageElems; ++i)
    {
#pragma HLS PIPELINE II=1
      input[i] = images[img * kImageElems + i];
    }

    predictions[img] = mlp_xcel(input);
  }
}
