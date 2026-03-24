`timescale 1ns / 1ps

//==============================================================================
// tb_top.v  -  Testbench for top_axi (AXI-Lite bus SoC)
//
// Tests: GPIO write, UART TX, dot product accelerator, no CPU trap
// UART:  115200 baud, 8N1 - BIT_NS = 434 * 20ns = 8680ns
// Sim:   30ms total
//==============================================================================

module tb_top();
    localparam CLK_PERIOD = 20;
    localparam BIT_NS     = 434 * CLK_PERIOD;

    reg  clk    = 0;
    reg  resetn = 0;

    wire [31:0] gpio_out;
    wire        uart_txd;
    wire [31:0] debug_pc;
    wire        debug_trap;

    top_axi soc (
        .clk       (clk),
        .resetn    (resetn),
        .gpio_out  (gpio_out),
        .uart_txd  (uart_txd),
        .debug_pc  (debug_pc),
        .debug_trap(debug_trap)
    );

    always #(CLK_PERIOD/2) clk = ~clk;

    // UART RX monitor
    reg [7:0] rx_byte;
    integer   rx_bit;
    initial begin rx_byte = 0; rx_bit = 0; end

    always @(negedge uart_txd) begin
        #(BIT_NS + BIT_NS/2);
        rx_byte = 8'h00;
        for (rx_bit = 0; rx_bit < 8; rx_bit = rx_bit + 1) begin
            rx_byte[rx_bit] = uart_txd;
            if (rx_bit < 7) #(BIT_NS);
        end
        $display("[%0t ns] UART RX: '%c'  (0x%02h)",
                 $time, (rx_byte >= 32 && rx_byte < 127) ? rx_byte : 8'h2E, rx_byte);
    end

    // GPIO monitor
    reg [31:0] prev_gpio = 32'hFFFF_FFFF;
    always @(gpio_out) begin
        $display("[%0t ns] GPIO: 0x%08h -> 0x%08h", $time, prev_gpio, gpio_out);
        prev_gpio = gpio_out;
    end

    // Trap monitor
    always @(posedge debug_trap)
        $display("\n!!! CPU TRAP at PC=0x%08h !!!\n", debug_pc);

    // AXI bus monitor
    always @(posedge clk) begin
        if (soc.m_awvalid && soc.m_awready)
            $display("[%0t ns] AXI-AW: addr=0x%08h", $time, soc.m_awaddr);
        if (soc.m_wvalid && soc.m_wready)
            $display("[%0t ns] AXI-W : data=0x%08h strb=%04b", $time, soc.m_wdata, soc.m_wstrb);
        if (soc.m_bvalid && soc.m_bready)
            $display("[%0t ns] AXI-B : resp=%02b", $time, soc.m_bresp_nc);
        if (soc.m_arvalid && soc.m_arready)
            $display("[%0t ns] AXI-AR: addr=0x%08h", $time, soc.m_araddr);
        if (soc.m_rvalid && soc.m_rready)
            $display("[%0t ns] AXI-R : data=0x%08h resp=%02b", $time, soc.m_rdata, soc.m_rresp);
    end

    // Accelerator-specific monitor - filters transactions to 0x4000_xxxx
    always @(posedge clk) begin
        if (soc.m_awvalid && soc.m_awready && soc.m_awaddr[31:28] == 4'h4)
            $display("[%0t ns] ACCEL-W: addr=0x%08h data=0x%08h",
                     $time, soc.m_awaddr, soc.m_wdata);
        if (soc.m_arvalid && soc.m_arready && soc.m_araddr[31:28] == 4'h4)
            $display("[%0t ns] ACCEL-R: addr=0x%08h", $time, soc.m_araddr);
        if (soc.m_rvalid && soc.m_rready && soc.m_araddr[31:28] == 4'h4)
            $display("[%0t ns] ACCEL-RESULT: data=0x%08h", $time, soc.m_rdata);
    end

    // Main sequence
    integer gpio_ok   = 0;
    integer accel_ok  = 0;

    initial begin
        $display("==============================================");
        $display("  PicoRV32 AXI-Lite SoC Simulation");
        $display("  UART: 115200 baud  |  BRAM: 4KB");
        $display("  Accel: dot_product @ 0x4000_0000");
        $display("==============================================\n");

        resetn = 0;
        #100;
        resetn = 1;
        $display("[%0t ns] Reset released\n", $time);

        // Wait 500us for gpio_write(1)
        #500_000;
        gpio_ok = (gpio_out == 32'h0000_0001);

        // Wait remainder - covers UART output and accelerator run
        #29_500_000;

        $display("\n==============================================");
        $display("  Results");
        $display("==============================================");

        if (gpio_ok)
            $display("  PASS  GPIO  : 0x00000001 seen within 500 us");
        else
            $display("  FAIL  GPIO  : gpio_out = 0x%08h at 500 us", gpio_out);

        if (!debug_trap)
            $display("  PASS  CPU   : no trap");
        else
            $display("  FAIL  CPU   : trap asserted");

        $display("  INFO  ACCEL : see ACCEL-W/ACCEL-R/ACCEL-RESULT above");
        $display("  INFO  UART  : see decoded bytes above");
        $display("==============================================\n");

        #500;
        $finish;
    end

endmodule