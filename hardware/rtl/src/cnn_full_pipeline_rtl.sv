`timescale 1ns/1ps

module cnn_full_pipeline_rtl #(
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
  parameter int SHIFT_CONV1 = 0,
  parameter int SHIFT_CONV2 = 0,
  parameter int SHIFT_FC1   = 0,
  parameter int SHIFT_FC2   = 0,
  // 0 = built-in demo quantized params, 1 = legacy ECE5775 data2 quantized params
  parameter int STATIC_WEIGHT_PROFILE = 0,
  parameter bit STATIC_DEMO_WEIGHTS = 1'b1,
  parameter int FC1_MACS_PER_CYCLE = 2,
  parameter int FC2_MACS_PER_CYCLE = 2,
  parameter int FC3_MACS_PER_CYCLE = 2
) (
  input  logic                         clk,
  input  logic                         rst_n,
  input  logic                         start,
  output logic                         busy,
  output logic                         done,
  output logic                         class_id,
  output logic signed [ACC_W-1:0]      logit0,
  output logic signed [ACC_W-1:0]      logit1,

  input  logic                         cfg_we8,
  input  logic [3:0]                   cfg_bank8,
  input  logic [31:0]                  cfg_addr8,
  input  logic signed [DATA_W-1:0]     cfg_data8,

  input  logic                         cfg_we32,
  input  logic [3:0]                   cfg_bank32,
  input  logic [31:0]                  cfg_addr32,
  input  logic signed [ACC_W-1:0]      cfg_data32
);

  localparam int C1_H      = IN_H - K1 + 1;
  localparam int C1_W      = IN_W - K1 + 1;
  localparam int P1_H      = C1_H / POOL;
  localparam int P1_W      = C1_W / POOL;
  localparam int C2_H      = P1_H - K2 + 1;
  localparam int C2_W      = P1_W - K2 + 1;
  localparam int P2_H      = C2_H / POOL;
  localparam int P2_W      = C2_W / POOL;

  localparam int IN_SIZE   = C_IN * IN_H * IN_W;
  localparam int C1_SIZE   = C1_OUT * C1_H * C1_W;
  localparam int P1_SIZE   = C1_OUT * P1_H * P1_W;
  localparam int C2_SIZE   = C2_OUT * C2_H * C2_W;
  localparam int P2_SIZE   = C2_OUT * P2_H * P2_W;
  localparam int FLAT_SIZE = P2_SIZE;

  localparam int W1_SIZE   = C1_OUT * C_IN   * K1 * K1;
  localparam int W2_SIZE   = C2_OUT * C1_OUT * K2 * K2;
  localparam int W3_SIZE   = FC1_OUT * FLAT_SIZE;
  localparam int W4_SIZE   = FC2_OUT * FC1_OUT;
  localparam int W5_SIZE   = FC3_OUT * FC2_OUT;
  localparam bit LEGACY_MODEL_GEOM = (
    (C_IN == 3) && (IN_H == 32) && (IN_W == 32) &&
    (C1_OUT == 6) && (K1 == 5) &&
    (C2_OUT == 16) && (K2 == 5) &&
    (POOL == 2) &&
    (FC1_OUT == 120) && (FC2_OUT == 84) && (FC3_OUT == 2)
  );

`include "../include/cnn_static_params_legacy.svh"

  typedef enum logic [4:0] {
    S_IDLE,
    S_C1_KICK,
    S_C1_WAIT,
    S_P1_KICK,
    S_P1_WAIT,
    S_C2_KICK,
    S_C2_WAIT,
    S_P2_KICK,
    S_P2_WAIT,
    S_F1_KICK,
    S_F1_WAIT,
    S_F2_KICK,
    S_F2_WAIT,
    S_F3_KICK,
    S_F3_WAIT,
    S_ARGMAX,
    S_DONE
  } state_t;

  state_t state;

  (* ram_style = "block" *) logic signed [DATA_W-1:0] input_mem [0:IN_SIZE-1];
  (* ram_style = "block" *) logic signed [DATA_W-1:0] conv1_w   [0:W1_SIZE-1];
  (* ram_style = "block" *) logic signed [DATA_W-1:0] conv2_w   [0:W2_SIZE-1];
  (* ram_style = "block" *) logic signed [DATA_W-1:0] fc1_w     [0:W3_SIZE-1];
  (* ram_style = "block" *) logic signed [DATA_W-1:0] fc2_w     [0:W4_SIZE-1];
  (* ram_style = "block" *) logic signed [DATA_W-1:0] fc3_w     [0:W5_SIZE-1];

  (* ram_style = "distributed" *) logic signed [ACC_W-1:0] conv1_b [0:C1_OUT-1];
  (* ram_style = "distributed" *) logic signed [ACC_W-1:0] conv2_b [0:C2_OUT-1];
  (* ram_style = "distributed" *) logic signed [ACC_W-1:0] fc1_b   [0:FC1_OUT-1];
  (* ram_style = "distributed" *) logic signed [ACC_W-1:0] fc2_b   [0:FC2_OUT-1];
  (* ram_style = "distributed" *) logic signed [ACC_W-1:0] fc3_b   [0:FC3_OUT-1];

  (* ram_style = "block" *) logic signed [DATA_W-1:0] act1     [0:C1_SIZE-1];
  (* ram_style = "block" *) logic signed [DATA_W-1:0] pool1    [0:P1_SIZE-1];
  (* ram_style = "block" *) logic signed [DATA_W-1:0] act2     [0:C2_SIZE-1];
  (* ram_style = "block" *) logic signed [DATA_W-1:0] pool2    [0:P2_SIZE-1];
  (* ram_style = "block" *) logic signed [DATA_W-1:0] fc1_act  [0:FC1_OUT-1];
  (* ram_style = "block" *) logic signed [DATA_W-1:0] fc2_act  [0:FC2_OUT-1];
  logic signed [ACC_W-1:0]  fc3_logit[0:FC3_OUT-1];

  logic conv1_start;
  logic pool1_start;
  logic conv2_start;
  logic pool2_start;
  logic fc1_start;
  logic fc2_start;
  logic fc3_start;

  logic conv1_busy;
  logic pool1_busy;
  logic conv2_busy;
  logic pool2_busy;
  logic fc1_busy;
  logic fc2_busy;
  logic fc3_busy;

  logic conv1_done;
  logic pool1_done;
  logic conv2_done;
  logic pool2_done;
  logic fc1_done;
  logic fc2_done;
  logic fc3_done;

  logic argmax_class;

  function automatic signed [DATA_W-1:0] demo_weight8(
    input int layer_id,
    input int idx
  );
    int signed v;
    begin
      case (layer_id)
        1: v = ((idx * 13 + 5) % 15) - 7; // conv1
        2: v = ((idx * 11 + 3) % 13) - 6; // conv2
        3: v = ((idx *  7 + 1) %  9) - 4; // fc1
        4: v = ((idx *  5 + 2) %  7) - 3; // fc2
        5: v = ((idx *  3 + 4) %  7) - 3; // fc3
        default: v = 0;
      endcase
      demo_weight8 = v[DATA_W-1:0];
    end
  endfunction

  function automatic signed [ACC_W-1:0] demo_bias32(
    input int layer_id,
    input int idx
  );
    int signed v;
    begin
      case (layer_id)
        1: v = ((idx * 3 + 1) % 7) - 3;
        2: v = ((idx * 5 + 2) % 9) - 4;
        3: v = ((idx * 7 + 3) % 11) - 5;
        4: v = ((idx * 9 + 4) % 13) - 6;
        5: v = ((idx * 11 + 5) % 15) - 7;
        default: v = 0;
      endcase
      demo_bias32 = v;
    end
  endfunction

  cnn_conv_layer_rtl #(
    .DATA_W(DATA_W),
    .ACC_W(ACC_W),
    .IN_C (C_IN),
    .IN_H (IN_H),
    .IN_W (IN_W),
    .OUT_C(C1_OUT),
    .K    (K1),
    .MACS_PER_CYCLE(CONV1_MACS_PER_CYCLE),
    .SHIFT(SHIFT_CONV1),
    .RELU_EN(1'b1)
  ) conv1_u (
    .clk(clk), .rst_n(rst_n), .start(conv1_start), .busy(conv1_busy), .done(conv1_done),
    .in_fmap(input_mem), .weights(conv1_w), .bias(conv1_b), .out_fmap(act1)
  );

  cnn_maxpool_layer_rtl #(
    .DATA_W(DATA_W),
    .C(C1_OUT),
    .IN_H(C1_H),
    .IN_W(C1_W),
    .POOL(POOL)
  ) pool1_u (
    .clk(clk), .rst_n(rst_n), .start(pool1_start), .busy(pool1_busy), .done(pool1_done),
    .in_fmap(act1), .out_fmap(pool1)
  );

  cnn_conv_layer_rtl #(
    .DATA_W(DATA_W),
    .ACC_W(ACC_W),
    .IN_C (C1_OUT),
    .IN_H (P1_H),
    .IN_W (P1_W),
    .OUT_C(C2_OUT),
    .K    (K2),
    .MACS_PER_CYCLE(CONV2_MACS_PER_CYCLE),
    .SHIFT(SHIFT_CONV2),
    .RELU_EN(1'b1)
  ) conv2_u (
    .clk(clk), .rst_n(rst_n), .start(conv2_start), .busy(conv2_busy), .done(conv2_done),
    .in_fmap(pool1), .weights(conv2_w), .bias(conv2_b), .out_fmap(act2)
  );

  cnn_maxpool_layer_rtl #(
    .DATA_W(DATA_W),
    .C(C2_OUT),
    .IN_H(C2_H),
    .IN_W(C2_W),
    .POOL(POOL)
  ) pool2_u (
    .clk(clk), .rst_n(rst_n), .start(pool2_start), .busy(pool2_busy), .done(pool2_done),
    .in_fmap(act2), .out_fmap(pool2)
  );

  cnn_fc_act_layer_rtl #(
    .DATA_W(DATA_W),
    .ACC_W(ACC_W),
    .IN_ELEMS(FLAT_SIZE),
    .OUT_ELEMS(FC1_OUT),
    .MACS_PER_CYCLE(FC1_MACS_PER_CYCLE),
    .SHIFT(SHIFT_FC1),
    .RELU_EN(1'b1)
  ) fc1_u (
    .clk(clk), .rst_n(rst_n), .start(fc1_start), .busy(fc1_busy), .done(fc1_done),
    .in_vec(pool2), .weights(fc1_w), .bias(fc1_b), .out_vec(fc1_act)
  );

  cnn_fc_act_layer_rtl #(
    .DATA_W(DATA_W),
    .ACC_W(ACC_W),
    .IN_ELEMS(FC1_OUT),
    .OUT_ELEMS(FC2_OUT),
    .MACS_PER_CYCLE(FC2_MACS_PER_CYCLE),
    .SHIFT(SHIFT_FC2),
    .RELU_EN(1'b1)
  ) fc2_u (
    .clk(clk), .rst_n(rst_n), .start(fc2_start), .busy(fc2_busy), .done(fc2_done),
    .in_vec(fc1_act), .weights(fc2_w), .bias(fc2_b), .out_vec(fc2_act)
  );

  cnn_fc_logit_layer_rtl #(
    .DATA_W(DATA_W),
    .ACC_W(ACC_W),
    .IN_ELEMS(FC2_OUT),
    .OUT_ELEMS(FC3_OUT),
    .MACS_PER_CYCLE(FC3_MACS_PER_CYCLE)
  ) fc3_u (
    .clk(clk), .rst_n(rst_n), .start(fc3_start), .busy(fc3_busy), .done(fc3_done),
    .in_vec(fc2_act), .weights(fc3_w), .bias(fc3_b), .out_logits(fc3_logit)
  );

  cnn_argmax2_rtl #(
    .ACC_W(ACC_W)
  ) argmax_u (
    .logit0(fc3_logit[0]),
    .logit1(fc3_logit[1]),
    .class_id(argmax_class)
  );

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      state      <= S_IDLE;
      busy       <= 1'b0;
      done       <= 1'b0;
      class_id   <= 1'b0;
      logit0     <= '0;
      logit1     <= '0;
      conv1_start <= 1'b0;
      pool1_start <= 1'b0;
      conv2_start <= 1'b0;
      pool2_start <= 1'b0;
      fc1_start   <= 1'b0;
      fc2_start   <= 1'b0;
      fc3_start   <= 1'b0;
    end else begin
      done <= 1'b0;

      conv1_start <= 1'b0;
      pool1_start <= 1'b0;
      conv2_start <= 1'b0;
      pool2_start <= 1'b0;
      fc1_start   <= 1'b0;
      fc2_start   <= 1'b0;
      fc3_start   <= 1'b0;

      if (cfg_we8 && !busy) begin
        if (cfg_bank8 == 4'd0) begin
          if (cfg_addr8 < IN_SIZE) input_mem[cfg_addr8] <= cfg_data8;
        end else if (!STATIC_DEMO_WEIGHTS) begin
          case (cfg_bank8)
            4'd1: if (cfg_addr8 < W1_SIZE) conv1_w[cfg_addr8] <= cfg_data8;
            4'd2: if (cfg_addr8 < W2_SIZE) conv2_w[cfg_addr8] <= cfg_data8;
            4'd3: if (cfg_addr8 < W3_SIZE) fc1_w[cfg_addr8]   <= cfg_data8;
            4'd4: if (cfg_addr8 < W4_SIZE) fc2_w[cfg_addr8]   <= cfg_data8;
            4'd5: if (cfg_addr8 < W5_SIZE) fc3_w[cfg_addr8]   <= cfg_data8;
            default: ;
          endcase
        end
      end

      if (!STATIC_DEMO_WEIGHTS && cfg_we32 && !busy) begin
        case (cfg_bank32)
          4'd0: if (cfg_addr32 < C1_OUT)  conv1_b[cfg_addr32] <= cfg_data32;
          4'd1: if (cfg_addr32 < C2_OUT)  conv2_b[cfg_addr32] <= cfg_data32;
          4'd2: if (cfg_addr32 < FC1_OUT) fc1_b[cfg_addr32]   <= cfg_data32;
          4'd3: if (cfg_addr32 < FC2_OUT) fc2_b[cfg_addr32]   <= cfg_data32;
          4'd4: if (cfg_addr32 < FC3_OUT) fc3_b[cfg_addr32]   <= cfg_data32;
          default: ;
        endcase
      end

      case (state)
        S_IDLE: begin
          if (start && !busy) begin
            busy  <= 1'b1;
            state <= S_C1_KICK;
          end
        end

        S_C1_KICK: begin
          conv1_start <= 1'b1;
          state <= S_C1_WAIT;
        end

        S_C1_WAIT: begin
          if (conv1_done) state <= S_P1_KICK;
        end

        S_P1_KICK: begin
          pool1_start <= 1'b1;
          state <= S_P1_WAIT;
        end

        S_P1_WAIT: begin
          if (pool1_done) state <= S_C2_KICK;
        end

        S_C2_KICK: begin
          conv2_start <= 1'b1;
          state <= S_C2_WAIT;
        end

        S_C2_WAIT: begin
          if (conv2_done) state <= S_P2_KICK;
        end

        S_P2_KICK: begin
          pool2_start <= 1'b1;
          state <= S_P2_WAIT;
        end

        S_P2_WAIT: begin
          if (pool2_done) state <= S_F1_KICK;
        end

        S_F1_KICK: begin
          fc1_start <= 1'b1;
          state <= S_F1_WAIT;
        end

        S_F1_WAIT: begin
          if (fc1_done) state <= S_F2_KICK;
        end

        S_F2_KICK: begin
          fc2_start <= 1'b1;
          state <= S_F2_WAIT;
        end

        S_F2_WAIT: begin
          if (fc2_done) state <= S_F3_KICK;
        end

        S_F3_KICK: begin
          fc3_start <= 1'b1;
          state <= S_F3_WAIT;
        end

        S_F3_WAIT: begin
          if (fc3_done) state <= S_ARGMAX;
        end

        S_ARGMAX: begin
          logit0   <= fc3_logit[0];
          logit1   <= fc3_logit[1];
          class_id <= argmax_class;
          state    <= S_DONE;
        end

        S_DONE: begin
          done  <= 1'b1;
          busy  <= 1'b0;
          state <= S_IDLE;
        end

        default: state <= S_IDLE;
      endcase
    end
  end

  initial begin : init_static_storage
    int i;
    for (i = 0; i < IN_SIZE; i++) input_mem[i] = '0;
    if (STATIC_WEIGHT_PROFILE == 1) begin
      if (!LEGACY_MODEL_GEOM) begin
        $fatal(1, "cnn_full_pipeline_rtl profile=1 requires legacy geometry (3x32x32 -> 6/16 conv -> 120/84/2 fc)");
      end
      for (i = 0; i < W1_SIZE; i++) conv1_w[i] = LEGACY_CONV1_W[i];
      for (i = 0; i < W2_SIZE; i++) conv2_w[i] = LEGACY_CONV2_W[i];
      for (i = 0; i < W3_SIZE; i++) fc1_w[i]   = LEGACY_FC1_W[i];
      for (i = 0; i < W4_SIZE; i++) fc2_w[i]   = LEGACY_FC2_W[i];
      for (i = 0; i < W5_SIZE; i++) fc3_w[i]   = LEGACY_FC3_W[i];

      for (i = 0; i < C1_OUT; i++)  conv1_b[i] = LEGACY_CONV1_B[i];
      for (i = 0; i < C2_OUT; i++)  conv2_b[i] = LEGACY_CONV2_B[i];
      for (i = 0; i < FC1_OUT; i++) fc1_b[i]   = LEGACY_FC1_B[i];
      for (i = 0; i < FC2_OUT; i++) fc2_b[i]   = LEGACY_FC2_B[i];
      for (i = 0; i < FC3_OUT; i++) fc3_b[i]   = LEGACY_FC3_B[i];
    end else begin
      for (i = 0; i < W1_SIZE; i++) conv1_w[i] = demo_weight8(1, i);
      for (i = 0; i < W2_SIZE; i++) conv2_w[i] = demo_weight8(2, i);
      for (i = 0; i < W3_SIZE; i++) fc1_w[i]   = demo_weight8(3, i);
      for (i = 0; i < W4_SIZE; i++) fc2_w[i]   = demo_weight8(4, i);
      for (i = 0; i < W5_SIZE; i++) fc3_w[i]   = demo_weight8(5, i);

      for (i = 0; i < C1_OUT; i++)  conv1_b[i] = demo_bias32(1, i);
      for (i = 0; i < C2_OUT; i++)  conv2_b[i] = demo_bias32(2, i);
      for (i = 0; i < FC1_OUT; i++) fc1_b[i]   = demo_bias32(3, i);
      for (i = 0; i < FC2_OUT; i++) fc2_b[i]   = demo_bias32(4, i);
      for (i = 0; i < FC3_OUT; i++) fc3_b[i]   = demo_bias32(5, i);
    end

    if (FC3_OUT != 2) begin
      $fatal(1, "cnn_full_pipeline_rtl currently expects FC3_OUT == 2");
    end
    if ((C1_H <= 0) || (C1_W <= 0) || (C2_H <= 0) || (C2_W <= 0) || (P1_H <= 0) || (P1_W <= 0) || (P2_H <= 0) || (P2_W <= 0)) begin
      $fatal(1, "cnn_full_pipeline_rtl invalid geometry parameters");
    end
    if ((CONV1_MACS_PER_CYCLE <= 0) || (CONV2_MACS_PER_CYCLE <= 0) ||
        (FC1_MACS_PER_CYCLE <= 0) || (FC2_MACS_PER_CYCLE <= 0) || (FC3_MACS_PER_CYCLE <= 0)) begin
      $fatal(1, "cnn_full_pipeline_rtl MACS_PER_CYCLE parameters must be > 0");
    end
    if (STATIC_WEIGHT_PROFILE == 1) begin
      if ((SHIFT_CONV1 != LEGACY_SHIFT_CONV1) ||
          (SHIFT_CONV2 != LEGACY_SHIFT_CONV2) ||
          (SHIFT_FC1   != LEGACY_SHIFT_FC1) ||
          (SHIFT_FC2   != LEGACY_SHIFT_FC2)) begin
        $fatal(1, "cnn_full_pipeline_rtl profile=1 requires shifts conv1=%0d conv2=%0d fc1=%0d fc2=%0d",
               LEGACY_SHIFT_CONV1, LEGACY_SHIFT_CONV2, LEGACY_SHIFT_FC1, LEGACY_SHIFT_FC2);
      end
    end
  end

endmodule
