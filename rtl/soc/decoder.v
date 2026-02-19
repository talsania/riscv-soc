`timescale 1ns / 1ps

//==============================================================================
// Memory Decoder  (Address Router)
//
// Memory map:
//   0x0xxx_xxxx  ->  BRAM  (instruction + data memory)
//   0x1xxx_xxxx  ->  BRAM  (data alias)
//   0x2xxx_xxxx  ->  UART  TX
//   0x3xxx_xxxx  ->  GPIO
//==============================================================================

module decoder (
    input  wire        clk,
    input  wire        resetn,

    // CPU side
    input  wire        mem_valid,
    input  wire        mem_instr,
    input  wire [31:0] mem_addr,
    input  wire [31:0] mem_wdata,
    input  wire [3:0]  mem_wstrb,
    output reg  [31:0] mem_rdata,
    output reg         mem_ready,

    // BRAM side
    output reg         bram_valid,
    input  wire [31:0] bram_rdata,
    input  wire        bram_ready,

    // GPIO side
    output reg         gpio_valid,
    output reg         gpio_we,
    output reg  [31:0] gpio_wdata,
    input  wire [31:0] gpio_rdata,
    input  wire        gpio_ready,

    // UART side
    output reg         uart_valid,
    output reg         uart_we,
    output reg  [7:0]  uart_wdata,
    input  wire        uart_ready
);

    // Address decode using top nibble
    wire sel_bram = (mem_addr[31:28] == 4'h0) || (mem_addr[31:28] == 4'h1);
    wire sel_uart = (mem_addr[31:28] == 4'h2);
    wire sel_gpio = (mem_addr[31:28] == 4'h3);
    wire is_write = |mem_wstrb;

    // Route valid / we / data to peripherals
    always @(*) begin
        bram_valid = 1'b0;
        gpio_valid = 1'b0;
        uart_valid = 1'b0;
        gpio_we    = is_write;
        gpio_wdata = mem_wdata;
        uart_we    = is_write;
        uart_wdata = mem_wdata[7:0];

        if (mem_valid) begin
            if      (sel_bram) bram_valid = 1'b1;
            else if (sel_gpio) gpio_valid = 1'b1;
            else if (sel_uart) uart_valid = 1'b1;
        end
    end

    // Mux response back to CPU
    always @(*) begin
        mem_rdata = 32'h0;
        mem_ready = 1'b0;
        if      (sel_bram) begin mem_rdata = bram_rdata; mem_ready = bram_ready; end
        else if (sel_gpio) begin mem_rdata = gpio_rdata; mem_ready = gpio_ready; end
        else if (sel_uart) begin mem_rdata = 32'h0;      mem_ready = uart_ready; end
        else               begin mem_rdata = 32'hDEADDEAD; mem_ready = mem_valid; end
    end

    // Debugging
    always @(posedge clk) begin
        if (mem_valid && mem_ready) begin
            if (sel_gpio) begin
                if (is_write)
                    $display("[%0t] DECODER -> GPIO WRITE  addr=0x%08h  data=0x%08h",
                             $time, mem_addr, mem_wdata);
                else
                    $display("[%0t] DECODER -> GPIO READ   addr=0x%08h  data=0x%08h",
                             $time, mem_addr, mem_rdata);
            end else if (sel_uart && is_write)
                $display("[%0t] DECODER -> UART WRITE  addr=0x%08h  char=0x%02h ('%c')",
                         $time, mem_addr, mem_wdata[7:0],
                         (mem_wdata[7:0] >= 32 && mem_wdata[7:0] < 127)
                             ? mem_wdata[7:0] : 8'h2E);
            else if (sel_bram && mem_instr)
                $display("[%0t] DECODER -> BRAM FETCH  addr=0x%08h  insn=0x%08h",
                         $time, mem_addr, bram_rdata);
            else if (!sel_bram && !sel_gpio && !sel_uart)
                $display("[%0t] DECODER -> UNMAPPED    addr=0x%08h", $time, mem_addr);
        end
    end

endmodule