`timescale 1ns / 1ps

// tb_systolic_array.v
// Tests 8x8 systolic array with two matrix multiply cases
//
// Data must be skewed before entering - each row of A is delayed by
// one extra cycle relative to the row above it, and each column of B
// is delayed by one extra cycle relative to the column to its left.
// This implements the wavefront (diagonal) scheduling pattern.
//
// For an 8x8 matrix multiply the last diagonal is index 14 (0-based).
// The FSM feeds cycles 0..15 (16 total) so diagonal 14 is presented on
// cycle 14 and the registered value is captured on the rising edge of
// cycle 15. The TB mirrors this: feed_and_clock runs for cycles 0..15.
//
// v2: updated for systolic_array flat-bus interface
//     a_in_flat[r*8+:8], b_in_flat[c*8+:8], a_valid_flat[r],
//     result_flat[(r*8+c)*32+:32]
// v3: fixed off-by-one - feed 16 cycles (0..15) not 15, and pack flat
//     buses with blocking assignments before each clock edge so the DUT
//     sees the correct data on every rising edge.

module tb_systolic_array;

    reg clk    = 0;
    reg resetn = 0;
    reg clr    = 0;

    // Flat buses driven into DUT
    reg  [63:0]  a_in_flat;
    reg  [7:0]   a_valid_flat;
    reg  [63:0]  b_in_flat;

    wire [2047:0] result_flat;

    // Unpack result_flat into readable 2D array
    wire signed [31:0] result [0:7][0:7];
    genvar gr, gc;
    generate
        for (gr = 0; gr < 8; gr = gr + 1) begin : UNPACK_R
            for (gc = 0; gc < 8; gc = gc + 1) begin : UNPACK_C
                assign result[gr][gc] = result_flat[(gr*8+gc)*32 +: 32];
            end
        end
    endgenerate

    always #10 clk = ~clk;

    systolic_array dut (
        .clk          (clk),
        .resetn       (resetn),
        .clr          (clr),
        .a_in_flat    (a_in_flat),
        .a_valid_flat (a_valid_flat),
        .b_in_flat    (b_in_flat),
        .result_flat  (result_flat)
    );

    // Raw matrix storage
    reg signed [7:0]  mat_a    [0:7][0:7];
    reg signed [7:0]  mat_b    [0:7][0:7];
    reg signed [31:0] expected [0:7][0:7];

    integer i, j, cycle, fail;

    // Compute flat bus values for a given feed cycle and drive them
    // with blocking assignments so the DUT sees them before the next
    // clock edge.
    task drive_cycle;
        input integer cyc;
        integer r, c;
        begin
            for (r = 0; r < 8; r = r + 1) begin
                if (cyc >= r && (cyc - r) < 8) begin
                    a_in_flat[r*8 +: 8] = mat_a[r][cyc - r];
                    a_valid_flat[r]     = 1;
                end else begin
                    a_in_flat[r*8 +: 8] = 0;
                    a_valid_flat[r]     = 0;
                end
            end
            for (c = 0; c < 8; c = c + 1) begin
                if (cyc >= c && (cyc - c) < 8)
                    b_in_flat[c*8 +: 8] = mat_b[cyc - c][c];
                else
                    b_in_flat[c*8 +: 8] = 0;
            end
        end
    endtask

    // Software reference multiply
    task compute_expected;
        integer ri, ci, ki;
        begin
            for (ri = 0; ri < 8; ri = ri + 1)
                for (ci = 0; ci < 8; ci = ci + 1) begin
                    expected[ri][ci] = 0;
                    for (ki = 0; ki < 8; ki = ki + 1)
                        expected[ri][ci] = expected[ri][ci] +
                            $signed(mat_a[ri][ki]) * $signed(mat_b[ki][ci]);
                end
        end
    endtask

    // Check all 64 results
    task check_results;
        input [127:0] label;
        integer ri, ci;
        begin
            for (ri = 0; ri < 8; ri = ri + 1)
                for (ci = 0; ci < 8; ci = ci + 1)
                    if (result[ri][ci] !== expected[ri][ci]) begin
                        $display("FAIL [%s] result[%0d][%0d]=%0d expected=%0d",
                                 label, ri, ci,
                                 result[ri][ci], expected[ri][ci]);
                        fail = fail + 1;
                    end
        end
    endtask

    // Run one complete matrix multiply: feed 16 cycles then drain 8
    task run_multiply;
        begin
            // Feed cycles 0..15 (16 diagonals):
            // drive_cycle sets buses before the rising edge so every
            // diagonal is captured correctly, including diagonal 14
            // which is presented on cycle 14 and latched on cycle 15.
            for (cycle = 0; cycle < 16; cycle = cycle + 1) begin
                drive_cycle(cycle);
                @(posedge clk); #1;
            end

            // Drain: zero inputs, wait 8 cycles for PE[7][7] to finish
            a_in_flat    = 0;
            a_valid_flat = 0;
            b_in_flat    = 0;
            repeat(8) @(posedge clk); #1;
        end
    endtask

    initial begin
        fail = 0;

        a_in_flat    = 0;
        a_valid_flat = 0;
        b_in_flat    = 0;

        // Reset
        resetn = 0; #40; resetn = 1; #20;

        // Test 1: Identity x Identity = Identity
        for (i = 0; i < 8; i = i + 1)
            for (j = 0; j < 8; j = j + 1) begin
                mat_a[i][j] = (i == j) ? 1 : 0;
                mat_b[i][j] = (i == j) ? 1 : 0;
            end
        compute_expected;

        clr = 1; @(posedge clk); #1; clr = 0;
        run_multiply;

        check_results("T1_identity");
        if (fail == 0) $display("PASS  T1: Identity x Identity = Identity");

        // Test 2: All-ones A x All-ones B = 8s
        for (i = 0; i < 8; i = i + 1)
            for (j = 0; j < 8; j = j + 1) begin
                mat_a[i][j] = 1;
                mat_b[i][j] = 1;
            end
        compute_expected;

        clr = 1; @(posedge clk); #1; clr = 0;
        run_multiply;

        check_results("T2_ones");
        if (fail == 0) $display("PASS  T2: Ones x Ones = 8s");

        // Test 3: Incrementing values - A[i][j]=i+1, B[i][j]=j+1
        for (i = 0; i < 8; i = i + 1)
            for (j = 0; j < 8; j = j + 1) begin
                mat_a[i][j] = i + 1;
                mat_b[i][j] = j + 1;
            end
        compute_expected;

        clr = 1; @(posedge clk); #1; clr = 0;
        run_multiply;

        check_results("T3_incr");
        if (fail == 0) $display("PASS  T3: Incrementing values");

        // summary
        #20;
        if (fail == 0)
            $display("PASS  all systolic array tests passed");
        else
            $display("FAIL  %0d error(s)", fail);

        $finish;
    end

endmodule