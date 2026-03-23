# RISC-V SoC

PicoRV32-based SoC with memory-mapped peripherals, bare-metal C firmware, AXI-Lite interconnect, and HLS-generated minimal dot product accelerator. 
Verified in Vivado behavioral simulation.

---

## Architecture

```
top_axi.v
├── picorv32 (submodule)      RV32I CPU core
├── picorv32_axi_adapter      native valid/ready → AXI-Lite master
├── axi_crossbar              1 master → 4 slaves, decode on addr[31:28]
├── bram_axi_slave            Slave 0: 4KB instruction + data memory
├── uart_axi_slave            Slave 1: 115200 baud TX
├── gpio_axi_slave            Slave 2: 32-bit output register
└── dot_product               Slave 3: INT8 dot product accelerator (HLS)
```

**Memory Map:**

| Address | Peripheral | Access |
|---|---|---|
| `0x0000_0000` | BRAM (4KB) | R/W |
| `0x2000_0000` | UART TX data | W |
| `0x2000_0004` | UART TX status | R |
| `0x3000_0000` | GPIO output | R/W |
| `0x4000_0000` | Dot product accelerator | R/W |

UART status bit 0 = `tx_busy` (1 = transmitting, 0 = ready)

**Accelerator Register Map (base 0x4000_0000):**

| Offset | Name | Access | Description |
|---|---|---|---|
| `0x00` | CTRL | R/W | bit0=ap_start, bit1=ap_done, bit2=ap_idle |
| `0x10`–`0x48` | vec_a[0..7] | W | INT8 input vector A, stride 0x8 |
| `0x50`–`0x88` | vec_b[0..7] | W | INT8 input vector B, stride 0x8 |
| `0x90` | result | R | 32-bit dot product result |
| `0xa0` | busy | R | bit0 = busy flag |

---

## File Structure

```
.
├── firmware
│   ├── start.S          startup: zero regs, set sp=0x1000, call main()
│   ├── link.ld          .text at 0x0, stack top at 0x1000 (4KB BRAM)
│   ├── main.c           uart_print() + gpio_write() + accel_dot_product()
│   └── Makefile         ELF → BIN → byte-swapped HEX for $readmemh
│
├── hls
│   └── dot_product
│       ├── dot_product.cpp      8x mac_unit, BIND_OP DSP, adder tree
│       └── dot_product_tb.cpp   C testbench, verifies result=120
│
└── rtl
    ├── axi
    │   ├── top_axi.v                       SoC top level
    │   ├── axi_crossbar.v                  1 master → 4 slaves
    │   ├── bram_axi_slave.v                4KB BRAM
    │   ├── gpio_axi_slave.v                32-bit GPIO
    │   ├── uart_axi_slave.v                115200 baud TX
    │   ├── dot_product.v                   HLS accelerator top
    │   ├── dot_product_CTRL_s_axi.v        HLS AXI-Lite wrapper
    │   ├── dot_product_mac_unit.v          HLS MAC unit (1 DSP each)
    │   └── dot_product_mul_8s_8s_16_4_1.v HLS multiplier primitive
    ├── sim
    │   ├── tb_top.v         full SoC testbench (AXI + UART + accel monitor)
    │   ├── tb_gpio.v        GPIO peripheral unit test
    │   ├── tb_picorv32.v    CPU instruction test
    │   └── wvfrm            simulation waveform screenshots
    └── soc
        ├── top.v            original SoC (valid/ready bus, pre-AXI)
        ├── decoder.v        combinational address router
        ├── bram.v           4KB BRAM
        ├── gpio.v           GPIO peripheral
        ├── uart_tx.v        UART TX peripheral
        └── cpu              PicoRV32 (forked from YosysHQ/picorv32)
```

---

## Simulation Waveforms

**Full SoC with HLS accelerator (`tb_top - hls.png`)**

![tb_top - hls](rtl/sim/wvfrm/tb_top%20-%20hls.png)

GPIO transitions from `0x00000001` to `0xDEADBEEF` after both accelerator tests complete. AXI bus activity visible throughout: instruction fetches, UART polling, and accelerator register writes to `0x4000_xxxx`.

**AXI-Lite SoC without accelerator (`tb_top - axi.png`)**

![tb_top - axi](rtl/sim/wvfrm/tb_top%20-%20axi.png)

**Original valid/ready SoC (`tb_top - soc.png`)**

![tb_top - soc](rtl/sim/wvfrm/tb_top%20-%20soc.png)

**GPIO unit test (`tb_gpio.png`)**

![tb_gpio](rtl/sim/wvfrm/tb_gpio.png)

**PicoRV32 instruction test (`tb_picorv32.png`)**

![tb_picorv32](rtl/sim/wvfrm/tb_picorv32.png)

---

## Firmware Build

```bash
sudo apt install gcc-riscv64-unknown-elf xxd
cd firmware/
make        # → firmware.elf, firmware.bin, firmware.hex
make clean
```

Compiler flags: `-march=rv32i -mabi=ilp32 -nostdlib -nostartfiles -ffreestanding -Os`

No libgcc dependency - integer printing uses repeated subtraction to avoid `__udivsi3`/`__umodsi3` on rv32i.

Current binary: **1168 bytes** (28% of 4KB BRAM)

---

## HLS Accelerator Build

Requires Vitis HLS 2025.2. Target: `xc7a100t-csg324-1`, clock: 10ns.

```
1. Create project with hls/dot_product/dot_product.cpp
2. Set top function: dot_product
3. Run C Simulation    → result=120 PASS
4. Run C Synthesis     → 8 DSP, 8x mac_unit II=1
5. Run C/RTL Cosim     → RTL result=120 PASS
6. Export RTL (Vivado IP)
7. Copy hdl/verilog/*.v to rtl/axi/
```

Synthesis results: 8 DSP48, 563 LUT, 475 FF, latency 50ns, II=6.
![dot_product - C Synthesis](hls/dot_product/dot_product%20-%20C%20Synthesis.png)

---

## Simulation

Hardcode firmware path in `bram_axi_slave.v`:
```verilog
$readmemh("C:/path/to/firmware/firmware.hex", memory);
```

Add all files under `rtl/axi/` and `rtl/soc/cpu/picorv32.v` as design sources. Add `rtl/sim/tb_top.v` as simulation source and set as top. Run Behavioral Simulation:

```tcl
run 60000000ns
```

Expected output:
```
[BRAM-AXI] Loaded firmware.hex
[100000 ns] Reset released
[t ns] GPIO WRITE: 0x00000001
[t ns] UART RX: 'P'  (0x50)
...
[t ns] ACCEL-W: addr=0x40000010 data=0x00000001
[t ns] ACCEL-R: addr=0x40000090
[t ns] ACCEL-RESULT: data=0x00000078
...
  PASS  GPIO  : 0x00000001 seen within 500 us
  PASS  CPU   : no trap
```

---

## Implementation Notes

**AXI-Lite bus** - five independent channels: AW, W, B (write path) and AR, R (read path). Crossbar decodes `addr[31:28]` and latches slave selection at AW/AR handshake so the B/R response mux stays stable for the full transaction.

**Adapter** - `picorv32_axi_adapter` is built into `picorv32.v`. Converts PicoRV32 `mem_valid/mem_ready` to AXI-Lite. No separate adapter file needed.

**Slave interface** - AW and W channels buffered independently since they can arrive in any order. Same pattern across all four slaves.

**UART state machine** - TX FSM and MMIO handshake share one `always @(posedge clk)` block. Two separate blocks driving `tx_state` causes a register conflict that locks `bit_idx` at 1 permanently.

**BRAM byte order** - raw `xxd` output is little-endian. `$readmemh` loads each line as a big-endian word. Without `--reverse-bytes=4` the CPU jumps to a garbage address on the first cycle.

**`$readmemh` path** - string parameters do not override reliably in XSim. Hardcode the absolute path directly in the `initial` block of `bram_axi_slave.v`.

**HLS BIND_OP scope** - `BIND_OP` must be placed in the same scope as the variable being bound, inside `mac_unit`, not at the call site. Placing it at the caller has no effect on the multiply in the callee.

**HLS INLINE off** - required on `mac_unit` or Vitis merges all 8 instances into one DSP cascade chain, giving 4 DSPs instead of 8.

**HLS ALLOCATION vs BIND_OP** - `ALLOCATION` sets a ceiling on resource sharing. For INT8 multiplies that fit in LUT fabric, it allows 0 DSPs. `BIND_OP` with `impl=dsp` is the only way to force DSP usage.

**ap_ctrl_hs** - write `0x1` to CTRL offset `0x00` to assert ap_start. Poll bit1 (ap_done) to detect completion. ap_done clears on read.

**HLS port naming** - generated ports use uppercase CTRL prefix (`s_axi_CTRL_AWADDR`). `top_axi.v` maps these to lowercase crossbar wires and slices the 32-bit address to 8 bits for the accelerator.

---

## Signal Reference

| Signal | Dir | Description |
|---|---|---|
| `mem_valid` | CPU → adapter | request active |
| `mem_instr` | CPU → adapter | 1=fetch, 0=data |
| `mem_addr` | CPU → adapter | byte address |
| `mem_wdata` | CPU → adapter | write data |
| `mem_wstrb` | CPU → adapter | byte enables (0000=read) |
| `mem_ready` | adapter → CPU | transaction complete |
| `mem_rdata` | adapter → CPU | read data |

| Channel | Signals | Direction |
|---|---|---|
| AW | `awaddr`, `awvalid`, `awready` | master → slave |
| W | `wdata`, `wstrb`, `wvalid`, `wready` | master → slave |
| B | `bresp`, `bvalid`, `bready` | slave → master |
| AR | `araddr`, `arvalid`, `arready` | master → slave |
| R | `rdata`, `rresp`, `rvalid`, `rready` | slave → master |

---

## References

- [PicoRV32](https://github.com/YosysHQ/picorv32)
- [RISC-V ISA Specification](https://riscv.org/technical/specifications/)
- [RISC-V GNU Toolchain](https://github.com/riscv-collab/riscv-gnu-toolchain)
- [AMBA AXI Protocol Specification](https://developer.arm.com/documentation/ihi0022)
- [Vitis HLS User Guide UG1399](https://docs.amd.com/r/en-US/ug1399-vitis-hls)