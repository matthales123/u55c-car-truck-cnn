#include "vector_add.hpp"

extern "C" {
void vector_add(const ap_uint<32>* a,
                const ap_uint<32>* b,
                ap_uint<32>* c,
                const unsigned int n) {
#pragma HLS INTERFACE m_axi port = a offset = slave bundle = gmem0
#pragma HLS INTERFACE m_axi port = b offset = slave bundle = gmem1
#pragma HLS INTERFACE m_axi port = c offset = slave bundle = gmem2
#pragma HLS INTERFACE s_axilite port = a bundle = control
#pragma HLS INTERFACE s_axilite port = b bundle = control
#pragma HLS INTERFACE s_axilite port = c bundle = control
#pragma HLS INTERFACE s_axilite port = n bundle = control
#pragma HLS INTERFACE s_axilite port = return bundle = control

  for (unsigned int i = 0; i < n; ++i) {
#pragma HLS PIPELINE II = 1
    c[i] = a[i] + b[i];
  }
}
}
