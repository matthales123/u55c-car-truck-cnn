`timescale 1ns/1ps

module cnn_argmax2_rtl #(
  parameter int ACC_W = 32
) (
  input  logic signed [ACC_W-1:0] logit0,
  input  logic signed [ACC_W-1:0] logit1,
  output logic                    class_id
);

  always_comb begin
    class_id = (logit1 > logit0);
  end

endmodule
