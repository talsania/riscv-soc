# RISC-V SoC

PicoRV32-based SoC with memory-mapped peripherals, bare-metal C firmware, and AXI-Lite interconnect. Verified in Vivado behavioral simulation.

---

## Architecture

```
top_axi.v
├── picorv32                  RV32I CPU core
├── picorv32_axi_adapter      native valid/ready → AXI-Lite master
├── axi_crossbar              1 master → 4 slaves, decode on addr[31:28]
├── bram_axi_slave            Slave 0: 4KB instruction + data memory
├── uart_axi_slave            Slave 1: 115200 baud TX
├── gpio_axi_slave            Slave 2: 32-bit output register
└── (Slave 3 reserved)        0x4000_0000 — accelerator slot
```

**Memory Map:**

| Address | Peripheral | Access |
|---|---|---|
| `0x0000_0000` | BRAM (4KB) | R/W |
| `0x2000_0000` | UART TX data | W |
| `0x2000_0004` | UART TX status | R |
| `0x3000_0000` | GPIO output | R/W |
| `0x4000_0000` | Reserved (accelerator) | R/W |

UART status bit 0 = `tx_busy` (1 = transmitting, 0 = ready)

---

## File Structure

```
├── firmware/
│   ├── start.S          startup: zero regs, set stack to 0x1000, call main()
│   ├── link.ld          .text at 0x0, stack top at 0x1000 (4KB BRAM)
│   ├── main.c           gpio_write() + uart_print() with tx_busy polling
│   └── Makefile         ELF → BIN → byte-swapped HEX for $readmemh
│
└── rtl/
    ├── soc/
    │   ├── top.v            original SoC (valid/ready bus)
    │   ├── decoder.v        combinational address router
    │   ├── bram.v           4KB BRAM
    │   ├── gpio.v           GPIO peripheral
    │   ├── uart_tx.v        UART TX peripheral
    │   └── cpu/picorv32.v   PicoRV32 core + built-in AXI adapter
    │
    ├── axi/
    │   ├── top_axi.v        AXI-Lite SoC top level
    │   ├── axi_crossbar.v   address-decode router, 4 slave slots
    │   ├── bram_axi_slave.v BRAM with AXI-Lite slave interface
    │   ├── gpio_axi_slave.v GPIO with AXI-Lite slave interface
    │   └── uart_axi_slave.v UART TX with AXI-Lite slave interface
    │
    └── sim/
        └── tb_top.v         GPIO check + UART decoder + AXI bus monitor
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

Hardcode the firmware path directly in `bram_axi_slave.v`:
```verilog
$readmemh("C:/path/to/firmware/firmware.hex", memory);
```

Add all files under `rtl/axi/` and `rtl/soc/cpu/picorv32.v` as design sources. Add `sim/tb_top.v` as simulation source and set as top. Run Behavioral Simulation → TCL: `run 30000000ns`

Expected output:
```
[BRAM-AXI] Loaded firmware.hex
[100000 ns] Reset released

[t ns] AXI-AW: addr=0x30000000
[t ns] AXI-W : data=0x00000001 strb=1111
[t ns] GPIO WRITE: 0x00000001
[t ns] AXI-AR: addr=0x20000004
[t ns] AXI-R : data=0x00000000
[t ns] UART MMIO: wrote 0x50 ('P')
[t ns] UART TX sent: 0x50 ('P')
[t ns] UART RX: 'P'  (0x50)
...
  PASS  GPIO : 0x00000001 seen within 500 us
  PASS  CPU  : no trap
```

Each UART byte takes ~87,000 ns at 115200 baud. Allow at least 30ms simulation time for full string output.

---

## Implementation Notes

**AXI-Lite bus** — five independent channels: AW, W, B (write path) and AR, R (read path). Each has its own `valid/ready` handshake. Transaction completes when both are high on the same clock edge. Crossbar decodes `addr[31:28]` and latches slave selection at AW/AR handshake so the B/R response mux stays stable for the full transaction.

**Adapter** — `picorv32_axi_adapter` is built into `picorv32.v`. Converts PicoRV32's `mem_valid/mem_ready` interface to AXI-Lite using ack registers. No separate adapter file needed.

**Slave interface** — AW and W channels buffered independently since they can arrive in any order. Write executes when both are captured. Read returns data one cycle after AR handshake. Same pattern across BRAM, GPIO, and UART slaves.

**UART state machine** — TX state machine and MMIO handshake share one `always @(posedge clk)` block. Two separate blocks both driving `tx_state` causes a register conflict that locks `bit_idx` at 1 permanently.

**BRAM byte order** — raw `xxd` output is little-endian. `$readmemh` loads each line as a big-endian word. Without `--reverse-bytes=4` every instruction is byte-swapped and the CPU jumps to a garbage address on the first cycle.

**`$readmemh` path** — string parameters do not override reliably in XSim. Hardcode the absolute path directly in the `initial` block of `bram_axi_slave.v`. Do not pass via module parameter.

**Stack** — `start.S` sets `sp = 0x1000` (top of 4KB BRAM), grows downward. With 996-byte binary, ~3KB available for stack and heap.

---

## Signal Reference

**PicoRV32 native interface:**

| Signal | Dir | Description |
|---|---|---|
| `mem_valid` | CPU → adapter | request active |
| `mem_instr` | CPU → adapter | 1 = fetch, 0 = data |
| `mem_addr` | CPU → adapter | byte address |
| `mem_wdata` | CPU → adapter | write data |
| `mem_wstrb` | CPU → adapter | byte enables (0000 = read) |
| `mem_ready` | adapter → CPU | transaction complete |
| `mem_rdata` | adapter → CPU | read data |

**AXI-Lite channels:**

| Channel | Signals | Direction |
|---|---|---|
| AW | `awaddr`, `awvalid`, `awready` | master → slave |
| W | `wdata`, `wstrb`, `wvalid`, `wready` | master → slave |
| B | `bresp`, `bvalid`, `bready` | slave → master |
| AR | `araddr`, `arvalid`, `arready` | master → slave |
| R | `rdata`, `rresp`, `rvalid`, `rready` | slave → master |

---

## Notes

**Implemented and verified in simulation:**
- RV32I CPU executing compiled C firmware over AXI-Lite
- BRAM loaded from compiled hex at simulation start
- GPIO write verified via testbench
- UART TX with `tx_busy` polling — zero dropped bytes
- UART RX decoded in testbench at 115200 baud
- Slave 3 slot wired and reserved at `0x4000_0000`

---

## References

- [PicoRV32](https://github.com/YosysHQ/picorv32)
- [RISC-V ISA Specification](https://riscv.org/technical/specifications/)
- [RISC-V GNU Toolchain](https://github.com/riscv-collab/riscv-gnu-toolchain)
- [AMBA AXI Protocol Specification](https://developer.arm.com/documentation/ihi0022)