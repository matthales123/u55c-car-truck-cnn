`timescale 1ns/1ps

module qint8_dotp_rtl #(
  parameter int IN_ELEMS = 32,
  parameter int DATA_W   = 8,
  parameter int ACC_W    = 32
) (
  input  logic                             clk,
  input  logic                             rst_n,
  input  logic                             start,
  input  logic signed [DATA_W-1:0]         vec [0:IN_ELEMS-1],
  input  logic signed [DATA_W-1:0]         wgt [0:IN_ELEMS-1],
  input  logic signed [ACC_W-1:0]          bias,
  output logic                             busy,
  output logic                             done,
  output logic signed [ACC_W-1:0]          acc_out
);

  localparam int PROD_W = 2 * DATA_W;
  localparam int IDX_W  = (IN_ELEMS <= 2) ? 1 : $clog2(IN_ELEMS);

  logic [IDX_W-1:0] idx_q;
  logic signed [ACC_W-1:0] acc_q;

  logic signed [PROD_W-1:0] prod_comb;
  logic signed [ACC_W-1:0]  prod_ext_comb;
  logic signed [ACC_W-1:0]  acc_next_comb;

  function automatic signed [ACC_W-1:0] sat_add(
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

      if (sum_ext > sat_max) begin
        sat_add = sat_max[ACC_W-1:0];
      end else if (sum_ext < sat_min) begin
        sat_add = sat_min[ACC_W-1:0];
      end else begin
        sat_add = sum_ext[ACC_W-1:0];
      end
    end
  endfunction

  always_comb begin
    prod_comb     = '0;
    prod_ext_comb = '0;
    acc_next_comb = acc_q;

    if (busy) begin
      prod_comb     = vec[idx_q] * wgt[idx_q];
      prod_ext_comb = {{(ACC_W - PROD_W){prod_comb[PROD_W-1]}}, prod_comb};
      acc_next_comb = sat_add(acc_q, prod_ext_comb);
    end
  end

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      idx_q   <= '0;
      acc_q   <= '0;
      acc_out <= '0;
      busy    <= 1'b0;
      done    <= 1'b0;
    end else begin
      done <= 1'b0;

      if (start && !busy) begin
        idx_q <= '0;
        acc_q <= bias;
        busy  <= 1'b1;
      end else if (busy) begin
        acc_q <= acc_next_comb;

        if (idx_q == IN_ELEMS-1) begin
          busy    <= 1'b0;
          done    <= 1'b1;
          acc_out <= acc_next_comb;
        end else begin
          idx_q <= idx_q + 1'b1;
        end
      end
    end
  end

  initial begin
    if (IN_ELEMS <= 0) begin
      $fatal(1, "qint8_dotp_rtl: IN_ELEMS must be > 0");
    end
    if (ACC_W < PROD_W) begin
      $fatal(1, "qint8_dotp_rtl: ACC_W must be >= 2*DATA_W");
    end
  end

endmodule
