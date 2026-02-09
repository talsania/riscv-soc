`timescale 1ns / 1ps

//==============================================================================
// Testbench for Simple SoC
//==============================================================================
// Tests the complete system:
//   - CPU executes program from BRAM
//   - Program writes to GPIO
//   - Verify GPIO output changes
//==============================================================================

module tb_top;

    // Clock and Reset
    reg clk;
    reg resetn;
    
    // Outputs from SoC
    wire [31:0] gpio_out;
    wire [31:0] debug_pc;
    wire        debug_trap;
    
    // Instantiate the SoC
    top soc (
        .clk(clk),
        .resetn(resetn),
        .gpio_out(gpio_out),
        .debug_pc(debug_pc),
        .debug_trap(debug_trap)
    );
    
    // Clock generation (50MHz)
    initial begin
        clk = 0;
        forever #10 clk = ~clk;
    end
    
    // Test sequence
    initial begin
        $display("========================================");
        $display("Simple SoC Test - CPU + GPIO");
        $display("========================================");
        $display("");
        $display("Program loaded in BRAM:");
        $display("  1. Load GPIO base address (0x30000000)");
        $display("  2. Write value 1 to GPIO");
        $display("  3. Loop forever");
        $display("");
        
        // Initialize
        resetn = 0;
        
        // Hold reset
        #100;
        resetn = 1;
        $display("[%0t] Reset released - CPU starting", $time);
        $display("");
        
        // Run for enough time to execute the program
        #5000;
        
        // Check results
        $display("");
        $display("========================================");
        $display("Test Results:");
        $display("========================================");
        
        if (gpio_out == 32'hAAA00000) begin
            $display("✓ PASS: GPIO output = 0x%08h (expected 0xAAA00000)", gpio_out);
            $display("");
            $display("SUCCESS! CPU successfully wrote to GPIO peripheral!");
        end else begin
            $display("✗ FAIL: GPIO output = 0x%08h (expected 0xAAA00000)", gpio_out);
            $display("");
            $display("The CPU did not write the expected value to GPIO.");
        end
        
        if (debug_trap) begin
            $display("⚠ WARNING: CPU entered trap state");
        end
        
        $display("========================================");
        
        #500;
        $finish;
    end
    
    // Monitor PC changes
    reg [31:0] last_pc;
    always @(posedge clk) begin
        if (resetn && debug_pc != 32'h0 && debug_pc != last_pc) begin
            $display("[%0t] PC = 0x%08h", $time, debug_pc);
            last_pc <= debug_pc;
        end
    end
    
    // Monitor GPIO changes
    reg [31:0] last_gpio;
    initial last_gpio = 32'h0;
    
    always @(gpio_out) begin
        if (gpio_out != last_gpio) begin
            $display("");
            $display("****************************************");
            $display("*** GPIO OUTPUT CHANGED!");
            $display("*** Old value: 0x%08h", last_gpio);
            $display("*** New value: 0x%08h", gpio_out);
            $display("*** Binary:    %32b", gpio_out);
            $display("****************************************");
            $display("");
            last_gpio = gpio_out;
        end
    end
    
    // Monitor for trap
    always @(posedge debug_trap) begin
        $display("");
        $display("!!! CPU TRAP OCCURRED at PC = 0x%08h !!!", debug_pc);
        $display("");
    end

endmodule

/* OUTPUT:-
Program loaded in BRAM:
  1. Load GPIO base address (0x30000000)
  2. Write value 1 to GPIO
  3. Loop forever

[100000] Reset released - CPU starting

[170000] DECODER: BRAM IFETCH from 0x00000000 = 0x300000b7
[250000] DECODER: BRAM IFETCH from 0x00000004 = 0xaaa00113
[330000] DECODER: BRAM IFETCH from 0x00000008 = 0x00208213
[410000] DECODER: BRAM IFETCH from 0x0000000c = 0x0020a023
[490000] DECODER: BRAM IFETCH from 0x00000010 = 0xffdff06f
[530000] GPIO WRITE: 0xfffffaaa

****************************************
*** GPIO OUTPUT CHANGED!
*** Old value: 0x00000000
*** New value: 0xfffffaaa
*** Binary:    11111111111111111111101010101010
****************************************

[550000] DECODER: GPIO WRITE to 0x30000000 = 0xfffffaaa
[630000] DECODER: BRAM IFETCH from 0x0000000c = 0x0020a023
[710000] DECODER: BRAM IFETCH from 0x00000010 = 0xffdff06f
[750000] GPIO WRITE: 0xfffffaaa
[770000] DECODER: GPIO WRITE to 0x30000000 = 0xfffffaaa
[850000] DECODER: BRAM IFETCH from 0x0000000c = 0x0020a023
[930000] DECODER: BRAM IFETCH from 0x00000010 = 0xffdff06f
[970000] GPIO WRITE: 0xfffffaaa
[990000] DECODER: GPIO WRITE to 0x30000000 = 0xfffffaaa */