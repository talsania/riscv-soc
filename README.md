## Project Overview

This repository documents the journey of building a RISC-V-based SoC from scratch, starting with understanding the CPU core and progressively adding peripherals, interrupts, and custom hardware accelerators.

### Development Timeline

- **Phase 1**: CPU Understanding & Simulation
- **Phase 2 (in progress...)**: Minimal SoC with Memory-Mapped Peripherals
- **Phase 3**: Interrupt Support
- **Phase 4**: AXI Bus Integration & Custom Accelerator

## Repository Structure

```
.
├── rtl/
│   ├── cpu/              # PicoRV32 core
│   └── peripherals/      # GPIO, UART, etc.
├── sim/
│   └── tb/               # Testbenches
├── sw/                   # Software (C programs)
├── docs/                 # Documentation
└── README.md
```

## Signal Reference

### Memory Interface Signals

**CPU to Memory (Request):**
- `mem_valid` - CPU is requesting memory access (1=active, 0=idle)
- `mem_instr` - Access type (1=instruction fetch, 0=data access)
- `mem_addr[31:0]` - Address to read/write
- `mem_wdata[31:0]` - Data to write (for stores)
- `mem_wstrb[3:0]` - Byte enables (0000=read, 1111=write word)

**Memory to CPU (Response):**
- `mem_ready` - Memory operation complete (1=ready, 0=busy)
- `mem_rdata[31:0]` - Data read from memory (for loads/fetches)

### Common Abbreviations

**Memory Operations:**
- IFETCH = Instruction Fetch
- DWRITE = Data Write (Store)
- DREAD = Data Read (Load)

**Address Notation:**
- @0xXX = Memory address being accessed
- [0x100] = Contents of memory address 0x100

**Register Operations:**
- xN = RISC-V register N (x0-x31)
- xN=value = Register N gets assigned value

**Instruction Types:**
- R-type = Register-register operations (ADD, SUB, etc.)
- I-type = Immediate operations (ADDI, LOAD, etc.)
- S-type = Store operations (SW, SH, SB)
- B-type = Branch operations (BEQ, BNE, etc.)
- J-type = Jump operations (JAL, JALR)

## Memory Interface Protocol

The PicoRV32 uses a simple valid/ready handshake:

```
Cycle 1: CPU asserts mem_valid with address
         CPU provides wdata and wstrb for writes
         
Cycle 2: Memory processes request
         Memory asserts mem_ready
         Memory provides rdata for reads
         
Cycle 3: Transaction completes
         Both valid and ready deassert
```

For instruction fetches: `mem_instr=1`  
For data access: `mem_instr=0`

For writes: `mem_wstrb != 0` (indicates which bytes to write)  
For reads: `mem_wstrb == 0`

## Testing & Verification

Each component is tested independently before integration:

1. **Unit tests** - Individual peripherals (GPIO, UART)
2. **Integration tests** - CPU with peripherals
3. **Software tests** - Bare-metal C programs
4. **Waveform verification** - Signal timing and protocol compliance

## Build Instructions

### Prerequisites

- Xilinx Vivado (tested with 2020.1+)
- RISC-V GCC toolchain (for compiling C code)
- Python 3.x (for helper scripts)

### Running Simulations

**CPU Only:**
```bash
# In Vivado:
1. Create new project
2. Add rtl/cpu/picorv32.v
3. Add sim/tb/tb_picorv32_simple.v
4. Set tb_picorv32_simple as top
5. Run Behavioral Simulation
```

**SoC with Peripherals:**
```bash
# Instructions will be added as components are completed
```

## Peripheral Specifications

### GPIO Peripheral

**Address:** 0x30000000  
**Type:** Write/Read  
**Width:** 32 bits  

**Usage:**
```c
*(volatile uint32_t*)0x30000000 = value;  // Write
uint32_t val = *(volatile uint32_t*)0x30000000;  // Read
```

### UART Peripheral

**Address:** 0x20000000  
**Type:** Write-only (TX)  
**Width:** 8 bits  

**Usage:**
```c
*(volatile uint8_t*)0x20000000 = 'A';  // Transmit character
```

**Baud rate:** Configurable (default 115200)  
**Format:** 8N1 (8 data bits, no parity, 1 stop bit)

## Software Development

### Bare-Metal C Programming

Programs run directly on hardware without an operating system. Key points:

- **volatile keyword**: Required for MMIO to prevent compiler optimization
- **Memory layout**: Defined by linker script
- **No standard library**: Must implement basic functions
- **Direct hardware access**: Peripherals accessed via pointers

### Compilation Flow

```
C Source → RISC-V GCC → ELF Binary → objcopy → HEX/BIN → Memory Init File
```

Example:
```bash
riscv32-unknown-elf-gcc -march=rv32i -mabi=ilp32 -nostdlib -o program.elf main.c
riscv32-unknown-elf-objcopy -O binary program.elf program.bin
python bin2hex.py program.bin > program.hex
```

## Future Enhancements

- Multi-cycle/pipelined CPU variants
- Cache hierarchy (I-cache, D-cache)
- Debug interface (JTAG)
- Bootloader implementation
- FPGA synthesis and deployment
- Linux port (long-term goal)

## Resources

### Documentation
- [PicoRV32 Repository](https://github.com/YosysHQ/picorv32)
- [RISC-V ISA Specification](https://riscv.org/technical/specifications/)
- [RISC-V Assembly Programmer's Manual](https://github.com/riscv/riscv-asm-manual)

### Tools
- [RISC-V GNU Toolchain](https://github.com/riscv/riscv-gnu-toolchain)
- [Xilinx Vivado](https://www.xilinx.com/products/design-tools/vivado.html)

## License

This project uses the PicoRV32 core which is licensed under ISC. See individual component licenses for details.

---
This is an educational project focused on learning RISC-V architecture and SoC design. The emphasis is on understanding rather than optimization.