`timescale 1ns / 1ps

//==============================================================================
// Testbench  -  Simple SoC  (CPU + GPIO + UART)
//
// What it checks:
//   1. GPIO output changes to 0x00000001
//   2. UART transmits 'H', 'i', '!'
//   3. No CPU trap
//==============================================================================

module tb_top();
    localparam CLK_PERIOD = 20;     // 50 MHz to 20 ns period

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

    // Clk
    always #(CLK_PERIOD/2) clk = ~clk;
    
    // UART RX monitor
    // Waits for start-bit falling edge, samples 8 data bits, prints character
    // Baud: 434 clocks * 20 ns = 8680 ns per bit
    localparam BIT_NS = 434 * CLK_PERIOD;   // 8680 ns

    reg [7:0] rx_byte;
    integer   rx_bit;

    initial begin
        rx_byte = 8'h00;
        rx_bit  = 0;
    end

    always @(negedge uart_txd) begin            // start-bit falling edge
        #(BIT_NS + BIT_NS/2);                   // skip start bit + land in middle of bit 0
        rx_byte = 8'h00;
        for (rx_bit = 0; rx_bit < 8; rx_bit = rx_bit + 1) begin
            rx_byte[rx_bit] = uart_txd;         // sample (LSB first)
            if (rx_bit < 7) #(BIT_NS);          // advance one bit period
        end
        $display("[%0t] UART RX: 0x%02h  ('%c')", $time, rx_byte,
                 (rx_byte >= 32 && rx_byte < 127) ? rx_byte : 8'h2E);
    end

    // GPIO change monitor
    reg [31:0] prev_gpio;
    initial prev_gpio = 32'h0;

    always @(gpio_out) begin
        if (gpio_out !== prev_gpio) begin
            $display("\n[%0t] *** GPIO changed:  0x%08h  ->  0x%08h ***\n",
                     $time, prev_gpio, gpio_out);
            prev_gpio = gpio_out;
        end
    end

    // PC change monitor
    reg [31:0] prev_pc;
    initial prev_pc = 32'hFFFF_FFFF;

    always @(posedge clk) begin
        if (resetn && debug_pc !== prev_pc && debug_pc !== 32'h0) begin
            $display("[%0t] PC = 0x%08h", $time, debug_pc);
            prev_pc <= debug_pc;
        end
    end

    // Trap monitor
    always @(posedge debug_trap)
        $display("\n!!! CPU TRAP detected at PC = 0x%08h !!!\n", debug_pc);

    // Main test sequence
    initial begin
        $display("==============================================");
        $display("  Simple SoC Simulation");
        $display("  Tests: GPIO write + UART TX 'Hi!'");
        $display("==============================================\n");

        // Hold reset for 100 ns
        resetn = 1'b0;
        #100;
        resetn = 1'b1;
        $display("[%0t] Reset released - CPU running\n", $time);

        // Wait long enough for:
        //   - GPIO write  (~300 ns)
        //   - 3x UART bytes @ 10 bits x 8680 ns = ~260 000 ns
        //   Total with margin = 600 000 ns
        #600_000;

        // Report results 
        $display("\n==============================================");
        $display("  Results");
        $display("==============================================");

        if (gpio_out == 32'h0000_0001)
            $display("  PASS  GPIO : gpio_out = 0x%08h  (expected 0x00000001)", gpio_out);
        else
            $display("  FAIL  GPIO : gpio_out = 0x%08h  (expected 0x00000001)", gpio_out);

        if (!debug_trap)
            $display("  PASS  CPU  : no trap");
        else
            $display("  FAIL  CPU  : trap asserted - check waveform");

        $display("  INFO  UART : check lines above for 'H', 'i', '!'");
        $display("==============================================\n");

        #500;
        $finish;
    end

endmodule

/* OUTPUT:-
==============================================
  Results
==============================================
  PASS  GPIO : gpio_out = 0x00000001  (expected 0x00000001)
  PASS  CPU  : no trap
  INFO  UART : check lines above for 'H', 'i', '!'
==============================================
*/