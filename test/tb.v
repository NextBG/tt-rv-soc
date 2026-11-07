`default_nettype none
`timescale 1ns / 1ps

/* Testbench: the SoC plus behavioural QSPI Pmod flash and PSRAM models.
   The flash image is loaded from the +FIRMWARE=<hex file> plusarg. */
module tb ();

  initial begin
    $dumpfile("tb.fst");
    $dumpvars(0, tb);
    #1;
  end

  reg clk;
  reg rst_n;
  reg ena;
  reg [7:0] ui_in;
  wire [7:0] uio_in;
  wire [7:0] uo_out;
  wire [7:0] uio_out;
  wire [7:0] uio_oe;
  wire uart_tx = uo_out[4];

  tt_um_nextbg_rv32e_soc user_project (
      .ui_in  (ui_in),
      .uo_out (uo_out),
      .uio_in (uio_in),
      .uio_out(uio_out),
      .uio_oe (uio_oe),
      .ena    (ena),
      .clk    (clk),
      .rst_n  (rst_n)
  );

  wire cs_flash_n = uio_oe[0] ? uio_out[0] : 1'b1;
  wire mosi       = uio_out[1];
  wire sck        = uio_oe[3] ? uio_out[3] : 1'b0;
  wire cs_ram_n   = uio_oe[6] ? uio_out[6] : 1'b1;
  wire miso;
  pullup (miso);

  assign uio_in = {uio_out[7:3], miso, uio_out[1:0]};

  spi_mem_model #(.AW(16), .WRITABLE(0)) flash (
      .csn(cs_flash_n), .sck(sck), .mosi(mosi), .miso(miso));
  spi_mem_model #(.AW(16), .WRITABLE(1)) psram (
      .csn(cs_ram_n), .sck(sck), .mosi(mosi), .miso(miso));

  reg [1023:0] fw;
  initial begin
    if ($value$plusargs("FIRMWARE=%s", fw)) $readmemh(fw, flash.mem);
  end

endmodule
