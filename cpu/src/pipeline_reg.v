`timescale 1ns / 1ps
// Pipeline register module
module pipeline_reg #(
    parameter REGS = 32
)(
    input  wire             clk,
    input  wire             rst_n,   // active-low reset
    input  wire             en,
    input  wire [REGS-1:0]  D,
    output reg  [REGS-1:0]  Q
);

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        Q <= 0;
    end
    else if (en) begin
        Q <= D;
    end
end

endmodule

