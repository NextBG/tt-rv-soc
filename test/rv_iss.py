# SPDX-FileCopyrightText: © 2026 NextBG
# SPDX-License-Identifier: Apache-2.0
"""Tiny RV32E instruction encoder, reference ISS and random program generator
used to cross-check the RTL core instruction by instruction result."""

import random

M32 = 0xFFFFFFFF
RAM_BASE = 0x01000000
RAM_SIZE = 1 << 16
FLASH_SIZE = 1 << 16
DATA_BASE = RAM_BASE + 0x100   # x15 points here in random programs
DUMP_OFF = 0x300               # registers are stored at DATA_BASE + DUMP_OFF
GPIO_DONE = 0xA5


def sx(v, bits):
    v &= (1 << bits) - 1
    return v - (1 << bits) if v >> (bits - 1) else v


# ---------------------------------------------------------------- encoder
def r_type(f7, rs2, rs1, f3, rd, op):
    return (f7 << 25) | (rs2 << 20) | (rs1 << 15) | (f3 << 12) | (rd << 7) | op


def i_type(imm, rs1, f3, rd, op):
    return ((imm & 0xFFF) << 20) | (rs1 << 15) | (f3 << 12) | (rd << 7) | op


def s_type(imm, rs2, rs1, f3, op):
    imm &= 0xFFF
    return ((imm >> 5) << 25) | (rs2 << 20) | (rs1 << 15) | (f3 << 12) | ((imm & 0x1F) << 7) | op


def b_type(imm, rs2, rs1, f3):
    imm &= 0x1FFF
    return (((imm >> 12) & 1) << 31) | (((imm >> 5) & 0x3F) << 25) | (rs2 << 20) | (rs1 << 15) | \
        (f3 << 12) | (((imm >> 1) & 0xF) << 8) | (((imm >> 11) & 1) << 7) | 0x63


def u_type(imm20, rd, op):
    return ((imm20 & 0xFFFFF) << 12) | (rd << 7) | op


def j_type(imm, rd):
    imm &= 0x1FFFFF
    return (((imm >> 20) & 1) << 31) | (((imm >> 1) & 0x3FF) << 21) | (((imm >> 11) & 1) << 20) | \
        (((imm >> 12) & 0xFF) << 12) | (rd << 7) | 0x6F


def li(rd, val):
    """lui+addi pair loading an arbitrary 32-bit constant."""
    val &= M32
    lo = sx(val, 12)
    hi = ((val - lo) >> 12) & 0xFFFFF
    return [u_type(hi, rd, 0x37), i_type(lo, rd, 0, rd, 0x13)]


# ---------------------------------------------------------------- ISS
class ISS:
    def __init__(self, flash: bytes):
        self.flash = bytearray(flash) + bytearray([0xFF] * (FLASH_SIZE - len(flash)))
        self.ram = bytearray([0xFF] * RAM_SIZE)
        self.x = [0] * 16
        self.pc = 0
        self.gpio_out = 0

    def _load(self, addr, n):
        if addr & 0x80000000:
            raise ValueError("peripheral load not modelled")
        if addr & 0x01000000:
            mem, a = self.ram, addr & (RAM_SIZE - 1)
        else:
            mem, a = self.flash, addr & (FLASH_SIZE - 1)
        return int.from_bytes(mem[a:a + n], "little")

    def _store(self, addr, val, n):
        if addr & 0x80000000:
            if (addr & 0x1C) == 0:
                self.gpio_out = val & 0xFF
            return
        if addr & 0x01000000:
            a = addr & (RAM_SIZE - 1)
            self.ram[a:a + n] = (val & ((1 << (8 * n)) - 1)).to_bytes(n, "little")

    def step(self):
        ins = self._load(self.pc, 4)
        op = ins & 0x7F
        rd = (ins >> 7) & 0x1F
        f3 = (ins >> 12) & 7
        rs1 = (ins >> 15) & 0x1F
        rs2 = (ins >> 20) & 0x1F
        f7 = ins >> 25
        a = self.x[rs1 & 15]
        b = self.x[rs2 & 15]
        imm_i = sx(ins >> 20, 12)
        imm_s = sx(((ins >> 25) << 5) | ((ins >> 7) & 0x1F), 12)
        imm_b = sx((((ins >> 31) & 1) << 12) | (((ins >> 7) & 1) << 11) |
                   (((ins >> 25) & 0x3F) << 5) | (((ins >> 8) & 0xF) << 1), 13)
        imm_u = ins & 0xFFFFF000
        imm_j = sx((((ins >> 31) & 1) << 20) | (((ins >> 12) & 0xFF) << 12) |
                   (((ins >> 20) & 1) << 11) | (((ins >> 21) & 0x3FF) << 1), 21)
        npc = (self.pc + 4) & M32
        res = None
        if op == 0x37:
            res = imm_u
        elif op == 0x17:
            res = (self.pc + imm_u) & M32
        elif op == 0x6F:
            res, npc = npc, (self.pc + imm_j) & M32
        elif op == 0x67:
            res, npc = npc, (a + imm_i) & M32 & ~1
        elif op == 0x63:
            sa, sb = sx(a, 32), sx(b, 32)
            take = {0: a == b, 1: a != b, 4: sa < sb, 5: sa >= sb, 6: a < b, 7: a >= b}[f3]
            if take:
                npc = (self.pc + imm_b) & M32
        elif op == 0x03:
            addr = (a + imm_i) & M32
            n = {0: 1, 1: 2, 2: 4, 4: 1, 5: 2}[f3]
            v = self._load(addr, n)
            res = sx(v, 8 * n) & M32 if f3 in (0, 1) else v
        elif op == 0x23:
            addr = (a + imm_s) & M32
            self._store(addr, b, {0: 1, 1: 2, 2: 4}[f3])
        elif op in (0x13, 0x33):
            bb = b if op == 0x33 else imm_i & M32
            sh = bb & 31
            alt = (f7 >> 5) & 1
            if f3 == 0:
                res = (a - bb) if (op == 0x33 and alt) else (a + bb)
            elif f3 == 1:
                res = a << sh
            elif f3 == 2:
                res = int(sx(a, 32) < sx(bb, 32))
            elif f3 == 3:
                res = int(a < (bb & M32))
            elif f3 == 4:
                res = a ^ bb
            elif f3 == 5:
                res = (sx(a, 32) >> sh) if alt else (a >> sh)
            elif f3 == 6:
                res = a | bb
            else:
                res = a & bb
            res &= M32
        # FENCE / SYSTEM: NOP
        if res is not None and (rd & 15):
            self.x[rd & 15] = res & M32
        self.pc = npc


# ---------------------------------------------------------------- random programs
def random_program(seed, n_body=200):
    rng = random.Random(seed)
    regs = list(range(1, 15))            # x15 is the data base pointer
    words = []
    for r in regs:
        words += li(r, rng.getrandbits(32) if rng.random() < 0.7 else rng.choice([0, 1, M32, 0x80000000, 0x7FFFFFFF]))
    words += li(15, DATA_BASE)

    body = []
    while len(body) < n_body:
        kind = rng.choices(["op", "imm", "lui", "auipc", "load", "flash", "store", "branch", "jal", "jalr"],
                           [20, 20, 3, 3, 10, 4, 10, 8, 3, 3])[0]
        rd, rs1, rs2 = rng.choice(regs), rng.randint(0, 15), rng.randint(0, 15)
        remaining = n_body - len(body)
        if kind == "op":
            f3 = rng.randint(0, 7)
            f7 = 0x20 if f3 in (0, 5) and rng.random() < 0.5 else 0
            body.append(r_type(f7, rs2, rs1, f3, rd, 0x33))
        elif kind == "imm":
            f3 = rng.randint(0, 7)
            if f3 == 1:
                imm = rng.randint(0, 31)
            elif f3 == 5:
                imm = rng.randint(0, 31) | (0x400 if rng.random() < 0.5 else 0)
            else:
                imm = rng.randint(-2048, 2047)
            body.append(i_type(imm, rs1, f3, rd, 0x13))
        elif kind == "lui":
            body.append(u_type(rng.getrandbits(20), rd, 0x37))
        elif kind == "auipc":
            body.append(u_type(rng.getrandbits(20), rd, 0x17))
        elif kind in ("load", "flash"):
            f3 = rng.choice([0, 1, 2, 4, 5])
            align = {0: 1, 4: 1, 1: 2, 5: 2, 2: 4}[f3]
            if kind == "load":
                body.append(i_type(rng.randrange(0, 0x200, align), 15, f3, rd, 0x03))
            else:
                body.append(i_type(rng.randrange(0, 0x400, align), 0, f3, rd, 0x03))
        elif kind == "store":
            f3 = rng.choice([0, 1, 2])
            align = 1 << f3
            body.append(s_type(rng.randrange(0, 0x200, align), rs2, 15, f3, 0x23))
        elif kind == "branch" and remaining > 4:
            skip = rng.randint(0, 3)
            body.append(b_type(4 * (skip + 1), rs2, rs1, rng.choice([0, 1, 4, 5, 6, 7])))
        elif kind == "jal" and remaining > 4:
            skip = rng.randint(0, 3)
            body.append(j_type(4 * (skip + 1), rng.choice([0] + regs)))
        elif kind == "jalr" and remaining > 4:
            skip = rng.randint(0, 3)
            target = 4 * (len(words) + len(body) + 1 + skip)       # absolute: program < 2 KB
            body.append(i_type(target | rng.randint(0, 1), 0, 0, rng.choice([0] + regs), 0x67))
    words += body

    for r in range(1, 16):
        words.append(s_type(DUMP_OFF + 4 * r, r, 15, 2, 0x23))     # sw xr, DUMP+4r(x15)
    words += li(1, 0x80000000)
    words += li(2, GPIO_DONE)
    words.append(s_type(0, 2, 1, 2, 0x23))                         # GPIO_OUT = done
    words.append(j_type(0, 0))                                      # j .
    return b"".join(w.to_bytes(4, "little") for w in words)


def run_iss(prog, max_steps=100000):
    iss = ISS(prog)
    for _ in range(max_steps):
        iss.step()
        if iss.gpio_out == GPIO_DONE:
            return iss
    raise RuntimeError("ISS did not finish")
