`timescale 1ns/1ps

module cnn_collect #(
  parameter int ENGINE_COUNT = 4,
  parameter int WORK_ID_W = 16
) (
  input  logic                           clk,
  input  logic                           rst_n,

  input  logic [ENGINE_COUNT-1:0]        engine_rsp_valid,
  output logic [ENGINE_COUNT-1:0]        engine_rsp_ready,
  input  logic [ENGINE_COUNT*WORK_ID_W-1:0] engine_rsp_work_id,
  input  logic [ENGINE_COUNT-1:0]        engine_rsp_class_id,
  input  logic [ENGINE_COUNT*32-1:0]     engine_rsp_logit0,
  input  logic [ENGINE_COUNT*32-1:0]     engine_rsp_logit1,
  input  logic [ENGINE_COUNT-1:0]        engine_rsp_error,

  output logic                           out_valid,
  input  logic                           out_ready,
  output logic [WORK_ID_W-1:0]           out_work_id,
  output logic                           out_class_id,
  output logic signed [31:0]             out_logit0,
  output logic signed [31:0]             out_logit1,
  output logic                           out_error
);

  localparam int ENG_IDX_W = (ENGINE_COUNT <= 1) ? 1 : $clog2(ENGINE_COUNT);

  logic [ENG_IDX_W-1:0] rr_start_q;
  logic [ENG_IDX_W-1:0] select_idx;
  logic                 select_valid;

  logic [WORK_ID_W-1:0] hold_work_id_q;
  logic                 hold_class_id_q;
  logic signed [31:0]   hold_logit0_q;
  logic signed [31:0]   hold_logit1_q;
  logic                 hold_error_q;
  logic                 hold_valid_q;

  integer i;
  integer idx;

  always_comb begin
    select_valid = 1'b0;
    select_idx = '0;
    for (i = 0; i < ENGINE_COUNT; i++) begin
      idx = rr_start_q + i;
      if (idx >= ENGINE_COUNT) begin
        idx = idx - ENGINE_COUNT;
      end
      if (!select_valid && engine_rsp_valid[idx]) begin
        select_valid = 1'b1;
        select_idx = idx[ENG_IDX_W-1:0];
      end
    end
  end

  always_comb begin
    engine_rsp_ready = '0;
    if (!hold_valid_q && select_valid) begin
      engine_rsp_ready[select_idx] = 1'b1;
    end
  end

  assign out_valid = hold_valid_q;
  assign out_work_id = hold_work_id_q;
  assign out_class_id = hold_class_id_q;
  assign out_logit0 = hold_logit0_q;
  assign out_logit1 = hold_logit1_q;
  assign out_error = hold_error_q;

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      rr_start_q <= '0;
      hold_work_id_q <= '0;
      hold_class_id_q <= 1'b0;
      hold_logit0_q <= '0;
      hold_logit1_q <= '0;
      hold_error_q <= 1'b0;
      hold_valid_q <= 1'b0;
    end else begin
      if (!hold_valid_q && select_valid && engine_rsp_valid[select_idx] && engine_rsp_ready[select_idx]) begin
        hold_work_id_q <= engine_rsp_work_id[select_idx*WORK_ID_W +: WORK_ID_W];
        hold_class_id_q <= engine_rsp_class_id[select_idx];
        hold_logit0_q <= engine_rsp_logit0[select_idx*32 +: 32];
        hold_logit1_q <= engine_rsp_logit1[select_idx*32 +: 32];
        hold_error_q <= engine_rsp_error[select_idx];
        hold_valid_q <= 1'b1;

        if (select_idx == ENGINE_COUNT-1) begin
          rr_start_q <= '0;
        end else begin
          rr_start_q <= select_idx + 1'b1;
        end
      end

      if (hold_valid_q && out_ready) begin
        hold_valid_q <= 1'b0;
      end
    end
  end

endmodule
