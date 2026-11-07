# SPDX-FileCopyrightText: © 2026 NextBG
# SPDX-License-Identifier: Apache-2.0

import os

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, FallingEdge, RisingEdge, Timer

import rv_iss

CLK_NS = 20                      # 50 MHz
UART_DIV = 434                   # firmware default: 115200 baud @ 50 MHz
BIT_NS = UART_DIV * CLK_NS
HERE = os.path.dirname(os.path.abspath(__file__))
GL = os.environ.get("GATES") == "yes"


def load_flash(dut, data: bytes):
    for i, b in enumerate(data):
        dut.flash.mem[i].value = b


async def start(dut, image: bytes, ui=0x08):
    cocotb.start_soon(Clock(dut.clk, CLK_NS, unit="ns").start())
    dut.ena.value = 1
    dut.ui_in.value = ui         # ui_in[3] is UART RX: idle high
    dut.rst_n.value = 0
    load_flash(dut, image)
    await ClockCycles(dut.clk, 10)
    assert int(dut.uio_oe.value) == 0, "QSPI pins must be released during reset"
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 2)


async def uart_recv(dut, timeout_bits=200000):
    """Receive one byte from uo_out[4]."""
    tx = dut.uart_tx
    while int(tx.value) != 1:
        await RisingEdge(tx)
    await FallingEdge(tx)
    await Timer(BIT_NS * 1.5, unit="ns")
    v = 0
    for i in range(8):
        v |= int(tx.value) << i
        await Timer(BIT_NS, unit="ns")
    assert int(tx.value) == 1, "bad stop bit"
    return v


async def uart_readline(dut):
    s = ""
    while not s.endswith("\n"):
        s += chr(await uart_recv(dut))
    return s


async def uart_send(dut, byte):
    ui = int(dut.ui_in.value)
    bits = [0] + [(byte >> i) & 1 for i in range(8)] + [1]
    for b in bits:
        ui = (ui & ~0x08) | (b << 3)
        dut.ui_in.value = ui
        await Timer(BIT_NS, unit="ns")


@cocotb.test()
async def test_hello_firmware(dut):
    """Boot the C firmware from flash: UART banner, self test, PWM, GPIO and UART echo."""
    with open(os.path.join(HERE, "..", "firmware", "hello.bin"), "rb") as f:
        image = f.read()
    await start(dut, image)

    line = await uart_readline(dut)
    dut._log.info(f"UART: {line!r}")
    assert line == "Hello from TinyRV-E!\r\n"
    line = await uart_readline(dut)
    dut._log.info(f"UART: {line!r}")
    assert line == "OK 00000000\r\n"

    # PWM: duty 64/256 on uo[6] and 192/256 on uo[7]
    await ClockCycles(dut.clk, 50)
    hi6 = hi7 = 0
    for _ in range(512):
        await RisingEdge(dut.clk)
        v = int(dut.uo_out.value)
        hi6 += (v >> 6) & 1
        hi7 += (v >> 7) & 1
    assert hi6 == 128 and hi7 == 384, (hi6, hi7)

    # GPIO: uo[3] set by firmware, uo[2:0] follow ui_in[2:0]
    dut.ui_in.value = 0x08 | 0x05
    await ClockCycles(dut.clk, 20000)
    assert int(dut.uo_out.value) & 0x0F == 0x0D

    # UART echo (upper-cased)
    for ch in "rv32":
        rx = cocotb.start_soon(uart_recv(dut))
        await uart_send(dut, ord(ch))
        got = await rx
        assert chr(got) == ch.upper(), (ch, chr(got))


@cocotb.test()
async def test_random_isa(dut):
    """Random RV32E programs executed from flash, results compared with a Python ISS."""
    seeds = range(int(os.environ.get("ISA_SEEDS", "1" if GL else "4")))
    for seed in seeds:
        prog = rv_iss.random_program(seed, n_body=120 if GL else 250)
        ref = rv_iss.run_iss(prog)
        if seed == 0:
            await start(dut, prog)
        else:
            dut.rst_n.value = 0
            load_flash(dut, prog)
            for i in range(0x100, 0x600):
                dut.psram.mem[i].value = 0xFF
            await ClockCycles(dut.clk, 10)
            dut.rst_n.value = 1
        for _ in range(4000):
            await ClockCycles(dut.clk, 500)
            if int(dut.uo_out.value) & 0xEF == rv_iss.GPIO_DONE:
                break
        else:
            raise AssertionError(f"seed {seed}: program did not finish")
        await ClockCycles(dut.clk, 10)
        lo, hi = rv_iss.DATA_BASE - rv_iss.RAM_BASE, rv_iss.DATA_BASE - rv_iss.RAM_BASE + rv_iss.DUMP_OFF + 64
        got = bytes(int(dut.psram.mem[i].value) for i in range(lo, hi))
        exp = bytes(ref.ram[lo:hi])
        if got != exp:
            for i in range(0, hi - lo, 4):
                if got[i:i + 4] != exp[i:i + 4]:
                    dut._log.error(f"seed {seed} @0x{lo + i:04x}: got {got[i:i+4][::-1].hex()} exp {exp[i:i+4][::-1].hex()}")
            raise AssertionError(f"seed {seed}: RAM/register dump mismatch")
        dut._log.info(f"seed {seed}: OK")
