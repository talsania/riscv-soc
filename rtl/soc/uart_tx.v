`timescale 1ns / 1ps

//==============================================================================
// uart_tx.v: UART TX Peripheral (Memory-Mapped)
//
// Fix: merged MMIO handler and TX state machine into ONE always block.
//      Previously two separate blocks both wrote tx_state/tx_busy/tx_data,
//      causing a race where a new CPU write would reset tx_state=START mid-
//      transmission, locking bit_idx at 1 forever in DATA state.
//
// Address map:
//   0x20000000  W  TX data: write byte to transmit
//   0x20000004  R  TX status: bit 0 = tx_busy (1=transmitting)
//
// Frame: 8N1  |  Baud: clk / BAUD_DIV  (434 = 115200 @ 50MHz)
//==============================================================================

module uart_tx #(
    parameter BAUD_DIV = 434
)(
    input  wire        clk,
    input  wire        resetn,
    // Memory-mapped interface
    input  wire        uart_valid,
    input  wire        uart_we,
    input  wire [31:0] uart_addr,
    input  wire [7:0]  uart_wdata,
    output reg  [31:0] uart_rdata,
    output reg         uart_ready,
    // Physical pin
    output reg         uart_txd
);

    // Baud tick generator
    reg [$clog2(BAUD_DIV)-1:0] baud_cnt;
    reg baud_tick;

    always @(posedge clk) begin
        if (!resetn) begin
            baud_cnt  <= 0;
            baud_tick <= 0;
        end else begin
            baud_tick <= 0;
            if (baud_cnt == BAUD_DIV - 1) begin
                baud_cnt  <= 0;
                baud_tick <= 1;
            end else
                baud_cnt <= baud_cnt + 1;
        end
    end

    // TX state machine + MMIO - ONE block, no register conflicts
    localparam IDLE  = 2'd0;
    localparam START = 2'd1;
    localparam DATA  = 2'd2;
    localparam STOP  = 2'd3;

    reg [1:0] tx_state;
    reg [7:0] tx_data;
    reg [2:0] bit_idx;
    reg       tx_busy;

    always @(posedge clk) begin
        if (!resetn) begin
            tx_state   <= IDLE;
            tx_data    <= 8'h00;
            bit_idx    <= 0;
            tx_busy    <= 1'b0;
            uart_txd   <= 1'b1;
            uart_ready <= 1'b0;
            uart_rdata <= 32'h0;
        end else begin

            // Default: ready is a one-cycle pulse
            uart_ready <= 1'b0;

            // TX state machine
            case (tx_state)
                IDLE: begin
                    uart_txd <= 1'b1;
                    tx_busy  <= 1'b0;
                end

                START: begin
                    if (baud_tick) begin
                        uart_txd <= 1'b0;       // start bit LOW
                        bit_idx  <= 0;
                        tx_state <= DATA;
                    end
                end

                DATA: begin
                    if (baud_tick) begin
                        uart_txd <= tx_data[bit_idx];
                        if (bit_idx == 7)
                            tx_state <= STOP;
                        else
                            bit_idx <= bit_idx + 1;
                    end
                end

                STOP: begin
                    if (baud_tick) begin
                        uart_txd <= 1'b1;       // stop bit HIGH
                        tx_busy  <= 1'b0;
                        tx_state <= IDLE;
                        $display("[%0t] UART TX sent: 0x%02h ('%c')",
                                 $time, tx_data,
                                 (tx_data >= 32 && tx_data < 127) ? tx_data : 8'h2E);
                    end
                end
            endcase

            // MMIO handshake - only acts when TX is IDLE (tx_busy=0)
            // CPU polling tx_busy ensures it never writes while busy,
            // but we guard here too for safety.
            if (uart_valid && !uart_ready) begin
                if (uart_we) begin
                    // Write: 0x20000000 - load byte and start TX
                    if (!tx_busy) begin
                        tx_data  <= uart_wdata;
                        tx_busy  <= 1'b1;
                        tx_state <= START;
                        $display("[%0t] UART MMIO: wrote 0x%02h ('%c')",
                                 $time, uart_wdata,
                                 (uart_wdata >= 32 && uart_wdata < 127) ? uart_wdata : 8'h2E);
                    end else begin
                        $display("[%0t] UART MMIO: BUSY - byte 0x%02h dropped!", $time, uart_wdata);
                    end
                end else begin
                    // Read: 0x20000004 - return tx_busy status
                    uart_rdata <= {31'h0, tx_busy};
                end
                uart_ready <= 1'b1;
            end

        end
    end

endmodule