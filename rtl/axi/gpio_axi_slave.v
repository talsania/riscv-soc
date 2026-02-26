`timescale 1ns / 1ps

//==============================================================================
// gpio_axi_slave.v
//
// AXI-Lite slave wrapper for GPIO peripheral.
// Single 32-bit register at offset 0x0 within the 0x3000_0000 region.
// Read returns current gpio_out value.
// Write updates gpio_out.
//==============================================================================

module gpio_axi_slave (
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

    // GPIO output pin
    output reg  [31:0] gpio_out
);

    reg        aw_captured;
    reg [31:0] aw_addr_buf;
    reg        w_captured;
    reg [31:0] w_data_buf;
    reg [3:0]  w_strb_buf;

    // Write path
    always @(posedge clk) begin
        if (!resetn) begin
            gpio_out      <= 32'h0;
            s_axi_awready <= 0; s_axi_wready <= 0;
            s_axi_bvalid  <= 0; s_axi_bresp  <= 0;
            aw_captured   <= 0; w_captured   <= 0;
        end else begin
            s_axi_awready <= 0;
            s_axi_wready  <= 0;

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
                // Byte-enable masked write to gpio_out register
                if (w_strb_buf[0]) gpio_out[ 7: 0] <= w_data_buf[ 7: 0];
                if (w_strb_buf[1]) gpio_out[15: 8] <= w_data_buf[15: 8];
                if (w_strb_buf[2]) gpio_out[23:16] <= w_data_buf[23:16];
                if (w_strb_buf[3]) gpio_out[31:24] <= w_data_buf[31:24];
                $display("[%0t] GPIO WRITE: 0x%08h", $time, w_data_buf);
                s_axi_bvalid <= 1;
                s_axi_bresp  <= 2'b00;
                aw_captured  <= 0;
                w_captured   <= 0;
            end

            if (s_axi_bvalid && s_axi_bready)
                s_axi_bvalid <= 0;
        end
    end

    // Read path - returns gpio_out
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
                s_axi_rdata   <= gpio_out;
                s_axi_rresp   <= 2'b00;
                s_axi_rvalid  <= 1;
            end
            if (s_axi_rvalid && s_axi_rready)
                s_axi_rvalid <= 0;
        end
    end
endmodule