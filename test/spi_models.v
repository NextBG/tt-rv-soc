/*
 * Behavioural models of the QSPI Pmod devices (single-bit SPI mode 0):
 * W25Q128 flash (READ 0x03) and APS6404 PSRAM (READ 0x03 / WRITE 0x02).
 * Output data changes TCO ns after the falling SCK edge.
 */

`default_nettype none
`timescale 1ns / 1ps

module spi_mem_model #(
    parameter integer AW       = 16,   // address bits implemented
    parameter integer WRITABLE = 0,
    parameter integer TCO      = 10
) (
    input  wire csn,
    input  wire sck,
    input  wire mosi,
    output reg  miso
);

  reg [7:0]  mem [0:(1<<AW)-1];
  integer    bitcnt;
  reg [7:0]  cmd;
  reg [23:0] addr;
  reg [7:0]  sh;
  reg [7:0]  outb;
  integer    idx;

  initial begin
    miso = 1'bz;
    for (idx = 0; idx < (1 << AW); idx = idx + 1) mem[idx] = 8'hff;
  end

  always @(negedge csn) bitcnt = 0;
  always @(posedge csn) miso <= #TCO 1'bz;

  always @(posedge sck) if (!csn) begin
    if (bitcnt < 8) cmd = {cmd[6:0], mosi};
    else if (bitcnt < 32) addr = {addr[22:0], mosi};
    else if (cmd == 8'h02 && WRITABLE) begin
      sh = {sh[6:0], mosi};
      if (bitcnt % 8 == 7) begin
        mem[addr[AW-1:0]] = sh;
        addr = addr + 1;
      end
    end
    bitcnt = bitcnt + 1;
  end

  always @(negedge sck) if (!csn && cmd == 8'h03 && bitcnt >= 32) begin
    if ((bitcnt - 32) % 8 == 0) begin
      outb = mem[addr[AW-1:0]];
      addr = addr + 1;
    end
    miso <= #TCO outb[7 - ((bitcnt - 32) % 8)];
  end

endmodule
