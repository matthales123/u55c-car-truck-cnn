`timescale 1ns/1ps

module cnn_full_pipeline_legacy_dataset_tb;

  localparam int DATA_W  = 8;
  localparam int ACC_W   = 32;
  localparam int C_IN    = 3;
  localparam int IN_H    = 32;
  localparam int IN_W    = 32;
  localparam int C1_OUT  = 6;
  localparam int K1      = 5;
  localparam int C2_OUT  = 16;
  localparam int K2      = 5;
  localparam int POOL    = 2;
  localparam int FC1_OUT = 120;
  localparam int FC2_OUT = 84;
  localparam int FC3_OUT = 2;

`include "../include/cnn_static_legacy_shifts.svh"

  localparam int SHIFT_CONV1 = LEGACY_TB_SHIFT_CONV1;
  localparam int SHIFT_CONV2 = LEGACY_TB_SHIFT_CONV2;
  localparam int SHIFT_FC1   = LEGACY_TB_SHIFT_FC1;
  localparam int SHIFT_FC2   = LEGACY_TB_SHIFT_FC2;

  localparam int CONV1_MACS_PER_CYCLE = 2;
  localparam int CONV2_MACS_PER_CYCLE = 2;
  localparam int FC1_MACS_PER_CYCLE   = 2;
  localparam int FC2_MACS_PER_CYCLE   = 2;
  localparam int FC3_MACS_PER_CYCLE   = 2;

  localparam int IMAGE_ELEMS = C_IN * IN_H * IN_W; // 3072
  localparam int MEM_SAMPLES = 100;
  localparam int RUN_SAMPLES = 20;

  localparam string DATA_MEM = "tb/data/cifar_test_q8_100.mem";
  localparam string PRED_MEM = "tb/data/cifar_test_hls_pred_100.mem";

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

  logic signed [DATA_W-1:0] sample_pixels [0:(MEM_SAMPLES*IMAGE_ELEMS)-1];
  logic [0:0] expected_pred [0:MEM_SAMPLES-1];

  int test_count;
  int fail_count;

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
    .STATIC_WEIGHT_PROFILE(1),
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

  task automatic load_sample_to_input(input int sample_idx);
    int j;
    begin
      for (j = 0; j < IMAGE_ELEMS; j++) begin
        @(posedge clk);
        cfg_we8   <= 1'b1;
        cfg_bank8 <= 4'd0;
        cfg_addr8 <= j;
        cfg_data8 <= sample_pixels[sample_idx * IMAGE_ELEMS + j];
      end
      @(posedge clk);
      cfg_we8   <= 1'b0;
      cfg_addr8 <= '0;
      cfg_data8 <= '0;
    end
  endtask

  task automatic run_one_sample(input int sample_idx);
    int wait_cycles;
    logic exp;
    begin
      exp = expected_pred[sample_idx][0];
      test_count = test_count + 1;

      load_sample_to_input(sample_idx);

      @(posedge clk);
      start <= 1'b1;
      @(posedge clk);
      start <= 1'b0;

      wait_cycles = 0;
      while (!done && wait_cycles < 2000000) begin
        @(posedge clk);
        wait_cycles = wait_cycles + 1;
      end

      if (!done) begin
        fail_count = fail_count + 1;
        $display("[FAIL] sample=%0d timeout waiting for done", sample_idx);
      end else if (class_id !== exp) begin
        fail_count = fail_count + 1;
        $display("[FAIL] sample=%0d class mismatch rtl=%0d hls=%0d logit0=%0d logit1=%0d",
                 sample_idx, class_id, exp, logit0, logit1);
      end else begin
        $display("[PASS] sample=%0d class=%0d cycles=%0d", sample_idx, class_id, wait_cycles);
      end

      @(posedge clk);
    end
  endtask

  initial begin
    clk = 1'b0;
    forever #5 clk = ~clk;
  end

  initial begin
    int i;

    $readmemh(DATA_MEM, sample_pixels);
    $readmemb(PRED_MEM, expected_pred);

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

    repeat (8) @(posedge clk);
    rst_n = 1'b1;
    @(posedge clk);

    for (i = 0; i < RUN_SAMPLES; i++) begin
      run_one_sample(i);
    end

    $display("[INFO] legacy dataset TB complete: tested=%0d failures=%0d", test_count, fail_count);
    if (fail_count != 0) begin
      $fatal(1, "cnn_full_pipeline_legacy_dataset_tb FAILED with %0d mismatches", fail_count);
    end else begin
      $display("[PASS] cnn_full_pipeline_legacy_dataset_tb passed.");
    end
    $finish;
  end

endmodule
