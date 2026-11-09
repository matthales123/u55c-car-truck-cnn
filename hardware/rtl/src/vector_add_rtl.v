module vector_add_rtl #(
    parameter WIDTH = 32
) (
    input  wire                 clk,
    input  wire                 rst_n,
    input  wire                 valid_in,
    input  wire [WIDTH-1:0]     a,
    input  wire [WIDTH-1:0]     b,
    output reg                  valid_out,
    output reg  [WIDTH-1:0]     c
);

always @(posedge clk) begin
    if (!rst_n) begin
        valid_out <= 1'b0;
        c <= {WIDTH{1'b0}};
    end else begin
        valid_out <= valid_in;
        if (valid_in) begin
            c <= a + b;
        end
    end
end

endmodule
