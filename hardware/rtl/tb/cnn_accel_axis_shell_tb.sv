`timescale 1ns/1ps

module cnn_accel_axis_shell_tb;
  localparam int ENGINE_COUNT = 4;
  localparam int WORK_ID_W = 16;
  localparam int ADDR_W = 64;
  localparam int COMPUTE_LATENCY = 11;
  localparam int WORK_ITEMS = 16;

  logic clk;
  logic rst_n;

  logic cmd_valid;
  logic cmd_ready;
  logic [WORK_ID_W-1:0] cmd_work_id;
  logic [ADDR_W-1:0] cmd_img_base_addr;
  logic cmd_mode_fast_strict;

  logic rsp_valid;
  logic rsp_ready;
  logic [WORK_ID_W-1:0] rsp_work_id;
  logic rsp_class_id;
  logic signed [31:0] rsp_logit0;
  logic signed [31:0] rsp_logit1;
  logic rsp_error;

  logic [31:0] issued_count;
  logic [31:0] completed_count;
  logic [31:0] inflight_count;
  logic [ENGINE_COUNT-1:0] engine_busy;

  logic [WORK_ITEMS-1:0] got_rsp;

  int recv_count;
  int timeout_cycles;
  int bp_counter;

  cnn_accel_axis_shell #(
    .ENGINE_COUNT(ENGINE_COUNT),
    .WORK_ID_W(WORK_ID_W),
    .ADDR_W(ADDR_W),
    .COMPUTE_LATENCY(COMPUTE_LATENCY),
    // Speed up simulation while preserving functional behavior.
    .CONV1_MACS_PER_CYCLE(75),
    .CONV2_MACS_PER_CYCLE(150),
    .FC1_MACS_PER_CYCLE(400),
    .FC2_MACS_PER_CYCLE(120),
    .FC3_MACS_PER_CYCLE(84)
  ) dut (
    .clk(clk),
    .rst_n(rst_n),
    .cmd_valid(cmd_valid),
    .cmd_ready(cmd_ready),
    .cmd_work_id(cmd_work_id),
    .cmd_img_base_addr(cmd_img_base_addr),
    .cmd_mode_fast_strict(cmd_mode_fast_strict),
    .rsp_valid(rsp_valid),
    .rsp_ready(rsp_ready),
    .rsp_work_id(rsp_work_id),
    .rsp_class_id(rsp_class_id),
    .rsp_logit0(rsp_logit0),
    .rsp_logit1(rsp_logit1),
    .rsp_error(rsp_error),
    .issued_count(issued_count),
    .completed_count(completed_count),
    .inflight_count(inflight_count),
    .engine_busy(engine_busy)
  );

  always #5 clk = ~clk;

  task automatic send_cmd(
    input logic [WORK_ID_W-1:0] work_id,
    input logic [ADDR_W-1:0] addr,
    input logic mode_fast
  );
    begin
      cmd_work_id <= work_id;
      cmd_img_base_addr <= addr;
      cmd_mode_fast_strict <= mode_fast;
      cmd_valid <= 1'b1;

      do begin
        @(posedge clk);
      end while (!cmd_ready);

      cmd_valid <= 1'b0;
      cmd_work_id <= '0;
      cmd_img_base_addr <= '0;
      cmd_mode_fast_strict <= 1'b0;
    end
  endtask

  initial begin
    clk = 1'b0;
    rst_n = 1'b0;
    cmd_valid = 1'b0;
    cmd_work_id = '0;
    cmd_img_base_addr = '0;
    cmd_mode_fast_strict = 1'b0;
    rsp_ready = 1'b0;
    got_rsp = '0;
    recv_count = 0;
    bp_counter = 0;

    repeat (6) @(posedge clk);
    rst_n = 1'b1;
    @(posedge clk);

    fork
      begin : p_backpressure
        forever begin
          @(posedge clk);
          // Deterministic but non-trivial backpressure pattern that cannot deadlock.
          bp_counter <= bp_counter + 1;
          rsp_ready <= ((bp_counter % 5) != 1);
        end
      end

      begin : p_recv
        int wid;
        forever begin
          @(posedge clk);
          if (rsp_valid && rsp_ready) begin
            wid = rsp_work_id;
            if (wid < 0 || wid >= WORK_ITEMS) begin
              $fatal(1, "Received invalid work_id=%0d", wid);
            end
            if (got_rsp[wid]) begin
              $fatal(1, "Duplicate response for work_id=%0d", wid);
            end

            if (rsp_error !== 1'b0) begin
              $fatal(1, "rsp_error asserted for work_id=%0d", wid);
            end
            if ($isunknown(rsp_logit0) || $isunknown(rsp_logit1) || $isunknown(rsp_class_id)) begin
              $fatal(1, "Unknown (X/Z) values in response for work_id=%0d", wid);
            end
            if (rsp_class_id !== (rsp_logit1 > rsp_logit0)) begin
              $fatal(1,
                     "class/logit mismatch for work_id=%0d: class=%0d logit0=%0d logit1=%0d",
                     wid, rsp_class_id, rsp_logit0, rsp_logit1);
            end

            got_rsp[wid] = 1'b1;
            recv_count = recv_count + 1;
          end
        end
      end
    join_none

    begin : p_send
      int i;
      logic [ADDR_W-1:0] addr;
      logic mode_fast;
      for (i = 0; i < WORK_ITEMS; i++) begin
        addr = 64'h1000_0000 + (i * 64'h40) + ((i % 7) << 20);
        mode_fast = i[0];
        send_cmd(i[WORK_ID_W-1:0], addr, mode_fast);
      end
    end

    timeout_cycles = 0;
    while (recv_count < WORK_ITEMS && timeout_cycles < 3000000) begin
      @(posedge clk);
      timeout_cycles = timeout_cycles + 1;
    end
    if (recv_count < WORK_ITEMS) begin
      $fatal(1, "Timeout waiting for responses. recv_count=%0d", recv_count);
    end

    disable p_backpressure;
    disable p_recv;

    repeat (20) @(posedge clk);

    if (issued_count != WORK_ITEMS) begin
      $fatal(1, "issued_count mismatch got=%0d exp=%0d", issued_count, WORK_ITEMS);
    end
    if (completed_count != WORK_ITEMS) begin
      $fatal(1, "completed_count mismatch got=%0d exp=%0d", completed_count, WORK_ITEMS);
    end
    if (inflight_count != 0) begin
      $fatal(1, "inflight_count mismatch got=%0d exp=0", inflight_count);
    end

    $display("PASS: cnn_accel_axis_shell_tb completed. issued=%0d completed=%0d", issued_count, completed_count);
    $finish;
  end

endmodule
