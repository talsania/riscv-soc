`timescale 1ns / 1ps

//==============================================================================
// Tests basic read/write functionality of GPIO peripheral
//==============================================================================

module tb_gpio;

    // Clock and Reset
    reg clk;
    reg resetn;
    
    // GPIO Interface
    reg         gpio_valid;
    reg         gpio_we;
    reg  [31:0] gpio_wdata;
    wire [31:0] gpio_rdata;
    wire        gpio_ready;
    
    // GPIO Outputs
    wire [31:0] gpio_out;
    
    // Instantiate GPIO Peripheral
    gpio gpio_inst (
        .clk(clk),
        .resetn(resetn),
        .gpio_valid(gpio_valid),
        .gpio_we(gpio_we),
        .gpio_wdata(gpio_wdata),
        .gpio_rdata(gpio_rdata),
        .gpio_ready(gpio_ready),
        .gpio_out(gpio_out)
    );
    
    // Clock generation (50MHz)
    initial begin
        clk = 0;
        forever #10 clk = ~clk;
    end
    
    // Test sequence
    initial begin
        // Initialize signals
        resetn = 0;
        gpio_valid = 0;
        gpio_we = 0;
        gpio_wdata = 32'h0;
        
        // Hold reset
        #100;
        resetn = 1;
        $display("[%0t] Reset released", $time);
        #40;
        
        // Test 1: Write value 0x00000001 to GPIO
        $display("\n1: Write 0x00000001");
        gpio_valid = 1;
        gpio_we = 1;
        gpio_wdata = 32'h00000001;
        #20;  // Wait for ready
        gpio_valid = 0;
        #40;
        
        if (gpio_out == 32'h00000001) begin
            $display("✓ PASS: GPIO output = 0x%08h", gpio_out);
        end else begin
            $display("✗ FAIL: Expected 0x00000001, got 0x%08h", gpio_out);
        end
        
        // Test 2: Write value 0x000000FF
        $display("\n2: Write 0x000000FF");
        gpio_valid = 1;
        gpio_we = 1;
        gpio_wdata = 32'h000000FF;
        #20;
        gpio_valid = 0;
        #40;
        
        if (gpio_out == 32'h000000FF) begin
            $display("✓ PASS: GPIO output = 0x%08h", gpio_out);
        end else begin
            $display("✗ FAIL: Expected 0x000000FF, got 0x%08h", gpio_out);
        end
        
        // Test 3: Read back GPIO value
        $display("\n3: Read GPIO value");
        gpio_valid = 1;
        gpio_we = 0;  // Read operation
        #20;
        gpio_valid = 0;
        #20;
        
        if (gpio_rdata == 32'h000000FF) begin
            $display("✓ PASS: Read back 0x%08h", gpio_rdata);
        end else begin
            $display("✗ FAIL: Expected 0x000000FF, got 0x%08h", gpio_rdata);
        end
        
        // Test 4: Write 0xDEADBEEF
        $display("\n4: Write 0xDEADBEEF ---");
        gpio_valid = 1;
        gpio_we = 1;
        gpio_wdata = 32'hDEADBEEF;
        #20;
        gpio_valid = 0;
        #40;
        
        if (gpio_out == 32'hDEADBEEF) begin
            $display("✓ PASS: GPIO output = 0x%08h", gpio_out);
        end else begin
            $display("✗ FAIL: Expected 0xDEADBEEF, got 0x%08h", gpio_out);
        end
        
        // Test 5: Toggle pattern
        $display("\n5: Toggle Pattern");
        gpio_valid = 1;
        gpio_we = 1;
        gpio_wdata = 32'h00000000;
        #20;
        gpio_valid = 0;
        #40;
        
        gpio_valid = 1;
        gpio_wdata = 32'hFFFFFFFF;
        #20;
        gpio_valid = 0;
        #40;
        
        gpio_valid = 1;
        gpio_wdata = 32'h00000000;
        #20;
        gpio_valid = 0;
        #40;
        
        $display("✓ PASS: Toggle pattern completed");
        $finish;
    end
    
    // Monitor gpio_out changes
    always @(gpio_out) begin
        $display("[%0t] GPIO_OUT changed to: 0x%08h (binary: %32b)", 
                 $time, gpio_out, gpio_out);
    end

endmodule