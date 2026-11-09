#pragma once

#include <ap_int.h>

extern "C" {
void vector_add(const ap_uint<32>* a,
                const ap_uint<32>* b,
                ap_uint<32>* c,
                unsigned int n);
}
