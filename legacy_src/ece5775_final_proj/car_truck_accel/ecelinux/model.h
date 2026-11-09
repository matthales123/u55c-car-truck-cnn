//===========================================================================
// model.h
//===========================================================================
// @brief: This header file include the parameters for mlp

#ifndef MODEL_CONV
#define MODEL_CONV

#include "layer.h"

// Optional debug vector used in legacy experiments. Keep disabled by default
// since the original "data/first_img" artifact is not present in this repo.
#ifdef MLP_INCLUDE_FIRST_IMG
float const first_img[3072] = {
#include "data/first_img"
};
#endif

// 6*3*5*5 = 450
const float conv1_weight[450] = {
#include "data2/conv1_weight"
};

const float conv1_bias[6] = {
#include "data2/conv1_bias"
};

// 16*6*5*5 = 2400
const float conv2_weight[2400] = {
#include "data2/conv2_weight"
};

const float conv2_bias[16] = {
#include "data2/conv2_bias"
};

// 120*400=48000
const float fc1_weight[48000] = {
#include "data2/fc1_weight"
};

const float fc1_bias[120] = {
#include "data2/fc1_bias"
};

// 84*120=10080
const float fc2_weight[10080] = {
#include "data2/fc2_weight"
};

const float fc2_bias[84] = {
#include "data2/fc2_bias"
};

// 2*84=168
const float fc3_weight[168] = {
#include "data2/fc3_weight"
};

const float fc3_bias[2] = {
#include "data2/fc3_bias"
};

#endif
