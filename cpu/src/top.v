`include "defines.v"

module top 
   #(
      parameter UDP_REG_SRC_WIDTH = 2
   )
   (
      // --- Register interface
      input                               reg_req_in,
      input                               reg_ack_in,
      input                               reg_rd_wr_L_in,
      input  [`UDP_REG_ADDR_WIDTH-1:0]    reg_addr_in,
      input  [`CPCI_NF2_DATA_WIDTH-1:0]   reg_data_in,
      input  [UDP_REG_SRC_WIDTH-1:0]      reg_src_in,

      output                              reg_req_out,
      output                              reg_ack_out,
      output                              reg_rd_wr_L_out,
      output  [`UDP_REG_ADDR_WIDTH-1:0]   reg_addr_out,
      output  [`CPCI_NF2_DATA_WIDTH-1:0]  reg_data_out,
      output  [UDP_REG_SRC_WIDTH-1:0]     reg_src_out,

      // misc
      input                                reset,
      input                                clk,

      // FIFO connections
      input wire [`DATA_WIDTH-1:0]        fifo_cpu_rdata,
      input wire                          fifo_packet_ready,
      output wire                         fifo_cpu_read,
      output wire                         fifo_cpu_write,
      output wire                         fifo_cpu_done,
      output wire [`FIFO_ADDR_WIDTH-1:0]  fifo_cpu_addr,
      output wire [`DATA_WIDTH-1:0]       fifo_cpu_wdata 
   );

   // Software registers
    wire [31:0] sw_req_cmd;         
    wire [31:0] sw_req_addr;        
    wire [31:0] sw_req_data_lo;     
    wire [31:0] sw_req_data_hi;     
    wire [31:0] sw_req_val;         
    wire [31:0] sw_resp_rdy;        
    wire [31:0] sw_cpu_start;       

    // Hardware registers
    reg [31:0] hw_req_rdy;                
    reg [31:0] hw_resp_data_lo;     
    reg [31:0] hw_resp_data_hi;     
    reg [31:0] hw_resp_val;         
   
    wire [63:0] req_data_64 = {sw_req_data_hi, sw_req_data_lo};

    wire                            cpu_req_rdy;
    wire [63:0]                     cpu_resp_data;   
    wire                            cpu_resp_val;

    cpu u_cpu (
        .clk              (clk),
        .rst_n            (~reset),                       

        // Request
        .req_cmd          (sw_req_cmd[0]),                
        .req_addr         (sw_req_addr),                  
        .req_data         (req_data_64),                  
        .req_val          (sw_req_val[0]),               
        .req_rdy          (cpu_req_rdy),

        // Response
        .resp_data        (cpu_resp_data),
        .resp_val         (cpu_resp_val),
        .resp_rdy         (sw_resp_rdy[0]),               

        // ---- CPU control ----
        .start            (sw_cpu_start[0]),
        
        // FIFO connections
        .fifo_cpu_rdata(fifo_cpu_rdata),
        .fifo_packet_ready(fifo_packet_ready),
        .fifo_cpu_read(fifo_cpu_read),
        .fifo_cpu_write(fifo_cpu_write),
        .fifo_cpu_done(fifo_cpu_done),
        .fifo_cpu_addr(fifo_cpu_addr),
        .fifo_cpu_wdata(fifo_cpu_wdata)
    );

    // Hardware Update

    always @(posedge clk) begin
        if (reset) begin
            hw_req_rdy        <= 32'b0;
            hw_resp_data_lo   <= 32'b0;
            hw_resp_data_hi   <= 32'b0;
            hw_resp_val       <= 32'b0;
        end
        else begin
            hw_req_rdy        <= {31'b0, cpu_req_rdy};
            hw_resp_val       <= {31'b0, cpu_resp_val};
            hw_resp_data_lo   <= cpu_resp_data[31:0];
            hw_resp_data_hi   <= cpu_resp_data[63:32];
        end
    end

    generic_regs
    #(
        .UDP_REG_SRC_WIDTH   (UDP_REG_SRC_WIDTH),
        .TAG                 (`TOP_BLOCK_ADDR),
        .REG_ADDR_WIDTH      (`TOP_REG_ADDR_WIDTH),
        .NUM_COUNTERS        (0),
        .NUM_SOFTWARE_REGS   (7),
        .NUM_HARDWARE_REGS   (4)
    ) module_regs (
        .reg_req_in        (reg_req_in),
        .reg_ack_in        (reg_ack_in),
        .reg_rd_wr_L_in    (reg_rd_wr_L_in),
        .reg_addr_in       (reg_addr_in),
        .reg_data_in       (reg_data_in),
        .reg_src_in        (reg_src_in),

        .reg_req_out       (reg_req_out),
        .reg_ack_out       (reg_ack_out),
        .reg_rd_wr_L_out   (reg_rd_wr_L_out),
        .reg_addr_out      (reg_addr_out),
        .reg_data_out      (reg_data_out),
        .reg_src_out       (reg_src_out),

        .counter_updates   (),
        .counter_decrement (),

        // Software Registers
        .software_regs     ({sw_cpu_start,        
                            sw_resp_rdy,          
                            sw_req_val,           
                            sw_req_data_hi,       
                            sw_req_data_lo,       
                            sw_req_addr,          
                            sw_req_cmd}),         

        // Hardware Registers
        .hardware_regs     ({hw_resp_val,         
                            hw_resp_data_hi,      
                            hw_resp_data_lo,         
                            hw_req_rdy}),         

        .clk               (clk),
        .reset             (reset)
    );

endmodule