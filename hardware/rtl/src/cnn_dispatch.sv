`timescale 1ns/1ps

module cnn_dispatch #(
  parameter int ENGINE_COUNT = 4,
  parameter int WORK_ID_W = 16,
  parameter int ADDR_W = 64
) (
  input  logic                           clk,
  input  logic                           rst_n,

  input  logic                           cmd_valid,
  output logic                           cmd_ready,
  input  logic [WORK_ID_W-1:0]           cmd_work_id,
  input  logic [ADDR_W-1:0]              cmd_img_base_addr,
  input  logic                           cmd_mode_fast_strict,

  output logic [ENGINE_COUNT-1:0]        engine_req_valid,
  input  logic [ENGINE_COUNT-1:0]        engine_req_ready,
  output logic [ENGINE_COUNT*WORK_ID_W-1:0] engine_req_work_id,
  output logic [ENGINE_COUNT*ADDR_W-1:0] engine_req_img_base_addr,
  output logic [ENGINE_COUNT-1:0]        engine_req_mode_fast_strict
);

  localparam int ENG_IDX_W = (ENGINE_COUNT <= 1) ? 1 : $clog2(ENGINE_COUNT);

  logic [ENG_IDX_W-1:0] rr_start_q;
  logic [ENG_IDX_W-1:0] select_idx;
  logic                 select_valid;
  logic                 cmd_fire;

  integer i;
  integer idx;

  always_comb begin
    select_valid = 1'b0;
    select_idx = '0;
    for (i = 0; i < ENGINE_COUNT; i++) begin
      idx = (rr_start_q + i) % ENGINE_COUNT;
      if (!select_valid && engine_req_ready[idx]) begin
        select_valid = 1'b1;
        select_idx = idx[ENG_IDX_W-1:0];
      end
    end
  end

  assign cmd_ready = select_valid;
  assign cmd_fire  = cmd_valid && cmd_ready;

  always_comb begin
    engine_req_valid = '0;
    engine_req_work_id = '0;
    engine_req_img_base_addr = '0;
    engine_req_mode_fast_strict = '0;

    if (cmd_fire) begin
      engine_req_valid[select_idx] = 1'b1;
      engine_req_work_id[select_idx*WORK_ID_W +: WORK_ID_W] = cmd_work_id;
      engine_req_img_base_addr[select_idx*ADDR_W +: ADDR_W] = cmd_img_base_addr;
      engine_req_mode_fast_strict[select_idx] = cmd_mode_fast_strict;
    end
  end

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      rr_start_q <= '0;
    end else if (cmd_fire) begin
      if (select_idx == ENGINE_COUNT-1) begin
        rr_start_q <= '0;
      end else begin
        rr_start_q <= select_idx + 1'b1;
      end
    end
  end

endmodule
