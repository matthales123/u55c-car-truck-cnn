`timescale 1ns/1ps

module cnn_maxpool_layer_rtl #(
  parameter int DATA_W = 8,
  parameter int C      = 6,
  parameter int IN_H   = 28,
  parameter int IN_W   = 28,
  parameter int POOL   = 2
) (
  input  logic                         clk,
  input  logic                         rst_n,
  input  logic                         start,
  output logic                         busy,
  output logic                         done,
  input  logic signed [DATA_W-1:0]     in_fmap [0:(C*IN_H*IN_W)-1],
  output logic signed [DATA_W-1:0]     out_fmap [0:(C*(IN_H/POOL)*(IN_W/POOL))-1]
);

  localparam int OUT_H = IN_H / POOL;
  localparam int OUT_W = IN_W / POOL;

  typedef enum logic [2:0] {
    S_IDLE,
    S_READ,
    S_CALC,
    S_ADV,
    S_DONE
  } state_t;

  state_t state;

  integer c_idx;
  integer h_idx;
  integer w_idx;
  logic signed [DATA_W-1:0] pool_data_reg [0:3];

  function automatic int idx_in(input int ch, input int h, input int w);
    idx_in = ((ch * IN_H) + h) * IN_W + w;
  endfunction

  function automatic int idx_out(input int ch, input int h, input int w);
    idx_out = ((ch * OUT_H) + h) * OUT_W + w;
  endfunction

  function automatic signed [DATA_W-1:0] max4(
    input signed [DATA_W-1:0] a,
    input signed [DATA_W-1:0] b,
    input signed [DATA_W-1:0] c,
    input signed [DATA_W-1:0] d
  );
    logic signed [DATA_W-1:0] m1;
    logic signed [DATA_W-1:0] m2;
    begin
      m1 = (a > b) ? a : b;
      m2 = (c > d) ? c : d;
      max4 = (m1 > m2) ? m1 : m2;
    end
  endfunction

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      busy   <= 1'b0;
      done   <= 1'b0;
      state  <= S_IDLE;
      c_idx  <= 0;
      h_idx  <= 0;
      w_idx  <= 0;
    end else begin
      done <= 1'b0;

      case (state)
        S_IDLE: begin
          if (start && !busy) begin
            busy  <= 1'b1;
            c_idx <= 0;
            h_idx <= 0;
            w_idx <= 0;
            state <= S_READ;
          end
        end

        S_READ: begin
          pool_data_reg[0] <= in_fmap[idx_in(c_idx, (h_idx*POOL)+0, (w_idx*POOL)+0)];
          pool_data_reg[1] <= in_fmap[idx_in(c_idx, (h_idx*POOL)+0, (w_idx*POOL)+1)];
          pool_data_reg[2] <= in_fmap[idx_in(c_idx, (h_idx*POOL)+1, (w_idx*POOL)+0)];
          pool_data_reg[3] <= in_fmap[idx_in(c_idx, (h_idx*POOL)+1, (w_idx*POOL)+1)];
          state <= S_CALC;
        end

        S_CALC: begin
          out_fmap[idx_out(c_idx, h_idx, w_idx)] <= max4(pool_data_reg[0], pool_data_reg[1], pool_data_reg[2], pool_data_reg[3]);
          state <= S_ADV;
        end

        S_ADV: begin
          if (w_idx < (OUT_W-1)) begin
            w_idx <= w_idx + 1;
            state <= S_READ;
          end else if (h_idx < (OUT_H-1)) begin
            w_idx <= 0;
            h_idx <= h_idx + 1;
            state <= S_READ;
          end else if (c_idx < (C-1)) begin
            w_idx <= 0;
            h_idx <= 0;
            c_idx <= c_idx + 1;
            state <= S_READ;
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

endmodule
