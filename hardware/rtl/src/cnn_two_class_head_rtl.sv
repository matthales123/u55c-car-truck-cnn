`timescale 1ns/1ps

module cnn_two_class_head_rtl #(
  parameter int IN_ELEMS = 32,
  parameter int DATA_W   = 8,
  parameter int ACC_W    = 32
) (
  input  logic                             clk,
  input  logic                             rst_n,
  input  logic                             start,
  input  logic                             relu_en,
  input  logic signed [DATA_W-1:0]         input_vec [0:IN_ELEMS-1],
  input  logic signed [DATA_W-1:0]         w_class0 [0:IN_ELEMS-1],
  input  logic signed [DATA_W-1:0]         w_class1 [0:IN_ELEMS-1],
  input  logic signed [ACC_W-1:0]          b_class0,
  input  logic signed [ACC_W-1:0]          b_class1,
  output logic                             busy,
  output logic                             class_valid,
  output logic                             class_id,
  output logic signed [ACC_W-1:0]          logit0,
  output logic signed [ACC_W-1:0]          logit1
);

  logic dot_busy0;
  logic dot_busy1;
  logic dot_done0;
  logic dot_done1;

  logic signed [ACC_W-1:0] dot_out0;
  logic signed [ACC_W-1:0] dot_out1;

  logic signed [ACC_W-1:0] post0;
  logic signed [ACC_W-1:0] post1;

  qint8_dotp_rtl #(
    .IN_ELEMS(IN_ELEMS),
    .DATA_W  (DATA_W),
    .ACC_W   (ACC_W)
  ) dot_class0 (
    .clk    (clk),
    .rst_n  (rst_n),
    .start  (start),
    .vec    (input_vec),
    .wgt    (w_class0),
    .bias   (b_class0),
    .busy   (dot_busy0),
    .done   (dot_done0),
    .acc_out(dot_out0)
  );

  qint8_dotp_rtl #(
    .IN_ELEMS(IN_ELEMS),
    .DATA_W  (DATA_W),
    .ACC_W   (ACC_W)
  ) dot_class1 (
    .clk    (clk),
    .rst_n  (rst_n),
    .start  (start),
    .vec    (input_vec),
    .wgt    (w_class1),
    .bias   (b_class1),
    .busy   (dot_busy1),
    .done   (dot_done1),
    .acc_out(dot_out1)
  );

  assign busy = dot_busy0 | dot_busy1;

  always_comb begin
    post0 = dot_out0;
    post1 = dot_out1;

    if (relu_en && dot_out0[ACC_W-1]) begin
      post0 = '0;
    end
    if (relu_en && dot_out1[ACC_W-1]) begin
      post1 = '0;
    end
  end

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      class_valid <= 1'b0;
      class_id    <= 1'b0;
      logit0      <= '0;
      logit1      <= '0;
    end else begin
      class_valid <= 1'b0;

      if (dot_done0 && dot_done1) begin
        logit0      <= post0;
        logit1      <= post1;
        class_id    <= (post1 > post0);
        class_valid <= 1'b1;
      end
    end
  end

endmodule
