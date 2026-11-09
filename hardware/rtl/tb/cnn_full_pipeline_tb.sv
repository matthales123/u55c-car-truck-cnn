`timescale 1ns/1ps

module cnn_full_pipeline_tb;

  localparam int DATA_W  = 8;
  localparam int ACC_W   = 32;
  localparam int C_IN    = 2;
  localparam int IN_H    = 12;
  localparam int IN_W    = 12;
  localparam int C1_OUT  = 3;
  localparam int K1      = 3;
  localparam int C2_OUT  = 2;
  localparam int K2      = 3;
  localparam int POOL    = 2;
  localparam int FC1_OUT = 5;
  localparam int FC2_OUT = 4;
  localparam int FC3_OUT = 2;

  localparam int SHIFT_CONV1 = 0;
  localparam int SHIFT_CONV2 = 0;
  localparam int SHIFT_FC1   = 0;
  localparam int SHIFT_FC2   = 0;
  localparam int CONV1_MACS_PER_CYCLE = 2;
  localparam int CONV2_MACS_PER_CYCLE = 2;
  localparam int FC1_MACS_PER_CYCLE = 2;
  localparam int FC2_MACS_PER_CYCLE = 2;
  localparam int FC3_MACS_PER_CYCLE = 2;

  localparam int C1_H = IN_H - K1 + 1;
  localparam int C1_W = IN_W - K1 + 1;
  localparam int P1_H = C1_H / POOL;
  localparam int P1_W = C1_W / POOL;
  localparam int C2_H = P1_H - K2 + 1;
  localparam int C2_W = P1_W - K2 + 1;
  localparam int P2_H = C2_H / POOL;
  localparam int P2_W = C2_W / POOL;

  localparam int IN_SIZE   = C_IN * IN_H * IN_W;
  localparam int C1_SIZE   = C1_OUT * C1_H * C1_W;
  localparam int P1_SIZE   = C1_OUT * P1_H * P1_W;
  localparam int C2_SIZE   = C2_OUT * C2_H * C2_W;
  localparam int P2_SIZE   = C2_OUT * P2_H * P2_W;
  localparam int FLAT_SIZE = P2_SIZE;

  localparam int W1_SIZE = C1_OUT * C_IN   * K1 * K1;
  localparam int W2_SIZE = C2_OUT * C1_OUT * K2 * K2;
  localparam int W3_SIZE = FC1_OUT * FLAT_SIZE;
  localparam int W4_SIZE = FC2_OUT * FC1_OUT;
  localparam int W5_SIZE = FC3_OUT * FC2_OUT;

  logic clk;
  logic rst_n;
  logic start;
  logic busy;
  logic done;
  logic class_id;
  logic signed [ACC_W-1:0] logit0;
  logic signed [ACC_W-1:0] logit1;

  logic cfg_we8;
  logic [3:0] cfg_bank8;
  logic [31:0] cfg_addr8;
  logic signed [DATA_W-1:0] cfg_data8;

  logic cfg_we32;
  logic [3:0] cfg_bank32;
  logic [31:0] cfg_addr32;
  logic signed [ACC_W-1:0] cfg_data32;

  int test_count;
  int fail_count;
  int cycle_count;

  logic signed [DATA_W-1:0] in_mem [0:IN_SIZE-1];
  logic signed [DATA_W-1:0] w1_mem [0:W1_SIZE-1];
  logic signed [DATA_W-1:0] w2_mem [0:W2_SIZE-1];
  logic signed [DATA_W-1:0] w3_mem [0:W3_SIZE-1];
  logic signed [DATA_W-1:0] w4_mem [0:W4_SIZE-1];
  logic signed [DATA_W-1:0] w5_mem [0:W5_SIZE-1];

  logic signed [ACC_W-1:0] b1_mem [0:C1_OUT-1];
  logic signed [ACC_W-1:0] b2_mem [0:C2_OUT-1];
  logic signed [ACC_W-1:0] b3_mem [0:FC1_OUT-1];
  logic signed [ACC_W-1:0] b4_mem [0:FC2_OUT-1];
  logic signed [ACC_W-1:0] b5_mem [0:FC3_OUT-1];

  logic signed [DATA_W-1:0] ref_act1 [0:C1_SIZE-1];
  logic signed [DATA_W-1:0] ref_pool1[0:P1_SIZE-1];
  logic signed [DATA_W-1:0] ref_act2 [0:C2_SIZE-1];
  logic signed [DATA_W-1:0] ref_pool2[0:P2_SIZE-1];
  logic signed [DATA_W-1:0] ref_fc1 [0:FC1_OUT-1];
  logic signed [DATA_W-1:0] ref_fc2 [0:FC2_OUT-1];
  logic signed [ACC_W-1:0] ref_fc3 [0:FC3_OUT-1];

  logic signed [ACC_W-1:0] exp_logit0;
  logic signed [ACC_W-1:0] exp_logit1;
  logic exp_class;

  logic [31:0] prng_state;

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
    .STATIC_DEMO_WEIGHTS(1'b1),
    .FC1_MACS_PER_CYCLE(FC1_MACS_PER_CYCLE),
    .FC2_MACS_PER_CYCLE(FC2_MACS_PER_CYCLE),
    .FC3_MACS_PER_CYCLE(FC3_MACS_PER_CYCLE)
  ) dut (
    .clk(clk),
    .rst_n(rst_n),
    .start(start),
    .busy(busy),
    .done(done),
    .class_id(class_id),
    .logit0(logit0),
    .logit1(logit1),
    .cfg_we8(cfg_we8),
    .cfg_bank8(cfg_bank8),
    .cfg_addr8(cfg_addr8),
    .cfg_data8(cfg_data8),
    .cfg_we32(cfg_we32),
    .cfg_bank32(cfg_bank32),
    .cfg_addr32(cfg_addr32),
    .cfg_data32(cfg_data32)
  );

  function automatic int idx_in(input int ch, input int h, input int w);
    idx_in = ((ch * IN_H) + h) * IN_W + w;
  endfunction

  function automatic int idx_c1(input int ch, input int h, input int w);
    idx_c1 = ((ch * C1_H) + h) * C1_W + w;
  endfunction

  function automatic int idx_p1(input int ch, input int h, input int w);
    idx_p1 = ((ch * P1_H) + h) * P1_W + w;
  endfunction

  function automatic int idx_c2(input int ch, input int h, input int w);
    idx_c2 = ((ch * C2_H) + h) * C2_W + w;
  endfunction

  function automatic int idx_p2(input int ch, input int h, input int w);
    idx_p2 = ((ch * P2_H) + h) * P2_W + w;
  endfunction

  function automatic int idx_w1(input int och, input int ich, input int k_h, input int k_w);
    idx_w1 = ((((och * C_IN) + ich) * K1) + k_h) * K1 + k_w;
  endfunction

  function automatic int idx_w2(input int och, input int ich, input int k_h, input int k_w);
    idx_w2 = ((((och * C1_OUT) + ich) * K2) + k_h) * K2 + k_w;
  endfunction

  function automatic int idx_w3(input int out_i, input int in_i);
    idx_w3 = out_i * FLAT_SIZE + in_i;
  endfunction

  function automatic int idx_w4(input int out_i, input int in_i);
    idx_w4 = out_i * FC1_OUT + in_i;
  endfunction

  function automatic int idx_w5(input int out_i, input int in_i);
    idx_w5 = out_i * FC2_OUT + in_i;
  endfunction

  function automatic signed [DATA_W-1:0] demo_weight8(
    input int layer_id,
    input int idx
  );
    int signed v;
    begin
      case (layer_id)
        1: v = ((idx * 13 + 5) % 15) - 7;
        2: v = ((idx * 11 + 3) % 13) - 6;
        3: v = ((idx *  7 + 1) %  9) - 4;
        4: v = ((idx *  5 + 2) %  7) - 3;
        5: v = ((idx *  3 + 4) %  7) - 3;
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

  function automatic signed [ACC_W-1:0] mul_ext(
    input signed [DATA_W-1:0] a,
    input signed [DATA_W-1:0] b
  );
    logic signed [(2*DATA_W)-1:0] p;
    begin
      p = a * b;
      mul_ext = {{(ACC_W - (2*DATA_W)){p[(2*DATA_W)-1]}}, p};
    end
  endfunction

  function automatic signed [DATA_W-1:0] quant_act(
    input signed [ACC_W-1:0] x,
    input int shift,
    input bit relu_en
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
      if (relu_en && y[ACC_W-1]) y = '0;
      if (y > 127) quant_act = 127;
      else if (y < -128) quant_act = -128;
      else quant_act = y[DATA_W-1:0];
    end
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

  task automatic prng_next(output logic [31:0] rnd);
    begin
      prng_state = (prng_state * 32'd1664525) + 32'd1013904223;
      rnd = prng_state;
    end
  endtask

  task automatic load_cfg8(input [3:0] bank, input int addr, input signed [DATA_W-1:0] data);
    begin
      @(posedge clk);
      cfg_we8   <= 1'b1;
      cfg_bank8 <= bank;
      cfg_addr8 <= addr;
      cfg_data8 <= data;
      @(posedge clk);
      cfg_we8   <= 1'b0;
      cfg_addr8 <= 0;
      cfg_data8 <= '0;
    end
  endtask

  task automatic load_cfg32(input [3:0] bank, input int addr, input signed [ACC_W-1:0] data);
    begin
      @(posedge clk);
      cfg_we32   <= 1'b1;
      cfg_bank32 <= bank;
      cfg_addr32 <= addr;
      cfg_data32 <= data;
      @(posedge clk);
      cfg_we32   <= 1'b0;
      cfg_addr32 <= 0;
      cfg_data32 <= '0;
    end
  endtask

  task automatic clear_model;
    int i;
    begin
      for (i = 0; i < IN_SIZE; i++) in_mem[i] = '0;
    end
  endtask

  task automatic init_static_params;
    int i;
    begin
      for (i = 0; i < W1_SIZE; i++) w1_mem[i] = demo_weight8(1, i);
      for (i = 0; i < W2_SIZE; i++) w2_mem[i] = demo_weight8(2, i);
      for (i = 0; i < W3_SIZE; i++) w3_mem[i] = demo_weight8(3, i);
      for (i = 0; i < W4_SIZE; i++) w4_mem[i] = demo_weight8(4, i);
      for (i = 0; i < W5_SIZE; i++) w5_mem[i] = demo_weight8(5, i);
      for (i = 0; i < C1_OUT; i++) b1_mem[i] = demo_bias32(1, i);
      for (i = 0; i < C2_OUT; i++) b2_mem[i] = demo_bias32(2, i);
      for (i = 0; i < FC1_OUT; i++) b3_mem[i] = demo_bias32(3, i);
      for (i = 0; i < FC2_OUT; i++) b4_mem[i] = demo_bias32(4, i);
      for (i = 0; i < FC3_OUT; i++) b5_mem[i] = demo_bias32(5, i);
    end
  endtask

  task automatic push_model_to_dut;
    int i;
    begin
      for (i = 0; i < IN_SIZE; i++) load_cfg8(4'd0, i, in_mem[i]);
    end
  endtask

  task automatic fill_pattern_case;
    int i;
    begin
      clear_model();
      for (i = 0; i < IN_SIZE; i++) in_mem[i] = (i % 11) - 5;
    end
  endtask

  task automatic fill_random_case(input int signedness_scale);
    int i;
    logic [31:0] rnd;
    begin
      clear_model();
      for (i = 0; i < IN_SIZE; i++) begin
        prng_next(rnd);
        in_mem[i] = $signed(rnd[7:0]) >>> signedness_scale;
      end
    end
  endtask

  task automatic fill_saturation_case;
    int i;
    begin
      clear_model();
      for (i = 0; i < IN_SIZE; i++) in_mem[i] = 8'sd127;
    end
  endtask

  task automatic run_reference;
    int o_c, o_h, o_w, i_c, k_h, k_w, out_i, in_i;
    logic signed [ACC_W-1:0] acc;
    begin
      for (o_c = 0; o_c < C1_OUT; o_c++) begin
        for (o_h = 0; o_h < C1_H; o_h++) begin
          for (o_w = 0; o_w < C1_W; o_w++) begin
            acc = b1_mem[o_c];
            for (i_c = 0; i_c < C_IN; i_c++) begin
              for (k_h = 0; k_h < K1; k_h++) begin
                for (k_w = 0; k_w < K1; k_w++) begin
                  acc = sat_add_acc(acc, mul_ext(in_mem[idx_in(i_c, o_h + k_h, o_w + k_w)], w1_mem[idx_w1(o_c, i_c, k_h, k_w)]));
                end
              end
            end
            ref_act1[idx_c1(o_c, o_h, o_w)] = quant_act(acc, SHIFT_CONV1, 1'b1);
          end
        end
      end

      for (o_c = 0; o_c < C1_OUT; o_c++) begin
        for (o_h = 0; o_h < P1_H; o_h++) begin
          for (o_w = 0; o_w < P1_W; o_w++) begin
            ref_pool1[idx_p1(o_c, o_h, o_w)] = max4(
              ref_act1[idx_c1(o_c, (o_h*POOL)+0, (o_w*POOL)+0)],
              ref_act1[idx_c1(o_c, (o_h*POOL)+0, (o_w*POOL)+1)],
              ref_act1[idx_c1(o_c, (o_h*POOL)+1, (o_w*POOL)+0)],
              ref_act1[idx_c1(o_c, (o_h*POOL)+1, (o_w*POOL)+1)]
            );
          end
        end
      end

      for (o_c = 0; o_c < C2_OUT; o_c++) begin
        for (o_h = 0; o_h < C2_H; o_h++) begin
          for (o_w = 0; o_w < C2_W; o_w++) begin
            acc = b2_mem[o_c];
            for (i_c = 0; i_c < C1_OUT; i_c++) begin
              for (k_h = 0; k_h < K2; k_h++) begin
                for (k_w = 0; k_w < K2; k_w++) begin
                  acc = sat_add_acc(acc, mul_ext(ref_pool1[idx_p1(i_c, o_h + k_h, o_w + k_w)], w2_mem[idx_w2(o_c, i_c, k_h, k_w)]));
                end
              end
            end
            ref_act2[idx_c2(o_c, o_h, o_w)] = quant_act(acc, SHIFT_CONV2, 1'b1);
          end
        end
      end

      for (o_c = 0; o_c < C2_OUT; o_c++) begin
        for (o_h = 0; o_h < P2_H; o_h++) begin
          for (o_w = 0; o_w < P2_W; o_w++) begin
            ref_pool2[idx_p2(o_c, o_h, o_w)] = max4(
              ref_act2[idx_c2(o_c, (o_h*POOL)+0, (o_w*POOL)+0)],
              ref_act2[idx_c2(o_c, (o_h*POOL)+0, (o_w*POOL)+1)],
              ref_act2[idx_c2(o_c, (o_h*POOL)+1, (o_w*POOL)+0)],
              ref_act2[idx_c2(o_c, (o_h*POOL)+1, (o_w*POOL)+1)]
            );
          end
        end
      end

      for (out_i = 0; out_i < FC1_OUT; out_i++) begin
        acc = b3_mem[out_i];
        for (in_i = 0; in_i < FLAT_SIZE; in_i++) begin
          acc = sat_add_acc(acc, mul_ext(ref_pool2[in_i], w3_mem[idx_w3(out_i, in_i)]));
        end
        ref_fc1[out_i] = quant_act(acc, SHIFT_FC1, 1'b1);
      end

      for (out_i = 0; out_i < FC2_OUT; out_i++) begin
        acc = b4_mem[out_i];
        for (in_i = 0; in_i < FC1_OUT; in_i++) begin
          acc = sat_add_acc(acc, mul_ext(ref_fc1[in_i], w4_mem[idx_w4(out_i, in_i)]));
        end
        ref_fc2[out_i] = quant_act(acc, SHIFT_FC2, 1'b1);
      end

      for (out_i = 0; out_i < FC3_OUT; out_i++) begin
        acc = b5_mem[out_i];
        for (in_i = 0; in_i < FC2_OUT; in_i++) begin
          acc = sat_add_acc(acc, mul_ext(ref_fc2[in_i], w5_mem[idx_w5(out_i, in_i)]));
        end
        ref_fc3[out_i] = acc;
      end

      exp_logit0 = ref_fc3[0];
      exp_logit1 = ref_fc3[1];
      exp_class  = (ref_fc3[1] > ref_fc3[0]);
    end
  endtask

  task automatic fail(input string msg);
    begin
      fail_count = fail_count + 1;
      $display("[FAIL] %s", msg);
    end
  endtask

  task automatic run_and_check(input string test_name, input bit pulse_start_while_busy);
    int wait_cycles;
    begin
      test_count = test_count + 1;
      run_reference();

      @(posedge clk);
      start <= 1'b1;
      @(posedge clk);
      start <= 1'b0;

      if (pulse_start_while_busy) begin
        repeat (8) @(posedge clk);
        start <= 1'b1;
        @(posedge clk);
        start <= 1'b0;
      end

      wait_cycles = 0;
      while (!done && wait_cycles < 40000) begin
        @(posedge clk);
        wait_cycles = wait_cycles + 1;
      end

      if (!done) begin
        fail($sformatf("%s timeout waiting for done", test_name));
      end else begin
        if (logit0 !== exp_logit0) fail($sformatf("%s logit0 mismatch got=%0d exp=%0d", test_name, logit0, exp_logit0));
        if (logit1 !== exp_logit1) fail($sformatf("%s logit1 mismatch got=%0d exp=%0d", test_name, logit1, exp_logit1));
        if (class_id !== exp_class) fail($sformatf("%s class mismatch got=%0d exp=%0d", test_name, class_id, exp_class));
      end

      @(posedge clk);
    end
  endtask

  initial begin
    clk = 1'b0;
    forever #5 clk = ~clk;
  end

  always_ff @(posedge clk) begin
    if (!rst_n) cycle_count <= 0;
    else cycle_count <= cycle_count + 1;
  end

  initial begin
    int i;
    logic [31:0] rnd;

    test_count = 0;
    fail_count = 0;

    rst_n = 1'b0;
    start = 1'b0;
    cfg_we8 = 1'b0;
    cfg_bank8 = '0;
    cfg_addr8 = '0;
    cfg_data8 = '0;
    cfg_we32 = 1'b0;
    cfg_bank32 = '0;
    cfg_addr32 = '0;
    cfg_data32 = '0;
    prng_state = 32'hC001_CAFE;

    repeat (5) @(posedge clk);
    rst_n = 1'b1;
    @(posedge clk);
    init_static_params();

    // Case 1: all zeros
    clear_model();
    push_model_to_dut();
    run_and_check("full_zero", 1'b0);

    // Case 2: deterministic pattern
    fill_pattern_case();
    push_model_to_dut();
    run_and_check("full_pattern", 1'b1);

    // Case 3: runtime weight/bias writes must not affect static demo parameters
    for (i = 0; i < 32; i++) begin
      load_cfg8(4'd1, i, 8'sd127);
      load_cfg8(4'd2, i, -8'sd128);
    end
    for (i = 0; i < 8; i++) begin
      load_cfg32(4'd0, i, 32'sh7FFF_FFFF);
      load_cfg32(4'd4, i, -32'sh7FFF_FFFF);
    end
    run_and_check("full_static_weights_immutable", 1'b0);

    // Case 4: saturation-heavy input
    fill_saturation_case();
    push_model_to_dut();
    run_and_check("full_saturation", 1'b0);

    // Case 5: reset mid-compute and recover
    fill_random_case(2);
    push_model_to_dut();
    test_count = test_count + 1;

    @(posedge clk);
    start <= 1'b1;
    @(posedge clk);
    start <= 1'b0;
    repeat (40) @(posedge clk);
    rst_n <= 1'b0;
    repeat (3) @(posedge clk);
    rst_n <= 1'b1;
    @(posedge clk);
    if (busy !== 1'b0) fail("reset_mid_compute: busy should clear after reset");
    run_and_check("full_post_reset", 1'b0);

    // Case 6: randomized input regressions (weights/bias remain static)
    for (i = 0; i < 30; i++) begin
      prng_next(rnd);
      fill_random_case((rnd[1:0] + 1));
      push_model_to_dut();
      run_and_check($sformatf("full_rand_%0d", i), (i % 4 == 0));
    end

    $display("[INFO] cnn_full_pipeline_tb complete: tests=%0d failures=%0d", test_count, fail_count);
    if (fail_count != 0) begin
      $fatal(1, "cnn_full_pipeline_tb FAILED with %0d failures", fail_count);
    end else begin
      $display("[PASS] cnn_full_pipeline_tb passed all checks.");
    end

    $finish;
  end

endmodule
