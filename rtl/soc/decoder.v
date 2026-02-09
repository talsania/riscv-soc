`timescale 1ns / 1ps

//==============================================================================
// Memory Decoder (Address Router)
//==============================================================================
// Routes CPU memory accesses to different peripherals based on address
//
// Memory Map:
//   0x0000_0000 - 0x0FFF_FFFF : BRAM (Instruction + Data memory)
//   0x2000_0000 - 0x2FFF_FFFF : UART
//   0x3000_0000 - 0x3FFF_FFFF : GPIO
//==============================================================================

module decoder (
    input  wire        clk,
    input  wire        resetn,
    
    // CPU Memory Interface (from PicoRV32)
    input  wire        mem_valid,
    input  wire        mem_instr,
    input  wire [31:0] mem_addr,
    input  wire [31:0] mem_wdata,
    input  wire [3:0]  mem_wstrb,
    output reg  [31:0] mem_rdata,
    output reg         mem_ready,
    
    // BRAM Interface (for instruction and data memory)
    output reg         bram_valid,
    input  wire [31:0] bram_rdata,
    input  wire        bram_ready,
    
    // GPIO Interface
    output reg         gpio_valid,
    output reg         gpio_we,
    output reg  [31:0] gpio_wdata,
    input  wire [31:0] gpio_rdata,
    input  wire        gpio_ready,
    
    // UART Interface (will add later)
    output reg         uart_valid,
    output reg         uart_we,
    output reg  [7:0]  uart_wdata,
    input  wire        uart_ready
);

    // Address decode
    wire sel_bram;
    wire sel_uart;
    wire sel_gpio;
    
    // Decode based on upper address bits
    assign sel_bram = (mem_addr[31:28] == 4'h0) || (mem_addr[31:28] == 4'h1);  // 0x0xxxxxxx or 0x1xxxxxxx
    assign sel_uart = (mem_addr[31:28] == 4'h2);  // 0x2xxxxxxx
    assign sel_gpio = (mem_addr[31:28] == 4'h3);  // 0x3xxxxxxx
    
    // Determine if this is a write operation
    wire is_write;
    assign is_write = |mem_wstrb;  // Any write strobe bit set = write operation
    
    // Route valid signals to selected peripheral
    always @(*) begin
        bram_valid = 1'b0;
        gpio_valid = 1'b0;
        uart_valid = 1'b0;
        
        if (mem_valid) begin
            if (sel_bram) begin
                bram_valid = 1'b1;
            end else if (sel_gpio) begin
                gpio_valid = 1'b1;
            end else if (sel_uart) begin
                uart_valid = 1'b1;
            end
        end
    end
    
    // Route write enable and data to GPIO
    always @(*) begin
        gpio_we = is_write;
        gpio_wdata = mem_wdata;
    end
    
    // Route write enable and data to UART
    always @(*) begin
        uart_we = is_write;
        uart_wdata = mem_wdata[7:0];  // UART only uses lower 8 bits
    end
    
    // Multiplex read data and ready signals back to CPU
    always @(*) begin
        mem_rdata = 32'h0;
        mem_ready = 1'b0;
        
        if (sel_bram) begin
            mem_rdata = bram_rdata;
            mem_ready = bram_ready;
        end else if (sel_gpio) begin
            mem_rdata = gpio_rdata;
            mem_ready = gpio_ready;
        end else if (sel_uart) begin
            mem_rdata = 32'h0;  // UART doesn't return data (TX only for now)
            mem_ready = uart_ready;
        end else begin
            // Invalid address - return immediately
            mem_rdata = 32'hDEADDEAD;  // Debug value for unmapped addresses
            mem_ready = mem_valid;      // Respond immediately to avoid CPU hang
        end
    end
    
    // Debugging
    always @(posedge clk) begin
        if (mem_valid && mem_ready) begin
            if (sel_gpio) begin
                if (is_write)
                    $display("[%0t] DECODER: GPIO WRITE to 0x%08h = 0x%08h", $time, mem_addr, mem_wdata);
                else
                    $display("[%0t] DECODER: GPIO READ from 0x%08h = 0x%08h", $time, mem_addr, mem_rdata);
            end else if (sel_uart) begin
                if (is_write)
                    $display("[%0t] DECODER: UART WRITE to 0x%08h = 0x%02h ('%c')", $time, mem_addr, mem_wdata[7:0], mem_wdata[7:0]);
            end else if (sel_bram) begin
                if (mem_instr)
                    $display("[%0t] DECODER: BRAM IFETCH from 0x%08h = 0x%08h", $time, mem_addr, mem_rdata);
                else if (is_write)
                    $display("[%0t] DECODER: BRAM WRITE to 0x%08h = 0x%08h", $time, mem_addr, mem_wdata);
                else
                    $display("[%0t] DECODER: BRAM READ from 0x%08h = 0x%08h", $time, mem_addr, mem_rdata);
            end else begin
                $display("[%0t] DECODER: UNMAPPED ACCESS to 0x%08h", $time, mem_addr);
            end
        end
    end

endmodule
