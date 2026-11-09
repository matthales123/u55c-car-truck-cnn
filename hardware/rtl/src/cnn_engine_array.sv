`timescale 1ns/1ps

module cnn_engine_array #(
  parameter int ENGINE_COUNT = 4,
  parameter int WORK_ID_W = 16,
  parameter int ADDR_W = 64,
  parameter int DATA_W      = 8,
  parameter int ACC_W       = 32,
  parameter int C_IN        = 3,
  parameter int IN_H        = 32,
  parameter int IN_W        = 32,
  parameter int C1_OUT      = 6,
  parameter int K1          = 5,
  parameter int C2_OUT      = 16,
  parameter int K2          = 5,
  parameter int POOL        = 2,
  parameter int FC1_OUT     = 120,
  parameter int FC2_OUT     = 84,
  parameter int FC3_OUT     = 2,
  parameter int CONV1_MACS_PER_CYCLE = 2,
  parameter int CONV2_MACS_PER_CYCLE = 2,
  parameter int FC1_MACS_PER_CYCLE   = 2,
  parameter int FC2_MACS_PER_CYCLE   = 2,
  parameter int FC3_MACS_PER_CYCLE   = 2,
  parameter int SHIFT_CONV1 = 9,
  parameter int SHIFT_CONV2 = 7,
  parameter int SHIFT_FC1   = 11,
  parameter int SHIFT_FC2   = 10,
  parameter int STATIC_WEIGHT_PROFILE = 1,
  parameter bit STATIC_DEMO_WEIGHTS   = 1'b0
) (
  input  logic                           clk,
  input  logic                           rst_n,

  input  logic [ENGINE_COUNT-1:0]        req_valid,
  output logic [ENGINE_COUNT-1:0]        req_ready,
  input  logic [ENGINE_COUNT*WORK_ID_W-1:0] req_work_id,
  input  logic [ENGINE_COUNT*ADDR_W-1:0] req_img_base_addr,
  input  logic [ENGINE_COUNT-1:0]        req_mode_fast_strict,

  output logic [ENGINE_COUNT-1:0]        rsp_valid,
  input  logic [ENGINE_COUNT-1:0]        rsp_ready,
  output logic [ENGINE_COUNT*WORK_ID_W-1:0] rsp_work_id,
  output logic [ENGINE_COUNT-1:0]        rsp_class_id,
  output logic [ENGINE_COUNT*32-1:0]     rsp_logit0,
  output logic [ENGINE_COUNT*32-1:0]     rsp_logit1,
  output logic [ENGINE_COUNT-1:0]        rsp_error,

  output logic [ENGINE_COUNT-1:0]        engine_busy
);

  genvar g;
  generate
    for (g = 0; g < ENGINE_COUNT; g++) begin : g_engine
      cnn_engine_core #(
        .WORK_ID_W(WORK_ID_W),
        .ADDR_W(ADDR_W),
        .DATA_W(DATA_W),
        .ACC_W(ACC_W),
        .C_IN(C_IN),
        .IN_H(IN_H),
        .IN_W(IN_W),
        .C1_OUT(C1_OUT),
        .K1(K1),
        .C2_OUT(C2_OUT),
        .K2(K2),
        .POOL(POOL),
        .FC1_OUT(FC1_OUT),
        .FC2_OUT(FC2_OUT),
        .FC3_OUT(FC3_OUT),
        .CONV1_MACS_PER_CYCLE(CONV1_MACS_PER_CYCLE),
        .CONV2_MACS_PER_CYCLE(CONV2_MACS_PER_CYCLE),
        .FC1_MACS_PER_CYCLE(FC1_MACS_PER_CYCLE),
        .FC2_MACS_PER_CYCLE(FC2_MACS_PER_CYCLE),
        .FC3_MACS_PER_CYCLE(FC3_MACS_PER_CYCLE),
        .SHIFT_CONV1(SHIFT_CONV1),
        .SHIFT_CONV2(SHIFT_CONV2),
        .SHIFT_FC1(SHIFT_FC1),
        .SHIFT_FC2(SHIFT_FC2),
        .STATIC_WEIGHT_PROFILE(STATIC_WEIGHT_PROFILE),
        .STATIC_DEMO_WEIGHTS(STATIC_DEMO_WEIGHTS)
      ) engine_u (
        .clk(clk),
        .rst_n(rst_n),
        .req_valid(req_valid[g]),
        .req_ready(req_ready[g]),
        .req_work_id(req_work_id[g*WORK_ID_W +: WORK_ID_W]),
        .req_img_base_addr(req_img_base_addr[g*ADDR_W +: ADDR_W]),
        .req_mode_fast_strict(req_mode_fast_strict[g]),
        .rsp_valid(rsp_valid[g]),
        .rsp_ready(rsp_ready[g]),
        .rsp_work_id(rsp_work_id[g*WORK_ID_W +: WORK_ID_W]),
        .rsp_class_id(rsp_class_id[g]),
        .rsp_logit0(rsp_logit0[g*32 +: 32]),
        .rsp_logit1(rsp_logit1[g*32 +: 32]),
        .rsp_error(rsp_error[g]),
        .busy(engine_busy[g])
      );
    end
  endgenerate

endmodule
