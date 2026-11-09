`timescale 1ns/1ps

package cnn_accel_pkg;
  parameter int CNN_ACCEL_ADDR_W = 64;
  parameter int CNN_ACCEL_AXI_W = 512;
  parameter int CNN_ACCEL_WORK_ID_W = 16;

  typedef struct packed {
    logic [CNN_ACCEL_WORK_ID_W-1:0] work_id;
    logic [CNN_ACCEL_ADDR_W-1:0]    img_base_addr;
    logic                           mode_fast_strict;
  } cnn_work_req_t;

  typedef struct packed {
    logic [CNN_ACCEL_WORK_ID_W-1:0] work_id;
    logic                           class_id;
    logic signed [31:0]             logit0;
    logic signed [31:0]             logit1;
    logic                           error;
  } cnn_work_rsp_t;
endpackage
