#!/usr/bin/env python3
"""Convert a raw binary into a byte-per-line hex file for $readmemh."""
import sys

data = open(sys.argv[1], "rb").read()
with open(sys.argv[2], "w") as f:
    for b in data:
        f.write(f"{b:02x}\n")
