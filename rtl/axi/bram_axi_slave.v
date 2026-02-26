`timescale 1ns / 1ps

//==============================================================================
// bram_axi_slave.v
//
// AXI-Lite slave wrapper around existing bram.v logic.
// Internal memory is identical - 4KB, $readmemh loaded.
// Interface replaces custom valid/ready with AXI-Lite channels.
//
// Read latency: 1 cycle (BRAM registered output)
// Write latency: 1 cycle
//==============================================================================

module bram_axi_slave #(
    parameter MEM_SIZE  = 1024                           // words (4KB)
)(
    input  wire        clk,
    input  wire        resetn,

    // AXI-Lite slave interface
    // Write Address
    input  wire [31:0] s_axi_awaddr,
    input  wire        s_axi_awvalid,
    output reg         s_axi_awready,
    // Write Data
    input  wire [31:0] s_axi_wdata,
    input  wire [3:0]  s_axi_wstrb,
    input  wire        s_axi_wvalid,
    output reg         s_axi_wready,
    // Write Response
    output reg  [1:0]  s_axi_bresp,
    output reg         s_axi_bvalid,
    input  wire        s_axi_bready,
    // Read Address
    input  wire [31:0] s_axi_araddr,
    input  wire        s_axi_arvalid,
    output reg         s_axi_arready,
    // Read Data
    output reg  [31:0] s_axi_rdata,
    output reg  [1:0]  s_axi_rresp,
    output reg         s_axi_rvalid,
    input  wire        s_axi_rready
);

    // Memory
    reg [31:0] memory [0:MEM_SIZE-1];

    wire [9:0] wr_word_addr = s_axi_awaddr[11:2];
    wire [9:0] rd_word_addr = s_axi_araddr[11:2];

    integer i;
    initial begin
        for (i = 0; i < MEM_SIZE; i = i + 1)
            memory[i] = 32'h00000013;   // NOP
        $readmemh("C:/Users/Krishang/Desktop/riscv-soc/firmware/firmware.hex", memory);
        $display("[BRAM-AXI] Loaded firmware.hex");
    end

    // Write path
    // AW and W channels must both arrive before we write and send B response.
    // Buffer whichever arrives first.
    reg        aw_captured;
    reg [31:0] aw_addr_buf;
    reg        w_captured;
    reg [31:0] w_data_buf;
    reg [3:0]  w_strb_buf;

    always @(posedge clk) begin
        if (!resetn) begin
            s_axi_awready <= 0;
            s_axi_wready  <= 0;
            s_axi_bvalid  <= 0;
            s_axi_bresp   <= 0;
            aw_captured   <= 0;
            w_captured    <= 0;
        end else begin
            // Default deassert
            s_axi_awready <= 0;
            s_axi_wready  <= 0;

            // Accept AW
            if (s_axi_awvalid && !aw_captured) begin
                s_axi_awready <= 1;
                aw_addr_buf   <= s_axi_awaddr;
                aw_captured   <= 1;
            end

            // Accept W
            if (s_axi_wvalid && !w_captured) begin
                s_axi_wready <= 1;
                w_data_buf   <= s_axi_wdata;
                w_strb_buf   <= s_axi_wstrb;
                w_captured   <= 1;
            end

            // Both arrived - do the write, send B response
            if (aw_captured && w_captured && !s_axi_bvalid) begin
                if (w_strb_buf[0]) memory[aw_addr_buf[11:2]][ 7: 0] <= w_data_buf[ 7: 0];
                if (w_strb_buf[1]) memory[aw_addr_buf[11:2]][15: 8] <= w_data_buf[15: 8];
                if (w_strb_buf[2]) memory[aw_addr_buf[11:2]][23:16] <= w_data_buf[23:16];
                if (w_strb_buf[3]) memory[aw_addr_buf[11:2]][31:24] <= w_data_buf[31:24];
                s_axi_bvalid  <= 1;
                s_axi_bresp   <= 2'b00;  // OKAY
                aw_captured   <= 0;
                w_captured    <= 0;
            end

            // B handshake complete
            if (s_axi_bvalid && s_axi_bready) begin
                s_axi_bvalid <= 0;
            end
        end
    end

    // Read path - 1 cycle latency (registered BRAM read)
    always @(posedge clk) begin
        if (!resetn) begin
            s_axi_arready <= 0;
            s_axi_rvalid  <= 0;
            s_axi_rresp   <= 0;
            s_axi_rdata   <= 0;
        end else begin
            s_axi_arready <= 0;

            // Accept AR, read memory, present R next cycle
            if (s_axi_arvalid && !s_axi_rvalid) begin
                s_axi_arready <= 1;
                s_axi_rdata   <= memory[s_axi_araddr[11:2]];
                s_axi_rresp   <= 2'b00;
                s_axi_rvalid  <= 1;
            end

            // R handshake complete
            if (s_axi_rvalid && s_axi_rready) begin
                s_axi_rvalid <= 0;
            end
        end
    end
endmodule