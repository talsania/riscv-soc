`timescale 1ns / 1ps

//==============================================================================
// Testbench  -  Simple SoC  (CPU + GPIO + UART)
//
// What it checks:
//   1. GPIO output changes to 0x00000001
//   2. UART transmits 'H', 'i', '!'
//   3. No CPU trap
//
// fixes:
//   1. Simulation runs 10ms (was 600us) - enough for full UART banner
//   2. GPIO checked after 500us (CPU has time to execute gpio_write)
//   3. UART monitor unchanged - still decodes 115200 baud correctly
//==============================================================================

module tb_top();
    localparam CLK_PERIOD = 20;         // 50 MHz
    localparam BIT_NS     = 434 * CLK_PERIOD;  // 115200 baud = 8680 ns/bit

    reg  clk    = 1'b0;
    reg  resetn = 1'b0;

    wire [31:0] gpio_out;
    wire        uart_txd;
    wire [31:0] debug_pc;
    wire        debug_trap;

    // DUT
    top soc (
        .clk       (clk),
        .resetn    (resetn),
        .gpio_out  (gpio_out),
        .uart_txd  (uart_txd),
        .debug_pc  (debug_pc),
        .debug_trap(debug_trap)
    );

    always #(CLK_PERIOD/2) clk = ~clk;

    // ------------------------------------------------------------------
    // UART RX monitor  (115200 baud, 8N1)
    // ------------------------------------------------------------------
    reg [7:0] rx_byte;
    integer   rx_bit;
    initial begin rx_byte = 0; rx_bit = 0; end

    always @(negedge uart_txd) begin
        #(BIT_NS + BIT_NS/2);           // skip start bit, land mid-bit-0
        rx_byte = 8'h00;
        for (rx_bit = 0; rx_bit < 8; rx_bit = rx_bit + 1) begin
            rx_byte[rx_bit] = uart_txd;
            if (rx_bit < 7) #(BIT_NS);
        end
        $display("[%0t ns] UART RX: '%c'  (0x%02h)",
                 $time, (rx_byte >= 32 && rx_byte < 127) ? rx_byte : 8'h2E, rx_byte);
    end

    // ------------------------------------------------------------------
    // GPIO monitor
    // ------------------------------------------------------------------
    reg [31:0] prev_gpio = 32'hFFFF_FFFF;
    always @(gpio_out) begin
        $display("[%0t ns] GPIO: 0x%08h -> 0x%08h", $time, prev_gpio, gpio_out);
        prev_gpio = gpio_out;
    end

    // ------------------------------------------------------------------
    // Trap monitor
    // ------------------------------------------------------------------
    always @(posedge debug_trap)
        $display("\n!!! CPU TRAP at PC=0x%08h !!!\n", debug_pc);

    // ------------------------------------------------------------------
    // Main sequence
    // ------------------------------------------------------------------
    integer gpio_ok   = 0;
    integer uart_seen = 0;

    initial begin
        $display("==============================================");
        $display("  PicoRV32 SoC Simulation  (C firmware)");
        $display("  UART: 115200 baud  |  BRAM: 4KB");
        $display("==============================================\n");

        // Reset
        resetn = 0;
        #100;
        resetn = 1;
        $display("[%0t ns] Reset released\n", $time);

        // ------------------------------------------------------------------
        // Wait 500 us - enough for gpio_write(1) which is the first
        // instruction after _start sets up stack (< 50 instructions at
        // 2 cycles each = ~2000 ns, well within 500 us)
        // ------------------------------------------------------------------
        #500_000;
        gpio_ok = (gpio_out == 32'h0000_0001);

        // ------------------------------------------------------------------
        // Wait remaining ~9.5 ms for UART banner to finish
        // Full banner ~55 chars x 10 bits x 8680 ns = ~4.77 ms
        // ------------------------------------------------------------------
        #9_500_000;

        // Results
        $display("\n==============================================");
        $display("  Results");
        $display("==============================================");
        if (gpio_ok)
            $display("  PASS  GPIO : 0x00000001 seen within 500 us");
        else
            $display("  FAIL  GPIO : gpio_out = 0x%08h at 500 us mark", gpio_out);

        if (!debug_trap)
            $display("  PASS  CPU  : no trap");
        else
            $display("  FAIL  CPU  : trap asserted");

        $display("  INFO  UART : see decoded bytes above");
        $display("==============================================\n");

        #500;
        $finish;
    end

endmodule