`timescale 1ns/1ps

module cnn_rtl_regression_tb;

  localparam int IN_ELEMS = 32;
  localparam int DATA_W   = 8;
  localparam int ACC_W    = 32;

  logic clk;
  logic rst_n;

  int cycle_count;
  int test_count;
  int fail_count;

  // --------------------------------------------------------------------------
  // DUT #1: low-level saturating dot product engine
  // --------------------------------------------------------------------------
  logic                             dot_start;
  logic                             dot_busy;
  logic                             dot_done;
  logic signed [DATA_W-1:0]         dot_vec [0:IN_ELEMS-1];
  logic signed [DATA_W-1:0]         dot_wgt [0:IN_ELEMS-1];
  logic signed [ACC_W-1:0]          dot_bias;
  logic signed [ACC_W-1:0]          dot_out;

  qint8_dotp_rtl #(
    .IN_ELEMS(IN_ELEMS),
    .DATA_W  (DATA_W),
    .ACC_W   (ACC_W)
  ) dot_dut (
    .clk    (clk),
    .rst_n  (rst_n),
    .start  (dot_start),
    .vec    (dot_vec),
    .wgt    (dot_wgt),
    .bias   (dot_bias),
    .busy   (dot_busy),
    .done   (dot_done),
    .acc_out(dot_out)
  );

  // --------------------------------------------------------------------------
  // DUT #2: two-class classifier head built from two dot-product engines
  // --------------------------------------------------------------------------
  logic                             head_start;
  logic                             head_relu_en;
  logic                             head_busy;
  logic                             head_valid;
  logic                             head_class_id;
  logic signed [DATA_W-1:0]         head_vec [0:IN_ELEMS-1];
  logic signed [DATA_W-1:0]         head_w0  [0:IN_ELEMS-1];
  logic signed [DATA_W-1:0]         head_w1  [0:IN_ELEMS-1];
  logic signed [ACC_W-1:0]          head_b0;
  logic signed [ACC_W-1:0]          head_b1;
  logic signed [ACC_W-1:0]          head_logit0;
  logic signed [ACC_W-1:0]          head_logit1;

  cnn_two_class_head_rtl #(
    .IN_ELEMS(IN_ELEMS),
    .DATA_W  (DATA_W),
    .ACC_W   (ACC_W)
  ) head_dut (
    .clk       (clk),
    .rst_n     (rst_n),
    .start     (head_start),
    .relu_en   (head_relu_en),
    .input_vec (head_vec),
    .w_class0  (head_w0),
    .w_class1  (head_w1),
    .b_class0  (head_b0),
    .b_class1  (head_b1),
    .busy      (head_busy),
    .class_valid(head_valid),
    .class_id  (head_class_id),
    .logit0    (head_logit0),
    .logit1    (head_logit1)
  );

  // --------------------------------------------------------------------------
  // Clocking + cycle counter
  // --------------------------------------------------------------------------
  initial begin
    clk = 1'b0;
    forever #5 clk = ~clk;
  end

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      cycle_count <= 0;
    end else begin
      cycle_count <= cycle_count + 1;
    end
  end

  // --------------------------------------------------------------------------
  // Reference model helpers
  // --------------------------------------------------------------------------
  function automatic signed [ACC_W-1:0] sat_add_ref(
    input signed [ACC_W-1:0] a,
    input signed [ACC_W-1:0] b
  );
    longint signed sum;
    longint signed sat_max;
    longint signed sat_min;
    begin
      sat_max = (64'sd1 <<< (ACC_W-1)) - 1;
      sat_min = -(64'sd1 <<< (ACC_W-1));
      sum     = a + b;

      if (sum > sat_max) begin
        sat_add_ref = signed'(sat_max);
      end else if (sum < sat_min) begin
        sat_add_ref = signed'(sat_min);
      end else begin
        sat_add_ref = signed'(sum);
      end
    end
  endfunction

  function automatic signed [ACC_W-1:0] dot_ref(
    input logic signed [DATA_W-1:0] vec_ref [0:IN_ELEMS-1],
    input logic signed [DATA_W-1:0] wgt_ref [0:IN_ELEMS-1],
    input signed [ACC_W-1:0]        bias_ref
  );
    logic signed [ACC_W-1:0] acc;
    logic signed [2*DATA_W-1:0] prod;
    int i;
    begin
      acc = bias_ref;
      for (i = 0; i < IN_ELEMS; i++) begin
        prod = vec_ref[i] * wgt_ref[i];
        acc  = sat_add_ref(acc, $signed(prod));
      end
      dot_ref = acc;
    end
  endfunction

  function automatic logic signed [DATA_W-1:0] rand_s8(input int max_abs);
    int signed tmp;
    begin
      tmp = $urandom_range(0, 2*max_abs) - max_abs;
      rand_s8 = tmp[DATA_W-1:0];
    end
  endfunction

  task automatic record_fail(input string msg);
    begin
      fail_count = fail_count + 1;
      $display("[FAIL] %s", msg);
    end
  endtask

  task automatic expect_eq_s(
    input string test_name,
    input string field_name,
    input signed [ACC_W-1:0] got,
    input signed [ACC_W-1:0] exp
  );
    begin
      if (got !== exp) begin
        record_fail($sformatf("%s %s mismatch: got=%0d exp=%0d", test_name, field_name, got, exp));
      end
    end
  endtask

  task automatic expect_eq_u1(
    input string test_name,
    input string field_name,
    input logic got,
    input logic exp
  );
    begin
      if (got !== exp) begin
        record_fail($sformatf("%s %s mismatch: got=%0d exp=%0d", test_name, field_name, got, exp));
      end
    end
  endtask

  task automatic reset_all_inputs;
    int i;
    begin
      dot_start  = 1'b0;
      dot_bias   = '0;
      head_start = 1'b0;
      head_relu_en = 1'b0;
      head_b0    = '0;
      head_b1    = '0;

      for (i = 0; i < IN_ELEMS; i++) begin
        dot_vec[i] = '0;
        dot_wgt[i] = '0;
        head_vec[i] = '0;
        head_w0[i]  = '0;
        head_w1[i]  = '0;
      end
    end
  endtask

  task automatic run_dot_case(
    input string test_name,
    input bit expect_exact_latency
  );
    logic signed [ACC_W-1:0] exp;
    int latency;
    begin
      test_count = test_count + 1;
      exp = dot_ref(dot_vec, dot_wgt, dot_bias);

      dot_start = 1'b1;
      @(posedge clk);
      dot_start = 1'b0;

      latency = 0;
      while (!dot_done && latency < (IN_ELEMS + 8)) begin
        @(posedge clk);
        latency = latency + 1;
      end

      if (!dot_done) begin
        record_fail($sformatf("%s timeout waiting for dot_done", test_name));
      end else begin
        if (expect_exact_latency && (latency != IN_ELEMS)) begin
          record_fail($sformatf("%s latency mismatch: got=%0d exp=%0d", test_name, latency, IN_ELEMS));
        end
        expect_eq_s(test_name, "dot_out", dot_out, exp);
      end

      @(posedge clk);
    end
  endtask

  task automatic run_head_case(
    input string test_name,
    input bit relu_mode,
    input bit expect_exact_latency
  );
    logic signed [ACC_W-1:0] exp0;
    logic signed [ACC_W-1:0] exp1;
    logic exp_class;
    int latency;
    begin
      test_count = test_count + 1;

      exp0 = dot_ref(head_vec, head_w0, head_b0);
      exp1 = dot_ref(head_vec, head_w1, head_b1);

      if (relu_mode && exp0[ACC_W-1]) exp0 = '0;
      if (relu_mode && exp1[ACC_W-1]) exp1 = '0;
      exp_class = (exp1 > exp0);

      head_relu_en = relu_mode;
      head_start   = 1'b1;
      @(posedge clk);
      head_start   = 1'b0;

      latency = 0;
      while (!head_valid && latency < (IN_ELEMS + 8)) begin
        @(posedge clk);
        latency = latency + 1;
      end

      if (!head_valid) begin
        record_fail($sformatf("%s timeout waiting for head_valid", test_name));
      end else begin
        if (expect_exact_latency && (latency != (IN_ELEMS + 1))) begin
          record_fail($sformatf("%s latency mismatch: got=%0d exp=%0d", test_name, latency, (IN_ELEMS + 1)));
        end
        expect_eq_s(test_name, "logit0", head_logit0, exp0);
        expect_eq_s(test_name, "logit1", head_logit1, exp1);
        expect_eq_u1(test_name, "class_id", head_class_id, exp_class);
      end

      @(posedge clk);
    end
  endtask

  task automatic run_dot_suite;
    int i;
    int t;
    begin
      $display("[INFO] Starting dot-product suite...");

      // Case 1: all zeros
      for (i = 0; i < IN_ELEMS; i++) begin
        dot_vec[i] = '0;
        dot_wgt[i] = '0;
      end
      dot_bias = '0;
      run_dot_case("dot_zero", 1'b1);

      // Case 2: bias-only result
      dot_bias = 32'sd12345;
      run_dot_case("dot_bias_only", 1'b1);

      // Case 3: deterministic mixed signs
      dot_bias = -32'sd777;
      for (i = 0; i < IN_ELEMS; i++) begin
        dot_vec[i] = (i[0]) ? 8'sd12 : -8'sd7;
        dot_wgt[i] = (i[1]) ? -8'sd9 : 8'sd5;
      end
      run_dot_case("dot_mixed_sign", 1'b1);

      // Case 4: positive saturation
      dot_bias = 32'sh7FFF_FF00;
      for (i = 0; i < IN_ELEMS; i++) begin
        dot_vec[i] = 8'sd127;
        dot_wgt[i] = 8'sd127;
      end
      run_dot_case("dot_pos_saturate", 1'b1);

      // Case 5: negative saturation
      dot_bias = 32'sh8000_0100;
      for (i = 0; i < IN_ELEMS; i++) begin
        dot_vec[i] = -8'sd128;
        dot_wgt[i] = 8'sd127;
      end
      run_dot_case("dot_neg_saturate", 1'b1);

      // Case 6: start while busy should be ignored
      for (i = 0; i < IN_ELEMS; i++) begin
        dot_vec[i] = (i % 5) - 2;
        dot_wgt[i] = (i % 7) - 3;
      end
      dot_bias = 32'sd99;

      test_count = test_count + 1;
      dot_start = 1'b1;
      @(posedge clk);
      dot_start = 1'b0;

      repeat (3) @(posedge clk);
      dot_start = 1'b1;
      @(posedge clk);
      dot_start = 1'b0;

      i = 0;
      while (!dot_done && i < (IN_ELEMS + 8)) begin
        @(posedge clk);
        i = i + 1;
      end
      if (!dot_done) begin
        record_fail("dot_start_while_busy timeout");
      end else begin
        expect_eq_s("dot_start_while_busy", "dot_out", dot_out, dot_ref(dot_vec, dot_wgt, dot_bias));
      end
      @(posedge clk);

      // Case 7: reset during compute must abort safely
      for (i = 0; i < IN_ELEMS; i++) begin
        dot_vec[i] = rand_s8(32);
        dot_wgt[i] = rand_s8(32);
      end
      dot_bias = -32'sd401;

      test_count = test_count + 1;
      dot_start = 1'b1;
      @(posedge clk);
      dot_start = 1'b0;
      repeat (4) @(posedge clk);

      rst_n = 1'b0;
      repeat (2) @(posedge clk);
      rst_n = 1'b1;
      @(posedge clk);

      if (dot_busy !== 1'b0) begin
        record_fail("dot_reset_mid_compute busy must clear after reset");
      end
      if (dot_done !== 1'b0) begin
        record_fail("dot_reset_mid_compute done must be low after reset");
      end

      // Re-run after reset to confirm clean restart behavior.
      run_dot_case("dot_post_reset_recovery", 1'b1);

      // Case 8: randomized regression
      for (t = 0; t < 200; t++) begin
        dot_bias = $signed($urandom()) >>> 3;
        for (i = 0; i < IN_ELEMS; i++) begin
          dot_vec[i] = rand_s8(127);
          dot_wgt[i] = rand_s8(127);
        end
        run_dot_case($sformatf("dot_rand_%0d", t), 1'b1);
      end
    end
  endtask

  task automatic run_head_suite;
    int i;
    int t;
    begin
      $display("[INFO] Starting two-class head suite...");

      // Case 1: bias-only classification (class 1 should win)
      for (i = 0; i < IN_ELEMS; i++) begin
        head_vec[i] = '0;
        head_w0[i]  = '0;
        head_w1[i]  = '0;
      end
      head_b0 = -32'sd5;
      head_b1 = 32'sd7;
      run_head_case("head_bias_only", 1'b0, 1'b1);

      // Case 2: exact tie should map to class 0 (strict > comparator)
      head_b0 = 32'sd123;
      head_b1 = 32'sd123;
      run_head_case("head_tie_break", 1'b0, 1'b1);

      // Case 3: deterministic mixed vectors
      for (i = 0; i < IN_ELEMS; i++) begin
        head_vec[i] = (i[0]) ? 8'sd10 : -8'sd4;
        head_w0[i]  = (i[1]) ? 8'sd6 : -8'sd9;
        head_w1[i]  = (i[2]) ? -8'sd8 : 8'sd11;
      end
      head_b0 = 32'sd30;
      head_b1 = -32'sd19;
      run_head_case("head_mixed_sign", 1'b0, 1'b1);

      // Case 4: relu mode clamps negatives
      for (i = 0; i < IN_ELEMS; i++) begin
        head_vec[i] = -8'sd16;
        head_w0[i]  = 8'sd2;
        head_w1[i]  = 8'sd1;
      end
      head_b0 = -32'sd1;
      head_b1 = -32'sd2;
      run_head_case("head_relu_clamp", 1'b1, 1'b1);

      // Case 5: saturating stress on both classes
      for (i = 0; i < IN_ELEMS; i++) begin
        head_vec[i] = 8'sd127;
        head_w0[i]  = 8'sd127;
        head_w1[i]  = -8'sd128;
      end
      head_b0 = 32'sh7FFF_FF00;
      head_b1 = 32'sh8000_0100;
      run_head_case("head_sat_stress", 1'b0, 1'b1);

      // Case 6: start while busy pulse must be ignored
      for (i = 0; i < IN_ELEMS; i++) begin
        head_vec[i] = rand_s8(40);
        head_w0[i]  = rand_s8(40);
        head_w1[i]  = rand_s8(40);
      end
      head_b0 = 32'sd5;
      head_b1 = -32'sd5;

      test_count = test_count + 1;
      head_relu_en = 1'b0;
      head_start   = 1'b1;
      @(posedge clk);
      head_start   = 1'b0;
      repeat (5) @(posedge clk);
      head_start   = 1'b1;
      @(posedge clk);
      head_start   = 1'b0;

      i = 0;
      while (!head_valid && i < (IN_ELEMS + 8)) begin
        @(posedge clk);
        i = i + 1;
      end
      if (!head_valid) begin
        record_fail("head_start_while_busy timeout");
      end else begin
        expect_eq_s("head_start_while_busy", "logit0", head_logit0, dot_ref(head_vec, head_w0, head_b0));
        expect_eq_s("head_start_while_busy", "logit1", head_logit1, dot_ref(head_vec, head_w1, head_b1));
      end
      @(posedge clk);

      // Case 7: reset mid-compute and recover
      for (i = 0; i < IN_ELEMS; i++) begin
        head_vec[i] = rand_s8(64);
        head_w0[i]  = rand_s8(64);
        head_w1[i]  = rand_s8(64);
      end
      head_b0 = 32'sd101;
      head_b1 = -32'sd37;

      test_count = test_count + 1;
      head_start = 1'b1;
      @(posedge clk);
      head_start = 1'b0;
      repeat (4) @(posedge clk);
      rst_n = 1'b0;
      repeat (2) @(posedge clk);
      rst_n = 1'b1;
      @(posedge clk);
      if (head_busy !== 1'b0) begin
        record_fail("head_reset_mid_compute busy must clear after reset");
      end
      if (head_valid !== 1'b0) begin
        record_fail("head_reset_mid_compute class_valid must be low after reset");
      end
      run_head_case("head_post_reset_recovery", 1'b0, 1'b1);

      // Case 8: randomized regression with/without relu
      for (t = 0; t < 200; t++) begin
        head_relu_en = (t % 3 == 0);
        head_b0 = $signed($urandom()) >>> 4;
        head_b1 = $signed($urandom()) >>> 4;
        for (i = 0; i < IN_ELEMS; i++) begin
          head_vec[i] = rand_s8(127);
          head_w0[i]  = rand_s8(127);
          head_w1[i]  = rand_s8(127);
        end
        run_head_case($sformatf("head_rand_%0d", t), head_relu_en, 1'b1);
      end
    end
  endtask

  // --------------------------------------------------------------------------
  // Main regression flow
  // --------------------------------------------------------------------------
  initial begin
    test_count  = 0;
    fail_count  = 0;

    rst_n = 1'b0;
    reset_all_inputs();

    repeat (5) @(posedge clk);
    rst_n = 1'b1;
    @(posedge clk);

    run_dot_suite();
    run_head_suite();

    $display("[INFO] Regression complete: tests=%0d failures=%0d", test_count, fail_count);

    if (fail_count != 0) begin
      $fatal(1, "cnn_rtl_regression_tb FAILED with %0d failing checks", fail_count);
    end else begin
      $display("[PASS] cnn_rtl_regression_tb passed all checks.");
    end

    $finish;
  end

endmodule
