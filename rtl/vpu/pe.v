`timescale 1ns / 1ps

//==============================================================================
// pe.v
//
// Systolic array processing element
// INT8 inputs, INT32 accumulator
// A flows right, B flows down, one cycle register delay each hop
// clr resets accumulator before new matrix operation
//==============================================================================

module pe (
    input  wire        clk,
    input  wire        resetn,
    input  wire        clr,

    input  wire signed [7:0]  a_in,
    input  wire signed [7:0]  b_in,
    input  wire               valid_in,

    output reg  signed [7:0]  a_out,
    output reg  signed [7:0]  b_out,
    output reg                valid_out,

    output reg  signed [31:0] mac_out
);
    always @(posedge clk) begin
        if (!resetn || clr) begin
            a_out     <= 0;
            b_out     <= 0;
            valid_out <= 0;
            mac_out   <= 0;
        end else begin
            a_out     <= a_in;
            b_out     <= b_in;
            valid_out <= valid_in;

            if (valid_in)
                mac_out <= mac_out + (a_in * b_in);
        end
    end
endmodule