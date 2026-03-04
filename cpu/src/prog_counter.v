`include "defines.v"

module prog_counter #(
    parameter INITIAL_PC = 0
)(
    input  wire clk,
    input  wire rst_n,
    input  wire en,
    input  wire load,
    input  wire [`PC_WIDTH-1:0] load_data,
    output reg  [`PC_WIDTH-1:0] pc_out
);

always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        pc_out <= INITIAL_PC;
    else if (load)
        pc_out <= load_data;
    else if (en)
        pc_out <= pc_out + 1;
end

endmodule