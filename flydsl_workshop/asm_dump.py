"""Dump the FlyDSL IR / assembly for a given kernel.

Usage:
    python asm_dump.py

This sets the FlyDSL dump environment variables *before* importing flydsl
(they are read at import time), disables the runtime cache so the kernel is
always recompiled, and then runs a kernel so the compiler emits its IR/asm
into the dump directory.

Edit `main()` below to point at whichever kernel you want to inspect. After
running, the generated assembly can be found under `./dumps`.
"""

import os

DUMP_DIR = os.environ.setdefault("FLYDSL_DUMP_DIR", "./dumps")
os.environ["FLYDSL_RUNTIME_ENABLE_CACHE"] = "0"  # always recompile
os.environ["FLYDSL_DUMP_IR"] = "1"  # dump the generated IR / asm

import torch

import flydsl.compiler as flyc
import flydsl.expr as fx
from flydsl.expr.vector import Vector as Vec


def ceildiv(x: int, y: int) -> int:
    return (x + y - 1) // y

# --- Kernel under inspection -------------------------------------------------
# Replace the body of `kernel` / `launch` with the kernel you want to dump.


@flyc.kernel
def grayscale_kernel(x: fx.Pointer, out: fx.Pointer):
    idx = fx.block_idx.x * fx.block_dim.x + fx.thread_idx.x
    
    # There are 3 channels per pixel
    r = x[idx * 3] 
    g = x[idx * 3 + 1]
    b = x[idx * 3 + 2]

    # out only has 1 channel per pixel
    out[idx] = r * 0.2126 + g * 0.7152 + b * 0.0722


@flyc.jit
def grayscale(x: fx.Pointer, out: fx.Pointer, w: fx.Int32, h: fx.Int32, stream: fx.Stream):
    block_dim = 256
    ne = w * h
    grid_x = ceildiv(ne, block_dim)
    grayscale_kernel(x, out).launch(grid=(grid_x, 1, 1), block=(block_dim, 1, 1), stream=stream)


def dispatch_kernel():
    n1 = 1024 * 3
    n2 = 1024 * 4
    A = torch.rand(n1, dtype=torch.float32, device="cuda")
    B = torch.rand(n2, dtype=torch.float32, device="cuda")

    # Running the kernel triggers jit compilation, which emits the dump.
    grayscale(A, B, n1, n2, torch.cuda.default_stream())
    torch.cuda.synchronize()


if __name__ == "__main__":
    dispatch_kernel()
    print(f"IR / assembly dumped to: {os.path.abspath(DUMP_DIR)}")
