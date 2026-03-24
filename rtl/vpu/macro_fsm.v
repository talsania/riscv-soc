`timescale 1ns / 1ps

// macro_fsm.v
// Vitis HLS 2025.2 project: riscv-soc VPU
//
// High-level controller sequencing a full 8x8 matrix multiply.
//
// States:
//   IDLE   wait for start
//   CLR    one cycle clear pulse
//   FEED   16 cycles (0..15) - 15 diagonals + 1 extra so diagonal 14
//          data latches into PE[7][7] on the rising edge of cycle 15
//   DRAIN  8 cycles for last data to propagate to PE[7][7]
//   DONE   assert done one cycle, return to IDLE
//
// v1: initial implementation
// v2: feed cycles 0..15 (was 0..14) - diagonal 14 data was presented
//     but never latched because FSM zeroed outputs in the same cycle
//     ports flattened to packed buses for Verilog-2001 compatibility

module macro_fsm (
    input  wire        clk,
    input  wire        resetn,
    input  wire        start,

    input  wire [511:0] mat_a_flat,
    input  wire [511:0] mat_b_flat,

    output reg  [63:0] a_in_flat,
    output reg  [7:0]  a_valid_flat,
    output reg  [63:0] b_in_flat,

    output reg         clr,
    output reg         busy,
    output reg         done
);
    localparam IDLE  = 3'd0;
    localparam CLR   = 3'd1;
    localparam FEED  = 3'd2;
    localparam DRAIN = 3'd3;
    localparam DONE  = 3'd4;

    reg [2:0] state;
    reg [4:0] cycle_cnt;

    wire signed [7:0] mat_a [0:7][0:7];
    wire signed [7:0] mat_b [0:7][0:7];

    genvar gi, gj;
    generate
        for (gi = 0; gi < 8; gi = gi + 1)
            for (gj = 0; gj < 8; gj = gj + 1) begin : UNPACK
                assign mat_a[gi][gj] = mat_a_flat[(gi*8+gj)*8 +: 8];
                assign mat_b[gi][gj] = mat_b_flat[(gi*8+gj)*8 +: 8];
            end
    endgenerate

    integer r, c;

    always @(posedge clk) begin
        if (!resetn) begin
            state        <= IDLE;
            cycle_cnt    <= 0;
            clr          <= 0;
            busy         <= 0;
            done         <= 0;
            a_in_flat    <= 0;
            a_valid_flat <= 0;
            b_in_flat    <= 0;
        end else begin
            clr  <= 0;
            done <= 0;

            case (state)
                IDLE: begin
                    busy <= 0;
                    if (start) begin
                        busy      <= 1;
                        state     <= CLR;
                        cycle_cnt <= 0;
                    end
                end

                CLR: begin
                    clr   <= 1;
                    state <= FEED;
                end

                FEED: begin
                    for (r = 0; r < 8; r = r + 1) begin
                        if (cycle_cnt >= r && (cycle_cnt - r) < 8) begin
                            a_in_flat[r*8 +: 8] <= mat_a[r][cycle_cnt - r];
                            a_valid_flat[r]      <= 1;
                        end else begin
                            a_in_flat[r*8 +: 8] <= 0;
                            a_valid_flat[r]      <= 0;
                        end
                    end
                    for (c = 0; c < 8; c = c + 1) begin
                        if (cycle_cnt >= c && (cycle_cnt - c) < 8)
                            b_in_flat[c*8 +: 8] <= mat_b[cycle_cnt - c][c];
                        else
                            b_in_flat[c*8 +: 8] <= 0;
                    end

                    if (cycle_cnt == 15) begin
                        cycle_cnt    <= 0;
                        state        <= DRAIN;
                        a_in_flat    <= 0;
                        a_valid_flat <= 0;
                        b_in_flat    <= 0;
                    end else
                        cycle_cnt <= cycle_cnt + 1;
                end

                DRAIN: begin
                    a_in_flat    <= 0;
                    a_valid_flat <= 0;
                    b_in_flat    <= 0;
                    if (cycle_cnt == 7) begin
                        cycle_cnt <= 0;
                        state     <= DONE;
                    end else
                        cycle_cnt <= cycle_cnt + 1;
                end

                DONE: begin
                    done  <= 1;
                    busy  <= 0;
                    state <= IDLE;
                end

                default: state <= IDLE;
            endcase
        end
    end
endmodule