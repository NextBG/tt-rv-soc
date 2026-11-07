#ifndef TINYRV_H
#define TINYRV_H

#include <stdint.h>

#define REG(off) (*(volatile uint32_t *)(0x80000000u + (off)))
#define GPIO_OUT  REG(0x00)
#define GPIO_IN   REG(0x04)
#define UART_DATA REG(0x08)
#define UART_STAT REG(0x0C)
#define UART_DIV  REG(0x10)
#define PWM       REG(0x14)
#define MTIME     REG(0x18)
#define CHIP_ID   REG(0x1C)

#define UART_TX_BUSY  1u
#define UART_RX_VALID 2u

#define PWM_CFG(d0, d1, pre, en0, en1) \
  ((uint32_t)(d0) | ((uint32_t)(d1) << 8) | ((uint32_t)(pre) << 16) | ((en0) ? 1u << 24 : 0) | ((en1) ? 1u << 25 : 0))

static inline void uart_putc(char c) {
  while (UART_STAT & UART_TX_BUSY) {}
  UART_DATA = (uint8_t)c;
}

static inline void uart_puts(const char *s) {
  while (*s) uart_putc(*s++);
}

static inline int uart_getc_nb(void) {
  if (UART_STAT & UART_RX_VALID) return (int)(UART_DATA & 0xff);
  return -1;
}

static inline void uart_puthex(uint32_t v) {
  for (int i = 28; i >= 0; i -= 4) uart_putc("0123456789abcdef"[(v >> i) & 0xf]);
}

#endif
