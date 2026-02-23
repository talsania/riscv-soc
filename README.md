# RISC-V SoC

PicoRV32-based SoC with memory-mapped peripherals and bare-metal C firmware, verified in Vivado simulation.

---

## Architecture

```
top.v
├── picorv32       RV32I CPU core
├── decoder        Address router (combinational)
├── bram           4KB instruction + data memory
├── gpio           32-bit output register
└── uart_tx        115200 baud 8N1 transmitter
```

**Memory Map:**

| Address       | Peripheral     | Access |
|---------------|----------------|--------|
| `0x0000_0000` | BRAM (4KB)     | R/W    |
| `0x2000_0000` | UART TX data   | W      |
| `0x2000_0004` | UART TX status | R      |
| `0x3000_0000` | GPIO output    | R/W    |

UART status bit 0 = `tx_busy` (1 = transmitting, 0 = ready)

---

## Repository Structure

```
├── firmware/
│   ├── start.S       Startup: zero registers, set stack, zero .bss, call main()
│   ├── link.ld       Maps .text/.data/.bss into 4KB BRAM at 0x00000000
│   ├── main.c        GPIO write + UART string output with tx_busy polling
│   └── Makefile      ELF → BIN → hex (with byte-swap for $readmemh)
└── rtl/soc/
    ├── top.v         Top-level integration
    ├── decoder.v     Combinational address decode on mem_addr[31:28]
    ├── bram.v        4KB BRAM, initialised via $readmemh
    ├── gpio.v        Single 32-bit register, 1-cycle latency
    ├── uart_tx.v     8N1 TX, baud tick counter, MMIO handshake
    └── cpu/picorv32.v
    sim/tb_top.v      GPIO check + UART byte decoder testbench
```

---

## Firmware Build

```bash
sudo apt install gcc-riscv64-unknown-elf xxd
cd firmware/
make        # → firmware.elf, firmware.bin, firmware.hex
make clean
```

Compiler flags: `-march=rv32i -mabi=ilp32 -nostdlib -nostartfiles -ffreestanding -Os`

Hex conversion byte-swaps for `$readmemh` word order:
```bash
objcopy --reverse-bytes=4 firmware.bin firmware.swap
xxd -p -c4 firmware.swap > firmware.hex
```

No libgcc dependency — integer printing uses repeated subtraction instead of `%`/`/` to avoid `__udivsi3`/`__umodsi3` on rv32i.

Current binary: **996 bytes** (24% of 4KB BRAM)

---

## Simulation

Set `HEX_FILE` in `bram.v` to the absolute path of `firmware.hex`, then run behavioral simulation in Vivado.

Expected output in TCL console:
```
DECODER -> GPIO WRITE  addr=0x30000000  data=0x00000001
UART MMIO: wrote 0x50 ('P')
UART TX sent: 0x50 ('P')
UART RX: 'P'  (0x50)
...
PASS  GPIO : 0x00000001 seen within 500 us
PASS  CPU  : no trap
```

Each UART byte takes ~87,000 ns at 115200 baud. Allow at least 30ms simulation time for a full string.

---

## Implementation Notes

**Decoder** — combinational decode, zero latency. `uart_rdata` must be wired from `uart_tx` back through the decoder to `mem_rdata`; without it the `tx_busy` poll loop stalls permanently.

**UART** — TX state machine and MMIO handshake share one `always @(posedge clk)` block. Splitting into two blocks causes both to drive `tx_state` on the same edge, locking `bit_idx` at 1 in DATA state.

**BRAM** — `$readmemh` expects one word per line in big-endian byte order. Raw `xxd` output is little-endian; `objcopy --reverse-bytes=4` corrects this before conversion.

**Stack** — initialised in `start.S` to `0x1000` (top of 4KB), grows downward.

---

## Signal Reference

**CPU memory interface:**

| Signal | Dir | Description |
|--------|-----|-------------|
| `mem_valid` | CPU→dec | Request active |
| `mem_instr` | CPU→dec | 1=fetch, 0=data |
| `mem_addr` | CPU→dec | Byte address |
| `mem_wdata` | CPU→dec | Write data |
| `mem_wstrb` | CPU→dec | Byte enables (0000=read) |
| `mem_ready` | dec→CPU | Transaction complete (1-cycle pulse) |
| `mem_rdata` | dec→CPU | Read data |

---

## Notes

**Implemented and verified in simulation:**
- RV32I CPU executing compiled C firmware
- BRAM loaded from compiled hex at simulation start
- GPIO write verified via testbench
- UART TX with `tx_busy` polling — zero dropped bytes
- UART RX decoded in testbench at 115200 baud

**Next:**
- AXI-Lite bus replacing simple valid/ready interface
- `picorv32_axi_adapter` bridge
- AXI crossbar with BRAM, GPIO, UART as AXI-Lite slaves
- HLS accelerator integration via AXI

---

## References

- [PicoRV32](https://github.com/YosysHQ/picorv32)
- [RISC-V ISA Spec](https://riscv.org/technical/specifications/)
- [RISC-V GNU Toolchain](https://github.com/riscv-collab/riscv-gnu-toolchain)