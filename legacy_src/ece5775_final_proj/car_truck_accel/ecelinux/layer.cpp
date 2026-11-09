//==========================================================================
// layer.cpp
//==========================================================================
// @brief: this file contains all layers

#include "layer.h"
#include "model.h"
#include <cmath>
#include <iostream>
#include <cfloat>

using namespace std;

//----------------------------------------------------------
// Perform Dense Layer
//----------------------------------------------------------
// @param[in] : input - input fmaps
//              weight - weights
//              bias - biases
//              M - number of input fmaps
//              N - number of output fmaps
//              use_relu - enable relu or not
// @param[out] : output - output fmaps

void dense_mlp(float input[MAX_FMAP], float output[MAX_FMAP], const float *weight, const float *bias, int M, int N, bool relu)
{
// float max = -100;
LOOP_DENSE_MLP_0:
  for (int n = 0; n < N; n++)
  {
    float sum = 0;
  LOOP_DENSE_MLP_1:
    for (int m = 0; m < M; m++)
    {
      //  int w_index = m * N + n;
      int w_index = n * M + m; // N*M
      sum += input[m] * weight[w_index];
    }
    float biased = sum + bias[n];
    if (relu)
    {
      output[n] = (biased > 0) ? biased : 0;
    }
    else
    {
      output[n] = biased;
    }
    // else {
    //   if (biased > max) {
    //     max = biased;
    //     output[n] = 1;
    //   } else {
    //     output[n] = 0;
    //   }
    // }
  }
}

//----------------------------------------------------------
// Max pooling
//----------------------------------------------------------
// @param[in] : input - input fmaps
//              M - number of input fmaps
//              I - width of input fmaps
// @param[out] : output - output fmaps

void max_pool(float input[MAX_FMAP], float output[MAX_FMAP], int M, int I)
{
  int O = I / 2;
  int ifmap_size = I * I;
  int ofmap_size = O * O;

  // LOOP_MAX_POOL_0:
  //   for (int i = 0; i < MAX_FMAP; i++)
  //     output[i] = -FLT_MAX;

LOOP_MAX_POOL_1:
  for (int m = 0; m < M; m++)
  {
  LOOP_MAX_POOL_2:
    for (int x = 0; x < O; x++)
    {
    LOOP_MAX_POOL_3:
      for (int y = 0; y < O; y++)
      {
        int o_index = x + y * O + m * ofmap_size; // output[m][y][x]
        float max = FLT_MIN;
      LOOP_MAX_POOL_4:
        for (int c = 0; c < 2; c++)
        {
        LOOP_MAX_POOL_5:
          for (int r = 0; r < 2; r++)
          {
            int i_index = 2 * x + c + (2 * y + r) * I + m * ifmap_size; // input[m][2y+r][2x+c]
            // if (input[i_index])
            //   max = 1; // this is because float 1 is represented as 0xff memory
            // cout << "input[i_index]" << input[i_index] << endl;
            max = input[i_index] > max ? input[i_index] : max;
          }
        }
        output[o_index] = max;
      }
    }
  }
}

//----------------------------------------------------------
// Reshpae the Output from Conv Layer
//----------------------------------------------------------
// @param[in] : input - output fmaps from the last conv layer
// @param[out] : output - input famps of the first dense layer

void reshape(float *input, float *output)
{
LOOP_RESHAPE_0:
  for (int c = 0; c < POOL2_OUT_N_CHANNEL; c++)
  {
  LOOP_RESHAPE_1:
    for (int y = 0; y < POOL2_OUT_WIDTH; y++)
    {
    LOOP_RESHAPE_2:
      for (int x = 0; x < POOL2_OUT_WIDTH; x++)
      {
        int o_index = c + (x + y * POOL2_OUT_WIDTH) * POOL2_OUT_N_CHANNEL;             // y*x*c
        int i_index = x + y * POOL2_OUT_WIDTH + c * POOL2_OUT_WIDTH * POOL2_OUT_WIDTH; // c*y*x
        output[o_index] = input[i_index];
      }
    }
  }
}

void conv1(float input[MAX_FMAP], float output[MAX_FMAP], int M, int N, int I, int L)
{
  int O = I - F + 1;
  int ifmap_size = I * I;
  int ofmap_size = O * O;
LOOP_N:
  for (int n = 0; n < N; n++)
  {
  LOOP_X:
    for (int x = 0; x < O; x++)
    {
      // std::cout << x <<" \n";
    LOOP_Y:
      for (int y = 0; y < O; y++)
      {
        float sum = 0;
        int o_index = y + x * O + n * ofmap_size; // N*O*O output[n][x][y]
      // std::cout << "o_index: " << o_index <<" \n";
      LOOP_M:
        for (int m = 0; m < M; m++)
        {
        LOOP_C:
          for (int c = 0; c < F; c++)
          {
          LOOP_R:
            for (int r = 0; r < F; r++)
            {
              int i_index = y + c + (x + r) * I + m * ifmap_size; // M*I*I input[m][x+r][y+c]
              // int w_index = c + r * F + (n + m * N) * FILTER_SIZE; // M*N*F*F ?
              int w_index = c + r * F + (n * M + m) * FILTER_SIZE; // N*M*F*F weight[n][m][r][c]
              // std::cout << "w_index: " << w_index <<" \n";
              if (L == 0)
                sum += input[i_index] * conv1_weight[w_index];
              else
                sum += input[i_index] * conv2_weight[w_index];
            }
          }
        }
        output[o_index] = sum; // N*O*O output[n][x][y]
      }
    }
  }
}
