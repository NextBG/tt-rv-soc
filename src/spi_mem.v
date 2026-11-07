/*
 * Copyright (c) 2026 NextBG
 * SPDX-License-Identifier: Apache-2.0
 *
 * Single-bit SPI (mode 0) controller for the Tiny Tapeout QSPI Pmod:
 *   - flash  : READ (0x03), execute-in-place. After a read the flash is left
 *              selected so that a following sequential word read just clocks
 *              out 32 more bits (no command/address).
 *   - PSRAM  : READ (0x03) / WRITE (0x02), byte/half/word writes.
 * SCK = clk/4. MISO is sampled on the clock edge that drives SCK low, i.e.
 * two clock cycles after the rising SCK edge, giving plenty of margin for
 * pad and board delays.
 */

`default_nettype none

module spi_mem (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        req,
    input  wire        is_ram,
    input  wire [23:0] addr,
    input  wire [31:0] wdata,
    input  wire [3:0]  wstrb,     // 0 = read
    output reg         ready,
    output wire [31:0] rdata,
    output reg         sck,
    output wire        mosi,
    input  wire        miso,
    output reg         cs_flash_n,
    output reg         cs_ram_n
);

  localparam ST_IDLE = 2'd0, ST_CSH = 2'd1, ST_XFER = 2'd2;

  reg [1:0]  st;
  reg [1:0]  ph;
  reg [5:0]  nbits;
  reg [63:0] sr;
  reg        open;          // flash still selected after a read
  reg        cur_flash_rd;  // current transfer is a flash read
  reg [23:0] next_addr;
  reg [1:0]  csh_cnt;

  assign mosi  = sr[63];
  assign rdata = {sr[7:0], sr[15:8], sr[23:16], sr[31:24]};

  wire is_wr = |wstrb;

  // Write data bytes in transmit order and their count
  reg [31:0] wbytes;
  reg [5:0]  wbits;
  always @(*) begin
    case (wstrb)
      4'b0001: begin wbytes = {wdata[7:0], 24'd0};   wbits = 6'd8;  end
      4'b0010: begin wbytes = {wdata[15:8], 24'd0};  wbits = 6'd8;  end
      4'b0100: begin wbytes = {wdata[23:16], 24'd0}; wbits = 6'd8;  end
      4'b1000: begin wbytes = {wdata[31:24], 24'd0}; wbits = 6'd8;  end
      4'b0011: begin wbytes = {wdata[7:0], wdata[15:8], 16'd0};   wbits = 6'd16; end
      4'b1100: begin wbytes = {wdata[23:16], wdata[31:24], 16'd0}; wbits = 6'd16; end
      default: begin wbytes = {wdata[7:0], wdata[15:8], wdata[23:16], wdata[31:24]}; wbits = 6'd32; end
    endcase
  end

  always @(posedge clk) begin
    if (!rst_n) begin
      st           <= ST_IDLE;
      ph           <= 2'd0;
      nbits        <= 6'd0;
      sr           <= 64'd0;
      open         <= 1'b0;
      cur_flash_rd <= 1'b0;
      next_addr    <= 24'd0;
      csh_cnt      <= 2'd0;
      ready        <= 1'b0;
      sck          <= 1'b0;
      cs_flash_n   <= 1'b1;
      cs_ram_n     <= 1'b1;
    end else begin
      ready <= 1'b0;
      case (st)
        ST_IDLE: if (req && !ready) begin
          if (!is_ram && is_wr) begin
            ready <= 1'b1;                          // flash is read-only
          end else if (!is_ram && open && addr[23:2] == next_addr[23:2]) begin
            nbits        <= 6'd32;                  // continue sequential read
            ph           <= 2'd0;
            cur_flash_rd <= 1'b1;
            st           <= ST_XFER;
          end else if (open) begin
            cs_flash_n <= 1'b1;                     // close flash, then restart
            open       <= 1'b0;
            csh_cnt    <= 2'd3;
            st         <= ST_CSH;
          end else begin
            ph <= 2'd0;
            st <= ST_XFER;
            cur_flash_rd <= !is_ram;
            if (is_ram) cs_ram_n <= 1'b0; else cs_flash_n <= 1'b0;
            if (is_wr) begin
              sr    <= {8'h02, addr, wbytes};
              nbits <= 6'd32 + wbits;
            end else begin
              sr    <= {8'h03, addr[23:2], 2'b00, 32'd0};
              nbits <= 6'd0;                        // 0 == 64 bits
            end
            next_addr <= {addr[23:2], 2'b00};
          end
        end
        ST_CSH: begin
          csh_cnt <= csh_cnt - 2'd1;
          if (csh_cnt == 2'd0) st <= ST_IDLE;
        end
        ST_XFER: begin
          ph <= ph + 2'd1;
          if (ph == 2'd1) sck <= 1'b1;
          if (ph == 2'd3) begin
            sck   <= 1'b0;
            sr    <= {sr[62:0], miso};
            nbits <= nbits - 6'd1;
            if (nbits == 6'd1) begin
              ready <= 1'b1;
              st    <= ST_IDLE;
              if (cur_flash_rd) begin
                open      <= 1'b1;
                next_addr <= next_addr + 24'd4;
              end else begin
                cs_ram_n   <= 1'b1;
                cs_flash_n <= 1'b1;
              end
            end
          end
        end
        default: st <= ST_IDLE;
      endcase
    end
  end

endmodule
