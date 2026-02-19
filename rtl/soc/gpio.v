`timescale 1ns / 1ps

//==============================================================================
// GPIO Peripheral  (Memory-Mapped)
// Address  : 0x30000000
// Write    : stores 32-bit value and drives gpio_out
// Read     : returns current gpio_out value
//==============================================================================

module gpio (
    input  wire        clk,
    input  wire        resetn,
    input  wire        gpio_valid,
    input  wire        gpio_we,
    input  wire [31:0] gpio_wdata,
    output reg  [31:0] gpio_rdata,
    output reg         gpio_ready,
    output reg  [31:0] gpio_out
);
    always @(posedge clk) begin
        if (!resetn) begin
            gpio_out   <= 32'h0;
            gpio_rdata <= 32'h0;
            gpio_ready <= 1'b0;
        end else begin
            gpio_ready <= 1'b0;
            if (gpio_valid && !gpio_ready) begin
                if (gpio_we) begin
                    gpio_out <= gpio_wdata;
                    $display("[%0t] GPIO WRITE: 0x%08h", $time, gpio_wdata);
                end else begin
                    gpio_rdata <= gpio_out;
                    $display("[%0t] GPIO READ : 0x%08h", $time, gpio_out);
                end
                gpio_ready <= 1'b1;
            end
        end
    end
endmodule