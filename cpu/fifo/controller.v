`timescale 1ns / 1ps

`include "defines.v"

module controller (
    //cpu inputs
    input [`D_MEM_ADDR_WIDTH-1:0]        cpu_d_addr,
    input [`DATA_WIDTH-1:0]              cpu_d_wdata,
    input                                cpu_d_we,

    //D_MEM i/o
    input [`DATA_WIDTH-1:0]              d_mem_dout,
    output reg                           d_mem_we,

    //fifo inputs
    input [`DATA_WIDTH-1:0]              fifo_cpu_rdata,
    input                                fifo_packet_ready,

    //Outputs
    output reg                           fifo_cpu_read,
    output reg                           fifo_cpu_write,
    output reg                           fifo_cpu_done,
    output reg [`FIFO_ADDR_WIDTH-1:0]    fifo_cpu_addr,
    output reg [`DATA_WIDTH-1:0]         fifo_cpu_wdata,

    output reg [`DATA_WIDTH-1:0]         ctrl_rdata_mux
);

// Decoded FIFO memory map
wire sel_fifo_data = (cpu_d_addr >= 10'h3E0) && (cpu_d_addr <= 10'h3EF);    //fifo memory location
wire sel_fifo_status = (cpu_d_addr == 10'h3F0);     //read packet ready
wire sel_fifo_done = (cpu_d_addr == 10'h3F1);       //set cpu done

always @(*) begin
    //defaults
    fifo_cpu_read = 0;
    fifo_cpu_write = 0;
    fifo_cpu_done = 0;
    fifo_cpu_addr = {`FIFO_ADDR_WIDTH{1'b0}};
    d_mem_we = cpu_d_we;
    ctrl_rdata_mux = d_mem_dout;
    
    //Control logic
    fifo_cpu_read = (sel_fifo_data && !cpu_d_we);
    fifo_cpu_write = (sel_fifo_data && cpu_d_we);
    fifo_cpu_done = (sel_fifo_done && cpu_d_we);
    fifo_cpu_addr = cpu_d_addr[3:0];
    fifo_cpu_wdata = cpu_d_wdata;

    // readback mux
    if (sel_fifo_data)
        ctrl_rdata_mux = fifo_cpu_rdata;
    else if (sel_fifo_status) 
        ctrl_rdata_mux = {63'b0, fifo_packet_ready};
    else 
        ctrl_rdata_mux = d_mem_dout;

    // Disable d_mem write enable 
    if (sel_fifo_data || sel_fifo_status || sel_fifo_done)
        d_mem_we = 1'b0;
    else
        d_mem_we = cpu_d_we;
end
endmodule