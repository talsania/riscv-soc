`timescale 1ns / 1ps

//==============================================================================
// uart_axi_slave.v
//
// AXI-Lite slave wrapper for UART TX peripheral.
// Wraps the proven uart_tx.v logic with an AXI-Lite interface.
//
// Address map (within 0x2000_0000 region):
//   offset 0x00  W  TX data   - write byte to transmit
//   offset 0x04  R  TX status - bit 0 = tx_busy
//
// BAUD_DIV: 434 = 115200 baud at 50 MHz (same as uart_tx.v)
//==============================================================================

module uart_axi_slave #(
    parameter BAUD_DIV = 434
)(
    input  wire        clk,
    input  wire        resetn,

    // AXI-Lite slave
    input  wire [31:0] s_axi_awaddr,
    input  wire        s_axi_awvalid,
    output reg         s_axi_awready,
    input  wire [31:0] s_axi_wdata,
    input  wire [3:0]  s_axi_wstrb,
    input  wire        s_axi_wvalid,
    output reg         s_axi_wready,
    output reg  [1:0]  s_axi_bresp,
    output reg         s_axi_bvalid,
    input  wire        s_axi_bready,
    input  wire [31:0] s_axi_araddr,
    input  wire        s_axi_arvalid,
    output reg         s_axi_arready,
    output reg  [31:0] s_axi_rdata,
    output reg  [1:0]  s_axi_rresp,
    output reg         s_axi_rvalid,
    input  wire        s_axi_rready,

    // UART TX pin
    output reg         uart_txd
);

    // Baud tick generator (identical to uart_tx.v)
    reg [$clog2(BAUD_DIV)-1:0] baud_cnt;
    reg baud_tick;

    always @(posedge clk) begin
        if (!resetn) begin
            baud_cnt  <= 0;
            baud_tick <= 0;
        end else begin
            baud_tick <= 0;
            if (baud_cnt == BAUD_DIV-1) begin
                baud_cnt  <= 0;
                baud_tick <= 1;
            end else
                baud_cnt <= baud_cnt + 1;
        end
    end

    // TX state machine (identical logic to uart_tx.v, same merged block fix)
    localparam IDLE  = 2'd0;
    localparam START = 2'd1;
    localparam DATA  = 2'd2;
    localparam STOP  = 2'd3;

    reg [1:0] tx_state;
    reg [7:0] tx_data;
    reg [2:0] bit_idx;
    reg       tx_busy;

    // Write path buffers
    reg        aw_captured;
    reg [31:0] aw_addr_buf;
    reg        w_captured;
    reg [31:0] w_data_buf;
    reg [3:0]  w_strb_buf;

    always @(posedge clk) begin
        if (!resetn) begin
            tx_state      <= IDLE;
            tx_data       <= 0;
            bit_idx       <= 0;
            tx_busy       <= 0;
            uart_txd      <= 1;
            s_axi_awready <= 0; s_axi_wready <= 0;
            s_axi_bvalid  <= 0; s_axi_bresp  <= 0;
            aw_captured   <= 0; w_captured   <= 0;
        end else begin
            s_axi_awready <= 0;
            s_axi_wready  <= 0;

            // TX state machine (merged - single driver for all TX registers)
            case (tx_state)
                IDLE:  begin uart_txd <= 1; tx_busy <= 0; end
                START: if (baud_tick) begin
                           uart_txd <= 0; bit_idx <= 0; tx_state <= DATA;
                       end
                DATA:  if (baud_tick) begin
                           uart_txd <= tx_data[bit_idx];
                           if (bit_idx == 7) tx_state <= STOP;
                           else bit_idx <= bit_idx + 1;
                       end
                STOP:  if (baud_tick) begin
                           uart_txd <= 1; tx_busy <= 0; tx_state <= IDLE;
                           $display("[%0t] UART TX sent: 0x%02h ('%c')",
                               $time, tx_data,
                               (tx_data>=32 && tx_data<127) ? tx_data : 8'h2E);
                       end
            endcase

            // AXI Write - capture AW and W, then act when both ready
            if (s_axi_awvalid && !aw_captured) begin
                s_axi_awready <= 1;
                aw_addr_buf   <= s_axi_awaddr;
                aw_captured   <= 1;
            end

            if (s_axi_wvalid && !w_captured) begin
                s_axi_wready <= 1;
                w_data_buf   <= s_axi_wdata;
                w_strb_buf   <= s_axi_wstrb;
                w_captured   <= 1;
            end

            if (aw_captured && w_captured && !s_axi_bvalid) begin
                // offset 0x00 - TX data register
                if (aw_addr_buf[3:0] == 4'h0) begin
                    if (!tx_busy) begin
                        tx_data  <= w_data_buf[7:0];
                        tx_busy  <= 1;
                        tx_state <= START;
                        $display("[%0t] UART MMIO: wrote 0x%02h ('%c')",
                            $time, w_data_buf[7:0],
                            (w_data_buf[7:0]>=32 && w_data_buf[7:0]<127)
                                ? w_data_buf[7:0] : 8'h2E);
                    end else
                        $display("[%0t] UART MMIO: BUSY - byte dropped!", $time);
                end
                // offset 0x04 - status register (read-only, ignore writes)
                s_axi_bvalid <= 1;
                s_axi_bresp  <= 2'b00;
                aw_captured  <= 0;
                w_captured   <= 0;
            end

            if (s_axi_bvalid && s_axi_bready)
                s_axi_bvalid <= 0;
        end
    end

    // AXI Read - status register at offset 0x04
    always @(posedge clk) begin
        if (!resetn) begin
            s_axi_arready <= 0;
            s_axi_rvalid  <= 0;
            s_axi_rdata   <= 0;
            s_axi_rresp   <= 0;
        end else begin
            s_axi_arready <= 0;
            if (s_axi_arvalid && !s_axi_rvalid) begin
                s_axi_arready <= 1;
                s_axi_rresp   <= 2'b00;
                s_axi_rvalid  <= 1;
                // offset 0x04 = status (tx_busy), anything else = 0
                s_axi_rdata <= (s_axi_araddr[3:0] == 4'h4) ?
                                {31'h0, tx_busy} : 32'h0;
            end
            if (s_axi_rvalid && s_axi_rready)
                s_axi_rvalid <= 0;
        end
    end

endmodule