`timescale 1ns / 1ps

module conv_fifo #(
    parameter ADDR_WIDTH = 8,
    parameter DATA_WIDTH = 72
)(
    input                               clk,
    input                               rst,
    input  [DATA_WIDTH-1:0]             in_fifo,
    input                               fifowrite,
    input                               fiforead,
    input                               firstword,
    input                               lastword,
    output reg [DATA_WIDTH-1:0]         out_fifo,
    output reg                          valid_data,
    output reg                          fifo_full,
    output reg                          packet_ready,
    input                               cpu_done,
    input                               cpu_read,
    input                               cpu_write,
    input  [ADDR_WIDTH-1:0]             cpu_addr,
    input  [DATA_WIDTH-1:0]             cpu_wdata,
    output reg [DATA_WIDTH-1:0]         cpu_rdata
);

// State Machine parameters
localparam IDLE_S     = 2'd0;
localparam RECEIVE_S  = 2'd1;
localparam WAIT_CPU_S = 2'd2;
localparam SEND_S     = 2'd3;

reg [1:0] state, next_state;

//=============== Signals ================== 
reg [ADDR_WIDTH-1:0] write_ptr;
reg [ADDR_WIDTH-1:0] send_ptr;
reg [ADDR_WIDTH-1:0] packet_start;
reg [ADDR_WIDTH-1:0] packet_end;
reg [ADDR_WIDTH-1:0] next_free_ptr;

// BRAM 
reg [0:0]               bram_we_a;
reg [ADDR_WIDTH-1:0]    bram_addr_a;
reg [DATA_WIDTH-1:0]    bram_din_a;
wire[DATA_WIDTH-1:0]    bram_dout_a;

reg [0:0]               bram_we_b;
reg [ADDR_WIDTH-1:0]    bram_addr_b;
reg [DATA_WIDTH-1:0]    bram_din_b;
wire[DATA_WIDTH-1:0]    bram_dout_b;

// State machine on reset
always @(posedge clk or posedge rst) begin
    if (rst)
        state <= IDLE_S;
    else
        state <= next_state;
end

// Next state logic
always @(*) begin
    next_state = state;

    case (state)
        IDLE_S: begin
            if (fifowrite && firstword && lastword)
                next_state <= WAIT_CPU_S;
            else if (fifowrite && firstword)
                next_state = RECEIVE_S;
        end

        RECEIVE_S: begin
            if (fifowrite && lastword)
                next_state = WAIT_CPU_S;
        end

        WAIT_CPU_S: begin
            if (cpu_done)
                next_state = SEND_S;
        end

        SEND_S: begin
            if (fiforead && (send_ptr == packet_end))
                next_state = IDLE_S;
        end

        default: next_state = IDLE_S;
    endcase
end

// Main Logic
always @(posedge clk or posedge rst) begin
    if (rst) begin
        fifo_full     <= 1'b0;
        packet_ready  <= 1'b0;
        valid_data    <= 1'b0;
        out_fifo      <= {DATA_WIDTH{1'b0}};
        cpu_rdata     <= {DATA_WIDTH{1'b0}};

        write_ptr     <= {ADDR_WIDTH{1'b0}};
        send_ptr      <= {ADDR_WIDTH{1'b0}};
        packet_start  <= {ADDR_WIDTH{1'b0}};
        packet_end    <= {ADDR_WIDTH{1'b0}};
        next_free_ptr <= {ADDR_WIDTH{1'b0}};

        bram_we_a     <= 1'b0;
        bram_addr_a   <= {ADDR_WIDTH{1'b0}};
        bram_din_a    <= {DATA_WIDTH{1'b0}};
        bram_we_b     <= 1'b0;
        bram_addr_b   <= {ADDR_WIDTH{1'b0}};
        bram_din_b    <= {DATA_WIDTH{1'b0}};
    end else begin
        bram_we_a   <= 1'b0;
        bram_we_b   <= 1'b0;
        valid_data  <= 1'b0;

        case (state)
            // Wait for first word
            IDLE_S: begin
                fifo_full    <= 1'b0;
                packet_ready <= 1'b0;

                bram_addr_a  <= write_ptr;
                bram_din_a   <= in_fifo;

                if (fifowrite && firstword) begin
                    packet_start <= write_ptr;

                    bram_we_a   <= 1'b1;
                    bram_addr_a <= write_ptr;
                    bram_din_a  <= in_fifo;

                    if (lastword) begin
                        packet_end <= write_ptr;
                        if (write_ptr == {ADDR_WIDTH{1'b1}})
                            next_free_ptr <= {ADDR_WIDTH{1'b0}};
                        else
                            next_free_ptr <= write_ptr + 1'b1;
                        send_ptr      <= write_ptr;
                        fifo_full     <= 1'b1;
                        packet_ready  <= 1'b1;
                    end

                    if (write_ptr == {ADDR_WIDTH{1'b1}})
                        write_ptr <= {ADDR_WIDTH{1'b0}};
                    else
                        write_ptr <= write_ptr + 1'b1;
                end
            end

            // Receive packets from NetFPGA
            RECEIVE_S: begin
                fifo_full    <= 1'b0;
                packet_ready <= 1'b0;

                if (fifowrite) begin
                    bram_we_a   <= 1'b1;
                    bram_addr_a <= write_ptr;
                    bram_din_a  <= in_fifo;

                    if (lastword) begin
                        packet_end <= write_ptr;
                        if (write_ptr == {ADDR_WIDTH{1'b1}})
                            next_free_ptr <= {ADDR_WIDTH{1'b0}};
                        else
                            next_free_ptr <= write_ptr + 1'b1;
                        send_ptr      <= packet_start;
                        fifo_full     <= 1'b1;
                        packet_ready  <= 1'b1;
                    end

                    if (write_ptr == {ADDR_WIDTH{1'b1}})
                        write_ptr <= {ADDR_WIDTH{1'b0}};
                    else
                        write_ptr <= write_ptr + 1'b1;
                end
            end

            // CPU accesses bram
            WAIT_CPU_S: begin
                fifo_full    <= 1'b1;
                packet_ready <= 1'b1;

                bram_addr_b <= cpu_addr;
                bram_din_b  <= cpu_wdata;

                if (cpu_write)
                    bram_we_b <= 1'b1;

                if (cpu_read)
                    cpu_rdata <= bram_dout_b;

                if (cpu_done)
                    send_ptr <= packet_start;
            end
            
            // Output processed packets
            SEND_S: begin
                fifo_full    <= 1'b1;
                packet_ready <= 1'b0;

                bram_addr_b <= send_ptr;

                if (fiforead) begin
                    out_fifo   <= bram_dout_b;
                    valid_data <= 1'b1;

                    if (send_ptr == packet_end) begin
                        fifo_full <= 1'b0;
                        write_ptr <= next_free_ptr;
                    end else begin
                        if (send_ptr == {ADDR_WIDTH{1'b1}})
                            send_ptr <= {ADDR_WIDTH{1'b0}};
                        else
                            send_ptr <= send_ptr + 1'b1;
                    end
                end
            end

            default: begin
                fifo_full    <= 1'b0;
                packet_ready <= 1'b0;
                valid_data   <= 1'b0;
            end
        endcase
    end
end

fifo_bram bram_i(
    .clka(clk),
    .dina(bram_din_a),
    .addra(bram_addr_a),
    .wea(bram_we_a),
    .douta(bram_dout_a),
    .clkb(clk),
    .dinb(bram_din_b),
    .addrb(bram_addr_b),
    .web(bram_we_b),
    .doutb(bram_dout_b)
);

endmodule