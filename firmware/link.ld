/* =============================================================================
 * link.ld  —  Linker script for PicoRV32 SoC
 *
 * BRAM: 4 KB at 0x00000000
 *   - Holds: .text (code)  → starts at 0x0
 *             .rodata      → after .text
 *             .data        → after .rodata
 *             .bss         → after .data  (zero-filled by start.S)
 *             stack        → grows DOWN from 0x1000
 *
 * Peripherals (not in MEMORY block — accessed via raw pointer in C):
 *   0x20000000  UART TX register
 *   0x30000000  GPIO register
 * =============================================================================
 */

OUTPUT_ARCH(riscv)
ENTRY(_start)

MEMORY {
    /*           name   attributes   origin       length */
    bram (rwx) : ORIGIN = 0x00000000, LENGTH = 4K
}

SECTIONS {

    /* ------------------------------------------------------------------ */
    /* .text  — executable code                                            */
    /* MUST start with .init so _start lands at address 0x0               */
    /* ------------------------------------------------------------------ */
    .text : {
        *(.init)        /* start.S _start — must be first */
        *(.text)
        *(.text.*)
        *(.rodata)
        *(.rodata.*)
        . = ALIGN(4);
    } > bram

    /* ------------------------------------------------------------------ */
    /* .data  — initialised globals/statics                                */
    /* For BRAM-only systems, LMA == VMA (no copy-from-flash needed)      */
    /* ------------------------------------------------------------------ */
    .data : {
        . = ALIGN(4);
        *(.data)
        *(.data.*)
        . = ALIGN(4);
    } > bram

    /* ------------------------------------------------------------------ */
    /* .bss   — zero-initialised globals/statics                           */
    /* start.S zeroes this region before calling main()                   */
    /* ------------------------------------------------------------------ */
    .bss : {
        . = ALIGN(4);
        __bss_start = .;
        *(.bss)
        *(.bss.*)
        *(COMMON)
        . = ALIGN(4);
        __bss_end = .;
    } > bram

    /* ------------------------------------------------------------------ */
    /* Stack lives between __bss_end and 0x1000.                           */
    /* start.S sets sp = 0x1000 (top of BRAM), grows downward.            */
    /* If .text + .data + .bss ever exceeds ~3.5 KB you will get overlap. */
    /* ------------------------------------------------------------------ */
    __stack_top = ORIGIN(bram) + LENGTH(bram);  /* 0x1000 */

    /* ------------------------------------------------------------------ */
    /* Discard C++ exception tables and other unused sections              */
    /* ------------------------------------------------------------------ */
    /DISCARD/ : {
        *(.eh_frame)
        *(.eh_frame_hdr)
        *(.note.*)
        *(.comment)
    }
}
