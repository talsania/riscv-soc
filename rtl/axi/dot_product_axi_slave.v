`timescale 1ns / 1ps

//==============================================================================
// dot_product_axi_slave.v
//
// This models the HLS-generated dot_product core.
//
// Register map - verified from Vitis HLS 2025.2 S_AXILITE Registers report:
//
//   Offset  Name         Access  Description
//   0x00    CTRL         RW      bit0=AP_START(W) bit1=AP_DONE(R) bit2=AP_IDLE(R) bit3=AP_READY(R)
//   0x04    GIER         RW      Global Interrupt Enable (accepted, ignored)
//   0x08    IP_IER       RW      IP Interrupt Enable    (accepted, ignored)
//   0x0C    IP_ISR       RW      IP Interrupt Status    (accepted, ignored)
//   0x10    a[0]         W       INT8 in bits[7:0], stride = 0x08
//   0x18    a[1]         W
//   0x20    a[2]         W
//   0x28    a[3]         W
//   0x30    a[4]         W
//   0x38    a[5]         W
//   0x40    a[6]         W
//   0x48    a[7]         W
//   0x50    b[0]         W       INT8 in bits[7:0], stride = 0x08
//   0x58    b[1]         W
//   0x60    b[2]         W
//   0x68    b[3]         W
//   0x70    b[4]         W
//   0x78    b[5]         W
//   0x80    b[6]         W
//   0x88    b[7]         W
//   0x90    result       R       INT32 dot product result
//   0x94    result_ctrl  R       bit0=result_ap_vld
//
// Pipeline depth: 4 cycles (HLS: Depth=5, Interval=1, Fmax=153MHz)
// After AP_START pulse, AP_DONE asserts for 1 cycle 4 clocks later.
// AP_IDLE is 0 during computation, 1 otherwise.
//
// Base address in SoC: 0x4000_0000 (Slave 3 in axi_crossbar)
//==============================================================================

module dot_product_axi_slave (
    input  wire        clk,
    input  wire        resetn,

    // AXI-Lite slave interface
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
    input  wire        s_axi_rready
);

    // Register file
    reg signed [7:0]  a [0:7];
    reg signed [7:0]  b [0:7];
    reg signed [31:0] result_reg;
    reg               result_vld;   // result_ap_vld

    // HLS control signals
    reg ap_start;   // one-cycle pulse, set by writing bit0 of CTRL
    reg ap_done;    // one-cycle pulse when result is ready
    reg ap_idle;    // 1 = idle/ready, 0 = computing
    reg ap_ready;   // mirrors ap_idle for ap_ctrl_hs

    // AXI-Lite Write Path
    // Buffer AW and W independently (they may arrive in any order per spec),
    // commit when both are captured.
    reg       aw_captured;
    reg [7:0] aw_offset;    // low byte of address = register offset
    reg       w_captured;
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
            ap_start      <= 0;
            a[0] <= 0; a[1] <= 0; a[2] <= 0; a[3] <= 0;
            a[4] <= 0; a[5] <= 0; a[6] <= 0; a[7] <= 0;
            b[0] <= 0; b[1] <= 0; b[2] <= 0; b[3] <= 0;
            b[4] <= 0; b[5] <= 0; b[6] <= 0; b[7] <= 0;
        end else begin
            s_axi_awready <= 0;
            s_axi_wready  <= 0;
            ap_start      <= 0;  // AP_START auto-clears each cycle

            // Capture AW
            if (s_axi_awvalid && !aw_captured) begin
                s_axi_awready <= 1;
                aw_offset     <= s_axi_awaddr[7:0];
                aw_captured   <= 1;
            end

            // Capture W
            if (s_axi_wvalid && !w_captured) begin
                s_axi_wready <= 1;
                w_data_buf   <= s_axi_wdata;
                w_strb_buf   <= s_axi_wstrb;
                w_captured   <= 1;
            end

            // decode write
            if (aw_captured && w_captured && !s_axi_bvalid) begin
                case (aw_offset)
                    // CTRL register - only AP_START bit matters
                    8'h00: ap_start <= w_data_buf[0];
                    // Interrupt registers: accept and ignore
                    8'h04: ;  // GIER
                    8'h08: ;  // IP_IER
                    8'h0C: ;  // IP_ISR
                    // a[] inputs - stride 0x08
                    8'h10: a[0] <= $signed(w_data_buf[7:0]);
                    8'h18: a[1] <= $signed(w_data_buf[7:0]);
                    8'h20: a[2] <= $signed(w_data_buf[7:0]);
                    8'h28: a[3] <= $signed(w_data_buf[7:0]);
                    8'h30: a[4] <= $signed(w_data_buf[7:0]);
                    8'h38: a[5] <= $signed(w_data_buf[7:0]);
                    8'h40: a[6] <= $signed(w_data_buf[7:0]);
                    8'h48: a[7] <= $signed(w_data_buf[7:0]);
                    // b[] inputs - stride 0x08
                    8'h50: b[0] <= $signed(w_data_buf[7:0]);
                    8'h58: b[1] <= $signed(w_data_buf[7:0]);
                    8'h60: b[2] <= $signed(w_data_buf[7:0]);
                    8'h68: b[3] <= $signed(w_data_buf[7:0]);
                    8'h70: b[4] <= $signed(w_data_buf[7:0]);
                    8'h78: b[5] <= $signed(w_data_buf[7:0]);
                    8'h80: b[6] <= $signed(w_data_buf[7:0]);
                    8'h88: b[7] <= $signed(w_data_buf[7:0]);
                    // result/result_ctrl are read-only - ignore writes silently
                    default: ;
                endcase
                s_axi_bvalid <= 1;
                s_axi_bresp  <= 2'b00;  // OKAY
                aw_captured  <= 0;
                w_captured   <= 0;
            end

            // B channel handshake
            if (s_axi_bvalid && s_axi_bready)
                s_axi_bvalid <= 0;
        end
    end

    /* Dot Product Compute Engine
    
      Models HLS pipeline: 4-cycle latency, accepts new start every cycle (II=1)
      This RTL slave handles one transaction at a time (ap_ctrl_hs protocol).
    
      State machine: IDLE  → (ap_start) → PIPE (count 4 cycles) → IDLE + ap_done pulse 
    */
    reg [2:0] pipe_cnt;
    reg       computing;

    always @(posedge clk) begin
        if (!resetn) begin
            ap_done    <= 0;
            ap_idle    <= 1;
            ap_ready   <= 1;
            result_reg <= 0;
            result_vld <= 0;
            pipe_cnt   <= 0;
            computing  <= 0;
        end else begin
            ap_done <= 0;  // AP_DONE is a one-cycle pulse

            // Kick off computation
            if (ap_start && !computing) begin
                computing  <= 1;
                ap_idle    <= 0;
                ap_ready   <= 0;
                result_vld <= 0;
                pipe_cnt   <= 0;
                $display("[%0t] DOT: start a=[%d,%d,%d,%d,%d,%d,%d,%d] b=[%d,%d,%d,%d,%d,%d,%d,%d]",
                    $time,
                    $signed(a[0]),$signed(a[1]),$signed(a[2]),$signed(a[3]),
                    $signed(a[4]),$signed(a[5]),$signed(a[6]),$signed(a[7]),
                    $signed(b[0]),$signed(b[1]),$signed(b[2]),$signed(b[3]),
                    $signed(b[4]),$signed(b[5]),$signed(b[6]),$signed(b[7]));
            end

            // Pipeline counter - 4 cycles (pipe_cnt 0→1→2→3 → done on 3)
            if (computing) begin
                pipe_cnt <= pipe_cnt + 1;
                if (pipe_cnt == 3'd3) begin
                    // Latch result
                    result_reg <= ($signed(a[0]) * $signed(b[0])) +
                                  ($signed(a[1]) * $signed(b[1])) +
                                  ($signed(a[2]) * $signed(b[2])) +
                                  ($signed(a[3]) * $signed(b[3])) +
                                  ($signed(a[4]) * $signed(b[4])) +
                                  ($signed(a[5]) * $signed(b[5])) +
                                  ($signed(a[6]) * $signed(b[6])) +
                                  ($signed(a[7]) * $signed(b[7]));
                    result_vld <= 1;
                    ap_done    <= 1;
                    ap_idle    <= 1;
                    ap_ready   <= 1;
                    computing  <= 0;
                    $display("[%0t] DOT: done, result=%d", $time,
                        ($signed(a[0])*$signed(b[0])) + ($signed(a[1])*$signed(b[1])) +
                        ($signed(a[2])*$signed(b[2])) + ($signed(a[3])*$signed(b[3])) +
                        ($signed(a[4])*$signed(b[4])) + ($signed(a[5])*$signed(b[5])) +
                        ($signed(a[6])*$signed(b[6])) + ($signed(a[7])*$signed(b[7])));
                end
            end
        end
    end

    // AXI-Lite Read Path
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

                case (s_axi_araddr[7:0])
                    // CTRL: bit3=AP_READY bit2=AP_IDLE bit1=AP_DONE bit0=0(AP_START W-only)
                    8'h00: s_axi_rdata <= {28'h0, ap_ready, ap_idle, ap_done, 1'b0};
                    8'h04: s_axi_rdata <= 32'h0;  // GIER
                    8'h08: s_axi_rdata <= 32'h0;  // IP_IER
                    8'h0C: s_axi_rdata <= 32'h0;  // IP_ISR
                    8'h90: s_axi_rdata <= result_reg;
                    8'h94: s_axi_rdata <= {31'h0, result_vld};
                    default: s_axi_rdata <= 32'h0;
                endcase
            end

            if (s_axi_rvalid && s_axi_rready)
                s_axi_rvalid <= 0;
        end
    end

endmodule