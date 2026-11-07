CROSS   ?= riscv64-unknown-elf-
CFLAGS  = -march=rv32e -mabi=ilp32e -Os -ffreestanding -nostdlib -Wall -Wextra
LDFLAGS = -march=rv32e -mabi=ilp32e -nostdlib -T link.ld -Wl,--gc-sections
PY      ?= python3

all: hello.hex

%.elf: start.S %.c tinyrv.h link.ld
	$(CROSS)gcc $(CFLAGS) -ffunction-sections $(LDFLAGS) -o $@ start.S $*.c -lgcc

%.bin: %.elf
	$(CROSS)objcopy -O binary $< $@

%.hex: %.bin
	$(PY) bin2hex.py $< $@

%.lst: %.elf
	$(CROSS)objdump -d $< > $@

clean:
	rm -f *.elf *.bin *.lst

.PRECIOUS: %.elf %.bin
