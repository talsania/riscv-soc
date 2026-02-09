`timescale 1ns / 1ps

//==============================================================================
// Simple BRAM Controller
//==============================================================================
// Combined instruction and data memory
// Single-cycle access for simplicity
//==============================================================================

module bram (
    input  wire        clk,
    input  wire        resetn,
    
    // Memory interface
    input  wire        bram_valid,
    input  wire [31:0] bram_addr,
    input  wire [31:0] bram_wdata,
    input  wire [3:0]  bram_wstrb,
    output reg  [31:0] bram_rdata,
    output reg         bram_ready
);

    // Memory array: 4KB = 1024 words of 32 bits
    reg [31:0] memory [0:1023];
    
    // Calculate word address (divide byte address by 4)
    wire [9:0] word_addr;
    assign word_addr = bram_addr[11:2];  // Address bits [11:2] give us 10 bits = 1024 words
    
    // Memory access
    always @(posedge clk) begin
        if (!resetn) begin
            bram_ready <= 1'b0;
            bram_rdata <= 32'h0;
        end else begin
            bram_ready <= 1'b0;
            
            if (bram_valid && !bram_ready) begin
                if (bram_wstrb != 4'b0000) begin
                    // WRITE
                    if (bram_wstrb[0]) memory[word_addr][7:0]   <= bram_wdata[7:0];
                    if (bram_wstrb[1]) memory[word_addr][15:8]  <= bram_wdata[15:8];
                    if (bram_wstrb[2]) memory[word_addr][23:16] <= bram_wdata[23:16];
                    if (bram_wstrb[3]) memory[word_addr][31:24] <= bram_wdata[31:24];
                end else begin
                    // READ
                    bram_rdata <= memory[word_addr];
                end
                bram_ready <= 1'b1;
            end
        end
    end
    
    // test program
    integer i;
    initial begin
        // NOPs
        for (i = 0; i < 1024; i = i + 1) begin
            memory[i] = 32'h00000013;  // NOP (ADDI x0, x0, 0)
        end
        
        /* Load a simple test program
         This program will write to GPIO at 0x30000000
         1. Load GPIO base address into x1: 0x30000000
         2. Load test value into x2: 0xAAA00000
         3. Write x2 to address in x1 (GPIO)
         4. Loop forever */
        
//        memory[0] = 32'h300000B7;  // LUI x1, 0x30000      (x1 = 0x30000000 - GPIO base)
//        memory[1] = 32'hAAA00137;  // LUI x2, 0xAAA00      (x2 = 0xAAA00000 - test pattern)
//        memory[2] = 32'h0020A023;  // SW x2, 0(x1)         (MEM[x1 + 0] = x2, write to GPIO!)
//        memory[3] = 32'hFFDFF06F;  // JAL x0, -4           (Loop forever at address 0x00)
        
        // Corrected test program, writes to GPIO at 0x30000000
        memory[0] = 32'h300000B7;  // LUI x1, 0x30000      (x1 = 0x30000000 - GPIO base)
        memory[1] = 32'hAAA00113;  // LUI x2, 0xAAA00      (x2 = 0xAAA00000)
        memory[2] = 32'h00208213;  // ADDI x4, x1, 2       (x4 = 0x30000002)
        memory[3] = 32'h0020A023;  // SW x2, 0(x1)         (MEM[0x30000000] = 0xAAA00000)
        memory[4] = 32'hFFDFF06F;  // JAL x0, -4           (Loop forever)
        
        $display("BRAM: Initialized with test program");
        $display("  0x00: LUI x1, 0x30000    -> x1 = 0x30000000 (GPIO address)");
        $display("  0x04: LUI x2, 0xAAA00    -> x2 = 0xAAA00000 (test value)");
        $display("  0x08: SW x2, 0(x1)       -> Write 0xAAA00000 to GPIO");
        $display("  0x0C: JAL x0, -4         -> Loop");
        $display("  Expected: GPIO output should change to 0xAAA00000");
    end

endmodule