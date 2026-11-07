#include "tinyrv.h"

static int counter = 42;          /* .data: copied from flash at boot */
static uint32_t scratch[8];       /* .bss: cleared at boot */

static uint32_t mul(uint32_t a, uint32_t b) { return a * b; }   /* libgcc __mulsi3 */

static int self_test(void) {
  volatile uint8_t *b = (volatile uint8_t *)scratch;
  volatile uint16_t *h = (volatile uint16_t *)scratch;
  int err = 0;

  if (counter != 42) err |= 1;
  for (int i = 0; i < 8; i++) if (scratch[i] != 0) err |= 2;

  scratch[0] = 0x11223344;
  b[1] = 0xaa;
  h[1] = 0xbeef;
  if (scratch[0] != 0xbeefaa44) err |= 4;
  if ((int8_t)b[1] != -86 || h[1] != 0xbeef) err |= 8;

  if (mul(12345, 6789) != 83810205u) err |= 16;
  if ((-7 >> 1) != -4 || (0x80000000u >> 31) != 1) err |= 32;
  if (CHIP_ID != 0x52563345) err |= 64;
  return err;
}

int main(void) {
  uart_puts("Hello from TinyRV-E!\r\n");
  int err = self_test();
  uart_puts(err ? "FAIL " : "OK ");
  uart_puthex((uint32_t)err);
  uart_puts("\r\n");

  GPIO_OUT = 0x0f ^ (uint32_t)err;
  PWM = PWM_CFG(64, 192, 0, 1, 1);

  /* Echo loop: received characters are echoed back upper-cased,
     and the low GPIO outputs follow the switches on ui_in[2:0]. */
  for (;;) {
    int c = uart_getc_nb();
    if (c >= 0) {
      if (c >= 'a' && c <= 'z') c -= 32;
      uart_putc((char)c);
      counter++;
    }
    GPIO_OUT = (GPIO_OUT & 0xf8) | (GPIO_IN & 0x07);
  }
}
