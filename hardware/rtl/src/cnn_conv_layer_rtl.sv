`timescale 1ns/1ps

module cnn_conv_layer_rtl #(
  parameter int DATA_W   = 8,
  parameter int ACC_W    = 32,
  parameter int IN_C     = 3,
  parameter int IN_H     = 32,
  parameter int IN_W     = 32,
  parameter int OUT_C    = 6,
  parameter int K        = 5,
  parameter int MACS_PER_CYCLE = 1,
  parameter int SHIFT    = 0,
  parameter bit RELU_EN  = 1'b1
) (
  input  logic                         clk,
  input  logic                         rst_n,
  input  logic                         start,
  output logic                         busy,
  output logic                         done,
  input  logic signed [DATA_W-1:0]     in_fmap [0:(IN_C*IN_H*IN_W)-1],
  input  logic signed [DATA_W-1:0]     weights [0:(OUT_C*IN_C*K*K)-1],
  input  logic signed [ACC_W-1:0]      bias [0:OUT_C-1],
  output logic signed [DATA_W-1:0]     out_fmap [0:(OUT_C*(IN_H-K+1)*(IN_W-K+1))-1]
);

  localparam int OUT_H = IN_H - K + 1;
  localparam int OUT_W = IN_W - K + 1;
  localparam int MAX_MACS_PER_CYCLE = 8;

  typedef enum logic [2:0] {
    S_IDLE,
    S_READ,
    S_MUL,
    S_ACCUM,
    S_WRITE,
    S_ADV,
    S_DONE
  } state_t;

  state_t state;

  integer oc;
  integer oh;
  integer ow;
  integer ic;
  integer kh;
  integer kw;
  integer ic_next_reg;
  integer kh_next_reg;
  integer kw_next_reg;

  logic signed [ACC_W-1:0] acc_reg;
  logic                    chunk_done_reg;
  logic signed [DATA_W-1:0] in_data_reg [0:MAX_MACS_PER_CYCLE-1];
  logic signed [DATA_W-1:0] weight_data_reg [0:MAX_MACS_PER_CYCLE-1];
  (* use_dsp = "yes" *) logic signed [(2*DATA_W)-1:0] mul_prod_reg [0:MAX_MACS_PER_CYCLE-1];

  function automatic int idx_in(input int ch, input int h, input int w);
    idx_in = ((ch * IN_H) + h) * IN_W + w;
  endfunction

  function automatic int idx_out(input int ch, input int h, input int w);
    idx_out = ((ch * OUT_H) + h) * OUT_W + w;
  endfunction

  function automatic int idx_w(input int och, input int ich, input int k_h, input int k_w);
    idx_w = ((((och * IN_C) + ich) * K) + k_h) * K + k_w;
  endfunction

  function automatic signed [ACC_W-1:0] sat_add_acc(
    input signed [ACC_W-1:0] a,
    input signed [ACC_W-1:0] b
  );
    logic signed [ACC_W:0] sum_ext;
    logic signed [ACC_W:0] sat_max;
    logic signed [ACC_W:0] sat_min;
    begin
      sum_ext = {a[ACC_W-1], a} + {b[ACC_W-1], b};
      sat_max = {2'b00, {(ACC_W-1){1'b1}}};
      sat_min = {2'b11, {(ACC_W-1){1'b0}}};
      if (sum_ext > sat_max) sat_add_acc = sat_max[ACC_W-1:0];
      else if (sum_ext < sat_min) sat_add_acc = sat_min[ACC_W-1:0];
      else sat_add_acc = sum_ext[ACC_W-1:0];
    end
  endfunction

  function automatic signed [DATA_W-1:0] quant_act(
    input signed [ACC_W-1:0] x,
    input int shift,
    input bit relu
  );
    logic signed [ACC_W-1:0] y;
    logic signed [ACC_W-1:0] round_off;
    begin
      if (shift > 0) begin
        round_off = x[ACC_W-1]
          ? ((({{(ACC_W-1){1'b0}},1'b1}) <<< (shift-1)) - 1)
          : (({{(ACC_W-1){1'b0}},1'b1}) <<< (shift-1));
        y = (x + round_off) >>> shift;
      end else begin
        y = x;
      end
      if (relu && y[ACC_W-1]) y = '0;
      if (y > 127) quant_act = 127;
      else if (y < -128) quant_act = -128;
      else quant_act = y[DATA_W-1:0];
    end
  endfunction

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      busy    <= 1'b0;
      done    <= 1'b0;
      state   <= S_IDLE;
      oc      <= 0;
      oh      <= 0;
      ow      <= 0;
      ic      <= 0;
      kh      <= 0;
      kw      <= 0;
      acc_reg <= '0;
    end else begin
      done <= 1'b0;

      case (state)
        S_IDLE: begin
          if (start && !busy) begin
            busy    <= 1'b1;
            oc      <= 0;
            oh      <= 0;
            ow      <= 0;
            ic      <= 0;
            kh      <= 0;
            kw      <= 0;
            acc_reg <= bias[0];
            state   <= S_READ;
          end
        end

        S_READ: begin
          integer t;
          integer ic_t;
          integer kh_t;
          integer kw_t;
          logic done_taps;

          ic_t = ic;
          kh_t = kh;
          kw_t = kw;
          done_taps = 1'b0;

          for (t = 0; t < MAX_MACS_PER_CYCLE; t++) begin
            if (!done_taps) begin
              if (t < MACS_PER_CYCLE) begin
                in_data_reg[t] <= in_fmap[idx_in(ic_t, oh + kh_t, ow + kw_t)];
                weight_data_reg[t] <= weights[idx_w(oc, ic_t, kh_t, kw_t)];
              end
            end else begin
              if (t < MACS_PER_CYCLE) begin
                in_data_reg[t] <= '0;
                weight_data_reg[t] <= '0;
              end
            end

            if ((t < MACS_PER_CYCLE) && !done_taps) begin

              if (kw_t < (K-1)) begin
                kw_t = kw_t + 1;
              end else begin
                kw_t = 0;
                if (kh_t < (K-1)) begin
                  kh_t = kh_t + 1;
                end else begin
                  kh_t = 0;
                  if (ic_t < (IN_C-1)) begin
                    ic_t = ic_t + 1;
                  end else begin
                    done_taps = 1'b1;
                  end
                end
              end
            end
          end

          chunk_done_reg <= done_taps;
          if (done_taps) begin
            ic_next_reg <= 0;
            kh_next_reg <= 0;
            kw_next_reg <= 0;
          end else begin
            ic_next_reg <= ic_t;
            kh_next_reg <= kh_t;
            kw_next_reg <= kw_t;
          end
          state <= S_MUL;
        end

        S_MUL: begin
          integer t;
          for (t = 0; t < MAX_MACS_PER_CYCLE; t++) begin
            if (t < MACS_PER_CYCLE) begin
              mul_prod_reg[t] <= in_data_reg[t] * weight_data_reg[t];
            end else begin
              mul_prod_reg[t] <= '0;
            end
          end
          state <= S_ACCUM;
        end

        S_ACCUM: begin
          integer t;
          logic signed [ACC_W-1:0] acc_next;

          acc_next = acc_reg;
          for (t = 0; t < MACS_PER_CYCLE; t++) begin
            acc_next = sat_add_acc(
              acc_next,
              {{(ACC_W - (2*DATA_W)){mul_prod_reg[t][(2*DATA_W)-1]}}, mul_prod_reg[t]}
            );
          end
          acc_reg <= acc_next;

          if (chunk_done_reg) begin
            ic    <= 0;
            kh    <= 0;
            kw    <= 0;
            state <= S_WRITE;
          end else begin
            ic    <= ic_next_reg;
            kh    <= kh_next_reg;
            kw    <= kw_next_reg;
            state <= S_READ;
          end
        end

        S_WRITE: begin
          out_fmap[idx_out(oc, oh, ow)] <= quant_act(acc_reg, SHIFT, RELU_EN);
          state <= S_ADV;
        end

        S_ADV: begin
          if (ow < (OUT_W-1)) begin
            ow      <= ow + 1;
            acc_reg <= bias[oc];
            state   <= S_READ;
          end else if (oh < (OUT_H-1)) begin
            ow      <= 0;
            oh      <= oh + 1;
            acc_reg <= bias[oc];
            state   <= S_READ;
          end else if (oc < (OUT_C-1)) begin
            ow      <= 0;
            oh      <= 0;
            oc      <= oc + 1;
            acc_reg <= bias[oc + 1];
            state   <= S_READ;
          end else begin
            state <= S_DONE;
          end
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

  initial begin
    if (MACS_PER_CYCLE <= 0) begin
      $fatal(1, "cnn_conv_layer_rtl MACS_PER_CYCLE must be > 0");
    end
    if (MACS_PER_CYCLE > MAX_MACS_PER_CYCLE) begin
      $fatal(1, "cnn_conv_layer_rtl MACS_PER_CYCLE=%0d exceeds safe RTL limit=%0d for current memory architecture",
             MACS_PER_CYCLE, MAX_MACS_PER_CYCLE);
    end
  end

endmodule
