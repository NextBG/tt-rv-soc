/* TinyRV-E memory layout: code + rodata in flash (XIP), data/bss/stack in PSRAM */
OUTPUT_ARCH(riscv)
ENTRY(_start)

MEMORY
{
  FLASH (rx)  : ORIGIN = 0x00000000, LENGTH = 16M
  RAM   (rwx) : ORIGIN = 0x01000000, LENGTH = 64K   /* 8 MB on the Pmod; keep small for simulation */
}

SECTIONS
{
  .text : {
    KEEP(*(.text.start))
    *(.text .text.*)
    *(.rodata .rodata.* .srodata .srodata.*)
    . = ALIGN(4);
  } > FLASH

  .data : {
    _data_start = .;
    *(.data .data.* .sdata .sdata.*)
    . = ALIGN(4);
    _data_end = .;
  } > RAM AT > FLASH
  _data_load = LOADADDR(.data);

  .bss (NOLOAD) : {
    _bss_start = .;
    *(.bss .bss.* .sbss .sbss.* COMMON)
    . = ALIGN(4);
    _bss_end = .;
  } > RAM

  _stack_top = ORIGIN(RAM) + LENGTH(RAM);
}
