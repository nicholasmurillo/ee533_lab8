`timescale 1ns / 1ps
`include "defines.v"

module top_sim (
    input wire clk,
    input wire rst,

    // CPU PCI connections
    input                               req_cmd,
    input [`MMIO_ADDR_WIDTH-1:0]        req_addr,
    input [`MMIO_DATA_WIDTH-1:0]        req_data,
    input                               req_val,
    output                              req_rdy,
    output [`MMIO_DATA_WIDTH-1:0]       resp_data,
    output                              resp_val,
    input                               resp_rdy,
    input                               start,

    //FIFO to CPU
    output [`DATA_WIDTH-1:0]            fifo_cpu_rdata,
    output                              fifo_packet_ready,

    //CPU to FIFO
    output                              fifo_cpu_read,
    output                              fifo_cpu_write,
    output                              fifo_cpu_done,
    output [`FIFO_ADDR_WIDTH-1:0]       fifo_cpu_addr,
    output [`DATA_WIDTH-1:0]            fifo_cpu_wdata,

    //Network to FIFO input 
    input  [`FIFO_DATA_WIDTH-1:0]       in_fifo,
    input                               fifowrite,
    input                               fiforead,

    //FIFO out to Network
    output [`FIFO_DATA_WIDTH-1:0]       out_fifo,
    output                              valid_data,
    output                              fifo_full
);

cpu u_cpu (
    .clk(clk),
    .rst_n(~rst),
    .req_cmd(req_cmd),
    .req_addr(req_addr),
    .req_data(req_data),
    .req_val(req_val),
    .req_rdy(req_rdy),
    .resp_data(resp_data),
    .resp_val(resp_val),
    .resp_rdy(resp_rdy),
    .start(start),
    .fifo_cpu_rdata(fifo_cpu_rdata),
    .fifo_packet_ready(fifo_packet_ready),
    .fifo_cpu_read(fifo_cpu_read),
    .fifo_cpu_write(fifo_cpu_write),
    .fifo_cpu_done(fifo_cpu_done),
    .fifo_cpu_addr(fifo_cpu_addr),
    .fifo_cpu_wdata(fifo_cpu_wdata)
);

conv_fifo u_conv_fifo(
    .clk(clk),
    .rst(rst),
    .in_fifo(in_fifo),
    .fifowrite(fifowrite),
    .fiforead(fiforead),
    .out_fifo(out_fifo),
    .valid_data(valid_data),
    .fifo_full(fifo_full),
    .packet_ready(fifo_packet_ready),
    .cpu_done(fifo_cpu_done),
    .cpu_read(fifo_cpu_read),
    .cpu_write(fifo_cpu_write),
    .cpu_addr(fifo_cpu_addr),
    .cpu_wdata(fifo_cpu_wdata),
    .cpu_rdata(fifo_cpu_rdata)
);
endmodule

