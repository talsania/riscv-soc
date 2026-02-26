`timescale 1ns / 1ps

//==============================================================================
// top_axi.v  -  PicoRV32 SoC with AXI-Lite bus
//
// Uses picorv32_axi_adapter from picorv32.v (line 2727) directly.
// picorv32_axi_adapter.v is NOT needed - delete it from the project.
//
// Hierarchy:
//   top_axi
//   ├── picorv32                 CPU (native valid/ready)
//   ├── picorv32_axi_adapter     built-in adapter from picorv32.v
//   ├── axi_crossbar             routes to 4 slaves by addr[31:28]
//   ├── bram_axi_slave           Slave 0: BRAM  0x0000_0000
//   ├── uart_axi_slave           Slave 1: UART  0x2000_0000
//   ├── gpio_axi_slave           Slave 2: GPIO  0x3000_0000
//   └── (Slave 3 tied off)       VPU placeholder 0x4000_0000
//
// awprot / arprot from the adapter are ignored (not used in AXI-Lite slaves).
//==============================================================================

module top_axi (
    input  wire        clk,
    input  wire        resetn,
    output wire [31:0] gpio_out,
    output wire        uart_txd,
    output wire [31:0] debug_pc,
    output wire        debug_trap
);

    // CPU native interface
    wire        mem_valid, mem_instr, mem_ready;
    wire [31:0] mem_addr, mem_wdata, mem_rdata;
    wire [3:0]  mem_wstrb;
    wire        trap;
    assign debug_trap = trap;

    reg [31:0] pc_latch;
    always @(posedge clk) begin
        if (!resetn)                     pc_latch <= 0;
        else if (mem_valid && mem_instr) pc_latch <= mem_addr;
    end
    assign debug_pc = pc_latch;

    // AXI-Lite master bus (adapter → crossbar)
    wire        m_awvalid; wire        m_awready; wire [31:0] m_awaddr;
    wire        m_wvalid;  wire        m_wready;
    wire [31:0] m_wdata;   wire [3:0]  m_wstrb;
    wire        m_bvalid;  wire        m_bready;
    wire [1:0]  m_bresp_nc;  // bresp - adapter doesn't check value
    wire        m_arvalid; wire        m_arready; wire [31:0] m_araddr;
    wire        m_rvalid;  wire        m_rready;
    wire [31:0] m_rdata;   wire [1:0]  m_rresp;
    // awprot / arprot from adapter - unused, left open
    wire [2:0]  m_awprot, m_arprot;
    // bresp not driven by adapter - crossbar drives it back through bvalid
    // (adapter only checks bvalid, not bresp value)

    // Slave buses (crossbar → slaves)
    // Slave 0: BRAM
    wire [31:0] s0_awaddr; wire s0_awvalid, s0_awready;
    wire [31:0] s0_wdata;  wire [3:0] s0_wstrb; wire s0_wvalid, s0_wready;
    wire [1:0]  s0_bresp;  wire s0_bvalid, s0_bready;
    wire [31:0] s0_araddr; wire s0_arvalid, s0_arready;
    wire [31:0] s0_rdata;  wire [1:0] s0_rresp; wire s0_rvalid, s0_rready;

    // Slave 1: UART
    wire [31:0] s1_awaddr; wire s1_awvalid, s1_awready;
    wire [31:0] s1_wdata;  wire [3:0] s1_wstrb; wire s1_wvalid, s1_wready;
    wire [1:0]  s1_bresp;  wire s1_bvalid, s1_bready;
    wire [31:0] s1_araddr; wire s1_arvalid, s1_arready;
    wire [31:0] s1_rdata;  wire [1:0] s1_rresp; wire s1_rvalid, s1_rready;

    // Slave 2: GPIO
    wire [31:0] s2_awaddr; wire s2_awvalid, s2_awready;
    wire [31:0] s2_wdata;  wire [3:0] s2_wstrb; wire s2_wvalid, s2_wready;
    wire [1:0]  s2_bresp;  wire s2_bvalid, s2_bready;
    wire [31:0] s2_araddr; wire s2_arvalid, s2_arready;
    wire [31:0] s2_rdata;  wire [1:0] s2_rresp; wire s2_rvalid, s2_rready;

    // Slave 3: VPU placeholder - tied off, returns OKAY immediately
    wire [31:0] s3_awaddr; wire s3_awvalid, s3_awready;
    wire [31:0] s3_wdata;  wire [3:0] s3_wstrb; wire s3_wvalid, s3_wready;
    wire [1:0]  s3_bresp;  wire s3_bvalid, s3_bready;
    wire [31:0] s3_araddr; wire s3_arvalid, s3_arready;
    wire [31:0] s3_rdata;  wire [1:0] s3_rresp; wire s3_rvalid, s3_rready;

    assign s3_awready = s3_awvalid;
    assign s3_wready  = s3_wvalid;
    assign s3_bresp   = 2'b00;
    assign s3_bvalid  = s3_awvalid & s3_wvalid;
    assign s3_arready = s3_arvalid;
    assign s3_rdata   = 32'hDEADBEEF;
    assign s3_rresp   = 2'b00;
    assign s3_rvalid  = s3_arvalid;

    // PicoRV32 CPU
    picorv32 #(
        .ENABLE_COUNTERS    (0), .ENABLE_COUNTERS64  (0),
        .ENABLE_REGS_16_31  (1), .ENABLE_REGS_DUALPORT(0),
        .LATCHED_MEM_RDATA  (0), .TWO_STAGE_SHIFT    (0),
        .BARREL_SHIFTER     (0), .TWO_CYCLE_COMPARE  (0),
        .TWO_CYCLE_ALU      (0), .CATCH_MISALIGN     (0),
        .CATCH_ILLINSN      (0), .COMPRESSED_ISA     (0),
        .ENABLE_PCPI        (0), .ENABLE_MUL         (0),
        .ENABLE_FAST_MUL    (0), .ENABLE_DIV         (0),
        .ENABLE_IRQ         (0), .ENABLE_TRACE       (0)
    ) cpu (
        .clk(clk), .resetn(resetn), .trap(trap),
        .mem_valid(mem_valid), .mem_instr(mem_instr), .mem_ready(mem_ready),
        .mem_addr(mem_addr),   .mem_wdata(mem_wdata), .mem_wstrb(mem_wstrb),
        .mem_rdata(mem_rdata),
        .mem_la_read(), .mem_la_write(), .mem_la_addr(),
        .mem_la_wdata(), .mem_la_wstrb(),
        .pcpi_valid(), .pcpi_insn(), .pcpi_rs1(), .pcpi_rs2(),
        .pcpi_wr(0), .pcpi_rd(0), .pcpi_wait(0), .pcpi_ready(0),
        .irq(32'h0), .eoi(), .trace_valid(), .trace_data()
    );

    // Built-in PicoRV32 AXI adapter (from picorv32.v line 2727)
    // Connects CPU native interface → AXI-Lite master signals
    picorv32_axi_adapter adapter (
        .clk            (clk),
        .resetn         (resetn),
        // Native CPU side
        .mem_valid      (mem_valid),
        .mem_instr      (mem_instr),
        .mem_ready      (mem_ready),
        .mem_addr       (mem_addr),
        .mem_wdata      (mem_wdata),
        .mem_wstrb      (mem_wstrb),
        .mem_rdata      (mem_rdata),
        // AXI-Lite master side
        .mem_axi_awvalid(m_awvalid),
        .mem_axi_awready(m_awready),
        .mem_axi_awaddr (m_awaddr),
        .mem_axi_awprot (m_awprot),   // unused by crossbar, left open
        .mem_axi_wvalid (m_wvalid),
        .mem_axi_wready (m_wready),
        .mem_axi_wdata  (m_wdata),
        .mem_axi_wstrb  (m_wstrb),
        .mem_axi_bvalid (m_bvalid),
        .mem_axi_bready (m_bready),
        .mem_axi_arvalid(m_arvalid),
        .mem_axi_arready(m_arready),
        .mem_axi_araddr (m_araddr),
        .mem_axi_arprot (m_arprot),   // unused by crossbar, left open
        .mem_axi_rvalid (m_rvalid),
        .mem_axi_rready (m_rready),
        .mem_axi_rdata  (m_rdata)
    );

    // AXI-Lite Crossbar
    axi_crossbar crossbar (
        .clk(clk), .resetn(resetn),
        // Master (from adapter)
        .s_axi_awaddr(m_awaddr), .s_axi_awvalid(m_awvalid), .s_axi_awready(m_awready),
        .s_axi_wdata (m_wdata),  .s_axi_wstrb  (m_wstrb),
        .s_axi_wvalid(m_wvalid), .s_axi_wready (m_wready),
        .s_axi_bresp (m_bresp_nc), // adapter doesn't use bresp value
        .s_axi_bvalid(m_bvalid), .s_axi_bready (m_bready),
        .s_axi_araddr(m_araddr), .s_axi_arvalid(m_arvalid), .s_axi_arready(m_arready),
        .s_axi_rdata (m_rdata),  .s_axi_rresp  (m_rresp),
        .s_axi_rvalid(m_rvalid), .s_axi_rready (m_rready),
        // Slave 0: BRAM
        .m0_axi_awaddr(s0_awaddr),.m0_axi_awvalid(s0_awvalid),.m0_axi_awready(s0_awready),
        .m0_axi_wdata (s0_wdata), .m0_axi_wstrb (s0_wstrb),
        .m0_axi_wvalid(s0_wvalid),.m0_axi_wready(s0_wready),
        .m0_axi_bresp (s0_bresp), .m0_axi_bvalid(s0_bvalid), .m0_axi_bready(s0_bready),
        .m0_axi_araddr(s0_araddr),.m0_axi_arvalid(s0_arvalid),.m0_axi_arready(s0_arready),
        .m0_axi_rdata (s0_rdata), .m0_axi_rresp (s0_rresp),
        .m0_axi_rvalid(s0_rvalid),.m0_axi_rready(s0_rready),
        // Slave 1: UART
        .m1_axi_awaddr(s1_awaddr),.m1_axi_awvalid(s1_awvalid),.m1_axi_awready(s1_awready),
        .m1_axi_wdata (s1_wdata), .m1_axi_wstrb (s1_wstrb),
        .m1_axi_wvalid(s1_wvalid),.m1_axi_wready(s1_wready),
        .m1_axi_bresp (s1_bresp), .m1_axi_bvalid(s1_bvalid), .m1_axi_bready(s1_bready),
        .m1_axi_araddr(s1_araddr),.m1_axi_arvalid(s1_arvalid),.m1_axi_arready(s1_arready),
        .m1_axi_rdata (s1_rdata), .m1_axi_rresp (s1_rresp),
        .m1_axi_rvalid(s1_rvalid),.m1_axi_rready(s1_rready),
        // Slave 2: GPIO
        .m2_axi_awaddr(s2_awaddr),.m2_axi_awvalid(s2_awvalid),.m2_axi_awready(s2_awready),
        .m2_axi_wdata (s2_wdata), .m2_axi_wstrb (s2_wstrb),
        .m2_axi_wvalid(s2_wvalid),.m2_axi_wready(s2_wready),
        .m2_axi_bresp (s2_bresp), .m2_axi_bvalid(s2_bvalid), .m2_axi_bready(s2_bready),
        .m2_axi_araddr(s2_araddr),.m2_axi_arvalid(s2_arvalid),.m2_axi_arready(s2_arready),
        .m2_axi_rdata (s2_rdata), .m2_axi_rresp (s2_rresp),
        .m2_axi_rvalid(s2_rvalid),.m2_axi_rready(s2_rready),
        // Slave 3: VPU (tied off)
        .m3_axi_awaddr(s3_awaddr),.m3_axi_awvalid(s3_awvalid),.m3_axi_awready(s3_awready),
        .m3_axi_wdata (s3_wdata), .m3_axi_wstrb (s3_wstrb),
        .m3_axi_wvalid(s3_wvalid),.m3_axi_wready(s3_wready),
        .m3_axi_bresp (s3_bresp), .m3_axi_bvalid(s3_bvalid), .m3_axi_bready(s3_bready),
        .m3_axi_araddr(s3_araddr),.m3_axi_arvalid(s3_arvalid),.m3_axi_arready(s3_arready),
        .m3_axi_rdata (s3_rdata), .m3_axi_rresp (s3_rresp),
        .m3_axi_rvalid(s3_rvalid),.m3_axi_rready(s3_rready)
    );

    // Slave 0: BRAM
    bram_axi_slave bram_inst (
        .clk(clk), .resetn(resetn),
        .s_axi_awaddr(s0_awaddr), .s_axi_awvalid(s0_awvalid), .s_axi_awready(s0_awready),
        .s_axi_wdata (s0_wdata),  .s_axi_wstrb  (s0_wstrb),
        .s_axi_wvalid(s0_wvalid), .s_axi_wready (s0_wready),
        .s_axi_bresp (s0_bresp),  .s_axi_bvalid (s0_bvalid),  .s_axi_bready(s0_bready),
        .s_axi_araddr(s0_araddr), .s_axi_arvalid(s0_arvalid), .s_axi_arready(s0_arready),
        .s_axi_rdata (s0_rdata),  .s_axi_rresp  (s0_rresp),
        .s_axi_rvalid(s0_rvalid), .s_axi_rready (s0_rready)
    );

    // Slave 1: UART
    uart_axi_slave #(.BAUD_DIV(434)) uart_inst (
        .clk(clk), .resetn(resetn),
        .s_axi_awaddr(s1_awaddr), .s_axi_awvalid(s1_awvalid), .s_axi_awready(s1_awready),
        .s_axi_wdata (s1_wdata),  .s_axi_wstrb  (s1_wstrb),
        .s_axi_wvalid(s1_wvalid), .s_axi_wready (s1_wready),
        .s_axi_bresp (s1_bresp),  .s_axi_bvalid (s1_bvalid),  .s_axi_bready(s1_bready),
        .s_axi_araddr(s1_araddr), .s_axi_arvalid(s1_arvalid), .s_axi_arready(s1_arready),
        .s_axi_rdata (s1_rdata),  .s_axi_rresp  (s1_rresp),
        .s_axi_rvalid(s1_rvalid), .s_axi_rready (s1_rready),
        .uart_txd(uart_txd)
    );

    // Slave 2: GPIO
    gpio_axi_slave gpio_inst (
        .clk(clk), .resetn(resetn),
        .s_axi_awaddr(s2_awaddr), .s_axi_awvalid(s2_awvalid), .s_axi_awready(s2_awready),
        .s_axi_wdata (s2_wdata),  .s_axi_wstrb  (s2_wstrb),
        .s_axi_wvalid(s2_wvalid), .s_axi_wready (s2_wready),
        .s_axi_bresp (s2_bresp),  .s_axi_bvalid (s2_bvalid),  .s_axi_bready(s2_bready),
        .s_axi_araddr(s2_araddr), .s_axi_arvalid(s2_arvalid), .s_axi_arready(s2_arready),
        .s_axi_rdata (s2_rdata),  .s_axi_rresp  (s2_rresp),
        .s_axi_rvalid(s2_rvalid), .s_axi_rready (s2_rready),
        .gpio_out(gpio_out)
    );
endmodule