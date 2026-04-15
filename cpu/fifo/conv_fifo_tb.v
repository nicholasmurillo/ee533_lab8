`timescale 1ns / 1ps

module conv_fifo_tb;

    parameter ADDR_WIDTH = 8;
    parameter DATA_WIDTH = 72;

    reg                     clk;
    reg                     rst;
    reg  [DATA_WIDTH-1:0]   in_fifo;
    reg                     fifowrite;
    reg                     fiforead;
    wire [DATA_WIDTH-1:0]   out_fifo;
    wire                    valid_data;
    wire                    fifo_full;
    wire                    packet_ready;
    reg                     cpu_done;
    reg                     cpu_read;
    reg                     cpu_write;
    reg  [ADDR_WIDTH-1:0]   cpu_addr;
    reg  [63:0]             cpu_wdata;
    wire [63:0]             cpu_rdata;

    // DUT
    conv_fifo #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH)
    ) dut (
        .clk(clk),
        .rst(rst),
        .in_fifo(in_fifo),
        .fifowrite(fifowrite),
        .fiforead(fiforead),
        .out_fifo(out_fifo),
        .valid_data(valid_data),
        .fifo_full(fifo_full),
        .packet_ready(packet_ready),
        .cpu_done(cpu_done),
        .cpu_read(cpu_read),
        .cpu_write(cpu_write),
        .cpu_addr(cpu_addr),
        .cpu_wdata(cpu_wdata),
        .cpu_rdata(cpu_rdata)
    );

    // Clock
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // Tasks
    task send_word;
        input [7:0]  ctrl;
        input [63:0] data;
        begin
            @(posedge clk);
            in_fifo    <= {ctrl, data};
            fifowrite  <= 1'b1;
            @(posedge clk);
            fifowrite  <= 1'b0;
            in_fifo    <= 72'd0;
        end
    endtask

    task cpu_read_word;
        input [ADDR_WIDTH-1:0] addr;
        begin
            @(posedge clk);
            cpu_addr  <= addr;
            cpu_read  <= 1'b1;
            cpu_write <= 1'b0;

            @(posedge clk);             
            cpu_read  <= 1'b0;

            @(posedge clk);
            @(posedge clk);
            @(posedge clk);
            @(posedge clk);                     
            $display("[%0t] CPU READ  addr=%0d data=%h", $time, addr, cpu_rdata);
        end
    endtask

    task cpu_write_word;
        input [ADDR_WIDTH-1:0] addr;
        input [63:0] data;
        begin
            @(posedge clk);
            cpu_addr   <= addr;
            cpu_wdata  <= data;
            cpu_write  <= 1'b1;
            cpu_read   <= 1'b0;

            @(posedge clk);          
            cpu_write  <= 1'b0;

            @(posedge clk);
            @(posedge clk);
            @(posedge clk);
            @(posedge clk);                         
            $display("[%0t] CPU WRITE addr=%0d data=%h", $time, addr, data);
        end
    endtask

    task fifo_read_word;
        begin
            @(posedge clk);
            fiforead <= 1'b1;
            @(posedge clk);
            fiforead <= 1'b0;

            @(posedge valid_data);
            @(posedge clk);  
            $display("[%0t] FIFO OUT ctrl=%h data=%h", $time, out_fifo[71:64], out_fifo[63:0]);
        end
    endtask

    // Stimulus
    initial begin
        rst       = 1'b1;
        in_fifo   = 72'd0;
        fifowrite = 1'b0;
        fiforead  = 1'b0;
        cpu_done  = 1'b0;
        cpu_read  = 1'b0;
        cpu_write = 1'b0;
        cpu_addr  = {ADDR_WIDTH{1'b0}};
        cpu_wdata = 64'd0;

        repeat (3) @(posedge clk);
        rst = 1'b0;

        $display("\n=== Sending packet into FIFO ===");

        send_word(8'hFF, 64'h1111_1111_1111_1111); // start
        send_word(8'h00, 64'h2222_2222_2222_2222);
        send_word(8'h00, 64'h3333_3333_3333_3333);
        send_word(8'h00, 64'h4444_4444_4444_4444);
        send_word(8'hEE, 64'h5555_5555_5555_5555); // end

        wait(packet_ready == 1'b1);
        $display("[%0t] packet_ready asserted", $time);

        $display("\n=== CPU accesses packet in BRAM ===");

        cpu_read_word(8'd0);
        cpu_read_word(8'd1);
        cpu_read_word(8'd2);
        cpu_read_word(8'd3);
        cpu_read_word(8'd4);

        // Modify one word 
        cpu_write_word(8'd2, 64'hDEAD_BEEF_CAFE_1234);

        // Read back 
        cpu_read_word(8'd2);

        $display("\n=== CPU done, FIFO should send packet out ===");
        @(posedge clk);
        cpu_done <= 1'b1;
        @(posedge clk);
        cpu_done <= 1'b0;

        fifo_read_word();
        fifo_read_word();
        fifo_read_word();
        fifo_read_word();
        fifo_read_word();

        repeat (5) @(posedge clk);

        $display("\n=== Simulation done ===");
        $finish;
    end

endmodule