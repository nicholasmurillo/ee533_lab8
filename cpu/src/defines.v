// Defines & Constants
`define DATA_WIDTH 64
`define INSTR_WIDTH 32
`define D_MEM_ADDR_WIDTH 10
`define I_MEM_ADDR_WIDTH 11
`define PC_WIDTH 32
`define REG_ADDR_WIDTH 4
`define MMIO_ADDR_WIDTH 32
`define MMIO_DATA_WIDTH 64
`define REGION_I_MEM 2'b00
`define REGION_CTRL 2'b01
`define REGION_D_MEM 2'b10
`define I_MEM_SIZE (1 << `I_MEM_ADDR_WIDTH)
`define I_MEM_BLOCK (`I_MEM_SIZE / 4)
`define FIFO_ADDR_WIDTH 8