//===========================================================================
// layer.h
//===========================================================================
// @brief: This header file defines the interface for the core functions.

#ifndef LAYER_H
#define LAYER_H

#include "typedefs.h"

// Constants used for MLP configuration
const int MAX_FMAP = 6 * 28 * 28; // 6*28*28

// Constants for conv
const int F = 5; // filter width
const int FILTER_SIZE = F * F;
const int PADDING = 0;
const int POOL2_OUT_N_CHANNEL = 16;
const int POOL2_OUT_WIDTH = 5;

// Perform dense layer for MLP
void dense_mlp(float input[MAX_FMAP], float output[MAX_FMAP], const float *weight, const float *bias, int M, int N, bool relu);

// Reduce the size of feature map
void max_pool(float input[MAX_FMAP], float output[MAX_FMAP], int M, int I);

// Reshape the conv laper output to dense layer input
void reshape(float *input, float *output);

// Perform convolutional kernel
void conv1(float input[MAX_FMAP], float output[MAX_FMAP], int M, int N, int I, int L);

#endif
