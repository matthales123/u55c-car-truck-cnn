`timescale 1ns/1ps

module cnn_engine_core #(
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

  // 0 = demo profile, 1 = legacy quantized profile
  parameter int STATIC_WEIGHT_PROFILE = 1,
  parameter bit STATIC_DEMO_WEIGHTS   = 1'b0
) (
  input  logic                      clk,
  input  logic                      rst_n,

  input  logic                      req_valid,
  output logic                      req_ready,
  input  logic [WORK_ID_W-1:0]      req_work_id,
  input  logic [ADDR_W-1:0]         req_img_base_addr,
  input  logic                      req_mode_fast_strict,

  output logic                      rsp_valid,
  input  logic                      rsp_ready,
  output logic [WORK_ID_W-1:0]      rsp_work_id,
  output logic                      rsp_class_id,
  output logic signed [31:0]        rsp_logit0,
  output logic signed [31:0]        rsp_logit1,
  output logic                      rsp_error,

  output logic                      busy
);

  localparam int IN_SIZE = C_IN * IN_H * IN_W;
  localparam int LOAD_IDX_W = (IN_SIZE <= 1) ? 1 : $clog2(IN_SIZE);

  typedef enum logic [2:0] {
    S_IDLE,
    S_LOAD,
    S_START,
    S_WAIT,
    S_RESP
  } state_t;

  state_t state_q;

  logic [WORK_ID_W-1:0] work_id_q;
  logic [ADDR_W-1:0]    img_base_addr_q;
  logic                 mode_q;
  logic [LOAD_IDX_W-1:0] load_idx_q;

  logic                 pipe_start;
  logic                 pipe_busy;
  logic                 pipe_done;
  logic                 pipe_class_id;
  logic signed [31:0]   pipe_logit0;
  logic signed [31:0]   pipe_logit1;

  logic                 pipe_cfg_we8;
  logic [3:0]           pipe_cfg_bank8;
  logic [31:0]          pipe_cfg_addr8;
  logic signed [DATA_W-1:0] pipe_cfg_data8;

  function automatic signed [DATA_W-1:0] gen_input_px(
    input logic [WORK_ID_W-1:0] wid,
    input logic [ADDR_W-1:0]    base_addr,
    input logic                 mode_fast,
    input int                   idx
  );
    logic [31:0] mix;
    logic [7:0]  px;
    begin
      mix = (idx * 32'd13) + ({16'd0, wid} * 32'd17) + base_addr[31:0] + (mode_fast ? 32'd31 : 32'd7);
      px = mix[7:0];
      gen_input_px = $signed(px);
    end
  endfunction

  assign req_ready = (state_q == S_IDLE);
  assign rsp_valid = (state_q == S_RESP);
  assign busy = (state_q != S_IDLE);

  assign pipe_cfg_we8 = (state_q == S_LOAD);
  assign pipe_cfg_bank8 = 4'd0;
  assign pipe_cfg_addr8 = load_idx_q;
  assign pipe_cfg_data8 = gen_input_px(work_id_q, img_base_addr_q, mode_q, load_idx_q);
  assign pipe_start = (state_q == S_START);

  cnn_full_pipeline_rtl #(
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
    .SHIFT_CONV1(SHIFT_CONV1),
    .SHIFT_CONV2(SHIFT_CONV2),
    .SHIFT_FC1(SHIFT_FC1),
    .SHIFT_FC2(SHIFT_FC2),
    .STATIC_WEIGHT_PROFILE(STATIC_WEIGHT_PROFILE),
    .STATIC_DEMO_WEIGHTS(STATIC_DEMO_WEIGHTS),
    .FC1_MACS_PER_CYCLE(FC1_MACS_PER_CYCLE),
    .FC2_MACS_PER_CYCLE(FC2_MACS_PER_CYCLE),
    .FC3_MACS_PER_CYCLE(FC3_MACS_PER_CYCLE)
  ) pipe_u (
    .clk(clk),
    .rst_n(rst_n),
    .start(pipe_start),
    .busy(pipe_busy),
    .done(pipe_done),
    .class_id(pipe_class_id),
    .logit0(pipe_logit0),
    .logit1(pipe_logit1),
    .cfg_we8(pipe_cfg_we8),
    .cfg_bank8(pipe_cfg_bank8),
    .cfg_addr8(pipe_cfg_addr8),
    .cfg_data8(pipe_cfg_data8),
    .cfg_we32(1'b0),
    .cfg_bank32('0),
    .cfg_addr32('0),
    .cfg_data32('0)
  );

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      state_q <= S_IDLE;
      work_id_q <= '0;
      img_base_addr_q <= '0;
      mode_q <= 1'b0;
      load_idx_q <= '0;

      rsp_work_id <= '0;
      rsp_class_id <= 1'b0;
      rsp_logit0 <= '0;
      rsp_logit1 <= '0;
      rsp_error <= 1'b0;
    end else begin
      case (state_q)
        S_IDLE: begin
          if (req_valid) begin
            work_id_q <= req_work_id;
            img_base_addr_q <= req_img_base_addr;
            mode_q <= req_mode_fast_strict;
            load_idx_q <= '0;
            rsp_error <= 1'b0;
            state_q <= S_LOAD;
          end
        end

        S_LOAD: begin
          if (load_idx_q == IN_SIZE-1) begin
            load_idx_q <= '0;
            state_q <= S_START;
          end else begin
            load_idx_q <= load_idx_q + 1'b1;
          end
        end

        S_START: begin
          state_q <= S_WAIT;
        end

        S_WAIT: begin
          if (pipe_done) begin
            rsp_work_id <= work_id_q;
            rsp_class_id <= pipe_class_id;
            rsp_logit0 <= pipe_logit0;
            rsp_logit1 <= pipe_logit1;
            rsp_error <= 1'b0;
            state_q <= S_RESP;
          end
        end

        S_RESP: begin
          if (rsp_ready) begin
            state_q <= S_IDLE;
          end
        end

        default: state_q <= S_IDLE;
      endcase
    end
  end

endmodule
