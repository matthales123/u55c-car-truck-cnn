//==========================================================================
//matmult.cpp
//==========================================================================
// @brief: Matrix multiplication

#include "matmult.h"

//----------------------------------------------------------
// Top function
//----------------------------------------------------------
// @param[a] : input - first matrix
// @param[b] : input - second matrix
// @param[c] : input - output matrix

// void matmult(float a[100][100],float b[100][100], float out[100][100]){
//    LOOP_MAT_MULT_0: for (int i = 0; i < 100; i++) {
//         LOOP_MAT_MULT_1: for (int j = 0; j < 100; j++) {
//             out[i][j] = 0;
//             LOOP_MAT_MULT_2: for (int k = 0; k < 100; k++) {
//                 out[i][j] += a[i][k] * b[k][j];
//             }
//         }
//     }
// }

void matmult(float a[100][100],float b[100][100], float out[100][100]){
    LOOP_MAT_MULT_0: for (int i = 0; i < 100; i++) {
        float out_vec[100];
        LOOP_MAT_MULT_1: for (int j = 0; j < 100; j++) {
            out_vec[j] = 0;
        }
        LOOP_MAT_MULT_2: for (int k = 0; k < 100; k++) {
            LOOP_MAT_MULT_3: for (int j = 0; j < 100; j++) {
                out_vec[j] += a[i][k] * b[k][j];
            }
        }
        LOOP_MAT_MULT_4: for (int j = 0; j < 100; j++) {
            out[i][j] = out_vec[j];
        }
    }
}