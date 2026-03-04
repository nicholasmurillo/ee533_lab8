`timescale 1ns / 1ps
// Datapath module

`include "defines.v"

module datapath (
    input  wire                     clk,
    input  wire                     rst_n,

    // Instruction memory interface
    input  wire [`INSTR_WIDTH-1:0] i_mem_data_in,
    output wire [`PC_WIDTH-1:0]          i_mem_addr_out,

    // Data memory interface
    input  wire [`DATA_WIDTH-1:0]        d_mem_data_in,
    output wire [`D_MEM_ADDR_WIDTH-1:0]  d_mem_addr_out,
    output wire [`DATA_WIDTH-1:0]        d_mem_data_out,
    output wire                          d_mem_wen_out,
		output wire 												 cpu_done
);

    // ============================================================
    // 5-Stage Pipeline Signals
    // ============================================================

    // IF (Instruction Fetch)
	 wire [`PC_WIDTH-1:0] current_pc;
	 wire [`PC_WIDTH-1:0] pc_thread[3:0];
	 wire [3:0] pc_en_thread;
	 reg [1:0] thread_sel;
	 wire [3:0] pc_load_thread;
	 reg [3:0] thread_done;
	 integer t;
	 wire [1:0] thread_id_if; // Thread ID pipeline tracking
	 wire [`PC_WIDTH-1:0] pc_fetch;
	 wire [`INSTR_WIDTH-1:0] instr_if;
	 wire pc_en;
	 wire [`PC_WIDTH-1:0] br_target;
	 assign pc_en = 1'b1; // update pc every clock

    // ID (Decode)
	 wire [`PC_WIDTH-1:0] pc_id;
	 wire [`INSTR_WIDTH-1:0] instr_id;
	 wire [1:0] thread_id_id;
	 wire is_noop;
	 wire [1:0] major_op;
	 reg wregen_id;
	 reg wmemen_id;
	 reg mem_to_reg_id;
	 reg br_en_id;
	 reg [1:0] cond_id;
	 reg [3:0] alu_op_id;
	 reg alu_src_id;
	 reg [`DATA_WIDTH-1:0] imm_id;
	 reg [`REG_ADDR_WIDTH-1:0] wreg1_id;
	 reg [`REG_ADDR_WIDTH-1:0] reg1_id;
	 reg [`REG_ADDR_WIDTH-1:0] reg2_id;
	 wire [2+`REG_ADDR_WIDTH-1:0] rf_addr_rs1;
	 wire [2+`REG_ADDR_WIDTH-1:0] rf_addr_rs2;
	 wire [2+`REG_ADDR_WIDTH-1:0] rf_addr_wb;

    // EX (Execute)
	 wire [`PC_WIDTH-1:0] pc_ex;
	 wire br_taken_ex;
	 wire [1:0] thread_id_ex;
	 wire wregen_ex;
	 wire wmemen_ex;
	 wire mem_to_reg_ex;
	 wire br_en_ex;
	 wire [1:0] cond_ex;
	 wire [3:0] alu_op_ex;
	 wire alu_src_ex;
	 wire [`DATA_WIDTH-1:0] imm_ex;
	 wire [`REG_ADDR_WIDTH-1:0] wreg1_ex;
	 wire [`DATA_WIDTH-1:0] r1out_ex;
	 wire [`DATA_WIDTH-1:0] r2out_ex;
	 wire [`DATA_WIDTH-1:0] r0data_thread [3:0];
	 wire [`DATA_WIDTH-1:0] r1data_thread [3:0];
	 wire [`DATA_WIDTH-1:0] alu_operand_b;
	 wire [`DATA_WIDTH-1:0] alu_result_ex;

    // MEM (Memory)
	 wire [1:0] thread_id_mem;
	 wire wregen_mem;
	 wire wmemen_mem;
	 wire mem_to_reg_mem;
	 wire [`DATA_WIDTH-1:0] imm_mem;
	 wire [`REG_ADDR_WIDTH-1:0] wreg1_mem;
	 wire [`DATA_WIDTH-1:0] r1out_mem;
	 wire [`DATA_WIDTH-1:0] r2out_mem;
	 //wire [`DATA_WIDTH-1:0] d_mem_data_mem;
	 wire [`DATA_WIDTH-1:0] alu_result_mem;


    // WB (Write Back)
	 wire [1:0] thread_id_wb;
	 wire wregen_wb;
	 wire mem_to_reg_wb;
	 wire [`DATA_WIDTH-1:0] imm_wb;
	 wire [`REG_ADDR_WIDTH-1:0] wreg1_wb;
	 wire [`DATA_WIDTH-1:0] d_mem_data_wb;
	 wire [`DATA_WIDTH-1:0] alu_result_wb;
	 wire [`DATA_WIDTH-1:0] write_data;

	 // ============================================================
    // 5-Stage Pipeline Logic
    // ============================================================

    // IF (Instruction Fetch)
	 assign br_target = pc_ex + imm_ex[`PC_WIDTH-1:0];
	 assign pc_load_thread[0] = (br_taken_ex && thread_id_ex == 2'b00);
	 assign pc_load_thread[1] = (br_taken_ex && thread_id_ex == 2'b01);
	 assign pc_load_thread[2] = (br_taken_ex && thread_id_ex == 2'b10);
	 assign pc_load_thread[3] = (br_taken_ex && thread_id_ex == 2'b11);
	 
	 // Round-robin thread scheduler
	 always @(posedge clk or negedge rst_n) begin
		if (!rst_n)
			thread_sel <= 2'b00;
		else
			thread_sel <= thread_sel + 1'b1;
		end
		
	 always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        thread_done <= 4'b0000;
    else begin
		  // End program instruction
        if (!thread_done[thread_id_id] &&
            instr_id == 32'hC0100000)
            thread_done[thread_id_id] <= 1'b1;

        // PC ran off its region
        for (t = 0; t < 4; t = t + 1) begin
            if (!thread_done[t] &&
                pc_thread[t] >= ((t+1)*`I_MEM_BLOCK - 1))
                thread_done[t] <= 1'b1;
				end
		  end
	 end
		
	 assign thread_id_if = thread_sel;
	 assign current_pc = pc_thread[thread_sel];
	 assign pc_en_thread[0] = (thread_sel == 2'b00) && !thread_done[0];
	 assign pc_en_thread[1] = (thread_sel == 2'b01) && !thread_done[1];
	 assign pc_en_thread[2] = (thread_sel == 2'b10) && !thread_done[2];
	 assign pc_en_thread[3] = (thread_sel == 2'b11) && !thread_done[3];
	 
	 genvar i;
	 generate
    for (i = 0; i < 4; i = i + 1) begin : PC_ARRAY
        prog_counter #(
			.INITIAL_PC(i * `I_MEM_BLOCK)
		  ) u_prog_counter (
			.clk(clk),
			.rst_n(rst_n),
			.en(pc_en_thread[i]),
			.load(pc_load_thread[i]),
			.load_data(br_target),
			.pc_out(pc_thread[i])
		  );
    end
	 endgenerate
	 
	 assign pc_fetch = current_pc;
	 assign i_mem_addr_out = pc_fetch;
	 
	 pipeline_reg #(.REGS(2+`PC_WIDTH)) if_id_stage (
		.clk(clk),
		.rst_n(rst_n),
		.en(1'b1),
		.D({thread_id_if, pc_fetch}),
		.Q({thread_id_id, pc_id})
	 );

    // ID (Decode)
	 assign instr_id = (thread_done[thread_id_id]) ? `INSTR_WIDTH'b0 : i_mem_data_in;
	 // assign instr_id = i_mem_data_in;
	 assign major_op = instr_id[31:30];	// ALU: 00, LW: 01, SW: 10, 11 Branch
	 assign is_noop = instr_id[29];
	 always @(*) begin
		wmemen_id = 1'b0;
		wregen_id = 1'b0;
		mem_to_reg_id = 1'b0;
		br_en_id = 1'b0;	 
		reg1_id = 4'b0;
		reg2_id = 4'b0;
		wreg1_id = 4'b0;
		cond_id = 2'b0;
		alu_op_id = 4'b0;
		alu_src_id = 1'b0;
		imm_id = 64'b0;

	 	if (is_noop) begin
			wmemen_id     = 1'b0;
			wregen_id     = 1'b0;
			mem_to_reg_id = 1'b0;
			br_en_id      = 1'b0;
			reg1_id       = 4'b0;
			reg2_id       = 4'b0;
			wreg1_id      = 4'b0;
			cond_id       = 2'b0;
			alu_op_id     = 4'b0;
			alu_src_id    = 1'b0;
			imm_id        = 64'b0;
		end
		else begin
			case(major_op)
				2'b00:	begin	//R-type and I-type
					wregen_id = 1'b1;
					reg1_id = instr_id[28:25];
					reg2_id = instr_id[24:21];
					wreg1_id = instr_id[20:17];
					alu_op_id = instr_id[16:13];
					alu_src_id = instr_id[12];
					imm_id = {{(64-12){instr_id[11]}}, instr_id[11:0]};
				end
				2'b01: begin	//LW
					wregen_id = 1'b1;	//regWrite
					mem_to_reg_id = 1'b1;
					reg1_id = instr_id[28:25];
					wreg1_id = instr_id[24:21];
					alu_op_id = 4'b0;	// Force add
					alu_src_id = 1'b1;	// Force use offset
					imm_id = {{(64-21){instr_id[20]}}, instr_id[20:0]};
				end
				2'b10: begin	//SW
					wmemen_id = 1'b1;	//memWrite
					reg1_id = instr_id[28:25];
					reg2_id = instr_id[24:21];
					alu_op_id = 4'b0;	// Force add
					alu_src_id = 1'b1;	// Force use offset
					imm_id = {{(64-21){instr_id[20]}}, instr_id[20:0]};
				end
				2'b11: begin	//Branch
					br_en_id = 1'b1;
					reg1_id = instr_id[28:25];
					reg2_id = instr_id[24:21];
					cond_id = instr_id[20:19];
					alu_op_id = 4'b1001;	// eq opcode
					imm_id = {{(64-10){instr_id[9]}}, instr_id[9:0]};	//PC Width
				end
			endcase
		end
	 end

	 // REGFILE
	 assign rf_addr_rs1 = {thread_id_id, reg1_id};
	 assign rf_addr_rs2 = {thread_id_id, reg2_id};
	 assign rf_addr_wb  = {thread_id_wb, wreg1_wb};

	 regfile rf_rs1 (
		.clka(clk),
		.clkb(clk),

		.addra(rf_addr_rs1),   // read rs1
		.addrb(rf_addr_wb),    // writeback

		.dinb(write_data),

		.douta(r1out_ex),

		.web(wregen_wb)
	 );

	 regfile rf_rs2 (
		.clka(clk),
		.clkb(clk),

		.addra(rf_addr_rs2),   // read rs2
		.addrb(rf_addr_wb),    // writeback

		.dinb(write_data),

		.douta(r2out_ex),

		.web(wregen_wb)
	 );	 
	 
	 pipeline_reg #(.REGS(2+`PC_WIDTH+1+1+1+1+`REG_ADDR_WIDTH+2+4+1+`DATA_WIDTH)) id_ex_stage(
		.clk(clk),
		.rst_n(rst_n),
		.en(1'b1),
		.D({thread_id_id, pc_id, wregen_id, wmemen_id, mem_to_reg_id, br_en_id, wreg1_id, cond_id, alu_op_id, alu_src_id, imm_id}),
		.Q({thread_id_ex, pc_ex, wregen_ex, wmemen_ex, mem_to_reg_ex, br_en_ex, wreg1_ex, cond_ex, alu_op_ex, alu_src_ex, imm_ex})
	 );

    // EX (Execute)
	assign alu_operand_b = (!alu_src_ex) ? r2out_ex : imm_ex;

	alu u_alu (
		.A(r1out_ex),
		.B(alu_operand_b), 
		.op(alu_op_ex),
		.ALU_out(alu_result_ex)
	);

	assign br_taken_ex = (br_en_ex) && (((cond_ex == 2'b00) && alu_result_ex[0]) || 
						((cond_ex == 2'b01) && (!alu_result_ex[0])) || (cond_ex == 2'b10));

	 pipeline_reg #(.REGS(2+1+1+1+`DATA_WIDTH+`DATA_WIDTH+`REG_ADDR_WIDTH+`DATA_WIDTH+`DATA_WIDTH)) ex_mem_stage(
		.clk(clk),
		.rst_n(rst_n),
		.en(1'b1),
		.D({thread_id_ex, wregen_ex, wmemen_ex, mem_to_reg_ex, r1out_ex, r2out_ex, wreg1_ex, alu_result_ex, imm_ex}),
		.Q({thread_id_mem, wregen_mem, wmemen_mem, mem_to_reg_mem, r1out_mem, r2out_mem, wreg1_mem, alu_result_mem, imm_mem})
	 );

    // MEM (Memory)
	 assign d_mem_addr_out = {thread_id_mem, alu_result_mem[7:0]}; // For data memory size 256 per thread, change for larger
	 assign d_mem_data_out = r2out_mem;
	 assign d_mem_wen_out = wmemen_mem;
	// assign d_mem_data_mem = d_mem_data_in;
	 
	 pipeline_reg #(.REGS(2+1+1+`REG_ADDR_WIDTH+`DATA_WIDTH+`DATA_WIDTH)) mem_wb_stage(
		.clk(clk),
		.rst_n(rst_n),
		.en(1'b1),
		.D({thread_id_mem, wregen_mem, mem_to_reg_mem, wreg1_mem, alu_result_mem, imm_mem}),
		.Q({thread_id_wb, wregen_wb, mem_to_reg_wb, wreg1_wb, alu_result_wb, imm_wb})
	 );

    // WB (Write Back)
	 assign write_data = (mem_to_reg_wb) ? d_mem_data_in : alu_result_wb;
	 
	 // CPU Done Logic
	 // ============================================================

	 assign cpu_done = (thread_done == 4'b1111);

endmodule