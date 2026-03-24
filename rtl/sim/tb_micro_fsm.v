`timescale 1ns / 1ps

// tb_micro_fsm.v
// Tests micro_fsm instruction decode for all one-hot opcodes
// and clear flag combinations

module tb_micro_fsm;

    reg        clk     = 0;
    reg        resetn  = 0;
    reg [31:0] instruction = 0;
    reg        execute = 0;

    wire       load_left, load_top, swap_left, swap_top;
    wire       shift_right, shift_down, load_acc, write_acc_out;
    wire       clr_acc, clr_systolic, clr_left_buf, clr_top_buf;
    wire       imm_flag, done;
    wire [12:0] addr_imm;

    micro_fsm dut (
        .clk          (clk),
        .resetn       (resetn),
        .instruction  (instruction),
        .execute      (execute),
        .load_left    (load_left),
        .load_top     (load_top),
        .swap_left    (swap_left),
        .swap_top     (swap_top),
        .shift_right  (shift_right),
        .shift_down   (shift_down),
        .load_acc     (load_acc),
        .write_acc_out(write_acc_out),
        .clr_acc      (clr_acc),
        .clr_systolic (clr_systolic),
        .clr_left_buf (clr_left_buf),
        .clr_top_buf  (clr_top_buf),
        .addr_imm     (addr_imm),
        .imm_flag     (imm_flag),
        .done         (done)
    );

    always #10 clk = ~clk;

    integer fail = 0;

    task exec_instr;
        input [31:0] instr;
        begin
            instruction = instr;
            execute = 1;
            @(posedge clk); #1;
            execute = 0;
        end
    endtask

    task check1;
        input       got;
        input       exp;
        input [127:0] label;
        begin
            if (got !== exp) begin
                $display("FAIL [%s] got=%b exp=%b", label, got, exp);
                fail = fail + 1;
            end
        end
    endtask

    initial begin
        resetn = 0; #40; resetn = 1; #20;

        // T1: LOAD_LEFT (bit 31)
        exec_instr(32'h80000000);
        check1(load_left,     1, "T1_load_left");
        check1(load_top,      0, "T1_no_load_top");
        check1(done,          1, "T1_done");

        // T2: LOAD_TOP (bit 30)
        exec_instr(32'h40000000);
        check1(load_top,      1, "T2_load_top");
        check1(load_left,     0, "T2_no_load_left");

        // T3: SWAP_LEFT (bit 29) + SWAP_TOP (bit 28)
        exec_instr(32'h30000000);
        check1(swap_left,     1, "T3_swap_left");
        check1(swap_top,      1, "T3_swap_top");

        // T4: SHIFT_RIGHT (bit 27) + SHIFT_DOWN (bit 26)
        exec_instr(32'h0C000000);
        check1(shift_right,   1, "T4_shift_right");
        check1(shift_down,    1, "T4_shift_down");

        // T5: LOAD_ACC (bit 25)
        exec_instr(32'h02000000);
        check1(load_acc,      1, "T5_load_acc");

        // T6: WRITE_ACC_OUT (bit 24)
        exec_instr(32'h01000000);
        check1(write_acc_out, 1, "T6_write_acc_out");

        // T7: CLR (bit 21) with CLR_ACC (bit 17) + CLR_SYSTOLIC (bit 16)
        exec_instr(32'h00200000 | 32'h00030000);
        check1(clr_acc,       1, "T7_clr_acc");
        check1(clr_systolic,  1, "T7_clr_systolic");

        // T8: CLR with CLR_LEFT_BUF (bit 15) + CLR_TOP_BUF (bit 14)
        exec_instr(32'h00200000 | 32'h0000C000);
        check1(clr_left_buf,  1, "T8_clr_left_buf");
        check1(clr_top_buf,   1, "T8_clr_top_buf");

        // T9: IMM_FLAG (bit 13) with addr_imm = 0x1A5
        exec_instr(32'h00002000 | 13'h1A5);
        check1(imm_flag,      1, "T9_imm_flag");
        if (addr_imm !== 13'h1A5) begin
            $display("FAIL T9_addr_imm: got=%h exp=%h", addr_imm, 13'h1A5);
            fail = fail + 1;
        end

        // T10: NOP (bit 20) - no control signals high except done
        exec_instr(32'h00100000);
        check1(load_left,     0, "T10_nop_no_load_left");
        check1(load_top,      0, "T10_nop_no_load_top");
        check1(load_acc,      0, "T10_nop_no_load_acc");
        check1(done,          1, "T10_nop_done");

        // T11: execute=0 after pulse, done should deassert
        @(posedge clk); #1;
        check1(done, 0, "T11_done_deassert");

        // T12: reset clears all outputs
        resetn = 0; @(posedge clk); #1;
        check1(load_left,     0, "T12_rst_load_left");
        check1(done,          0, "T12_rst_done");
        resetn = 1;

        #20;
        if (fail == 0)
            $display("PASS  all micro_fsm tests passed");
        else
            $display("FAIL  %0d error(s)", fail);

        $finish;
    end

endmodule