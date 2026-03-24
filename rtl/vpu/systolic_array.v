`timescale 1ns / 1ps

// systolic_array.v
// Vitis HLS 2025.2 project: riscv-soc VPU
//
// 8x8 output-stationary systolic array.
// A flows right, B flows down, 1-cycle register delay per hop.
// Inputs must be pre-skewed by the controller (wavefront pattern).
//
// v1: initial implementation - 2D array ports
// v2: ports flattened to packed buses for Verilog-2001 XSim compatibility
//     a_in_flat[r*8+:8]        = row r input
//     b_in_flat[c*8+:8]        = col c input
//     a_valid_flat[r]           = valid for row r
//     result_flat[(r*8+c)*32+:32] = result[r][c]

module systolic_array (
    input  wire        clk,
    input  wire        resetn,
    input  wire        clr,

    input  wire [63:0]   a_in_flat,
    input  wire [7:0]    a_valid_flat,
    input  wire [63:0]   b_in_flat,

    output wire [2047:0] result_flat
);
    wire signed [7:0] a_wire [0:7][0:8];
    wire signed [7:0] b_wire [0:8][0:7];
    wire              v_wire [0:7][0:8];

    genvar r, c;

    generate
        for (r = 0; r < 8; r = r + 1) begin : A_IN
            assign a_wire[r][0] = a_in_flat[r*8 +: 8];
            assign v_wire[r][0] = a_valid_flat[r];
        end
        for (c = 0; c < 8; c = c + 1) begin : B_IN
            assign b_wire[0][c] = b_in_flat[c*8 +: 8];
        end
    endgenerate

    generate
        for (r = 0; r < 8; r = r + 1) begin : ROW
            for (c = 0; c < 8; c = c + 1) begin : COL
                pe pe_inst (
                    .clk      (clk),
                    .resetn   (resetn),
                    .clr      (clr),
                    .a_in     (a_wire[r][c]),
                    .b_in     (b_wire[r][c]),
                    .valid_in (v_wire[r][c]),
                    .a_out    (a_wire[r][c+1]),
                    .b_out    (b_wire[r+1][c]),
                    .valid_out(v_wire[r][c+1])
                );
                assign result_flat[(r*8+c)*32 +: 32] = ROW[r].COL[c].pe_inst.mac_out;
            end
        end
    endgenerate

endmodule