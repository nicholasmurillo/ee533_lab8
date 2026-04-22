`timescale 1ns / 1ps
`include "defines.v"

module top_sim_tb;
    reg clk;
    reg rst;

    initial clk = 0;
    always #5 clk = ~clk;

    // MMIO interface (PCI side)
    reg                          req_cmd;
    reg  [`MMIO_ADDR_WIDTH-1:0]  req_addr;
    reg  [`MMIO_DATA_WIDTH-1:0]  req_data;
    reg                          req_val;
    wire                         req_rdy;
    wire [`MMIO_DATA_WIDTH-1:0]  resp_data;
    wire                         resp_val;
    reg                          resp_rdy;
    reg                          start;

    // CPU FIFO interface
    wire [`DATA_WIDTH-1:0]       fifo_cpu_rdata;
    wire                         fifo_packet_ready;
    wire                         fifo_cpu_read;
    wire                         fifo_cpu_write;
    wire                         fifo_cpu_done;
    wire [`FIFO_ADDR_WIDTH-1:0]  fifo_cpu_addr;
    wire [`DATA_WIDTH-1:0]       fifo_cpu_wdata;

    // Network FIFO interface
    reg  [`FIFO_DATA_WIDTH-1:0]  in_fifo;
    reg                          fifowrite;
    reg                          fiforead;
    wire [`FIFO_DATA_WIDTH-1:0]  out_fifo;
    wire                         valid_data;
    wire                         fifo_full;

    // DUT
    top_sim dut (
        .clk(clk),
        .rst(rst),
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
        .fifo_cpu_wdata(fifo_cpu_wdata),
        .in_fifo(in_fifo),
        .fifowrite(fifowrite),
        .fiforead(fiforead),
        .out_fifo(out_fifo),
        .valid_data(valid_data),
        .fifo_full(fifo_full)
    );

    // Tasks

    // Send one 72-bit word into the FIFO from the network side
    task net_send_word;
        input [7:0]  ctrl;
        input [63:0] data;
        begin
            @(posedge clk);
            in_fifo   <= {ctrl, data};
            fifowrite <= 1'b1;
            @(posedge clk);
            fifowrite <= 1'b0;
            in_fifo   <= {`DATA_WIDTH{1'b0}};
        end
    endtask

    // Read one word out of the FIFO on the network side
    task net_read_word;
        begin
            @(posedge clk);
            fiforead <= 1'b1;
            @(posedge clk);
            fiforead <= 1'b0;
            @(posedge clk);
            @(posedge clk);
            $display("[%0t] NET READ  ctrl=%h data=%h",
                     $time, out_fifo[`DATA_WIDTH-1:`DATA_WIDTH-8], out_fifo[63:0]);
        end
    endtask

    // Issue one MMIO transaction
    task mmio_write;
        input [`MMIO_ADDR_WIDTH-1:0] addr;
        input [`MMIO_DATA_WIDTH-1:0] data;
        begin
            @(posedge clk);
            req_cmd  <= 1'b1;   // write
            req_addr <= addr;
            req_data <= data;
            req_val  <= 1'b1;

            // Wait for handshake
            wait(req_rdy == 1'b1);
            @(posedge clk);
            req_val <= 1'b0;

            // Wait for response
            wait(resp_val == 1'b1);
            @(posedge clk);
            resp_rdy <= 1'b1;
            @(posedge clk);
            resp_rdy <= 1'b0;
        end
    endtask

    task mmio_read;
        input  [`MMIO_ADDR_WIDTH-1:0] addr;
        output [`MMIO_DATA_WIDTH-1:0] rdata;
        begin
            @(posedge clk);
            req_cmd  <= 1'b0;   // read
            req_addr <= addr;
            req_data <= {`MMIO_DATA_WIDTH{1'b0}};
            req_val  <= 1'b1;

            wait(req_rdy == 1'b1);
            @(posedge clk);
            req_val <= 1'b0;

            wait(resp_val == 1'b1);
            rdata = resp_data;
            @(posedge clk);
            resp_rdy <= 1'b1;
            @(posedge clk);
            resp_rdy <= 1'b0;
        end
    endtask

    // Stimulus
    integer i;
    reg [`MMIO_DATA_WIDTH-1:0] rd;

    initial begin
        // Init
        rst      = 1'b1;
        req_cmd  = 1'b0;
        req_addr = {`MMIO_ADDR_WIDTH{1'b0}};
        req_data = {`MMIO_DATA_WIDTH{1'b0}};
        req_val  = 1'b0;
        resp_rdy = 1'b0;
        start    = 1'b0;
        in_fifo  = {`DATA_WIDTH{1'b0}};
        fifowrite = 1'b0;
        fiforead  = 1'b0;

        repeat(4) @(posedge clk);
        rst = 1'b0;
        repeat(2) @(posedge clk);

        // Send a packet in from the network side and
        // verify packet_ready asserts inside conv_fifo
        // CPU is not running yet so controller outputs are 0
        $display("\n=== Test 1: Network packet into FIFO ===");

        net_send_word(8'hFF, 64'h1111_1111_1111_1111); // SOP
        net_send_word(8'h00, 64'h2222_2222_2222_2222);
        net_send_word(8'h00, 64'h3333_3333_3333_3333);
        net_send_word(8'h00, 64'h4444_4444_4444_4444);
        net_send_word(8'hEE, 64'h5555_5555_5555_5555); // EOP

        wait(fifo_packet_ready == 1'b1);
        $display("[%0t] packet_ready asserted", $time);

        // Verify controller decoding when CPU is idle
        $display("\n=== Test 2: Controller idle check ===");
        $display("[%0t] fifo_cpu_read=%b fifo_cpu_write=%b fifo_cpu_done=%b",
                 $time,
                 fifo_cpu_read,
                 fifo_cpu_write,
                 fifo_cpu_done);
        
        // Write to IMEM thread 3 packet inspect assembly program
        $display("\n Load packet inspect assembly program");
        mmio_write(32'h3000_6000, 32'h00021001);
        mmio_write(32'h3000_6001, 32'h404003F0);
        mmio_write(32'h3000_6002, 32'h80200310);
        mmio_write(32'h3000_6003, 32'hC24FFFFE);
        mmio_write(32'h3000_6004, 32'h406003E4);
        mmio_write(32'h3000_6005, 32'h80600300);
        mmio_write(32'h3000_6006, 32'h0606100A);
        mmio_write(32'h3000_6007, 32'h806003E4);
        mmio_write(32'h3000_6008, 32'h802003F1);
        mmio_write(32'h3000_6009, 32'h82600301);

        $display("[%0t] MMIO write complete", $time);

        // Read back IMEM
        mmio_read(32'h3000_6000, rd);
        $display("[%0t] MMIO read back data=%h", $time, rd);
        mmio_read(32'h3000_6002, rd);
        $display("[%0t] MMIO read back data=%h", $time, rd);
        mmio_read(32'h3000_6003, rd);
        $display("[%0t] MMIO read back data=%h", $time, rd);
        mmio_read(32'h3000_6004, rd);
        $display("[%0t] MMIO read back data=%h", $time, rd);
        mmio_read(32'h3000_6005, rd);
        $display("[%0t] MMIO read back data=%h", $time, rd);
        mmio_read(32'h3000_6006, rd);
        $display("[%0t] MMIO read back data=%h", $time, rd);
        mmio_read(32'h3000_6007, rd);
        $display("[%0t] MMIO read back data=%h", $time, rd);
        mmio_read(32'h3000_6008, rd);
        $display("[%0t] MMIO read back data=%h", $time, rd);
        mmio_read(32'h3000_6009, rd);
        $display("[%0t] MMIO read back data=%h", $time, rd);

        // Start the CPU
        $display("\n=== Test 3: Start CPU ===");
        @(posedge clk);
        start <= 1'b1;
        @(posedge clk);
        start <= 1'b0;

        repeat(20) @(posedge clk);

        // Verify fifo_cpu_done causes SEND_S transition
        $display("\n=== Test 4: Check FIFO SEND_S ===");
        wait(fifo_packet_ready == 1'b0);
        $display("[%0t] FIFO in SEND_S", $time);

        // Read all 5 words from network side
        $display("\n=== Test 5: Read processed packet out ===");
        repeat(5) net_read_word();

        repeat(5) @(posedge clk);
        $display("\n=== Simulation done ===");
        $finish;
    end

    // prevents infinite hang
    initial begin
        #100000;
        $display("TIMEOUT — simulation exceeded 100us");
        $finish;
    end

endmodule