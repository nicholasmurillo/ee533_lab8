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
    output reg [DATA_WIDTH-1:0]         out_fifo,
    output reg                          valid_data,
    output reg                          fifo_full,
    output reg                          packet_ready,
    input                               cpu_done,
    input                               cpu_read,
    input                               cpu_write,
    input  [ADDR_WIDTH-1:0]             cpu_addr,
    input  [63:0]                       cpu_wdata,
    output reg [63:0]                   cpu_rdata
);

// State Machine parameters
localparam IDLE_S     = 2'd0;
localparam RECEIVE_S  = 2'd1;
localparam WAIT_CPU_S = 2'd2;
localparam SEND_S     = 2'd3;
reg [1:0] state, next_state;

// CPU access sub-states
localparam CPU_IDLE      = 2'd0;
localparam CPU_ADDR_SET  = 2'd1; 
localparam CPU_DATA_RDY  = 2'd2;  
localparam CPU_WRITE_COM = 2'd3; 
reg [1:0] cpu_state;

// pkt sm
localparam START_P   = 2'd0;
localparam HEADER_P  = 2'd1;
localparam PAYLOAD_P = 2'd2;

reg [1:0] pkt_state;
reg [2:0] header_count;
wire begin_pkt;
wire end_pkt;
wire [7:0] in_ctrl;
assign in_ctrl = in_fifo[DATA_WIDTH-1:DATA_WIDTH-8];

//=============== Signals ================== 

reg [ADDR_WIDTH-1:0] write_ptr;
reg [ADDR_WIDTH-1:0] send_ptr;
reg [ADDR_WIDTH-1:0] packet_start;
reg [ADDR_WIDTH-1:0] packet_end;

// Delayed
reg                  cpu_is_write;
reg [63:0]           cpu_wdata_d;
reg                  fifo_read_d;
reg                  cpu_done_pending;
// BRAM 
reg [0:0]               bram_we_a;
reg [ADDR_WIDTH-1:0]    bram_addr_a;
reg [DATA_WIDTH-1:0]    bram_din_a;
wire[DATA_WIDTH-1:0]    bram_dout_a;

reg [0:0]               bram_we_b;
reg [ADDR_WIDTH-1:0]    bram_addr_b;
reg [DATA_WIDTH-1:0]    bram_din_b;
wire[DATA_WIDTH-1:0]    bram_dout_b;

// Packet logic
assign begin_pkt = (pkt_state == START_P) && fifowrite && (in_ctrl != 0);
assign end_pkt = (pkt_state == PAYLOAD_P) && fifowrite && (in_ctrl != 0);

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
            if (begin_pkt)
                next_state = RECEIVE_S;
        end

        RECEIVE_S: begin
            if (end_pkt)
                next_state = WAIT_CPU_S;
        end

        WAIT_CPU_S: begin
            if (cpu_done_pending && (cpu_state == CPU_IDLE))
                next_state = SEND_S;
        end

        SEND_S: begin
            if (fifo_read_d && (send_ptr == packet_end + 8'd1))
                next_state = IDLE_S;
        end

        default: next_state = IDLE_S;
    endcase
end

// Main Logic
always @(posedge clk or posedge rst) begin
    if (rst) begin
        fifo_full <= 1'b0;
        packet_ready <= 1'b0;
        valid_data <= 1'b0;
        out_fifo <= {DATA_WIDTH{1'b0}};
        cpu_rdata <= 64'b0;

        write_ptr <= {ADDR_WIDTH{1'b0}};
        send_ptr <= {ADDR_WIDTH{1'b0}};
        packet_start <= {ADDR_WIDTH{1'b0}};
        packet_end <= {ADDR_WIDTH{1'b0}};

        bram_we_a <= 1'b0;
        bram_addr_a <= {ADDR_WIDTH{1'b0}};
        bram_din_a <= {DATA_WIDTH{1'b0}};
        bram_we_b <= 1'b0;
        bram_addr_b <= {ADDR_WIDTH{1'b0}};
        bram_din_b <= {DATA_WIDTH{1'b0}};

        cpu_is_write <= 1'b0;
        cpu_wdata_d <= 64'b0;
        cpu_state <= CPU_IDLE;
        fifo_read_d <= 1'b0;
        cpu_done_pending <= 1'b0;
        // Pkt
        pkt_state <= START_P;
        header_count <= 3'd0;

    end else begin
        bram_we_a <= 1'b0;
        valid_data <= 1'b0;

        // Packet parser
        if (fifowrite) begin
            case (pkt_state)
                START_P: begin
                    if (in_ctrl != 0) begin
                        pkt_state <= HEADER_P;
                        header_count <= 3'd0;
                    end
                end

                HEADER_P: begin
                    if (in_ctrl == 0) begin
                        header_count <= header_count + 1'b1;
                        if (header_count == 3'd2)
                            pkt_state <= PAYLOAD_P;
                    end
                end

                PAYLOAD_P: begin
                    if (in_ctrl != 0) begin
                        pkt_state <= START_P;
                        header_count <= 3'd0;
                    end
                end

                default: begin
                    pkt_state <= START_P;
                    header_count <= 3'd0;
                end
            endcase
        end

        // Main FSM
        case (state)
            IDLE_S: begin
                fifo_full <= 1'b0;
                packet_ready <= 1'b0;
                bram_addr_a <= write_ptr;
                bram_din_a <= in_fifo;

                if (fifowrite) begin
                    bram_we_a <= 1'b1;
                    bram_addr_a <= write_ptr;
                    bram_din_a <= in_fifo;

                    if (begin_pkt)
                        packet_start <= write_ptr;

                    if (end_pkt) begin
                        packet_end <= write_ptr;                         
                        fifo_full <= 1'b1;
                        packet_ready <= 1'b1;
                    end

                    if (write_ptr == {ADDR_WIDTH{1'b1}})
                        write_ptr <= {ADDR_WIDTH{1'b0}};
                    else
                        write_ptr <= write_ptr + 1'b1;
                end
            end

            RECEIVE_S: begin
                fifo_full    <= 1'b0;
                packet_ready <= 1'b0;

                if (fifowrite) begin
                    bram_we_a <= 1'b1;
                    bram_addr_a <= write_ptr;
                    bram_din_a <= in_fifo;

                    if (end_pkt) begin
                        packet_end <= write_ptr;
                        fifo_full <= 1'b1;
                        packet_ready <= 1'b1;
                    end

                    if (write_ptr == {ADDR_WIDTH{1'b1}})
                        write_ptr <= {ADDR_WIDTH{1'b0}};
                    else
                        write_ptr <= write_ptr + 1'b1;
                end
            end

            WAIT_CPU_S: begin
                fifo_full <= 1'b1;
                packet_ready <= 1'b1;
                bram_we_b <= 1'b0;

                // Latch cpu_done
                if (cpu_done)
                    cpu_done_pending <= 1'b1;

                case (cpu_state)
                    CPU_IDLE: begin
                        if (cpu_done_pending) begin
                            send_ptr <= packet_start + 8'd1;
                            bram_addr_b <= packet_start;
                            cpu_done_pending <= 1'b0;
                        end
                        if (cpu_read || cpu_write) begin
                            cpu_is_write <= cpu_write;
                            cpu_wdata_d <= cpu_wdata;
                            bram_addr_b <= packet_start + cpu_addr;
                            cpu_state <= CPU_ADDR_SET;
                        end
                    end

                    CPU_ADDR_SET: begin
                        cpu_state <= CPU_DATA_RDY;
                    end

                    CPU_DATA_RDY: begin
                        if (!cpu_is_write) begin
                            cpu_rdata <= bram_dout_b[63:0];
                            cpu_state <= CPU_IDLE;
                        end else begin
                            bram_din_b <= {bram_dout_b[71:64], cpu_wdata_d};
                            bram_we_b <= 1'b1;
                            cpu_state <= CPU_WRITE_COM;
                        end
                    end

                    CPU_WRITE_COM: begin
                        cpu_state <= CPU_IDLE;
                    end

                    default: cpu_state <= CPU_IDLE;
                endcase
            end
            
            SEND_S: begin
                bram_we_b <= 1'b0;
                fifo_full <= 1'b1;
                packet_ready <= 1'b0;
                valid_data <= 1'b0;

                if (fiforead && !fifo_read_d) begin
                    fifo_read_d <= 1'b1;
                    bram_addr_b <= send_ptr;
                end
                else if (fifo_read_d) begin
                    fifo_read_d <= 1'b0;
                    out_fifo <= bram_dout_b;
                    valid_data <= 1'b1;

                    if (send_ptr == packet_end + 8'd1)
                        fifo_full <= 1'b0;
                    else begin
                        if (send_ptr == {ADDR_WIDTH{1'b1}})
                            send_ptr <= {ADDR_WIDTH{1'b0}};
                        else
                            send_ptr <= send_ptr + 1'b1;
                    end
                end
            end

            default: begin
                fifo_full <= 1'b0;
                packet_ready <= 1'b0;
                valid_data <= 1'b0;
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