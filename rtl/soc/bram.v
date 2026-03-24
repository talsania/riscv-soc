`timescale 1ns / 1ps

// =============================================================================
// bram.v  -  4 KB single-port BRAM for PicoRV32 SoC
//
// Changes from previous version:
//   - Removed hardcoded assembly program
//   - Loads firmware/firmware.hex at simulation start via $readmemh
//   - hex format: one 32-bit word per line (produced by Makefile)
//
// Interface is IDENTICAL to the previous bram.v - top.v needs no changes.
//
// Memory map:
//   Base : 0x00000000
//   Size : 4 KB  (1024 × 32-bit words)
//   word_addr = byte_addr[11:2]
//
// Timing:
//   Read/write completes in 1 clock cycle (bram_ready asserts one cycle
//   after bram_valid, then deasserts the next cycle - same as before).
// =============================================================================

module bram (
    input  wire        clk,
    input  wire        resetn,

    // PicoRV32 memory interface (simple valid/ready)
    input  wire        bram_valid,
    input  wire [31:0] bram_addr,
    input  wire [31:0] bram_wdata,
    input  wire [3:0]  bram_wstrb,
    output reg  [31:0] bram_rdata,
    output reg         bram_ready
);

    // Memory array - 1024 words × 32 bits = 4 KB
    reg [31:0] memory [0:1023];

    // Byte address - word index (drop bottom 2 bits)
    wire [9:0] word_addr = bram_addr[11:2];

    // Read / Write
    always @(posedge clk) begin
        if (!resetn) begin
            bram_ready <= 1'b0;
            bram_rdata <= 32'h0;
        end else begin
            bram_ready <= 1'b0;                         // default: not ready

            if (bram_valid && !bram_ready) begin

                if (bram_wstrb != 4'b0000) begin
                    // WRITE - byte-enable masked
                    if (bram_wstrb[0]) memory[word_addr][ 7: 0] <= bram_wdata[ 7: 0];
                    if (bram_wstrb[1]) memory[word_addr][15: 8] <= bram_wdata[15: 8];
                    if (bram_wstrb[2]) memory[word_addr][23:16] <= bram_wdata[23:16];
                    if (bram_wstrb[3]) memory[word_addr][31:24] <= bram_wdata[31:24];
                end else begin
                    // READ
                    bram_rdata <= memory[word_addr];
                end

                bram_ready <= 1'b1;
            end
        end
    end

    // Initialisation - load hex file produced by firmware/Makefile
    //
    // $readmemh expects one hex word per line with NO "0x" prefix:
    //   00000013
    //   300000b7
    //   ...
    // This matches the output of:
    //   xxd -p -c4 firmware.bin > firmware.hex
    //
    // Simulation path: Vivado resolves relative to the project root or the
    // directory containing the testbench. Adjust HEX_FILE if needed.
    //
    // For synthesis (loading into block RAM):
    //   Use Vivado's "Memory Initialization File" (.mif) flow or set the
    //   BRAM primitive's INIT attribute - or keep $readmemh and use
    //   "Simulation only" mode while programming via JTAG for hardware.

    // Path relative to Vivado project root (where .xpr lives).
    localparam HEX_FILE = "C:/Users/Krishang/Desktop/riscv-soc/firmware/firmware.hex";
    integer i;
    initial begin
        // Zero-fill first so any unused words are NOP (0x00000013)
        for (i = 0; i < 1024; i = i + 1)
            memory[i] = 32'h00000013;   // ADDI x0,x0,0  =  NOP

        // Load compiled firmware
        $readmemh(HEX_FILE, memory);

        $display("[BRAM] Loaded %s", HEX_FILE);
        $display("[BRAM] First 12 words:");
        for (i = 0; i < 12; i = i + 1)
            $display("  [%04x] %08x", i*4, memory[i]);
    end

endmodule


// `timescale 1ns / 1ps

// //==============================================================================
// // Simple BRAM  (4 KB, 1-cycle latency)
// //
// // Pre-loaded program:
// //   0x00  LUI  x1, 0x30000      x1 = 0x30000000  (GPIO base)
// //   0x04  ADDI x3, x0, 1        x3 = 1
// //   0x08  SW   x3, 0(x1)        GPIO = 1
// //   0x0C  LUI  x2, 0x20000      x2 = 0x20000000  (UART base)
// //   0x10  ADDI x3, x0, 'H'      x3 = 0x48
// //   0x14  SB   x3, 0(x2)        UART TX 'H'
// //   0x18  ADDI x3, x0, 'i'      x3 = 0x69
// //   0x1C  SB   x3, 0(x2)        UART TX 'i'
// //   0x20  ADDI x3, x0, '!'      x3 = 0x21
// //   0x24  SB   x3, 0(x2)        UART TX '!'
// //   0x28  JAL  x0, 0            loop forever
// //
// // BUG FIX: memory[3] was 0x200000B7 which decodes as LUI x1 (rd=1) NOT LUI x2
// //          because rd field bits[11:7] = 00001 = register 1.
// //          Correct LUI x2 needs rd=2 → bits[11:7] = 00010
// //          Fixed value: 0x20000137
// //==============================================================================

// module bram (
//     input  wire        clk,
//     input  wire        resetn,
//     input  wire        bram_valid,
//     input  wire [31:0] bram_addr,
//     input  wire [31:0] bram_wdata,
//     input  wire [3:0]  bram_wstrb,
//     output reg  [31:0] bram_rdata,
//     output reg         bram_ready
// );
//     reg [31:0] memory [0:1023];             // 4 KB
//     wire [9:0] word_addr = bram_addr[11:2]; // byte addr -> word index

//     // Memory access
//     always @(posedge clk) begin
//         if (!resetn) begin
//             bram_ready <= 1'b0;
//             bram_rdata <= 32'h0;
//         end else begin
//             bram_ready <= 1'b0;
//             if (bram_valid && !bram_ready) begin
//                 if (bram_wstrb != 4'b0000) begin
//                     if (bram_wstrb[0]) memory[word_addr][ 7: 0] <= bram_wdata[ 7: 0];
//                     if (bram_wstrb[1]) memory[word_addr][15: 8] <= bram_wdata[15: 8];
//                     if (bram_wstrb[2]) memory[word_addr][23:16] <= bram_wdata[23:16];
//                     if (bram_wstrb[3]) memory[word_addr][31:24] <= bram_wdata[31:24];
//                 end else
//                     bram_rdata <= memory[word_addr];
//                 bram_ready <= 1'b1;
//             end
//         end
//     end

//     // Program pre-load
//     integer i;
//     initial begin
//         for (i = 0; i < 1024; i = i + 1)
//             memory[i] = 32'h00000013;   // NOP

//         // GPIO
//         memory[0]  = 32'h300000B7;  // LUI  x1, 0x30000   -> x1 = 0x30000000 (GPIO)
//         memory[1]  = 32'h00100193;  // ADDI x3, x0, 1     -> x3 = 1
//         memory[2]  = 32'h0030A023;  // SW   x3, 0(x1)     -> MEM[0x30000000] = 1

//         // UART 
//         // FIX: original was 0x200000B7 which is LUI x1 (rd bits = 00001 = 1)
//         // Correct LUI x2 encoding: rd = 2 = 00010, so bit[8]=1 not bit[7]=1
//         // 0x20000137 has bits[11:7] = 00010 = rd 2 = x2
//         memory[3]  = 32'h20000137;  // LUI  x2, 0x20000   -> x2 = 0x20000000 (UART)

//         memory[4]  = 32'h04800193;  // ADDI x3, x0, 72    -> x3 = 'H' (0x48)
//         memory[5]  = 32'h00310023;  // SB   x3, 0(x2)     -> UART TX 'H'

//         memory[6]  = 32'h06900193;  // ADDI x3, x0, 105   -> x3 = 'i' (0x69)
//         memory[7]  = 32'h00310023;  // SB   x3, 0(x2)     -> UART TX 'i'

//         memory[8]  = 32'h02100193;  // ADDI x3, x0, 33    -> x3 = '!' (0x21)
//         memory[9]  = 32'h00310023;  // SB   x3, 0(x2)     -> UART TX '!'

//         // Loop 
//         memory[10] = 32'h0000006F;  // JAL  x0, 0         -> loop forever

//         $display("BRAM loaded. Program summary:");
//         $display("  0x00: LUI  x1, 0x30000  -> x1=0x30000000 (GPIO base)");
//         $display("  0x04: ADDI x3, x0, 1    -> x3=1");
//         $display("  0x08: SW   x3, 0(x1)    -> Write 1 to GPIO");
//         $display("  0x0C: LUI  x2, 0x20000  -> x2=0x20000000 (UART base) [FIXED]");
//         $display("  0x10: ADDI x3, x0, 'H'  -> x3=0x48");
//         $display("  0x14: SB   x3, 0(x2)    -> UART TX 'H'");
//         $display("  0x18: ADDI x3, x0, 'i'  -> x3=0x69");
//         $display("  0x1C: SB   x3, 0(x2)    -> UART TX 'i'");
//         $display("  0x20: ADDI x3, x0, '!'  -> x3=0x21");
//         $display("  0x24: SB   x3, 0(x2)    -> UART TX '!'");
//         $display("  0x28: JAL  x0, 0        -> loop");
//     end

// endmodule