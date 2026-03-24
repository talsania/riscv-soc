`timescale 1ns / 1ps

//==============================================================================
// micro_fsm.v
//
// Low-level controller for the 8x8 systolic array.
// Implements the VLIW microinstruction set from the VPU spec.
// Drives datapath control signals one cycle per instruction.
//
// 32-bit microinstruction format:
//   [31:18]  one-hot control bits
//   [17:13]  clear flags
//   [12:0]   address or immediate
//
// One-hot opcode map:
//   31  LOAD_LEFT       serial load to left buffer
//   30  LOAD_TOP        serial load to top buffer
//   29  SWAP_LEFT       swap left double buffer
//   28  SWAP_TOP        swap top double buffer
//   27  SHIFT_RIGHT     shift systolic array right
//   26  SHIFT_DOWN      shift systolic array down
//   25  LOAD_ACC        load partial products into accumulator
//   24  WRITE_ACC_OUT   write accumulator to output memory
//   23  WAIT_CYCLES     stall for imm cycles
//   22  JUMP            jump to rom address
//   21  CLR             clear datapath per clear flags
//   20  NOP             do nothing
//
// Clear flags:
//   17  CLR_ACC         clear accumulators
//   16  CLR_SYSTOLIC    zero systolic array registers
//   15  CLR_LEFT_BUF    clear left buffer
//   14  CLR_TOP_BUF     clear top buffer
//   13  IMM_FLAG        1 = addr_imm is immediate, 0 = address
//
// v1: initial implementation
//==============================================================================

module micro_fsm (
    input  wire        clk,
    input  wire        resetn,
    input  wire [31:0] instruction,
    input  wire        execute,

    output reg         load_left,
    output reg         load_top,
    output reg         swap_left,
    output reg         swap_top,
    output reg         shift_right,
    output reg         shift_down,
    output reg         load_acc,
    output reg         write_acc_out,
    output reg         clr_acc,
    output reg         clr_systolic,
    output reg         clr_left_buf,
    output reg         clr_top_buf,
    output reg  [12:0] addr_imm,
    output reg         imm_flag,
    output reg         done
);
    always @(posedge clk) begin
        if (!resetn) begin
            load_left     <= 0;
            load_top      <= 0;
            swap_left     <= 0;
            swap_top      <= 0;
            shift_right   <= 0;
            shift_down    <= 0;
            load_acc      <= 0;
            write_acc_out <= 0;
            clr_acc       <= 0;
            clr_systolic  <= 0;
            clr_left_buf  <= 0;
            clr_top_buf   <= 0;
            addr_imm      <= 0;
            imm_flag      <= 0;
            done          <= 0;
        end else if (execute) begin
            load_left     <= instruction[31];
            load_top      <= instruction[30];
            swap_left     <= instruction[29];
            swap_top      <= instruction[28];
            shift_right   <= instruction[27];
            shift_down    <= instruction[26];
            load_acc      <= instruction[25];
            write_acc_out <= instruction[24];
            clr_acc       <= instruction[17];
            clr_systolic  <= instruction[16];
            clr_left_buf  <= instruction[15];
            clr_top_buf   <= instruction[14];
            imm_flag      <= instruction[13];
            addr_imm      <= instruction[12:0];
            done          <= 1;
        end else begin
            done <= 0;
        end
    end
endmodule