`timescale 1ns/1ps

module cnn_fc_logit_layer_rtl #(
  parameter int DATA_W    = 8,
  parameter int ACC_W     = 32,
  parameter int IN_ELEMS  = 84,
  parameter int OUT_ELEMS = 2,
  parameter int MACS_PER_CYCLE = 1
) (
  input  logic                         clk,
  input  logic                         rst_n,
  input  logic                         start,
  output logic                         busy,
  output logic                         done,
  input  logic signed [DATA_W-1:0]     in_vec [0:IN_ELEMS-1],
  input  logic signed [DATA_W-1:0]     weights [0:(OUT_ELEMS*IN_ELEMS)-1],
  input  logic signed [ACC_W-1:0]      bias [0:OUT_ELEMS-1],
  output logic signed [ACC_W-1:0]      out_logits [0:OUT_ELEMS-1]
);
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

  integer out_idx;
  integer in_idx;
  integer in_idx_next_reg;
  logic signed [ACC_W-1:0] acc_reg;
  logic                    chunk_done_reg;
  logic signed [DATA_W-1:0] in_data_reg [0:MAX_MACS_PER_CYCLE-1];
  logic signed [DATA_W-1:0] weight_data_reg [0:MAX_MACS_PER_CYCLE-1];
  (* use_dsp = "yes" *) logic signed [(2*DATA_W)-1:0] mul_prod_reg [0:MAX_MACS_PER_CYCLE-1];

  function automatic int idx_w(input int out_i, input int in_i);
    idx_w = out_i * IN_ELEMS + in_i;
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

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      busy    <= 1'b0;
      done    <= 1'b0;
      state   <= S_IDLE;
      out_idx <= 0;
      in_idx  <= 0;
      acc_reg <= '0;
    end else begin
      done <= 1'b0;

      case (state)
        S_IDLE: begin
          if (start && !busy) begin
            busy    <= 1'b1;
            out_idx <= 0;
            in_idx  <= 0;
            acc_reg <= bias[0];
            state   <= S_READ;
          end
        end

        S_READ: begin
          integer t;
          integer idx_t;

          for (t = 0; t < MAX_MACS_PER_CYCLE; t++) begin
            idx_t = in_idx + t;
            if ((t < MACS_PER_CYCLE) && (idx_t < IN_ELEMS)) begin
              in_data_reg[t] <= in_vec[idx_t];
              weight_data_reg[t] <= weights[idx_w(out_idx, idx_t)];
            end else if (t < MACS_PER_CYCLE) begin
              in_data_reg[t] <= '0;
              weight_data_reg[t] <= '0;
            end
          end
          chunk_done_reg <= ((in_idx + MACS_PER_CYCLE) >= IN_ELEMS);

          if ((in_idx + MACS_PER_CYCLE) < IN_ELEMS) begin
            in_idx_next_reg <= in_idx + MACS_PER_CYCLE;
          end else begin
            in_idx_next_reg <= 0;
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
            state <= S_WRITE;
          end else begin
            in_idx <= in_idx_next_reg;
            state  <= S_READ;
          end
        end

        S_WRITE: begin
          out_logits[out_idx] <= acc_reg;
          state <= S_ADV;
        end

        S_ADV: begin
          if (out_idx < (OUT_ELEMS-1)) begin
            out_idx <= out_idx + 1;
            in_idx  <= 0;
            acc_reg <= bias[out_idx + 1];
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
      $fatal(1, "cnn_fc_logit_layer_rtl MACS_PER_CYCLE must be > 0");
    end
    if (MACS_PER_CYCLE > MAX_MACS_PER_CYCLE) begin
      $fatal(1, "cnn_fc_logit_layer_rtl MACS_PER_CYCLE=%0d exceeds safe RTL limit=%0d for current memory architecture",
             MACS_PER_CYCLE, MAX_MACS_PER_CYCLE);
    end
  end

endmodule
