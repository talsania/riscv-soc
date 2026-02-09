`timescale 1ns / 1ps

//==============================================================================
// Simple SoC (PicoRV32 + GPIO)
//==============================================================================
// Integrates:
//   - PicoRV32 CPU
//   - Memory Decoder (address router)
//   - BRAM (instruction + data memory)
//   - GPIO peripheral
//==============================================================================

module top (
    input  wire        clk,
    input  wire        resetn,
    
    // GPIO outputs (visible to outside world)
    output wire [31:0] gpio_out,
    
    // Debug signals
    output wire [31:0] debug_pc,
    output wire        debug_trap
);

    // CPU <-> Memory Decoder Interface
    wire        mem_valid;
    wire        mem_instr;
    wire [31:0] mem_addr;
    wire [31:0] mem_wdata;
    wire [3:0]  mem_wstrb;
    wire [31:0] mem_rdata;
    wire        mem_ready;
    // Memory Decoder <-> BRAM Interface
    wire        bram_valid;
    wire [31:0] bram_rdata;
    wire        bram_ready;
    // Memory Decoder <-> GPIO Interface
    wire        gpio_valid;
    wire        gpio_we;
    wire [31:0] gpio_wdata;
    wire [31:0] gpio_rdata;
    wire        gpio_ready;
    // Memory Decoder <-> UART Interface (placeholder)
    wire        uart_valid;
    wire        uart_we;
    wire [7:0]  uart_wdata;
    wire        uart_ready;
    // UART not implemented yet, just tie ready signal
    assign uart_ready = uart_valid;  // Respond immediately
    // PicoRV32 CPU Instance
    wire trap;
    assign debug_trap = trap;
    
    picorv32 #(
        .ENABLE_COUNTERS(0),
        .ENABLE_COUNTERS64(0),
        .ENABLE_REGS_16_31(1),
        .ENABLE_REGS_DUALPORT(0),
        .LATCHED_MEM_RDATA(0),
        .TWO_STAGE_SHIFT(0),
        .BARREL_SHIFTER(0),
        .TWO_CYCLE_COMPARE(0),
        .TWO_CYCLE_ALU(0),
        .CATCH_MISALIGN(0),
        .CATCH_ILLINSN(0),
        .COMPRESSED_ISA(0),
        .ENABLE_PCPI(0),
        .ENABLE_MUL(0),
        .ENABLE_FAST_MUL(0),
        .ENABLE_DIV(0),
        .ENABLE_IRQ(0),
        .ENABLE_TRACE(0)
    ) cpu (
        .clk(clk),
        .resetn(resetn),
        .trap(trap),
        
        // Memory interface
        .mem_valid(mem_valid),
        .mem_instr(mem_instr),
        .mem_ready(mem_ready),
        .mem_addr(mem_addr),
        .mem_wdata(mem_wdata),
        .mem_wstrb(mem_wstrb),
        .mem_rdata(mem_rdata),
        
        // Unused ports
        .mem_la_read(),
        .mem_la_write(),
        .mem_la_addr(),
        .mem_la_wdata(),
        .mem_la_wstrb(),
        .pcpi_valid(),
        .pcpi_insn(),
        .pcpi_rs1(),
        .pcpi_rs2(),
        .pcpi_wr(1'b0),
        .pcpi_rd(32'h0),
        .pcpi_wait(1'b0),
        .pcpi_ready(1'b0),
        .irq(32'h0),
        .eoi(),
        .trace_valid(),
        .trace_data()
    );
    
    // Extract PC for debugging
    assign debug_pc = mem_instr ? mem_addr : 32'h0;
    
    // Memory Decoder Instance
    decoder decoder (
        .clk(clk),
        .resetn(resetn),
        
        // CPU side
        .mem_valid(mem_valid),
        .mem_instr(mem_instr),
        .mem_addr(mem_addr),
        .mem_wdata(mem_wdata),
        .mem_wstrb(mem_wstrb),
        .mem_rdata(mem_rdata),
        .mem_ready(mem_ready),
        
        // BRAM side
        .bram_valid(bram_valid),
        .bram_rdata(bram_rdata),
        .bram_ready(bram_ready),
        
        // GPIO side
        .gpio_valid(gpio_valid),
        .gpio_we(gpio_we),
        .gpio_wdata(gpio_wdata),
        .gpio_rdata(gpio_rdata),
        .gpio_ready(gpio_ready),
        
        // UART side
        .uart_valid(uart_valid),
        .uart_we(uart_we),
        .uart_wdata(uart_wdata),
        .uart_ready(uart_ready)
    );
    
    // BRAM Instance
    bram bram (
        .clk(clk),
        .resetn(resetn),
        .bram_valid(bram_valid),
        .bram_addr(mem_addr),
        .bram_wdata(mem_wdata),
        .bram_wstrb(mem_wstrb),
        .bram_rdata(bram_rdata),
        .bram_ready(bram_ready)
    );
    
    // GPIO Instance
    gpio gpio (
        .clk(clk),
        .resetn(resetn),
        .gpio_valid(gpio_valid),
        .gpio_we(gpio_we),
        .gpio_wdata(gpio_wdata),
        .gpio_rdata(gpio_rdata),
        .gpio_ready(gpio_ready),
        .gpio_out(gpio_out)
    );

endmodule