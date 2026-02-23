# =============================================================================
# Makefile  —  PicoRV32 Firmware Build
#
# Targets:
#   make          → build all (ELF, binary, hex)
#   make sim      → build + show disassembly (good for verifying output)
#   make clean    → remove all build artefacts
#
# Requires: riscv32-unknown-elf-gcc (or riscv64-unknown-elf-gcc with -m32)
#
# Install options:
#   Ubuntu/Debian : sudo apt install gcc-riscv64-linux-gnu
#                   (use CROSS=riscv64-linux-gnu and add -march/-mabi flags)
#   Prebuilt      : https://github.com/sifive/freedom-tools/releases
#                   https://github.com/riscv-collab/riscv-gnu-toolchain
#
# Toolchain auto-detection: tries riscv32 first, falls back to riscv64
# =============================================================================

# --------------------------------------------------------------------------- #
# Toolchain                                                                    #
# --------------------------------------------------------------------------- #
CROSS_32  := riscv32-unknown-elf
CROSS_64  := riscv64-unknown-elf

# Detect which toolchain is installed
ifeq ($(shell which $(CROSS_32)-gcc 2>/dev/null),)
    CROSS := $(CROSS_64)
else
    CROSS := $(CROSS_32)
endif

CC      := $(CROSS)-gcc
OBJCOPY := $(CROSS)-objcopy
OBJDUMP := $(CROSS)-objdump
SIZE    := $(CROSS)-size

# --------------------------------------------------------------------------- #
# Compiler flags                                                               #
# --------------------------------------------------------------------------- #
#   -march=rv32i      : base integer ISA only (matches PicoRV32 default)
#   -mabi=ilp32       : 32-bit integer ABI, no hardware float
#   -nostdlib         : no standard library (no printf, malloc, etc.)
#   -nostartfiles     : we supply our own start.S
#   -ffreestanding    : tell compiler this is a bare-metal environment
#   -Os               : optimise for size (4KB BRAM is tight)
#   -g                : debug info (for objdump readability)
#   -Wall             : all warnings
CFLAGS  := -march=rv32i -mabi=ilp32 \
            -nostdlib -nostartfiles -ffreestanding \
            -Os -g -Wall

LDFLAGS := -T link.ld -lgcc

# --------------------------------------------------------------------------- #
# Sources & outputs                                                            #
# --------------------------------------------------------------------------- #
SRCS    := start.S main.c
TARGET  := firmware

ELF     := $(TARGET).elf
BIN     := $(TARGET).bin
HEX     := $(TARGET).hex       # Verilog $readmemh format
DUMP    := $(TARGET).dump      # human-readable disassembly

# --------------------------------------------------------------------------- #
# Default target                                                               #
# --------------------------------------------------------------------------- #
.PHONY: all
all: $(HEX) size

# --------------------------------------------------------------------------- #
# Link ELF                                                                     #
# --------------------------------------------------------------------------- #
$(ELF): $(SRCS) link.ld
	@echo "[LD]  $@"
	$(CC) $(CFLAGS) $(LDFLAGS) $(SRCS) -o $@

# --------------------------------------------------------------------------- #
# Raw binary (needed for hex conversion)                                       #
# --------------------------------------------------------------------------- #
$(BIN): $(ELF)
	@echo "[BIN] $@"
	$(OBJCOPY) -O binary $< $@

# --------------------------------------------------------------------------- #
# Verilog hex — one 32-bit word per line, big-endian bytes                    #
#                                                                              #
# Format understood by:  $readmemh("firmware.hex", memory);                   #
#                                                                              #
# xxd -p -c4   : dump 4 bytes per line as plain hex (no 0x, no spaces)        #
# awk           : print each line as-is (already correct 8-char hex word)      #
# --------------------------------------------------------------------------- #
$(HEX): $(BIN)
	@echo "[HEX] $@"
	$(OBJCOPY) -I binary -O binary --reverse-bytes=4 $(BIN) $(BIN).swap
	xxd -p -c4 $(BIN).swap > $(HEX)
	@rm -f $(BIN).swap
	@echo "      → $(HEX) ready for \$$readmemh"
	@wc -l $(HEX) | awk '{print "      Lines (words):", $$1, "(max 1024 for 4KB BRAM)"}'

# --------------------------------------------------------------------------- #
# Size report                                                                  #
# --------------------------------------------------------------------------- #
.PHONY: size
size: $(ELF)
	@echo ""
	@echo "=== Size Report ==="
	$(SIZE) $(ELF)
	@echo "=== BRAM budget: 4096 bytes ==="
	@echo ""

# --------------------------------------------------------------------------- #
# Disassembly — useful for verifying instruction encoding                      #
# --------------------------------------------------------------------------- #
$(DUMP): $(ELF)
	$(OBJDUMP) -d -S $< > $@

.PHONY: sim
sim: $(DUMP)
	@echo "[DUMP] $(DUMP)"
	@head -60 $(DUMP)

# --------------------------------------------------------------------------- #
# Helper: show full disassembly in terminal                                    #
# --------------------------------------------------------------------------- #
.PHONY: disasm
disasm: $(DUMP)
	cat $(DUMP)

# --------------------------------------------------------------------------- #
# Clean                                                                        #
# --------------------------------------------------------------------------- #
.PHONY: clean
clean:
	@echo "[CLEAN]"
	rm -f $(ELF) $(BIN) $(HEX) $(DUMP)

# --------------------------------------------------------------------------- #
# Help                                                                         #
# --------------------------------------------------------------------------- #
.PHONY: help
help:
	@echo ""
	@echo "Targets:"
	@echo "  make          Build ELF + BIN + HEX (default)"
	@echo "  make sim      Build + print first 60 lines of disassembly"
	@echo "  make disasm   Print full disassembly"
	@echo "  make clean    Remove build artefacts"
	@echo ""
	@echo "Output files:"
	@echo "  firmware.elf  Linked ELF (for GDB / objdump)"
	@echo "  firmware.bin  Raw binary"
	@echo "  firmware.hex  Verilog hex for \$$readmemh"
	@echo ""
