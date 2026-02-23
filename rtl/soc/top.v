`timescale 1ns / 1ps

//==============================================================================
// top.v  -  Simple SoC  (PicoRV32 + BRAM + GPIO + UART)
//
// Fix: removed duplicate .uart_rdata port connection on uart_inst
//==============================================================================

module top (
    input  wire        clk,
    input  wire        resetn,
    output wire [31:0] gpio_out,
    output wire        uart_txd,
    output wire [31:0] debug_pc,
    output wire        debug_trap
);

    // CPU <-> Decoder
    wire        mem_valid, mem_instr, mem_ready;
    wire [31:0] mem_addr, mem_wdata, mem_rdata;
    wire [3:0]  mem_wstrb;

    // Decoder <-> BRAM
    wire        bram_valid, bram_ready;
    wire [31:0] bram_rdata;

    // Decoder <-> GPIO
    wire        gpio_valid, gpio_we, gpio_ready;
    wire [31:0] gpio_wdata, gpio_rdata;

    // Decoder <-> UART
    wire        uart_valid, uart_we, uart_ready;
    wire [7:0]  uart_wdata;
    wire [31:0] uart_rdata;

    wire trap;
    assign debug_trap = trap;

    // Latch PC on instruction fetch for stable waveform display
    reg [31:0] pc_latch;
    always @(posedge clk) begin
        if (!resetn)
            pc_latch <= 32'h0;
        else if (mem_valid && mem_instr)
            pc_latch <= mem_addr;
    end
    assign debug_pc = pc_latch;

    // PicoRV32 CPU
    picorv32 #(
        .ENABLE_COUNTERS    (0),
        .ENABLE_COUNTERS64  (0),
        .ENABLE_REGS_16_31  (1),
        .ENABLE_REGS_DUALPORT(0),
        .LATCHED_MEM_RDATA  (0),
        .TWO_STAGE_SHIFT    (0),
        .BARREL_SHIFTER     (0),
        .TWO_CYCLE_COMPARE  (0),
        .TWO_CYCLE_ALU      (0),
        .CATCH_MISALIGN     (0),
        .CATCH_ILLINSN      (0),
        .COMPRESSED_ISA     (0),
        .ENABLE_PCPI        (0),
        .ENABLE_MUL         (0),
        .ENABLE_FAST_MUL    (0),
        .ENABLE_DIV         (0),
        .ENABLE_IRQ         (0),
        .ENABLE_TRACE       (0)
    ) cpu (
        .clk      (clk),
        .resetn   (resetn),
        .trap     (trap),
        .mem_valid(mem_valid),
        .mem_instr(mem_instr),
        .mem_ready(mem_ready),
        .mem_addr (mem_addr),
        .mem_wdata(mem_wdata),
        .mem_wstrb(mem_wstrb),
        .mem_rdata(mem_rdata),
        .mem_la_read  (),
        .mem_la_write (),
        .mem_la_addr  (),
        .mem_la_wdata (),
        .mem_la_wstrb (),
        .pcpi_valid   (),
        .pcpi_insn    (),
        .pcpi_rs1     (),
        .pcpi_rs2     (),
        .pcpi_wr      (1'b0),
        .pcpi_rd      (32'h0),
        .pcpi_wait    (1'b0),
        .pcpi_ready   (1'b0),
        .irq          (32'h0),
        .eoi          (),
        .trace_valid  (),
        .trace_data   ()
    );

    // Memory Decoder
    decoder decoder (
        .clk       (clk),
        .resetn    (resetn),
        .mem_valid (mem_valid),
        .mem_instr (mem_instr),
        .mem_addr  (mem_addr),
        .mem_wdata (mem_wdata),
        .mem_wstrb (mem_wstrb),
        .mem_rdata (mem_rdata),
        .mem_ready (mem_ready),
        .bram_valid(bram_valid),
        .bram_rdata(bram_rdata),
        .bram_ready(bram_ready),
        .gpio_valid(gpio_valid),
        .gpio_we   (gpio_we),
        .gpio_wdata(gpio_wdata),
        .gpio_rdata(gpio_rdata),
        .gpio_ready(gpio_ready),
        .uart_valid(uart_valid),
        .uart_we   (uart_we),
        .uart_wdata(uart_wdata),
        .uart_ready(uart_ready),
        .uart_rdata(uart_rdata)     // ← single connection, passes tx_busy back to CPU
    );

    // BRAM
    bram bram (
        .clk       (clk),
        .resetn    (resetn),
        .bram_valid(bram_valid),
        .bram_addr (mem_addr),
        .bram_wdata(mem_wdata),
        .bram_wstrb(mem_wstrb),
        .bram_rdata(bram_rdata),
        .bram_ready(bram_ready)
    );

    // GPIO
    gpio gpio_inst (
        .clk       (clk),
        .resetn    (resetn),
        .gpio_valid(gpio_valid),
        .gpio_we   (gpio_we),
        .gpio_wdata(gpio_wdata),
        .gpio_rdata(gpio_rdata),
        .gpio_ready(gpio_ready),
        .gpio_out  (gpio_out)
    );

    // UART TX  -  single .uart_rdata connection (bug fix: was listed twice)
    uart_tx #(
        .BAUD_DIV(434)
    ) uart_inst (
        .clk       (clk),
        .resetn    (resetn),
        .uart_valid(uart_valid),
        .uart_we   (uart_we),
        .uart_addr (mem_addr),
        .uart_wdata(uart_wdata),
        .uart_rdata(uart_rdata),   
        .uart_ready(uart_ready),
        .uart_txd  (uart_txd)
    );

endmodule 