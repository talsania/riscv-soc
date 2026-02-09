`timescale 1ns / 1ps

//==============================================================================
// Simple GPIO Peripheral (Memory-Mapped)
//==============================================================================
// Address: 0x30000000
// Functionality: 32-bit output register
// When CPU writes to this address, the value is captured and output on gpio_out
//==============================================================================

module gpio (
    input  wire        clk,
    input  wire        resetn,
    
    // Memory-mapped interface (connected to CPU memory bus)
    input  wire        gpio_valid,      // CPU wants to access GPIO
    input  wire        gpio_we,         // Write enable (1=write, 0=read)
    input  wire [31:0] gpio_wdata,      // Data to write
    output reg  [31:0] gpio_rdata,      // Data to read back
    output reg         gpio_ready,      // GPIO is ready
    
    // GPIO outputs (connected to external pins/LEDs)
    output reg  [31:0] gpio_out         // CHANGED: Keep as reg, assign in always block
);

    // Handle memory-mapped accesses
    always @(posedge clk) begin
        if (!resetn) begin
            // Reset: Clear GPIO register and outputs
            gpio_out <= 32'h0;
            gpio_ready <= 1'b0;
            gpio_rdata <= 32'h0;
        end else begin
            gpio_ready <= 1'b0;  // Default: not ready
            
            if (gpio_valid && !gpio_ready) begin
                if (gpio_we) begin
                    // WRITE operation: Update GPIO output directly
                    gpio_out <= gpio_wdata;
                    $display("[%0t] GPIO WRITE: 0x%08h", $time, gpio_wdata);
                end else begin
                    // READ operation: Return current GPIO value
                    gpio_rdata <= gpio_out;
                    $display("[%0t] GPIO READ: 0x%08h", $time, gpio_out);
                end
                gpio_ready <= 1'b1;  // Signal operation complete
            end
        end
    end

endmodule