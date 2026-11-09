`timescale 1ns/1ps

module vector_add_rtl_tb;

reg clk;
reg rst_n;
reg valid_in;
reg [31:0] a;
reg [31:0] b;
wire valid_out;
wire [31:0] c;

vector_add_rtl dut (
    .clk(clk),
    .rst_n(rst_n),
    .valid_in(valid_in),
    .a(a),
    .b(b),
    .valid_out(valid_out),
    .c(c)
);

always #5 clk = ~clk;

initial begin
    clk = 0;
    rst_n = 0;
    valid_in = 0;
    a = 0;
    b = 0;

    repeat (4) @(posedge clk);
    rst_n = 1;

    @(posedge clk);
    valid_in <= 1;
    a <= 32'd10;
    b <= 32'd20;

    @(posedge clk);
    valid_in <= 0;

    @(posedge clk);
    if (!valid_out || c != 32'd30) begin
        $display("FAIL: expected c=30, got c=%0d valid=%0d", c, valid_out);
        $fatal(1);
    end

    $display("PASS: vector_add_rtl_tb");
    $finish;
end

endmodule
