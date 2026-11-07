/*
 * Copyright (c) 2026 NextBG
 * SPDX-License-Identifier: Apache-2.0
 *
 * Memory mapped peripherals (base 0x8000_0000, word registers):
 *   0x00 GPIO_OUT   rw [7:0]
 *   0x04 GPIO_IN    r  [7:0]  = ui_in
 *   0x08 UART_DATA  w: transmit byte   r: received byte (clears RX valid)
 *   0x0C UART_STAT  r  bit0 = TX busy, bit1 = RX valid
 *   0x10 UART_DIV   rw [15:0] clock cycles per bit
 *   0x14 PWM        rw [7:0] duty0, [15:8] duty1, [23:16] prescaler, [24] en0, [25] en1
 *   0x18 MTIME      r  free running clock cycle counter
 *   0x1C ID         r  0x52563345 ("RV3E")
 */

`default_nettype none

module periph #(
    parameter [15:0] UART_DIV_RESET = 16'd434   // 115200 baud @ 50 MHz
) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        sel,
    input  wire [4:2]  addr,
    input  wire [31:0] wdata,
    input  wire        we,
    output reg  [31:0] rdata,
    input  wire [7:0]  gpio_in,
    output reg  [7:0]  gpio_out,
    input  wire        uart_rx,
    output wire        uart_tx,
    output wire        pwm0,
    output wire        pwm1,
    output wire [1:0]  pwm_en
);

  reg [15:0] uart_div;
  reg [7:0]  duty0, duty1, prescale;
  reg [1:0]  pwm_enable;
  reg [31:0] mtime;

  wire       _unused = &{wdata[31:26], 1'b0};
  wire       tx_busy;
  wire [7:0] rx_data;
  wire       rx_valid;

  wire wr = sel & we;
  wire rd_data = sel & ~we & (addr == 3'd2);

  assign pwm_en = pwm_enable;

  always @(posedge clk) begin
    if (!rst_n) begin
      gpio_out   <= 8'd0;
      uart_div   <= UART_DIV_RESET;
      duty0      <= 8'd0;
      duty1      <= 8'd0;
      prescale   <= 8'd0;
      pwm_enable <= 2'd0;
      mtime      <= 32'd0;
    end else begin
      mtime <= mtime + 32'd1;
      if (wr) begin
        case (addr)
          3'd0: gpio_out <= wdata[7:0];
          3'd4: uart_div <= wdata[15:0];
          3'd5: begin
            duty0      <= wdata[7:0];
            duty1      <= wdata[15:8];
            prescale   <= wdata[23:16];
            pwm_enable <= wdata[25:24];
          end
          default: ;
        endcase
      end
    end
  end

  always @(*) begin
    case (addr)
      3'd0: rdata = {24'd0, gpio_out};
      3'd1: rdata = {24'd0, gpio_in};
      3'd2: rdata = {24'd0, rx_data};
      3'd3: rdata = {30'd0, rx_valid, tx_busy};
      3'd4: rdata = {16'd0, uart_div};
      3'd5: rdata = {6'd0, pwm_enable, prescale, duty1, duty0};
      3'd6: rdata = mtime;
      default: rdata = 32'h5256_3345;
    endcase
  end

  uart u_uart (
      .clk     (clk),
      .rst_n   (rst_n),
      .div     (uart_div),
      .tx_start(wr && addr == 3'd2),
      .tx_data (wdata[7:0]),
      .tx_busy (tx_busy),
      .tx      (uart_tx),
      .rx      (uart_rx),
      .rx_data (rx_data),
      .rx_valid(rx_valid),
      .rx_ack  (rd_data)
  );

  // PWM: 8-bit counter advanced every (prescale+1) clocks
  reg [7:0] pre_cnt, pwm_cnt;
  always @(posedge clk) begin
    if (!rst_n) begin
      pre_cnt <= 8'd0;
      pwm_cnt <= 8'd0;
    end else if (pre_cnt == prescale) begin
      pre_cnt <= 8'd0;
      pwm_cnt <= pwm_cnt + 8'd1;
    end else begin
      pre_cnt <= pre_cnt + 8'd1;
    end
  end
  reg pwm0_r, pwm1_r;
  always @(posedge clk) begin
    pwm0_r <= rst_n && (pwm_cnt < duty0);
    pwm1_r <= rst_n && (pwm_cnt < duty1);
  end
  assign pwm0 = pwm0_r;
  assign pwm1 = pwm1_r;

endmodule
