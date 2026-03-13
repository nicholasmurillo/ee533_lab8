`timescale 1ns / 1ps
`include "defines.v"

module cpu (
    input  wire clk,
    input  wire rst_n,

    // ================= MMIO Request =================
    input  wire req_cmd,   // 0 = read, 1 = write
    input  wire [`MMIO_ADDR_WIDTH-1:0] req_addr,
    input  wire [`MMIO_DATA_WIDTH-1:0] req_data,
    input  wire req_val,
    output wire req_rdy,

    // ================= MMIO Response =================
    output wire [`MMIO_DATA_WIDTH-1:0] resp_data,
    output wire resp_val,
    input  wire resp_rdy,

    // External start
    input wire start,

    // FIFO connections
    input wire [`DATA_WIDTH-1:0]        fifo_cpu_rdata,
    input wire                          fifo_packet_ready,
    output wire                         fifo_cpu_read,
    output wire                         fifo_cpu_write,
    output wire                         fifo_cpu_done,
    output wire [`FIFO_ADDR_WIDTH-1:0]  fifo_cpu_addr,
    output wire [`DATA_WIDTH-1:0]       fifo_cpu_wdata
);

///////////////////////////////////////////////////////////////
// MMIO State Machine
///////////////////////////////////////////////////////////////

localparam S_IDLE   = 2'b00;
localparam S_ACCESS = 2'b01;
localparam S_RESP   = 2'b10;

reg [1:0] state_q, state_d;

///////////////////////////////////////////////////////////////
// MMIO Request Registers
///////////////////////////////////////////////////////////////

reg mmio_cmd_q;
reg [`MMIO_ADDR_WIDTH-1:0] mmio_addr_q;
reg [`MMIO_DATA_WIDTH-1:0] mmio_data_q;
reg [1:0] mmio_region_q;
reg [1:0] mmio_thread_q;

///////////////////////////////////////////////////////////////
// MMIO Response Registers
///////////////////////////////////////////////////////////////

reg mmio_resp_valid_q;
reg mmio_resp_cmd_q;
reg [`MMIO_ADDR_WIDTH-1:0] mmio_resp_addr_q;
reg [`MMIO_DATA_WIDTH-1:0] mmio_resp_data_q;
reg mmio_busy_q;

assign resp_val  = mmio_resp_valid_q;
assign resp_data = mmio_resp_data_q;

///////////////////////////////////////////////////////////////
// CPU Control
///////////////////////////////////////////////////////////////

reg  cpu_enable_q;
wire cpu_running;
wire cpu_done;

assign cpu_running = cpu_enable_q | start;
wire cpu_rst_n = rst_n & cpu_running;

///////////////////////////////////////////////////////////////
// MMIO Handshake / Decode
///////////////////////////////////////////////////////////////

wire mmio_handshake = req_val && req_rdy;
assign req_rdy = (state_q == S_IDLE) && !cpu_running;

wire [1:0] region_decode = req_addr[31:30];
wire [1:0] thread_decode = req_addr[29:28];

wire sel_i_mem = (mmio_region_q == `REGION_I_MEM);
wire sel_d_mem = (mmio_region_q == `REGION_D_MEM);
wire sel_ctrl  = (mmio_region_q == `REGION_CTRL);

wire mmio_active = (state_q == S_ACCESS) ||
                   (state_q == S_RESP);

///////////////////////////////////////////////////////////////
// CPU Start Control
///////////////////////////////////////////////////////////////

wire ctrl_start_event =
    (state_q == S_ACCESS) &&
    sel_ctrl &&
    mmio_cmd_q &&
    !cpu_running;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        cpu_enable_q <= 1'b0;
    else begin
        if (ctrl_start_event)
            cpu_enable_q <= 1'b1;
        else if (cpu_done)
            cpu_enable_q <= 1'b0;
    end
end

///////////////////////////////////////////////////////////////
// Instruction Memory Arbiter
///////////////////////////////////////////////////////////////

wire [`PC_WIDTH-1:0]    cpu_i_addr;
wire [`INSTR_WIDTH-1:0] i_mem_dout;

reg  [`PC_WIDTH-1:0]    i_mem_addr_mux;
reg  [`INSTR_WIDTH-1:0] i_mem_din_mux;
reg                     i_mem_we_mux;

always @(*) begin
    if (mmio_active && sel_i_mem) begin
        i_mem_addr_mux = mmio_addr_q[`PC_WIDTH-1:0];
        i_mem_din_mux  = mmio_data_q[`INSTR_WIDTH-1:0];
        i_mem_we_mux   = mmio_cmd_q && (state_q == S_ACCESS);
    end else begin
        i_mem_addr_mux = cpu_i_addr;
        i_mem_din_mux  = {`INSTR_WIDTH{1'b0}};
        i_mem_we_mux   = 1'b0;
    end
end

///////////////////////////////////////////////////////////////
// Data Memory Arbiter
///////////////////////////////////////////////////////////////

wire [`D_MEM_ADDR_WIDTH-1:0] cpu_d_addr;
wire [`DATA_WIDTH-1:0]       cpu_d_wdata;
wire                         cpu_d_we;
wire [`DATA_WIDTH-1:0]       d_mem_dout;
wire                         d_mem_we;
wire [`DATA_WIDTH-1:0]       ctrl_rdata_mux;

reg  [`D_MEM_ADDR_WIDTH-1:0] d_mem_addr_mux;
reg  [`DATA_WIDTH-1:0]       d_mem_din_mux;
reg                          d_mem_we_mux;

always @(*) begin
    if (mmio_active && sel_d_mem) begin
        d_mem_addr_mux = mmio_addr_q[`D_MEM_ADDR_WIDTH-1:0];
        d_mem_din_mux  = mmio_data_q;
        d_mem_we_mux   = mmio_cmd_q && (state_q == S_ACCESS);
    end else begin
        d_mem_addr_mux = cpu_d_addr;
        d_mem_din_mux  = cpu_d_wdata;
        d_mem_we_mux   = d_mem_we;
    end
end

///////////////////////////////////////////////////////////////
// MMIO FSM
///////////////////////////////////////////////////////////////

always @(*) begin
    state_d = state_q;
    case (state_q)
        S_IDLE:
            if (mmio_handshake)
                state_d = S_ACCESS;

        S_ACCESS:
            state_d = S_RESP;

        S_RESP:
            if (mmio_resp_valid_q && resp_rdy)
                state_d = S_IDLE;
    endcase
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state_q <= S_IDLE;
        mmio_busy_q <= 1'b0;
        mmio_resp_valid_q <= 1'b0;
    end else begin
        state_q <= state_d;

        if (mmio_handshake) begin
            mmio_cmd_q    <= req_cmd;
            mmio_addr_q   <= req_addr;
            mmio_data_q   <= req_data;
            mmio_region_q <= region_decode;
            mmio_thread_q <= thread_decode;
            mmio_busy_q   <= 1'b1;
            mmio_resp_valid_q <= 1'b0;
        end

        if (mmio_resp_valid_q && resp_rdy) begin
            mmio_resp_valid_q <= 1'b0;
            mmio_busy_q <= 1'b0;
        end

        if (state_q == S_RESP &&
            mmio_busy_q &&
            !mmio_resp_valid_q) begin

            mmio_resp_valid_q <= 1'b1;
            mmio_resp_cmd_q   <= mmio_cmd_q;
            mmio_resp_addr_q  <= mmio_addr_q;

            case (mmio_region_q)

                `REGION_I_MEM:
                    mmio_resp_data_q <=
                        {{(`MMIO_DATA_WIDTH-`INSTR_WIDTH){1'b0}},
                         i_mem_dout};

                `REGION_D_MEM:
                    mmio_resp_data_q <= d_mem_dout;

                `REGION_CTRL:
                    mmio_resp_data_q <=
                        {{(`MMIO_DATA_WIDTH-1){1'b0}},
                         cpu_running};

                default:
                    mmio_resp_data_q <= {`MMIO_DATA_WIDTH{1'b0}};

            endcase
        end
    end
end

datapath u_datapath (
    .clk(clk),
    .rst_n(cpu_rst_n),

    .i_mem_data_in(i_mem_dout),
    .i_mem_addr_out(cpu_i_addr),

    .d_mem_addr_out(cpu_d_addr),
    .d_mem_data_in(ctrl_rdata_mux),
    .d_mem_data_out(cpu_d_wdata),
    .d_mem_wen_out(cpu_d_we),

    .cpu_done(cpu_done)
);

controller u_controller (
    .cpu_d_addr(cpu_d_addr),
    .cpu_d_wdata(cpu_d_wdata),
    .cpu_d_we(cpu_d_we),
    .d_mem_dout(d_mem_dout),
    .d_mem_we(d_mem_we),
    .fifo_cpu_rdata(fifo_cpu_rdata),
    .fifo_packet_ready(fifo_packet_ready),
    .fifo_cpu_read(fifo_cpu_read),
    .fifo_cpu_write(fifo_cpu_write),
    .fifo_cpu_done(fifo_cpu_done),
    .fifo_cpu_addr(fifo_cpu_addr),
    .fifo_cpu_wdata(fifo_cpu_wdata),
    .ctrl_rdata_mux(ctrl_rdata_mux)
);

i_mem u_i_mem (
    .clk(clk),
    .din(i_mem_din_mux),
    .addr(i_mem_addr_mux),
    .we(i_mem_we_mux),
    .dout(i_mem_dout)
);

d_mem u_d_mem (
    .clka(clk),
    .dina(d_mem_din_mux),
    .addra(d_mem_addr_mux),
    .wea(d_mem_we_mux),
    .douta(d_mem_dout),

    .clkb(clk),
    .dinb({`DATA_WIDTH{1'b0}}),
    .addrb({`D_MEM_ADDR_WIDTH{1'b0}}),
    .web(1'b0),
    .doutb()
);

endmodule