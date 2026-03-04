// ALU 64-bit
// OPCODES: (0000 - 1001): 
// ADD, SUB, SLT, SLTU, BW_AND, BW_OR, BW_XNOR, SHIFT_L, SHIFT_R, EQ
`timescale 1ns/1ps

module alu (A, B, op, ALU_out);
    input [63:0] A;
    input [63:0] B;
    input [3:0] op;
    output [63:0] ALU_out;

    reg [63:0] ALU_next;
    reg [63:0] sub;
    reg borrow;
    reg sub_overflow;
    reg slt;
    reg sltu;

    always @(*) begin
        ALU_next = 64'b0;
        sub = 64'b0;
        borrow = 1'b0;
        sub_overflow = 1'b0;
        slt = 1'b0;
        sltu = 1'b0;

        // ALU OP select
        case (op)
            4'b0000: ALU_next = (A+B);   //Add

            // Subtract block
            4'b0001, 4'b0010, 4'b0011: begin 
                {borrow, sub} = ({1'b0, A} + {1'b0, ~B} + 1);
                sub_overflow = ((A[63] ^ B[63]) & (A[63] ^ sub[63]));
                slt = (sub_overflow ^ sub[63]);
                sltu = ~borrow;
                if (op == 4'b0001) ALU_next = sub;                 //Sub
                else if (op == 4'b0010) ALU_next = {63'b0, slt};   //signed slt
                else ALU_next = {63'b0, sltu};               //unsigned slt
            end

            4'b0100: ALU_next = (A & B);     //Bitwise AND
            4'b0101: ALU_next = (A | B);     //Bitwise OR
            4'b0110: ALU_next = ~(A ^ B);    //Bitwise XNOR
            4'b0111: ALU_next = A<<B[5:0];   //Left Shift
            4'b1000: ALU_next = A>>B[5:0];   //Right Shift
            4'b1001: ALU_next = {63'b0, (A == B)};  //Equal
            default: ALU_next = 64'b0;
        endcase            
    end

    assign ALU_out = ALU_next;
    
endmodule

