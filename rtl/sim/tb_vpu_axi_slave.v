`timescale 1ns / 1ps

// =============================================================================
// tb_vpu_axi_slave.v
// Tb for vpu_axi_slave + macro_fsm + systolic_array + pe
//
// Tests:
//   T1  Reset: CTRL reads 0 after release
//   T2  Identity x Identity = Identity  (full timing chain validation)
//   T3  Arbitrary matrix: software reference vs hardware result
//   T4  Start-while-busy guard: second start ignored, FSM completes normally
//   T5  Mid-operation reset: CTRL returns to 0
// =============================================================================

module tb_vpu_axi_slave;

    localparam AW = 10;
    localparam DW = 32;

    // clock / reset
    reg clk, resetn;
    initial clk = 0;
    always #5 clk = ~clk;

    // AXI signals
    reg  [AW-1:0] m_awaddr;  reg [2:0] m_awprot; reg m_awvalid; wire m_awready;
    reg  [DW-1:0] m_wdata;   reg [3:0] m_wstrb;  reg m_wvalid;  wire m_wready;
    wire [1:0]    m_bresp;   wire      m_bvalid;  reg  m_bready;
    reg  [AW-1:0] m_araddr;  reg [2:0] m_arprot;  reg m_arvalid; wire m_arready;
    wire [DW-1:0] m_rdata;   wire [1:0] m_rresp;  wire m_rvalid; reg  m_rready;

    // DUT
    vpu_axi_slave #(.C_S_AXI_DATA_WIDTH(DW),.C_S_AXI_ADDR_WIDTH(AW)) dut(
        .S_AXI_ACLK(clk),.S_AXI_ARESETN(resetn),
        .S_AXI_AWADDR(m_awaddr),.S_AXI_AWPROT(m_awprot),.S_AXI_AWVALID(m_awvalid),.S_AXI_AWREADY(m_awready),
        .S_AXI_WDATA(m_wdata),.S_AXI_WSTRB(m_wstrb),.S_AXI_WVALID(m_wvalid),.S_AXI_WREADY(m_wready),
        .S_AXI_BRESP(m_bresp),.S_AXI_BVALID(m_bvalid),.S_AXI_BREADY(m_bready),
        .S_AXI_ARADDR(m_araddr),.S_AXI_ARPROT(m_arprot),.S_AXI_ARVALID(m_arvalid),.S_AXI_ARREADY(m_arready),
        .S_AXI_RDATA(m_rdata),.S_AXI_RRESP(m_rresp),.S_AXI_RVALID(m_rvalid),.S_AXI_RREADY(m_rready)
    );

    // Tasks

    task axi_write;
        input [AW-1:0] addr;
        input [DW-1:0] data;
        input [3:0]    strb;
        begin
            @(negedge clk);
            m_awaddr=addr; m_awprot=0; m_awvalid=1;
            m_wdata=data;  m_wstrb=strb; m_wvalid=1; m_bready=1;
            @(posedge clk);
            while(!(m_awready && m_wready)) @(posedge clk);
            @(negedge clk); m_awvalid=0; m_wvalid=0;
            @(posedge clk);
            while(!m_bvalid) @(posedge clk);
            @(negedge clk); m_bready=0;
        end
    endtask

    reg [DW-1:0] rd_result;
    task axi_read;
        input  [AW-1:0] addr;
        output [DW-1:0] rdata;
        begin
            @(negedge clk);
            m_araddr=addr; m_arprot=0; m_arvalid=1; m_rready=1;
            @(posedge clk);
            while(!m_arready) @(posedge clk);
            @(negedge clk); m_arvalid=0;
            @(posedge clk);
            while(!m_rvalid) @(posedge clk);
            rdata=m_rdata;
            @(negedge clk); m_rready=0;
        end
    endtask

    // Write a single INT8 element into matrix A or B
    // mat=0:A mat=1:B  row,col 0..7
    task write_byte;
        input       mat;
        input [2:0] row, col;
        input [7:0] val;
        reg [AW-1:0] addr;
        reg [DW-1:0] wdata;
        reg [3:0]    wstrb;
        reg [5:0]    lin;
        reg [3:0]    wi;
        reg [1:0]    bi2;
        begin
            lin  = {row,col};
            wi   = lin[5:2];
            bi2  = lin[1:0];
            addr  = (mat ? 10'h040 : 10'h000) | {wi,2'b00};
            wdata = {24'd0,val} << (bi2*8);
            wstrb = 4'b0001 << bi2;
            axi_write(addr, wdata, wstrb);
        end
    endtask

    // Software reference
    integer refa[0:7][0:7], refb[0:7][0:7], refc[0:7][0:7];
    integer rr,rc,rk;
    task compute_ref;
        begin
            for(rr=0;rr<8;rr=rr+1)
                for(rc=0;rc<8;rc=rc+1) begin
                    refc[rr][rc]=0;
                    for(rk=0;rk<8;rk=rk+1)
                        refc[rr][rc] = refc[rr][rc] + refa[rr][rk]*refb[rk][rc];
                end
        end
    endtask

    // Poll done with timeout
    integer tc;
    task wait_done;
        output timed_out;
        reg    timed_out;
        begin
            timed_out=0; tc=0;
            axi_read(10'h080,rd_result);
            while(!rd_result[2]) begin
                if(tc>300) begin timed_out=1; disable wait_done; end
                tc=tc+1;
                axi_read(10'h080,rd_result);
            end
        end
    endtask

    // Stimulus
    integer       i,j,errs;
    reg [31:0]    cval;
    reg           to;
    reg signed [31:0] gs;

    initial begin
        m_awvalid=0; m_wvalid=0; m_bready=0; m_arvalid=0; m_rready=0;
        m_awaddr=0; m_awprot=0; m_wdata=0; m_wstrb=0; m_araddr=0; m_arprot=0;
        resetn=0; errs=0;

        repeat(4) @(posedge clk);
        resetn=1;
        @(posedge clk);

        // ---- T1: reset ----
        axi_read(10'h080, cval);
        if(cval!==0) begin $display("FAIL[T1] CTRL=%0h",cval); errs=errs+1; end
        else           $display("PASS[T1] CTRL=0 after reset");

        // ---- T2: Identity * Identity ----
        $display("--- T2: Identity * Identity ---");
        for(i=0;i<8;i=i+1) for(j=0;j<8;j=j+1) begin
            refa[i][j]=(i==j)?1:0; refb[i][j]=(i==j)?1:0;
            write_byte(0,i[2:0],j[2:0],(i==j)?8'd1:8'd0);
            write_byte(1,i[2:0],j[2:0],(i==j)?8'd1:8'd0);
        end
        axi_write(10'h080,32'h1,4'hF);
        axi_read(10'h080,cval);
        if(cval[0]) begin $display("FAIL[T2] start bit not self-cleared"); errs=errs+1; end
        else $display("PASS[T2] start self-cleared");
        if(!cval[1]) begin $display("FAIL[T2] busy not asserted"); errs=errs+1; end
        else $display("PASS[T2] busy asserted");

        wait_done(to);
        if(to) begin $display("FAIL[T2] timeout"); errs=errs+1; end
        else   $display("PASS[T2] done asserted (polls=%0d)",tc);

        axi_read(10'h080,cval);
        if(cval[1]) begin $display("FAIL[T2] busy should clear with done"); errs=errs+1; end

        compute_ref;
        for(i=0;i<8;i=i+1) for(j=0;j<8;j=j+1) begin
            axi_read(10'h100+((i*8+j)*4), cval);
            gs=$signed(cval);
            if(gs!==refc[i][j]) begin
                $display("FAIL[T2] C[%0d][%0d] exp=%0d got=%0d",i,j,refc[i][j],gs);
                errs=errs+1;
            end
        end
        if(errs==0) $display("PASS[T2] identity result correct");

        // ---- T3: Arbitrary ----
        $display("--- T3: Arbitrary multiply ---");
        for(i=0;i<8;i=i+1) for(j=0;j<8;j=j+1) begin
            refa[i][j]=(i+j+1)%8;
            refb[i][j]=(i*3+j+1)%5;
            write_byte(0,i[2:0],j[2:0],refa[i][j][7:0]);
            write_byte(1,i[2:0],j[2:0],refb[i][j][7:0]);
        end
        // done_sticky still set from T2
        axi_read(10'h080,cval);
        if(!cval[2]) $display("WARN[T3] done_sticky should still be set");

        axi_write(10'h080,32'h1,4'hF);  // clears done_sticky, fires start
        axi_read(10'h080,cval);
        if(cval[2]) begin $display("FAIL[T3] done not cleared on start"); errs=errs+1; end
        else $display("PASS[T3] done cleared by start");

        wait_done(to);
        if(to) begin $display("FAIL[T3] timeout"); errs=errs+1; end

        compute_ref;
        for(i=0;i<8;i=i+1) for(j=0;j<8;j=j+1) begin
            axi_read(10'h100+((i*8+j)*4), cval);
            gs=$signed(cval);
            if(gs!==refc[i][j]) begin
                $display("FAIL[T3] C[%0d][%0d] exp=%0d got=%0d",i,j,refc[i][j],gs);
                errs=errs+1;
            end
        end
        if(errs==0) $display("PASS[T3] arbitrary multiply correct");

        // ---- T4: Start-while-busy guard ----
        $display("--- T4: Start-while-busy guard ---");
        for(i=0;i<8;i=i+1) for(j=0;j<8;j=j+1) begin
            write_byte(0,i[2:0],j[2:0],(i==j)?8'd3:8'd0);
            write_byte(1,i[2:0],j[2:0],(i==j)?8'd3:8'd0);
        end
        axi_write(10'h080,32'h1,4'hF);
        axi_read(10'h080,cval);
        if(cval[1]) begin
            // busy - try another start (should be ignored)
            axi_write(10'h080,32'h1,4'hF);
        end
        wait_done(to);
        if(to) begin $display("FAIL[T4] timeout after guarded start"); errs=errs+1; end
        else   $display("PASS[T4] FSM completed after guarded-start attempt");

        // ---- T5: Reset mid-operation ----
        $display("--- T5: Reset mid-op ---");
        for(i=0;i<8;i=i+1) for(j=0;j<8;j=j+1) begin
            write_byte(0,i[2:0],j[2:0],8'd5);
            write_byte(1,i[2:0],j[2:0],8'd5);
        end
        axi_write(10'h080,32'h1,4'hF);
        repeat(5) @(posedge clk);
        @(negedge clk); resetn=0;
        repeat(4) @(posedge clk);
        @(negedge clk); resetn=1;
        repeat(2) @(posedge clk);
        axi_read(10'h080,cval);
        if(cval!==0) begin $display("FAIL[T5] CTRL=%0h after mid-op reset",cval); errs=errs+1; end
        else $display("PASS[T5] CTRL=0 after mid-op reset");

        // ---- Summary ----
        $display("=== DONE  errors=%0d ===", errs);
        if(errs==0) $display("ALL TESTS PASSED");
        $finish;
    end

    initial begin #500000; $display("FATAL: global timeout"); $finish; end

endmodule