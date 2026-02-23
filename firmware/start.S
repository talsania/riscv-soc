/* =============================================================================
 * start.S  —  Minimal RISC-V startup for PicoRV32 SoC
 *
 * Memory map (matches your decoder):
 *   0x00000000  BRAM 4KB   (code + data + stack)
 *   0x20000000  UART TX    (single byte write, fire-and-forget)
 *   0x30000000  GPIO       (32-bit write)
 *
 * Stack: grows DOWN from top of BRAM → 0x00001000 (4KB boundary)
 * =============================================================================
 */

.section .init, "ax", @progbits
.global  _start
.type    _start, @function

_start:
    /* ------------------------------------------------------------------ */
    /* 1. Zero all integer registers (good practice, not strictly required) */
    /* ------------------------------------------------------------------ */
    li  x1,  0
    li  x2,  0
    li  x3,  0
    li  x4,  0
    li  x5,  0
    li  x6,  0
    li  x7,  0
    li  x8,  0
    li  x9,  0
    li  x10, 0
    li  x11, 0
    li  x12, 0
    li  x13, 0
    li  x14, 0
    li  x15, 0
    li  x16, 0
    li  x17, 0
    li  x18, 0
    li  x19, 0
    li  x20, 0
    li  x21, 0
    li  x22, 0
    li  x23, 0
    li  x24, 0
    li  x25, 0
    li  x26, 0
    li  x27, 0
    li  x28, 0
    li  x29, 0
    li  x30, 0
    li  x31, 0

    /* ------------------------------------------------------------------ */
    /* 2. Set stack pointer to top of BRAM (4KB = 0x1000)                 */
    /*    Stack grows downward; leave x1=0 (ra) so a misplaced ret faults */
    /* ------------------------------------------------------------------ */
    li  sp, 0x00001000      /* sp = 0x1000 (4 KB, top of BRAM) */

    /* ------------------------------------------------------------------ */
    /* 3. Zero .bss section                                                */
    /*    Linker exports __bss_start and __bss_end                         */
    /* ------------------------------------------------------------------ */
    la  a0, __bss_start
    la  a1, __bss_end
    beq a0, a1, .bss_done   /* skip if bss is empty */
.bss_loop:
    sw   zero, 0(a0)
    addi a0, a0, 4
    bltu a0, a1, .bss_loop
.bss_done:

    /* ------------------------------------------------------------------ */
    /* 4. Call main()                                                      */
    /* ------------------------------------------------------------------ */
    call main

    /* ------------------------------------------------------------------ */
    /* 5. Halt — loop forever if main() returns                           */
    /* ------------------------------------------------------------------ */
.halt:
    j   .halt

.size _start, . - _start
