/*
 * Copyright (c) 2026 NextBG
 * SPDX-License-Identifier: Apache-2.0
 *
 * TinyRV-E: a tiny RV32E SoC for Tiny Tapeout.
 *   0x0000_0000 - 0x00FF_FFFF  QSPI Pmod flash (read only, code executes in place)
 *   0x0100_0000 - 0x017F_FFFF  QSPI Pmod PSRAM A (8 MB, read/write)
 *   0x8000_0000 - 0x8000_001F  peripherals (see periph.v)
 */

`default_nettype none

module tt_um_nextbg_rv32e_soc (
    input  wire [7:0] ui_in,    // Dedicated inputs
    output wire [7:0] uo_out,   // Dedicated outputs
    input  wire [7:0] uio_in,   // IOs: Input path
    output wire [7:0] uio_out,  // IOs: Output path
    output wire [7:0] uio_oe,   // IOs: Enable path (active high: 0=input, 1=output)
    input  wire       ena,      // always 1 when the design is powered, so you can ignore it
    input  wire       clk,      // clock
    input  wire       rst_n     // reset_n - low to reset
);

  // Registered reset so the large reset fan-out does not see the pad directly
  reg rst_n_r;
  always @(posedge clk) rst_n_r <= rst_n;

  wire        mem_valid;
  wire [31:0] mem_addr;
  wire [31:0] mem_wdata;
  wire [3:0]  mem_wstrb;
  wire [31:0] mem_rdata;
  wire        mem_ready;

  rv_core u_core (
      .clk      (clk),
      .rst_n    (rst_n_r),
      .mem_valid(mem_valid),
      .mem_addr (mem_addr),
      .mem_wdata(mem_wdata),
      .mem_wstrb(mem_wstrb),
      .mem_rdata(mem_rdata),
      .mem_ready(mem_ready)
  );

  wire is_periph = mem_addr[31];
  wire is_ram    = mem_addr[24];

  wire [31:0] spi_rdata;
  wire        spi_ready;
  wire        sck, mosi, cs_flash_n, cs_ram_n;

  spi_mem u_spi (
      .clk       (clk),
      .rst_n     (rst_n_r),
      .req       (mem_valid & ~is_periph),
      .is_ram    (is_ram),
      .addr      (mem_addr[23:0]),
      .wdata     (mem_wdata),
      .wstrb     (mem_wstrb),
      .ready     (spi_ready),
      .rdata     (spi_rdata),
      .sck       (sck),
      .mosi      (mosi),
      .miso      (uio_in[2]),
      .cs_flash_n(cs_flash_n),
      .cs_ram_n  (cs_ram_n)
  );

  wire [31:0] p_rdata;
  wire [7:0]  gpio_out;
  wire        uart_tx, pwm0, pwm1;
  wire [1:0]  pwm_en;

  periph u_periph (
      .clk     (clk),
      .rst_n   (rst_n_r),
      .sel     (mem_valid & is_periph),
      .addr    (mem_addr[4:2]),
      .wdata   (mem_wdata),
      .we      (|mem_wstrb),
      .rdata   (p_rdata),
      .gpio_in (ui_in),
      .gpio_out(gpio_out),
      .uart_rx (ui_in[3]),
      .uart_tx (uart_tx),
      .pwm0    (pwm0),
      .pwm1    (pwm1),
      .pwm_en  (pwm_en)
  );

  assign mem_ready = is_periph ? mem_valid : spi_ready;
  assign mem_rdata = is_periph ? p_rdata : spi_rdata;

  assign uo_out = {pwm_en[1] ? pwm1 : gpio_out[7],
                   pwm_en[0] ? pwm0 : gpio_out[6],
                   gpio_out[5],
                   uart_tx,
                   gpio_out[3:0]};

  // QSPI Pmod pinout: 0 CS flash, 1 SD0/MOSI, 2 SD1/MISO, 3 SCK, 4 SD2, 5 SD3, 6 CS RAM A, 7 CS RAM B
  // SD2/SD3 (WP#/HOLD#) are held high. All pins are released while in reset so
  // the flash can be programmed by the demo board.
  assign uio_out = {1'b1, cs_ram_n, 1'b1, 1'b1, sck, 1'b0, mosi, cs_flash_n};
  assign uio_oe  = rst_n_r ? 8'b1111_1011 : 8'b0000_0000;

  wire _unused = &{ena, uio_in[7:3], uio_in[1:0], mem_addr[30:25], gpio_out[4], 1'b0};

endmodule
