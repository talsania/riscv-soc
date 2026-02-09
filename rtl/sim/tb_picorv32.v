`timescale 1ns / 1ps

module tb_picorv32;

    // Clock and Reset
    reg clk;
    reg resetn;
    
    // Memory Interface signals from CPU
    wire        mem_valid;
    wire        mem_instr;
    reg         mem_ready;
    wire [31:0] mem_addr;
    wire [31:0] mem_wdata;
    wire [3:0]  mem_wstrb;
    reg  [31:0] mem_rdata;
    
    // Instantiate PicoRV32 CPU
    picorv32 #(
        .ENABLE_COUNTERS(0),
        .ENABLE_COUNTERS64(0),
        .ENABLE_REGS_16_31(1),
        .ENABLE_REGS_DUALPORT(0),
        .LATCHED_MEM_RDATA(0),
        .TWO_STAGE_SHIFT(0),
        .BARREL_SHIFTER(0),
        .TWO_CYCLE_COMPARE(0),
        .TWO_CYCLE_ALU(0),
        .CATCH_MISALIGN(0),
        .CATCH_ILLINSN(0),
        .COMPRESSED_ISA(0),
        .ENABLE_PCPI(0),
        .ENABLE_MUL(0),
        .ENABLE_FAST_MUL(0),
        .ENABLE_DIV(0),
        .ENABLE_IRQ(0),
        .ENABLE_TRACE(0)
    ) cpu (
        .clk(clk),
        .resetn(resetn),
        .mem_valid(mem_valid),
        .mem_instr(mem_instr),
        .mem_ready(mem_ready),
        .mem_addr(mem_addr),
        .mem_wdata(mem_wdata),
        .mem_wstrb(mem_wstrb),
        .mem_rdata(mem_rdata),
        .trap(),
        .mem_la_read(),
        .mem_la_write(),
        .mem_la_addr(),
        .mem_la_wdata(),
        .mem_la_wstrb(),
        .pcpi_valid(),
        .pcpi_insn(),
        .pcpi_rs1(),
        .pcpi_rs2(),
        .pcpi_wr(1'b0),
        .pcpi_rd(32'h0),
        .pcpi_wait(1'b0),
        .pcpi_ready(1'b0),
        .irq(32'h0),
        .eoi(),
        .trace_valid(),
        .trace_data()
    );
    
    // Simple Memory Model (4KB)
    reg [31:0] memory [0:1023];
    
    // Memory Access Counter
    integer access_count;
    
    // Memory Read/Write Logic
    always @(posedge clk) begin
        mem_ready <= 1'b0;
        
        if (mem_valid && !mem_ready && resetn) begin
            if (mem_addr[1:0] == 2'b00 && mem_addr < 32'h1000) begin
                if (mem_wstrb != 4'b0000) begin
                    // WRITE operation
                    if (mem_wstrb[0]) memory[mem_addr[11:2]][7:0]   <= mem_wdata[7:0];
                    if (mem_wstrb[1]) memory[mem_addr[11:2]][15:8]  <= mem_wdata[15:8];
                    if (mem_wstrb[2]) memory[mem_addr[11:2]][23:16] <= mem_wdata[23:16];
                    if (mem_wstrb[3]) memory[mem_addr[11:2]][31:24] <= mem_wdata[31:24];
                    
                    $display("[%0t] WRITE: Addr=0x%08h Data=0x%08h Strb=%b", 
                             $time, mem_addr, mem_wdata, mem_wstrb);
                end else begin
                    // READ operation
                    mem_rdata <= memory[mem_addr[11:2]];
                    
                    if (mem_instr)
                        $display("[%0t] IFETCH: Addr=0x%08h Data=0x%08h", 
                                 $time, mem_addr, memory[mem_addr[11:2]]);
                    else
                        $display("[%0t] READ: Addr=0x%08h Data=0x%08h", 
                                 $time, mem_addr, memory[mem_addr[11:2]]);
                end
                mem_ready <= 1'b1;
                access_count <= access_count + 1;
            end
        end
    end
    
    // Clock Generation (50MHz = 20ns period)
    initial begin
        clk = 1'b0;
        forever #10 clk = ~clk;
    end
    
    // Initialize Memory with Test Program
    integer i;
    initial begin
        // Initialize all memory to NOP
        for (i = 0; i < 1024; i = i + 1) begin
            memory[i] = 32'h00000013; // NOP (ADDI x0, x0, 0)
        end
        
        // Load Test Program
        // Address 0x00: ADDI x1, x0, 5
        memory[0] = 32'h00500093; 
        
        // Address 0x04: ADDI x2, x0, 10
        memory[1] = 32'h00A00113;
        
        // Address 0x08: ADD x3, x1, x2
        memory[2] = 32'h002081B3;
        
        // Address 0x0C: SW x3, 0x100(x0)
        memory[3] = 32'h10302023;
        
        // Address 0x10: LW x4, 0x100(x0)
        memory[4] = 32'h10002203;
        
        // Address 0x14: ADD x5, x4, x1
        memory[5] = 32'h001202B3;
        
        // Address 0x18: Loop forever
        memory[6] = 32'hFFDFF06F;
    end
    
    // Simulation Control
    initial begin
        // Initialize signals
        resetn = 1'b0;
        mem_ready = 1'b0;
        mem_rdata = 32'h0;
        access_count = 0;
        
        $display("========================================");
        $display("PicoRV32 Basic Instruction Simulation");
        $display("========================================");
        $display("");
        $display("Test Program:");
        $display("  0x00: ADDI x1, x0, 5");
        $display("  0x04: ADDI x2, x0, 10");
        $display("  0x08: ADD  x3, x1, x2");
        $display("  0x0C: SW   x3, 0x100(x0)");
        $display("  0x10: LW   x4, 0x100(x0)");
        $display("  0x14: ADD  x5, x4, x1");
        $display("  0x18: JAL  x0, -4 (loop)");
        $display("");
        
        // Hold reset for 100ns
        #100;
        resetn = 1'b1;
        $display("[%0t] Reset released", $time);
        $display("");
        
        // Run for 2000ns
        #2000;
        
        // Check results
        $display("");
        $display("========================================");
        $display("Results:");
        $display("  Memory[0x100] = 0x%08h (expected: 0x0000000F)", memory[64]);
        $display("  Total memory accesses: %0d", access_count);
        $display("========================================");
        
        $finish;
    end

endmodule