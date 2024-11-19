import os
import sys
from pathlib import Path

import cocotb
from cocotb.clock import Clock
from cocotb.runner import get_runner
from cocotb.triggers import ClockCycles, FallingEdge, ReadOnly, RisingEdge

import random
import numpy as np

WIDTH = 16
WINDOW_SIZE = 16
TAUMAX = 16

CYCLES = 64

S_ADDR_WIDTH = 3
D_ADDR_WIDTH = 3

FRACTION_WIDTH = 10
FP_WIDTH = WIDTH*2+FRACTION_WIDTH

random_window = [[random.randrange(0, 2**8-1) for _ in range(WINDOW_SIZE)] for _ in range(3)]
async def send_window(dut):
    await ClockCycles(dut.clk_in, 2)
    for rw in random_window:
        for sample in rw:
            dut.sample_in.value = sample
            dut.valid_in.value = 1

            await RisingEdge(dut.clk_in)
            dut.sample_in.value = 0xDEAD
            dut.valid_in.value = 0

            await ClockCycles(dut.clk_in, CYCLES - 1)

def index(value, index, width):
    return (value >> (index*width)) & ((1<<width)-1);

def to_fp(value):
    accum = 0
    for x in range(FP_WIDTH-1, -1, -1):
        digit = int(value / (2**(x - FRACTION_WIDTH)))
        accum += 2**x * digit
        value -= 2**(x - FRACTION_WIDTH) * digit

    return hex(accum)

async def test_sample_pipeline(dut, sample_read, sample_in):
    bram_port_idx_s = (sample_read % WINDOW_SIZE) % 4

    bram_port_idx_d = abs(sample_in - sample_read) % 4
    read_addr_d = (abs(sample_in - sample_read) // 4) * 2 + (bram_port_idx_d % 2)

    valid = sample_read <= sample_in

    # SHOULD SEE RESULTS OF STAGE 1 HERE
    await ClockCycles(dut.clk_in, 2, rising=False)

    if valid:
        assert index(dut.sample_out.value, bram_port_idx_s, WIDTH) == random_window[sample_read // WINDOW_SIZE][sample_read % WINDOW_SIZE], "expected bram output"
        assert index(dut.read_addr_d.value, bram_port_idx_d, D_ADDR_WIDTH) == read_addr_d, "wrong diff BRAM read address"

    # RESULTS OF SUBTRACT
    sub = abs(random_window[sample_read // WINDOW_SIZE][sample_read % WINDOW_SIZE] - random_window[sample_in // WINDOW_SIZE][sample_in % WINDOW_SIZE])
    await ClockCycles(dut.clk_in, 1, rising=False)
    if valid:
        assert index(dut.subtracted.value, bram_port_idx_s, WIDTH) == sub, "expected subtraction result"

    # RESULTS OF MUL
    await ClockCycles(dut.clk_in, 1, rising=False)
    diff_so_far = sum((random_window[sample_in // WINDOW_SIZE][s1] - random_window[sample_in // WINDOW_SIZE][s2])**2 for s1 in range(sample_in % WINDOW_SIZE) for s2 in range(s1) if (s1 - s2) == (sample_in - sample_read))
    if valid:
        assert index(dut.multiplied.value, bram_port_idx_s, 2*WIDTH) == sub**2, "expected multiplication result"
        assert index(dut.diff.value, bram_port_idx_d, 2*WIDTH) == diff_so_far, "grabbed wrong diff bram"

    # RESULTS OF ADD
    await ClockCycles(dut.clk_in, 1, rising=False)
    if valid:
        assert index(dut.added.value, bram_port_idx_d, 2*WIDTH) == diff_so_far + sub**2, "expected addition result"
        assert index(dut.write_addr_d.value, bram_port_idx_d, D_ADDR_WIDTH) == read_addr_d, "wrong diff BRAM write address"
    assert index(dut.wen_d.value, bram_port_idx_d, 1) == valid, "wrong diff BRAM write enable"

async def test_cumdiff(dut, iteration, window_idx):
    if window_idx == 0:
        return

    window = random_window[window_idx-1]
    diff = [sum((window[s1] - window[s2])**2 for s1 in range(WINDOW_SIZE) for s2 in range(s1) if (s1-s2) == x) for x in range(WINDOW_SIZE)]
    prefix_sum = [sum(diff[:x+1]) for x in range(WINDOW_SIZE)]

    div = [diff[x] / prefix_sum[x] if prefix_sum[x] != 0 else 0 for x in range(WINDOW_SIZE)]
    div = [d if d <= 1000 else 0 for d in div]
    div = list(map(to_fp, div))

    mins = [(min(div[:x+1]), np.argmin(div[:x+1])) for x in range(WINDOW_SIZE)]

    # RESULTS OF READ
    await ClockCycles(dut.clk_in, 3, rising=False)
    for x in range(4):
        assert index(dut.cd_diff.value, x, 2*WIDTH) == diff[iteration*4+x], f"incorrect diff data out for index {x}"

    # RESULTS OF ADD
    print(prefix_sum[7])
    await ClockCycles(dut.clk_in, 1, rising=False)
    for x in range(4):
        assert index(dut.cd_add.value, x, 2*WIDTH) == prefix_sum[iteration*4+x], f"incorrect addition for index {x}"

    # RESULTS OF DIV
    await ClockCycles(dut.clk_in, 6, rising=False)
    for x in range(4):
        assert hex(index(dut.cd_div.value, x, FP_WIDTH)) == div[iteration*4+x], f"incorrect division for index {x}"

    # RESULTS OF CNP
    await ClockCycles(dut.clk_in, 1, rising=False)
    for x in range(4):
        assert hex(index(dut.next_cd_min.value, x, FP_WIDTH)) == mins[iteration*4+x][0], f"incorrect min for index {x}"
        assert index(dut.next_taumin.value, x, D_ADDR_WIDTH) == mins[iteration*4+x][1], f"incorrect argmin for index {x}"

@cocotb.test()
async def test_yin(dut):
    cocotb.start_soon(Clock(dut.clk_in, 10, units="ns").start())
    cocotb.start_soon(send_window(dut))


    dut.rst_in.value = 1
    await ClockCycles(dut.clk_in, 2)
    dut.rst_in.value = 0

    # sample_in = 31
    # sample_read = 25

    # assert (sample_in // WINDOW_SIZE == sample_read // WINDOW_SIZE), "samples not in same window"

    # for _ in range(sample_in+1):
    #     await RisingEdge(dut.valid_in)

    # await FallingEdge(dut.clk_in) # Receive the sample_in here

    # await FallingEdge(dut.clk_in)
    # assert dut.current_sample.value == random_window[sample_in // WINDOW_SIZE][sample_in % WINDOW_SIZE], "not loading current sample"
    # await ClockCycles(dut.clk_in, ((sample_read % WINDOW_SIZE) // 4)*2, rising=False)
    # await test_sample_pipeline(dut, sample_read, sample_in)

    window_idx = 2
    iteration = 2
    for _ in range(window_idx*WINDOW_SIZE + 1):
        await RisingEdge(dut.valid_in)
    await FallingEdge(dut.clk_in) # Receive the sample_in here

    await ClockCycles(dut.clk_in, iteration*11, rising=False)
    await test_cumdiff(dut, iteration, window_idx)


def main():
    """Simulate the counter using the Python runner."""
    sim = os.getenv("SIM", "icarus")
    proj_path = Path(__file__).resolve().parent.parent
    sys.path.append(str(proj_path / "sim" / "model"))
    sources = [
        proj_path / "hdl" / "yin.sv",
        proj_path / "hdl" / "xilinx_true_dual_port_read_first_1_clock_ram.v",
        proj_path / "hdl" / "fp_div.sv"
    ]
    build_test_args = ["-Wall"]
    parameters = {"WIDTH" : WIDTH, "TAUMAX" : TAUMAX, "WINDOW_SIZE" : WINDOW_SIZE }
    sys.path.append(str(proj_path / "sim"))
    runner = get_runner(sim)
    runner.build(
        sources=sources,
        hdl_toplevel="yin",
        always=True,
        build_args=build_test_args,
        parameters=parameters,
        timescale=("1ns", "1ps"),
        waves=True,
    )
    run_test_args = []
    runner.test(
        hdl_toplevel="yin",
        test_module="test_yin",
        test_args=run_test_args,
        waves=True,
    )


if __name__ == "__main__":
    main()
