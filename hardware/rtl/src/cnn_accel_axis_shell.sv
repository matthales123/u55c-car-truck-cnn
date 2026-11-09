`timescale 1ns/1ps

module cnn_accel_axis_shell #(
  parameter int ENGINE_COUNT = 8,
  parameter int WORK_ID_W = 16,
  parameter int ADDR_W = 64,
  // Deprecated placeholder timing knob (kept for compatibility with old TBs/scripts).
  parameter int COMPUTE_LATENCY = 32,
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
  input  logic                      clk,
  input  logic                      rst_n,

  input  logic                      cmd_valid,
  output logic                      cmd_ready,
  input  logic [WORK_ID_W-1:0]      cmd_work_id,
  input  logic [ADDR_W-1:0]         cmd_img_base_addr,
  input  logic                      cmd_mode_fast_strict,

  output logic                      rsp_valid,
  input  logic                      rsp_ready,
  output logic [WORK_ID_W-1:0]      rsp_work_id,
  output logic                      rsp_class_id,
  output logic signed [31:0]        rsp_logit0,
  output logic signed [31:0]        rsp_logit1,
  output logic                      rsp_error,

  output logic [31:0]               issued_count,
  output logic [31:0]               completed_count,
  output logic [31:0]               inflight_count,
  output logic [ENGINE_COUNT-1:0]   engine_busy
);

  logic [ENGINE_COUNT-1:0] req_valid;
  logic [ENGINE_COUNT-1:0] req_ready;
  logic [ENGINE_COUNT*WORK_ID_W-1:0] req_work_id;
  logic [ENGINE_COUNT*ADDR_W-1:0] req_img_base_addr;
  logic [ENGINE_COUNT-1:0] req_mode_fast_strict;

  logic [ENGINE_COUNT-1:0] eng_rsp_valid;
  logic [ENGINE_COUNT-1:0] eng_rsp_ready;
  logic [ENGINE_COUNT*WORK_ID_W-1:0] eng_rsp_work_id;
  logic [ENGINE_COUNT-1:0] eng_rsp_class_id;
  logic [ENGINE_COUNT*32-1:0] eng_rsp_logit0;
  logic [ENGINE_COUNT*32-1:0] eng_rsp_logit1;
  logic [ENGINE_COUNT-1:0] eng_rsp_error;

  logic cmd_fire;
  logic rsp_fire;

  assign cmd_fire = cmd_valid && cmd_ready;
  assign rsp_fire = rsp_valid && rsp_ready;

  cnn_dispatch #(
    .ENGINE_COUNT(ENGINE_COUNT),
    .WORK_ID_W(WORK_ID_W),
    .ADDR_W(ADDR_W)
  ) dispatch_u (
    .clk(clk),
    .rst_n(rst_n),
    .cmd_valid(cmd_valid),
    .cmd_ready(cmd_ready),
    .cmd_work_id(cmd_work_id),
    .cmd_img_base_addr(cmd_img_base_addr),
    .cmd_mode_fast_strict(cmd_mode_fast_strict),
    .engine_req_valid(req_valid),
    .engine_req_ready(req_ready),
    .engine_req_work_id(req_work_id),
    .engine_req_img_base_addr(req_img_base_addr),
    .engine_req_mode_fast_strict(req_mode_fast_strict)
  );

  cnn_engine_array #(
    .ENGINE_COUNT(ENGINE_COUNT),
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
  ) engine_array_u (
    .clk(clk),
    .rst_n(rst_n),
    .req_valid(req_valid),
    .req_ready(req_ready),
    .req_work_id(req_work_id),
    .req_img_base_addr(req_img_base_addr),
    .req_mode_fast_strict(req_mode_fast_strict),
    .rsp_valid(eng_rsp_valid),
    .rsp_ready(eng_rsp_ready),
    .rsp_work_id(eng_rsp_work_id),
    .rsp_class_id(eng_rsp_class_id),
    .rsp_logit0(eng_rsp_logit0),
    .rsp_logit1(eng_rsp_logit1),
    .rsp_error(eng_rsp_error),
    .engine_busy(engine_busy)
  );

  cnn_collect #(
    .ENGINE_COUNT(ENGINE_COUNT),
    .WORK_ID_W(WORK_ID_W)
  ) collect_u (
    .clk(clk),
    .rst_n(rst_n),
    .engine_rsp_valid(eng_rsp_valid),
    .engine_rsp_ready(eng_rsp_ready),
    .engine_rsp_work_id(eng_rsp_work_id),
    .engine_rsp_class_id(eng_rsp_class_id),
    .engine_rsp_logit0(eng_rsp_logit0),
    .engine_rsp_logit1(eng_rsp_logit1),
    .engine_rsp_error(eng_rsp_error),
    .out_valid(rsp_valid),
    .out_ready(rsp_ready),
    .out_work_id(rsp_work_id),
    .out_class_id(rsp_class_id),
    .out_logit0(rsp_logit0),
    .out_logit1(rsp_logit1),
    .out_error(rsp_error)
  );

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      issued_count <= 32'd0;
      completed_count <= 32'd0;
      inflight_count <= 32'd0;
    end else begin
      if (cmd_fire) begin
        issued_count <= issued_count + 32'd1;
      end
      if (rsp_fire) begin
        completed_count <= completed_count + 32'd1;
      end

      case ({cmd_fire, rsp_fire})
        2'b10: inflight_count <= inflight_count + 32'd1;
        2'b01: begin
          if (inflight_count != 0) begin
            inflight_count <= inflight_count - 32'd1;
          end else begin
            inflight_count <= 32'd0;
          end
        end
        default: inflight_count <= inflight_count;
      endcase
    end
  end

endmodule
