`timescale 1ns / 1ps

//==============================================================================
// axi_crossbar.v
//
// Single-master AXI-Lite crossbar - routes one AXI-Lite master to N slaves
// by address decode on top nibble (matches existing memory map).
//
// Memory map (same as decoder.v):
//   0x0xxx_xxxx  →  Slave 0: BRAM
//   0x1xxx_xxxx  →  Slave 0: BRAM  (alias)
//   0x2xxx_xxxx  →  Slave 1: UART
//   0x3xxx_xxxx  →  Slave 2: GPIO
//   0x4xxx_xxxx  →  Slave 3: VPU accelerator (future)
//   others       →  error response (DECERR)
//
// AXI-Lite protocol:
//   Each channel has valid/ready handshake.
//   Transaction completes when both valid and ready are high same cycle.
//   Crossbar is combinational for address decode, registered for response mux.
//==============================================================================

module axi_crossbar #(
    parameter NUM_SLAVES = 4    // BRAM, UART, GPIO, VPU(future)
)(
    input  wire        clk,
    input  wire        resetn,

    // Master port (from picorv32_axi_adapter)
    // Write Address
    input  wire [31:0] s_axi_awaddr,
    input  wire        s_axi_awvalid,
    output wire        s_axi_awready,
    // Write Data
    input  wire [31:0] s_axi_wdata,
    input  wire [3:0]  s_axi_wstrb,
    input  wire        s_axi_wvalid,
    output wire        s_axi_wready,
    // Write Response
    output wire [1:0]  s_axi_bresp,
    output wire        s_axi_bvalid,
    input  wire        s_axi_bready,
    // Read Address
    input  wire [31:0] s_axi_araddr,
    input  wire        s_axi_arvalid,
    output wire        s_axi_arready,
    // Read Data
    output wire [31:0] s_axi_rdata,
    output wire [1:0]  s_axi_rresp,
    output wire        s_axi_rvalid,
    input  wire        s_axi_rready,

    // Slave 0: BRAM  (0x0000_0000 and 0x1000_0000)
    output wire [31:0] m0_axi_awaddr,  output wire m0_axi_awvalid,  input wire m0_axi_awready,
    output wire [31:0] m0_axi_wdata,   output wire [3:0] m0_axi_wstrb,
    output wire        m0_axi_wvalid,  input wire m0_axi_wready,
    input  wire [1:0]  m0_axi_bresp,   input wire m0_axi_bvalid,    output wire m0_axi_bready,
    output wire [31:0] m0_axi_araddr,  output wire m0_axi_arvalid,  input wire m0_axi_arready,
    input  wire [31:0] m0_axi_rdata,   input wire [1:0] m0_axi_rresp,
    input  wire        m0_axi_rvalid,  output wire m0_axi_rready,

    // Slave 1: UART  (0x2000_0000)
    output wire [31:0] m1_axi_awaddr,  output wire m1_axi_awvalid,  input wire m1_axi_awready,
    output wire [31:0] m1_axi_wdata,   output wire [3:0] m1_axi_wstrb,
    output wire        m1_axi_wvalid,  input wire m1_axi_wready,
    input  wire [1:0]  m1_axi_bresp,   input wire m1_axi_bvalid,    output wire m1_axi_bready,
    output wire [31:0] m1_axi_araddr,  output wire m1_axi_arvalid,  input wire m1_axi_arready,
    input  wire [31:0] m1_axi_rdata,   input wire [1:0] m1_axi_rresp,
    input  wire        m1_axi_rvalid,  output wire m1_axi_rready,

    // Slave 2: GPIO  (0x3000_0000)
    output wire [31:0] m2_axi_awaddr,  output wire m2_axi_awvalid,  input wire m2_axi_awready,
    output wire [31:0] m2_axi_wdata,   output wire [3:0] m2_axi_wstrb,
    output wire        m2_axi_wvalid,  input wire m2_axi_wready,
    input  wire [1:0]  m2_axi_bresp,   input wire m2_axi_bvalid,    output wire m2_axi_bready,
    output wire [31:0] m2_axi_araddr,  output wire m2_axi_arvalid,  input wire m2_axi_arready,
    input  wire [31:0] m2_axi_rdata,   input wire [1:0] m2_axi_rresp,
    input  wire        m2_axi_rvalid,  output wire m2_axi_rready,

    // Slave 3: VPU / future accelerator  (0x4000_0000)
    output wire [31:0] m3_axi_awaddr,  output wire m3_axi_awvalid,  input wire m3_axi_awready,
    output wire [31:0] m3_axi_wdata,   output wire [3:0] m3_axi_wstrb,
    output wire        m3_axi_wvalid,  input wire m3_axi_wready,
    input  wire [1:0]  m3_axi_bresp,   input wire m3_axi_bvalid,    output wire m3_axi_bready,
    output wire [31:0] m3_axi_araddr,  output wire m3_axi_arvalid,  input wire m3_axi_arready,
    input  wire [31:0] m3_axi_rdata,   input wire [1:0] m3_axi_rresp,
    input  wire        m3_axi_rvalid,  output wire m3_axi_rready
);

    // Address decode - combinational, uses current transaction address
    // Write channel uses AW address, read channel uses AR address
    wire [3:0] wr_top = s_axi_awaddr[31:28];
    wire [3:0] rd_top = s_axi_araddr[31:28];

    // Write slave select
    wire wr_sel0 = (wr_top == 4'h0) || (wr_top == 4'h1);  // BRAM
    wire wr_sel1 = (wr_top == 4'h2);                        // UART
    wire wr_sel2 = (wr_top == 4'h3);                        // GPIO
    wire wr_sel3 = (wr_top == 4'h4);                        // VPU
    wire wr_err  = !(wr_sel0 | wr_sel1 | wr_sel2 | wr_sel3);

    // Read slave select
    wire rd_sel0 = (rd_top == 4'h0) || (rd_top == 4'h1);
    wire rd_sel1 = (rd_top == 4'h2);
    wire rd_sel2 = (rd_top == 4'h3);
    wire rd_sel3 = (rd_top == 4'h4);
    wire rd_err  = !(rd_sel0 | rd_sel1 | rd_sel2 | rd_sel3);

    // Write Address (AW) channel - fan out to selected slave
    assign m0_axi_awaddr  = s_axi_awaddr;
    assign m0_axi_awvalid = s_axi_awvalid && wr_sel0;
    assign m1_axi_awaddr  = s_axi_awaddr;
    assign m1_axi_awvalid = s_axi_awvalid && wr_sel1;
    assign m2_axi_awaddr  = s_axi_awaddr;
    assign m2_axi_awvalid = s_axi_awvalid && wr_sel2;
    assign m3_axi_awaddr  = s_axi_awaddr;
    assign m3_axi_awvalid = s_axi_awvalid && wr_sel3;

    assign s_axi_awready = (wr_sel0 & m0_axi_awready) |
                           (wr_sel1 & m1_axi_awready) |
                           (wr_sel2 & m2_axi_awready) |
                           (wr_sel3 & m3_axi_awready) |
                           (wr_err  & s_axi_awvalid);  // error: accept immediately

    // Write Data (W) channel - fan out to selected slave
    assign m0_axi_wdata  = s_axi_wdata;
    assign m0_axi_wstrb  = s_axi_wstrb;
    assign m0_axi_wvalid = s_axi_wvalid && wr_sel0;
    assign m1_axi_wdata  = s_axi_wdata;
    assign m1_axi_wstrb  = s_axi_wstrb;
    assign m1_axi_wvalid = s_axi_wvalid && wr_sel1;
    assign m2_axi_wdata  = s_axi_wdata;
    assign m2_axi_wstrb  = s_axi_wstrb;
    assign m2_axi_wvalid = s_axi_wvalid && wr_sel2;
    assign m3_axi_wdata  = s_axi_wdata;
    assign m3_axi_wstrb  = s_axi_wstrb;
    assign m3_axi_wvalid = s_axi_wvalid && wr_sel3;

    assign s_axi_wready = (wr_sel0 & m0_axi_wready) |
                          (wr_sel1 & m1_axi_wready) |
                          (wr_sel2 & m2_axi_wready) |
                          (wr_sel3 & m3_axi_wready) |
                          (wr_err  & s_axi_wvalid);

    // Write Response (B) channel - mux from selected slave
    // Error response: DECERR (2'b11) for unmapped addresses
    // Latch which slave was selected at start of write (AW phase)
    reg [1:0] wr_slave_latch;
    reg       wr_err_latch;

    always @(posedge clk) begin
        if (!resetn) begin
            wr_slave_latch <= 0;
            wr_err_latch   <= 0;
        end else if (s_axi_awvalid && s_axi_awready) begin
            wr_slave_latch <= wr_sel1 ? 2'd1 :
                              wr_sel2 ? 2'd2 :
                              wr_sel3 ? 2'd3 : 2'd0;
            wr_err_latch   <= wr_err;
        end
    end

    assign s_axi_bresp  = wr_err_latch         ? 2'b11 :           // DECERR
                          (wr_slave_latch==2'd1) ? m1_axi_bresp :
                          (wr_slave_latch==2'd2) ? m2_axi_bresp :
                          (wr_slave_latch==2'd3) ? m3_axi_bresp :
                                                   m0_axi_bresp;

    assign s_axi_bvalid = wr_err_latch         ? 1'b1          :
                          (wr_slave_latch==2'd1) ? m1_axi_bvalid :
                          (wr_slave_latch==2'd2) ? m2_axi_bvalid :
                          (wr_slave_latch==2'd3) ? m3_axi_bvalid :
                                                   m0_axi_bvalid;

    assign m0_axi_bready = s_axi_bready && (wr_slave_latch==2'd0) && !wr_err_latch;
    assign m1_axi_bready = s_axi_bready && (wr_slave_latch==2'd1);
    assign m2_axi_bready = s_axi_bready && (wr_slave_latch==2'd2);
    assign m3_axi_bready = s_axi_bready && (wr_slave_latch==2'd3);

    // Read Address (AR) channel - fan out to selected slave
    assign m0_axi_araddr  = s_axi_araddr;
    assign m0_axi_arvalid = s_axi_arvalid && rd_sel0;
    assign m1_axi_araddr  = s_axi_araddr;
    assign m1_axi_arvalid = s_axi_arvalid && rd_sel1;
    assign m2_axi_araddr  = s_axi_araddr;
    assign m2_axi_arvalid = s_axi_arvalid && rd_sel2;
    assign m3_axi_araddr  = s_axi_araddr;
    assign m3_axi_arvalid = s_axi_arvalid && rd_sel3;

    assign s_axi_arready = (rd_sel0 & m0_axi_arready) |
                           (rd_sel1 & m1_axi_arready) |
                           (rd_sel2 & m2_axi_arready) |
                           (rd_sel3 & m3_axi_arready) |
                           (rd_err  & s_axi_arvalid);

    // Read Data (R) channel - mux from selected slave
    reg [1:0] rd_slave_latch;
    reg       rd_err_latch;

    always @(posedge clk) begin
        if (!resetn) begin
            rd_slave_latch <= 0;
            rd_err_latch   <= 0;
        end else if (s_axi_arvalid && s_axi_arready) begin
            rd_slave_latch <= rd_sel1 ? 2'd1 :
                              rd_sel2 ? 2'd2 :
                              rd_sel3 ? 2'd3 : 2'd0;
            rd_err_latch   <= rd_err;
        end
    end

    assign s_axi_rdata  = rd_err_latch         ? 32'hDEADDEAD  :
                          (rd_slave_latch==2'd1) ? m1_axi_rdata  :
                          (rd_slave_latch==2'd2) ? m2_axi_rdata  :
                          (rd_slave_latch==2'd3) ? m3_axi_rdata  :
                                                   m0_axi_rdata;

    assign s_axi_rresp  = rd_err_latch         ? 2'b11         :
                          (rd_slave_latch==2'd1) ? m1_axi_rresp  :
                          (rd_slave_latch==2'd2) ? m2_axi_rresp  :
                          (rd_slave_latch==2'd3) ? m3_axi_rresp  :
                                                   m0_axi_rresp;

    assign s_axi_rvalid = rd_err_latch         ? 1'b1          :
                          (rd_slave_latch==2'd1) ? m1_axi_rvalid :
                          (rd_slave_latch==2'd2) ? m2_axi_rvalid :
                          (rd_slave_latch==2'd3) ? m3_axi_rvalid :
                                                   m0_axi_rvalid;

    assign m0_axi_rready = s_axi_rready && (rd_slave_latch==2'd0) && !rd_err_latch;
    assign m1_axi_rready = s_axi_rready && (rd_slave_latch==2'd1);
    assign m2_axi_rready = s_axi_rready && (rd_slave_latch==2'd2);
    assign m3_axi_rready = s_axi_rready && (rd_slave_latch==2'd3);
endmodule