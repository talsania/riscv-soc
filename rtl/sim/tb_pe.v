`timescale 1ns / 1ps

// tb_pe.v
// Tests: accumulation, clr reset, forwarding delay, signed arithmetic

module tb_pe;

    reg        clk     = 0;
    reg        resetn  = 0;
    reg        clr     = 0;
    reg signed [7:0] a_in    = 0;
    reg signed [7:0] b_in    = 0;
    reg        valid_in = 0;

    wire signed [7:0]  a_out;
    wire signed [7:0]  b_out;
    wire               valid_out;
    wire signed [31:0] mac_out;

    pe dut (
        .clk      (clk),
        .resetn   (resetn),
        .clr      (clr),
        .a_in     (a_in),
        .b_in     (b_in),
        .valid_in (valid_in),
        .a_out    (a_out),
        .b_out    (b_out),
        .valid_out(valid_out),
        .mac_out  (mac_out)
    );

    always #10 clk = ~clk;

    integer fail = 0;

    task check;
        input signed [31:0] expected_mac;
        input signed [7:0]  expected_a;
        input signed [7:0]  expected_b;
        input               expected_vld;
        input [127:0]       label;
        begin
            if (mac_out !== expected_mac) begin
                $display("FAIL [%s] mac_out=%0d expected=%0d @ %0t",
                         label, mac_out, expected_mac, $time);
                fail = fail + 1;
            end
            if (a_out !== expected_a) begin
                $display("FAIL [%s] a_out=%0d expected=%0d @ %0t",
                         label, a_out, expected_a, $time);
                fail = fail + 1;
            end
            if (b_out !== expected_b) begin
                $display("FAIL [%s] b_out=%0d expected=%0d @ %0t",
                         label, b_out, expected_b, $time);
                fail = fail + 1;
            end
            if (valid_out !== expected_vld) begin
                $display("FAIL [%s] valid_out=%0b expected=%0b @ %0t",
                         label, valid_out, expected_vld, $time);
                fail = fail + 1;
            end
        end
    endtask

    initial begin
        resetn = 0;
        #40;
        resetn = 1;
        #20;

        // T1: single MAC
        // a=3 b=4, expect mac=12
        a_in = 3; b_in = 4; valid_in = 1;
        @(posedge clk); #1;
        check(12, 3, 4, 1, "T1_mac");

        // T2: accumulate
        // a=2 b=5, mac=12+10=22
        a_in = 2; b_in = 5;
        @(posedge clk); #1;
        check(22, 2, 5, 1, "T2_acc");

        // T3: accumulate
        // a=1 b=1, mac=22+1=23
        a_in = 1; b_in = 1;
        @(posedge clk); #1;
        check(23, 1, 1, 1, "T3_acc");

        // T4: valid=0, mac must not change
        valid_in = 0;
        a_in = 10; b_in = 10;
        @(posedge clk); #1;
        check(23, 10, 10, 0, "T4_novalid");

        // T5: clr=1 with no valid data - realistic usage
        // clr is asserted between matrix operations, not during them
        valid_in = 0;
        a_in = 0; b_in = 0;
        clr = 1;
        @(posedge clk); #1;
        check(0, 0, 0, 0, "T5_clr");
        clr = 0;

        // T6: first accumulate after clr
        // a=6 b=7, mac=42
        valid_in = 1;
        a_in = 6; b_in = 7;
        @(posedge clk); #1;
        check(42, 6, 7, 1, "T6_post_clr");

        // T7: signed negative a
        // a=-3 b=4, mac=42+(-12)=30
        a_in = -3; b_in = 4;
        @(posedge clk); #1;
        check(30, -3, 4, 1, "T7_signed");

        // T8: both negative
        // a=-2 b=-5, mac=30+10=40
        a_in = -2; b_in = -5;
        @(posedge clk); #1;
        check(40, -2, -5, 1, "T8_neg_neg");

        // T9: max INT8
        // a=127 b=127, mac=40+16129=16169
        a_in = 127; b_in = 127;
        @(posedge clk); #1;
        check(16169, 127, 127, 1, "T9_max");

        // T10: min INT8
        // a=-128 b=-128, mac=16169+16384=32553
        a_in = -128; b_in = -128;
        @(posedge clk); #1;
        check(32553, -128, -128, 1, "T10_min");

        valid_in = 0;
        #40;

        if (fail == 0)
            $display("PASS  all PE tests passed");
        else
            $display("FAIL  %0d test(s) failed", fail);

        $finish;
    end

endmodule