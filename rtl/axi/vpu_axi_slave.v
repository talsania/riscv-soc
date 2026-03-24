`timescale 1ns / 1ps

// =============================================================================
// vpu_axi_slave.v
//
// AXI4-Lite slave wrapper around macro_fsm + systolic_array.
//
// Register map (byte addresses, 32-bit AXI data bus):
//   0x000-0x03F   Matrix A  8x8 INT8, row-major, 4 bytes per 32-bit word (16 words)
//   0x040-0x07F   Matrix B  8x8 INT8, row-major, 4 bytes per 32-bit word (16 words)
//   0x080         CTRL      bit[0]=start(W,self-clear)  bit[1]=busy(R)  bit[2]=done(R,sticky)
//   0x100-0x1FC   Result    8x8 INT32, row-major, 64 words  (read-only)
//
// AXI4-Lite data width : 32 bits
// AXI4-Lite addr width : 10 bits (covers 0x000-0x3FF)
//
// Usage:
//   1. Write 8x8 INT8 matrices into 0x000-0x07F (WSTRB byte-granular).
//   2. Write 0x01 to CTRL (0x080).  start auto-clears once busy asserts.
//   3. Poll CTRL bit[2] (done) until set  (total latency = 26 + AXI overhead clocks).
//   4. Read INT32 results from 0x100-0x1FC.
//
// Timing invariants honoured:
//   - ctrl_start is a registered 1-cycle pulse seen by macro_fsm.
//     It self-clears the cycle after fsm_busy rises (FSM IDLE->CLR same edge
//     as start, busy asserts immediately).
//   - result_reg shadow-latches result_flat on posedge(fsm_done).  Results are
//     therefore stable for CPU reads even if a new operation is started right away.
//   - done_sticky is cleared atomically with the next start write.
//   - Writes to result registers (0x100-0x1FC) are silently ignored.
//   - CTRL bit[0] reads as 0 (start is write-only).
//
// v1: initial implementation
// =============================================================================

module vpu_axi_slave #(
    parameter C_S_AXI_DATA_WIDTH = 32,
    parameter C_S_AXI_ADDR_WIDTH = 10
)(
    input  wire                              S_AXI_ACLK,
    input  wire                              S_AXI_ARESETN,

    // Write address channel
    input  wire [C_S_AXI_ADDR_WIDTH-1:0]    S_AXI_AWADDR,
    input  wire [2:0]                        S_AXI_AWPROT,
    input  wire                              S_AXI_AWVALID,
    output wire                              S_AXI_AWREADY,

    // Write data channel
    input  wire [C_S_AXI_DATA_WIDTH-1:0]    S_AXI_WDATA,
    input  wire [C_S_AXI_DATA_WIDTH/8-1:0]  S_AXI_WSTRB,
    input  wire                              S_AXI_WVALID,
    output wire                              S_AXI_WREADY,

    // Write response channel
    output wire [1:0]                        S_AXI_BRESP,
    output wire                              S_AXI_BVALID,
    input  wire                              S_AXI_BREADY,

    // Read address channel
    input  wire [C_S_AXI_ADDR_WIDTH-1:0]    S_AXI_ARADDR,
    input  wire [2:0]                        S_AXI_ARPROT,
    input  wire                              S_AXI_ARVALID,
    output wire                              S_AXI_ARREADY,

    // Read data channel
    output wire [C_S_AXI_DATA_WIDTH-1:0]    S_AXI_RDATA,
    output wire [1:0]                        S_AXI_RRESP,
    output wire                              S_AXI_RVALID,
    input  wire                              S_AXI_RREADY
);

    // AXI handshake registers
    reg                            axi_awready;
    reg                            axi_wready;
    reg                            axi_bvalid;
    reg                            axi_arready;
    reg                            axi_rvalid;
    reg [C_S_AXI_ADDR_WIDTH-1:0]  axi_awaddr_lat;
    reg [C_S_AXI_ADDR_WIDTH-1:0]  axi_araddr_lat;
    reg [C_S_AXI_DATA_WIDTH-1:0]  axi_rdata_r;

    assign S_AXI_AWREADY = axi_awready;
    assign S_AXI_WREADY  = axi_wready;
    assign S_AXI_BRESP   = 2'b00;
    assign S_AXI_BVALID  = axi_bvalid;
    assign S_AXI_ARREADY = axi_arready;
    assign S_AXI_RDATA   = axi_rdata_r;
    assign S_AXI_RRESP   = 2'b00;
    assign S_AXI_RVALID  = axi_rvalid;

    // One-cycle write strobe: address and data both accepted simultaneously
    wire slv_wen = axi_awready & S_AXI_AWVALID & axi_wready & S_AXI_WVALID;

    // Write address ready
    always @(posedge S_AXI_ACLK) begin
        if (!S_AXI_ARESETN) begin
            axi_awready    <= 1'b0;
            axi_awaddr_lat <= {C_S_AXI_ADDR_WIDTH{1'b0}};
        end else if (!axi_awready && S_AXI_AWVALID && S_AXI_WVALID) begin
            axi_awready    <= 1'b1;
            axi_awaddr_lat <= S_AXI_AWADDR;
        end else
            axi_awready <= 1'b0;
    end

    // Write data ready (mirrors AW)
    always @(posedge S_AXI_ACLK) begin
        if (!S_AXI_ARESETN)
            axi_wready <= 1'b0;
        else if (!axi_wready && S_AXI_WVALID && S_AXI_AWVALID)
            axi_wready <= 1'b1;
        else
            axi_wready <= 1'b0;
    end

    // Write response
    always @(posedge S_AXI_ACLK) begin
        if (!S_AXI_ARESETN)
            axi_bvalid <= 1'b0;
        else if (slv_wen)
            axi_bvalid <= 1'b1;
        else if (axi_bvalid && S_AXI_BREADY)
            axi_bvalid <= 1'b0;
    end

    // Read address ready
    always @(posedge S_AXI_ACLK) begin
        if (!S_AXI_ARESETN) begin
            axi_arready    <= 1'b0;
            axi_araddr_lat <= {C_S_AXI_ADDR_WIDTH{1'b0}};
        end else if (!axi_arready && S_AXI_ARVALID) begin
            axi_arready    <= 1'b1;
            axi_araddr_lat <= S_AXI_ARADDR;
        end else
            axi_arready <= 1'b0;
    end

    // Read data valid
    always @(posedge S_AXI_ACLK) begin
        if (!S_AXI_ARESETN)
            axi_rvalid <= 1'b0;
        else if (axi_arready && S_AXI_ARVALID && !axi_rvalid)
            axi_rvalid <= 1'b1;
        else if (axi_rvalid && S_AXI_RREADY)
            axi_rvalid <= 1'b0;
    end

    // Register banks
    reg [31:0] mat_a_reg [0:15];   // 16 x 32b = 64 bytes: Matrix A
    reg [31:0] mat_b_reg [0:15];   // 16 x 32b = 64 bytes: Matrix B
    reg        ctrl_start;         // 1-cycle pulse into macro_fsm
    reg        ctrl_done_sticky;   // sticky done flag, readable via CTRL[2]

    // Pack matrix registers into 512-bit flat buses for macro_fsm
    // mat_x_reg[0][7:0]  = element A[0][0]
    // mat_x_reg[0][15:8] = element A[0][1]  ... etc. (row-major, INT8 packed)
    wire [511:0] mat_a_flat;
    wire [511:0] mat_b_flat;

    genvar fw;
    generate
        for (fw = 0; fw < 16; fw = fw + 1) begin : FLAT_A
            assign mat_a_flat[fw*32 +: 32] = mat_a_reg[fw];
        end
        for (fw = 0; fw < 16; fw = fw + 1) begin : FLAT_B
            assign mat_b_flat[fw*32 +: 32] = mat_b_reg[fw];
        end
    endgenerate

    // Core instantiation
    wire [63:0]   a_in_flat;
    wire [7:0]    a_valid_flat;
    wire [63:0]   b_in_flat;
    wire          fsm_clr;
    wire          fsm_busy;
    wire          fsm_done;
    wire [2047:0] result_flat;

    macro_fsm u_fsm (
        .clk          (S_AXI_ACLK),
        .resetn       (S_AXI_ARESETN),
        .start        (ctrl_start),
        .mat_a_flat   (mat_a_flat),
        .mat_b_flat   (mat_b_flat),
        .a_in_flat    (a_in_flat),
        .a_valid_flat (a_valid_flat),
        .b_in_flat    (b_in_flat),
        .clr          (fsm_clr),
        .busy         (fsm_busy),
        .done         (fsm_done)
    );

    systolic_array u_sa (
        .clk          (S_AXI_ACLK),
        .resetn       (S_AXI_ARESETN),
        .clr          (fsm_clr),
        .a_in_flat    (a_in_flat),
        .a_valid_flat (a_valid_flat),
        .b_in_flat    (b_in_flat),
        .result_flat  (result_flat)
    );

    // Result shadow registers (64 x INT32)
    // Latch on fsm_done - CPU always reads a coherent completed result.
    reg [31:0] result_reg [0:63];
    integer    lk;

    always @(posedge S_AXI_ACLK) begin
        if (!S_AXI_ARESETN) begin
            for (lk = 0; lk < 64; lk = lk + 1)
                result_reg[lk] <= 32'd0;
        end else if (fsm_done) begin
            for (lk = 0; lk < 64; lk = lk + 1)
                result_reg[lk] <= result_flat[lk*32 +: 32];
        end
    end

    ////////////////////////////////////////////////////////////////////////////
    // Register write dispatch
    //
    // 7-bit word address = axi_awaddr_lat[8:2]:
    //   7'h00-7'h0F  (addr 0x000-0x03C)  -> Mat A word [3:0]
    //   7'h10-7'h1F  (addr 0x040-0x07C)  -> Mat B word [3:0]
    //   7'h20        (addr 0x080)         -> CTRL
    //   7'h40-7'h7F  (addr 0x100-0x1FC)  -> Result (read-only, writes ignored)
    ////////////////////////////////////////////////////////////////////////////
    wire [6:0] wr_word = axi_awaddr_lat[8:2];

    integer bi;
    always @(posedge S_AXI_ACLK) begin
        if (!S_AXI_ARESETN) begin
            for (bi = 0; bi < 16; bi = bi + 1) begin
                mat_a_reg[bi] <= 32'd0;
                mat_b_reg[bi] <= 32'd0;
            end
            ctrl_start       <= 1'b0;
            ctrl_done_sticky <= 1'b0;
        end else begin
            // --- auto-clear start once FSM is busy ---
            if (ctrl_start && fsm_busy)
                ctrl_start <= 1'b0;

            // --- sticky done ---
            if (fsm_done)
                ctrl_done_sticky <= 1'b1;

            // --- AXI write ---
            if (slv_wen) begin
                if (!wr_word[6] && !wr_word[5]) begin
                    // 0x000-0x07C: Matrix A and B
                    if (!wr_word[4]) begin
                        // Mat A  (7'h00-7'h0F)
                        if (S_AXI_WSTRB[0]) mat_a_reg[wr_word[3:0]][ 7: 0] <= S_AXI_WDATA[ 7: 0];
                        if (S_AXI_WSTRB[1]) mat_a_reg[wr_word[3:0]][15: 8] <= S_AXI_WDATA[15: 8];
                        if (S_AXI_WSTRB[2]) mat_a_reg[wr_word[3:0]][23:16] <= S_AXI_WDATA[23:16];
                        if (S_AXI_WSTRB[3]) mat_a_reg[wr_word[3:0]][31:24] <= S_AXI_WDATA[31:24];
                    end else begin
                        // Mat B  (7'h10-7'h1F)
                        if (S_AXI_WSTRB[0]) mat_b_reg[wr_word[3:0]][ 7: 0] <= S_AXI_WDATA[ 7: 0];
                        if (S_AXI_WSTRB[1]) mat_b_reg[wr_word[3:0]][15: 8] <= S_AXI_WDATA[15: 8];
                        if (S_AXI_WSTRB[2]) mat_b_reg[wr_word[3:0]][23:16] <= S_AXI_WDATA[23:16];
                        if (S_AXI_WSTRB[3]) mat_b_reg[wr_word[3:0]][31:24] <= S_AXI_WDATA[31:24];
                    end
                end else if (wr_word == 7'h20) begin
                    // CTRL  (0x080)
                    // Guard: only fire start if FSM is not already busy
                    if (S_AXI_WSTRB[0] && S_AXI_WDATA[0] && !fsm_busy) begin
                        ctrl_start       <= 1'b1;
                        ctrl_done_sticky <= 1'b0;
                    end
                    // CTRL bits [2:1] (done, busy) are read-only
                end
                // 0x100-0x1FC: result is read-only; writes silently dropped
            end
        end
    end

    ////////////////////////////////////////////////////////////////////////////
    // Read data mux (registered, one cycle after AR handshake)
    //
    // 7-bit word address = axi_araddr_lat[8:2]:
    //   0x00-0x0F  -> Mat A
    //   0x10-0x1F  -> Mat B
    //   0x20       -> CTRL
    //   0x40-0x7F  -> Result shadow
    ////////////////////////////////////////////////////////////////////////////
    wire [6:0] rd_word = axi_araddr_lat[8:2];

    always @(posedge S_AXI_ACLK) begin
        if (!S_AXI_ARESETN)
            axi_rdata_r <= 32'd0;
        else if (axi_arready && S_AXI_ARVALID && !axi_rvalid) begin
            if (!rd_word[6] && !rd_word[5]) begin
                if (!rd_word[4])
                    axi_rdata_r <= mat_a_reg[rd_word[3:0]];
                else
                    axi_rdata_r <= mat_b_reg[rd_word[3:0]];
            end else if (rd_word == 7'h20) begin
                // CTRL: bit0 always 0 (start is write-only)
                axi_rdata_r <= {29'd0, ctrl_done_sticky, fsm_busy, 1'b0};
            end else if (rd_word[6]) begin
                // Result: rd_word[5:0] = 0..63
                axi_rdata_r <= result_reg[rd_word[5:0]];
            end else begin
                axi_rdata_r <= 32'hDEAD_BEEF;  // unmapped region
            end
        end
    end

endmodule