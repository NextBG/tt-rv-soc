/*
 * Copyright (c) 2026 NextBG
 * SPDX-License-Identifier: Apache-2.0
 *
 * 8N1 UART, bit period = div clock cycles (div >= 4).
 */

`default_nettype none

module uart (
    input  wire        clk,
    input  wire        rst_n,
    input  wire [15:0] div,
    input  wire        tx_start,
    input  wire [7:0]  tx_data,
    output wire        tx_busy,
    output reg         tx,
    input  wire        rx,
    output reg  [7:0]  rx_data,
    output reg         rx_valid,
    input  wire        rx_ack
);

  // ---------------- TX ----------------
  reg [9:0]  tx_sr;
  reg [3:0]  tx_bits;
  reg [15:0] tx_cnt;
  assign tx_busy = (tx_bits != 4'd0);

  always @(posedge clk) begin
    if (!rst_n) begin
      tx      <= 1'b1;
      tx_sr   <= 10'h3ff;
      tx_bits <= 4'd0;
      tx_cnt  <= 16'd0;
    end else if (!tx_busy) begin
      tx <= 1'b1;
      if (tx_start) begin
        tx_sr   <= {1'b1, tx_data, 1'b0};
        tx_bits <= 4'd10;
        tx_cnt  <= 16'd0;
      end
    end else begin
      tx <= tx_sr[0];
      if (tx_cnt == div - 16'd1) begin
        tx_cnt  <= 16'd0;
        tx_sr   <= {1'b1, tx_sr[9:1]};
        tx_bits <= tx_bits - 4'd1;
      end else begin
        tx_cnt <= tx_cnt + 16'd1;
      end
    end
  end

  // ---------------- RX ----------------
  reg [1:0]  rx_sync;
  reg [3:0]  rx_bits;
  reg [7:0]  rx_sr;
  reg [15:0] rx_cnt;
  wire       rx_s = rx_sync[1];

  always @(posedge clk) begin
    if (!rst_n) begin
      rx_sync  <= 2'b11;
      rx_bits  <= 4'd0;
      rx_sr    <= 8'd0;
      rx_cnt   <= 16'd0;
      rx_data  <= 8'd0;
      rx_valid <= 1'b0;
    end else begin
      rx_sync <= {rx_sync[0], rx};
      if (rx_ack) rx_valid <= 1'b0;
      if (rx_bits == 4'd0) begin
        if (!rx_s) begin                      // start bit edge
          rx_bits <= 4'd10;
          rx_cnt  <= {1'b0, div[15:1]};       // sample mid-bit
        end
      end else if (rx_cnt == 16'd0) begin
        rx_cnt  <= div - 16'd1;
        rx_bits <= rx_bits - 4'd1;
        if (rx_bits == 4'd10) begin
          if (rx_s) rx_bits <= 4'd0;          // false start
        end else if (rx_bits == 4'd1) begin
          rx_bits <= 4'd0;
          if (rx_s) begin                     // valid stop bit
            rx_data  <= rx_sr;
            rx_valid <= 1'b1;
          end
        end else begin
          rx_sr <= {rx_s, rx_sr[7:1]};
        end
      end else begin
        rx_cnt <= rx_cnt - 16'd1;
      end
    end
  end

endmodule
