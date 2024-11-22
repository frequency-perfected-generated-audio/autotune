import os
import sys
from pathlib import Path

import cocotb
from cocotb.clock import Clock
from cocotb.runner import get_runner
from cocotb.triggers import ClockCycles, FallingEdge, ReadOnly, RisingEdge

import random
import numpy as np
import math

WIDTH = 16
WINDOW_SIZE = 512
TAUMAX = WINDOW_SIZE
DIFFS_PER_BRAM = WINDOW_SIZE / 4

CYCLES = WINDOW_SIZE

S_ADDR_WIDTH = int(math.log2(TAUMAX/2))
D_ADDR_WIDTH = int(math.log2(TAUMAX/2))

TAU_WIDTH = int(math.log2(TAUMAX))

FRACTION_WIDTH = 10
FP_WIDTH = WIDTH*2+FRACTION_WIDTH

NUM_WINDOWS = 4

random_window = [[random.randrange(0, 2**8-1) for _ in range(WINDOW_SIZE)] for _ in range(NUM_WINDOWS)]
async def send_window(dut):
    while True:
        await ClockCycles(dut.clk_in, 5)
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

    return int(hex(accum), 16)

async def test_sample_pipeline(dut, sample_read, sample_in):
    bram_port_idx_s = (sample_read % WINDOW_SIZE) % 4

    bram_port_idx_d = (sample_in - sample_read) % 4
    read_addr_d = (abs(sample_in - sample_read) // 4) * 2 + (bram_port_idx_d % 2)

    valid = sample_read <= sample_in

    # SHOULD SEE RESULTS OF STAGE 1 HERE
    if valid:
        sample_out = index(dut.sample_out.value, bram_port_idx_s, WIDTH)
        expected_sample_out = random_window[sample_read // WINDOW_SIZE][sample_read % WINDOW_SIZE]
        assert expected_sample_out == sample_out, f"expected {hex(expected_sample_out)}, got {hex(sample_out)} for port {bram_port_idx_s}"
        diff_addr = index(dut.read_addr_d.value, bram_port_idx_d, D_ADDR_WIDTH)
        assert diff_addr == read_addr_d, f"expected {hex(read_addr_d)}, got {hex(diff_addr)} for port {bram_port_idx_d}"

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

    # Cycle align
    await ClockCycles(dut.clk_in, 1, rising=False)

async def test_cumdiff(dut, iteration, window_idx):
    if window_idx == 0:
        return

    window = random_window[window_idx-1]
    diff = [sum((window[s1] - window[s2])**2 for s1 in range(WINDOW_SIZE) for s2 in range(s1) if (s1-s2) == x) for x in range(WINDOW_SIZE)]
    prefix_sum = [sum(diff[:x+1]) for x in range(WINDOW_SIZE)]

    div = [diff[x] / prefix_sum[x] if prefix_sum[x] != 0 else (1<<FP_WIDTH)-1 for x in range(WINDOW_SIZE)]
    div = list(map(to_fp, div))

    mins = [(min(div[:x+1]), np.argmin(div[:x+1])) for x in range(WINDOW_SIZE)]
    early_out = [False] + [min < 0b0001100110 for min, _ in mins[:-1]]

    final_mins = []
    min_reached = [False]
    for i in range(WINDOW_SIZE):
        if i > 0:
            min_reached.append((early_out[i] and div[i] >= mins[i-1][0]) or min_reached[-1])
        if not min_reached[-1]:
            final_mins.append(mins[i])
        else:
            final_mins.append(final_mins[-1])

    # RESULTS OF READ
    await ClockCycles(dut.clk_in, 3, rising=False)
    for x in range(4):
        assert index(dut.cd_diff.value, x, 2*WIDTH) == diff[iteration*4+x], f"incorrect diff data out for index {x}"

    # RESULTS OF ADD
    await ClockCycles(dut.clk_in, 1, rising=False)
    for x in range(4):
        assert index(dut.cd_add.value, x, 2*WIDTH) == prefix_sum[iteration*4+x], f"incorrect addition for index {x}"

    # RESULTS OF DIV
    await ClockCycles(dut.clk_in, 7, rising=False)
    for x in range(4):
        if iteration*4+x != 0:
            actual_div = index(dut.cd_div_out.value, x, FP_WIDTH)
            expected_div = div[iteration*4+x]
            assert expected_div == actual_div, f"expected {expected_div}, got {actual_div} for div index {x}"

    # RESULTS OF CMP
    for y in range(2):
        for x in range(2):
            actual_eo = index(dut.early_out.value, x, 1)
            expected_eo = early_out[iteration*4+y*2+x]
            assert actual_eo == expected_eo, f"expected {expected_eo}, got {actual_eo} for early_out index {y*2+x}"

            actual_mr = index(dut.next_min_reached.value, x, 1)
            expected_mr = min_reached[iteration*4+y*2+x]
            assert actual_mr == expected_mr, f"expected {expected_mr}, got {actual_mr} for min_reached index {y*2+x}"

            actual_min = index(dut.next_cd_min.value, x, FP_WIDTH)
            expected_min = final_mins[iteration*4+y*2+x][0]
            if iteration*4+y*2+x != 0:
                assert actual_min == expected_min, f"expected {hex(expected_min)}, got {hex(actual_min)} for min index {y*2+x}"

            actual_argmin = index(dut.next_taumin.value, x, TAU_WIDTH)
            expected_argmin = final_mins[iteration*4+y*2+x][1]
            assert actual_argmin == expected_argmin, f"expected {expected_argmin}, got {actual_argmin} for argmin index {y*2+x}"
        if y == 0:
            await ClockCycles(dut.clk_in, 1, rising=False)

@cocotb.test()
async def test_yin(dut):
    cocotb.start_soon(Clock(dut.clk_in, 10, units="ns").start())
    cocotb.start_soon(send_window(dut))


    dut.rst_in.value = 1
    await ClockCycles(dut.clk_in, 2)
    dut.rst_in.value = 0

    # Testing diff portion
    for sample_in in range(NUM_WINDOWS*WINDOW_SIZE):
        await RisingEdge(dut.valid_in)

        await FallingEdge(dut.clk_in) # Receive the sample_in here

        await ClockCycles(dut.clk_in, 3, rising=False)
        for iteration in range(0, WINDOW_SIZE, 4*2):
            await test_sample_pipeline(dut, (sample_in // WINDOW_SIZE)*WINDOW_SIZE + random.randrange(4) + iteration, sample_in)


    dut.rst_in.value = 1
    await ClockCycles(dut.clk_in, 2)
    dut.rst_in.value = 0

    # Testing cumdiff portion
    for window_idx in range(NUM_WINDOWS-1):
        await RisingEdge(dut.valid_in)
        await FallingEdge(dut.clk_in) # Receive the sample_in here

        for iteration in range(WINDOW_SIZE // 4):
            await test_cumdiff(dut, iteration, window_idx)

        if dut.window_toggle.value == 0:
            await RisingEdge(dut.window_toggle)
        else:
            await FallingEdge(dut.window_toggle)


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
    parameters = {"WIDTH" : WIDTH, "TAUMAX" : TAUMAX, "WINDOW_SIZE" : WINDOW_SIZE, "DIFFS_PER_BRAM" : DIFFS_PER_BRAM }
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
