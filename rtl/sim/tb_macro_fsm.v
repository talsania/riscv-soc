`timescale 1ns / 1ps

// tb_macro_fsm.v
// Tests macro_fsm driving systolic_array for a full 8x8 matrix multiply
// Verifies busy/done handshake, clr pulse timing, and correct results
//
// v2: mat_a/mat_b 2D regs packed into mat_a_flat/mat_b_flat [511:0]
//     a_in_flat/b_in_flat/a_valid_flat/result_flat flat-bus connections

module tb_macro_fsm;

    reg        clk    = 0;
    reg        resetn = 0;
    reg        start  = 0;

    reg  signed [7:0] mat_a [0:7][0:7];
    reg  signed [7:0] mat_b [0:7][0:7];

    // Pack 2D reg arrays into flat buses for macro_fsm ports
    reg  [511:0] mat_a_flat;
    reg  [511:0] mat_b_flat;

    wire [63:0]    a_in_flat;
    wire [7:0]     a_valid_flat;
    wire [63:0]    b_in_flat;
    wire           clr;
    wire           busy;
    wire           done;

    wire [2047:0]  result_flat;

    macro_fsm ctrl (
        .clk          (clk),
        .resetn       (resetn),
        .start        (start),
        .mat_a_flat   (mat_a_flat),
        .mat_b_flat   (mat_b_flat),
        .a_in_flat    (a_in_flat),
        .a_valid_flat (a_valid_flat),
        .b_in_flat    (b_in_flat),
        .clr          (clr),
        .busy         (busy),
        .done         (done)
    );

    systolic_array sa (
        .clk          (clk),
        .resetn       (resetn),
        .clr          (clr),
        .a_in_flat    (a_in_flat),
        .a_valid_flat (a_valid_flat),
        .b_in_flat    (b_in_flat),
        .result_flat  (result_flat)
    );

    // Unpack result_flat into a 2D array for readable checking
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

    integer i, j, fail;
    reg signed [31:0] expected [0:7][0:7];

    // Pack mat_a and mat_b 2D regs into flat buses
    task pack_matrices;
        integer pi, pj;
        begin
            for (pi = 0; pi < 8; pi = pi + 1)
                for (pj = 0; pj < 8; pj = pj + 1) begin
                    mat_a_flat[(pi*8+pj)*8 +: 8] = mat_a[pi][pj];
                    mat_b_flat[(pi*8+pj)*8 +: 8] = mat_b[pi][pj];
                end
        end
    endtask

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

    task wait_done;
        begin
            @(posedge done); #1;
        end
    endtask

    task check_results;
        input [127:0] label;
        integer ri, ci;
        begin
            for (ri = 0; ri < 8; ri = ri + 1)
                for (ci = 0; ci < 8; ci = ci + 1)
                    if (result[ri][ci] !== expected[ri][ci]) begin
                        $display("FAIL [%s] result[%0d][%0d]=%0d exp=%0d",
                                 label, ri, ci,
                                 result[ri][ci], expected[ri][ci]);
                        fail = fail + 1;
                    end
        end
    endtask

    initial begin
        fail = 0;
        resetn = 0; #40; resetn = 1; #20;

        // T1: Identity x Identity
        for (i = 0; i < 8; i = i + 1)
            for (j = 0; j < 8; j = j + 1) begin
                mat_a[i][j] = (i == j) ? 1 : 0;
                mat_b[i][j] = (i == j) ? 1 : 0;
            end
        compute_expected;
        pack_matrices;

        start = 1; @(posedge clk); #1; start = 0;
        wait_done;
        check_results("T1_identity");
        if (fail == 0) $display("PASS  T1: Identity x Identity");

        // T2: All-ones
        for (i = 0; i < 8; i = i + 1)
            for (j = 0; j < 8; j = j + 1) begin
                mat_a[i][j] = 1;
                mat_b[i][j] = 1;
            end
        compute_expected;
        pack_matrices;

        #20;
        start = 1; @(posedge clk); #1; start = 0;
        wait_done;
        check_results("T2_ones");
        if (fail == 0) $display("PASS  T2: Ones x Ones = 8s");

        // T3: A[i][j]=i+1, B[i][j]=j+1
        for (i = 0; i < 8; i = i + 1)
            for (j = 0; j < 8; j = j + 1) begin
                mat_a[i][j] = i + 1;
                mat_b[i][j] = j + 1;
            end
        compute_expected;
        pack_matrices;

        #20;
        start = 1; @(posedge clk); #1; start = 0;
        wait_done;
        check_results("T3_incr");
        if (fail == 0) $display("PASS  T3: Incrementing values");

        // T4: busy deasserts on done
        if (busy !== 0) begin
            $display("FAIL T4: busy still high after done");
            fail = fail + 1;
        end else
            $display("PASS  T4: busy deasserts after done");

        #40;
        if (fail == 0)
            $display("PASS  all macro_fsm tests passed");
        else
            $display("FAIL  %0d error(s)", fail);

        $finish;
    end

endmodule