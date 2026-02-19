# RISC-V SoC from Scratch

Educational project building a complete RISC-V System-on-Chip with PicoRV32 CPU, memory-mapped peripherals, and bare-metal software.

## Current Status

Working SoC with GPIO and UART peripherals, verified in simulation.

## Architecture
```
simple_soc
├── PicoRV32 CPU (RV32I)
├── Memory Decoder (address router)
├── BRAM (4KB instruction + data)
├── GPIO (32-bit output register)
└── UART TX (115200 baud, 8N1)
```

**Memory Map:**
- `0x0000_0000` - BRAM (instruction/data)
- `0x2000_0000` - UART data register
- `0x2000_0004` - UART status register (bit 0 = busy)
- `0x3000_0000` - GPIO output register

## Files

**RTL (Design Sources):**
- `picorv32.v` - CPU core
- `memory_decoder.v` - Address router
- `simple_bram.v` - 4KB memory with test program
- `gpio_peripheral.v` - GPIO output register
- `uart_tx_peripheral.v` - Serial transmitter
- `simple_soc.v` - Top-level integration

**Simulation:**
- `tb_top.v` - Complete system testbench

## Running Simulation

1. Create Vivado project
2. Add all RTL files as design sources
3. Add `tb_top.v` as simulation source, set as top
4. Run Behavioral Simulation
5. In TCL console: `run 600000ns`

**Expected output:**
```
PASS  GPIO : gpio_out = 0x00000001
PASS  CPU  : no trap
UART RX: 0x48 ('H')
UART RX: 0x69 ('i')
UART RX: 0x21 ('!')
```

## Test Program

Assembly program pre-loaded in BRAM:
1. Write `1` to GPIO (address 0x30000000)
2. Send 'H' via UART (address 0x20000000)
3. Poll UART status until transmission complete
4. Send 'i' (with polling)
5. Send '!' (with polling)
6. Loop forever

Demonstrates memory-mapped I/O and busy-wait synchronization between fast CPU and slow peripherals.

## Key Implementation Details

**GPIO Peripheral:**
- Single 32-bit register, 1-cycle latency
- Supports both read and write

**UART Peripheral:**
- 10 bits per byte (1 start + 8 data + 1 stop)
- 434 clock cycles per bit at 50MHz = 115200 baud
- Transmit time: ~87,000ns per byte
- Status register allows software polling

**Memory Decoder:**
- Combinational address decode (top 4 bits)
- Routes CPU requests to correct peripheral
- Returns 0xDEADDEAD for unmapped addresses

**CPU-Peripheral Synchronization:**
- Software polls status register before each write
- Busy-wait loop: `LW status → ANDI → BNE`
- Prevents data loss when peripheral slower than CPU

## Common Issues Fixed

**Issue 1: Instruction Encoding**
- Bug: `LUI x2, 0x20000` encoded as 0x200000B7 (rd=1)
- Fix: Correct encoding 0x20000137 (rd=2)
- Impact: Wrong register loaded, UART writes to address 0

**Issue 2: Debug PC Visibility**
- Bug: `debug_pc` showed 0 between instruction fetches
- Fix: Latch PC value on every `mem_instr` access
- Impact: Waveform now shows stable PC progression

**Issue 3: UART Data Loss**
- Bug: CPU sent bytes 400x faster than UART could transmit
- Fix: Software busy-wait polling of status register
- Impact: All bytes transmitted successfully

## Signal Reference

**CPU Memory Interface:**
- `mem_valid` - Request active
- `mem_instr` - 1=instruction fetch, 0=data
- `mem_addr` - Address
- `mem_wdata` - Write data
- `mem_wstrb` - Byte enables (0=read, F=write)
- `mem_ready` - Operation complete
- `mem_rdata` - Read data

**Peripheral Interface (example GPIO):**
- `gpio_valid` - Access request
- `gpio_we` - Write enable
- `gpio_wdata` - Data to write
- `gpio_rdata` - Data read back
- `gpio_ready` - Operation complete
- `gpio_out` - Physical output pins

## Next Steps

- Interrupt controller + timer peripheral
- RISC-V GCC toolchain + C programming
- FPGA synthesis and hardware deployment
- Additional peripherals (SPI, I2C, PWM)

## Resources

- [PicoRV32 Core](https://github.com/YosysHQ/picorv32)
- [RISC-V ISA Spec](https://riscv.org/technical/specifications/)
- [RISC-V Assembly Reference](https://github.com/riscv/riscv-asm-manual)

## License

Educational project. PicoRV32 core uses ISC license.