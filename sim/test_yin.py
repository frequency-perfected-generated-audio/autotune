import os
import sys
from pathlib import Path

import cocotb
from cocotb.clock import Clock
from cocotb.runner import get_runner
from cocotb.triggers import ClockCycles, FallingEdge, ReadOnly, RisingEdge

import random
from fxpmath import Fxp

WIDTH = 16
WINDOW_SIZE = 2048
TAUMAX = 2048

CYCLES = 2267

S_ADDR_WIDTH = 10
D_ADDR_WIDTH = 10

random_window = [random.randrange(0, 2**8-1) for _ in range(WINDOW_SIZE)]
async def send_window(dut):
    await ClockCycles(dut.clk_in, 2)
    for sample in random_window:
        dut.sample_in.value = sample
        dut.valid_in.value = 1

        await RisingEdge(dut.clk_in)
        dut.sample_in.value = 0xDEAD
        dut.valid_in.value = 0

        await ClockCycles(dut.clk_in, CYCLES - 1)

def index(value, index, width):
    return (value >> (index*width)) & ((1<<width)-1);

async def test_sample_pipeline(dut, sample_read, sample_in):
    bram_port_idx_s = sample_read % 4

    bram_port_idx_d = abs(sample_in - sample_read) % 4
    read_addr_d = (abs(sample_in - sample_read) // 4) * 2 + (bram_port_idx_d % 2)

    valid = sample_read <= sample_in

    # SHOULD SEE RESULTS OF STAGE 1 HERE
    await ClockCycles(dut.clk_in, 2, rising=False)

    if valid:
        assert index(dut.sample_out.value, bram_port_idx_s, WIDTH) == random_window[sample_read], "expected bram output"
        assert index(dut.read_addr_d.value, bram_port_idx_d, D_ADDR_WIDTH) == read_addr_d, "wrong diff BRAM read address"

    # RESULTS OF SUBTRACT
    sub = abs(random_window[sample_read] - random_window[sample_in])
    await ClockCycles(dut.clk_in, 1, rising=False)
    if valid:
        assert index(dut.subtracted.value, bram_port_idx_s, WIDTH) == sub, "expected subtraction result"

    # RESULTS OF MUL
    await ClockCycles(dut.clk_in, 1, rising=False)
    if valid:
        assert index(dut.multiplied.value, bram_port_idx_s, 2*WIDTH) == sub**2, "expected multiplication result"

    diff_so_far = sum((random_window[s1] - random_window[s2])**2 for s1 in range(sample_in) for s2 in range(s1) if (s1 - s2) == (sample_in - sample_read))
    print([(s1, s2) for s1 in range(sample_in) for s2 in range(s1) if (s1 - s2) == (sample_in - sample_read)])

    # RESULTS OF ADD
    await ClockCycles(dut.clk_in, 1, rising=False)
    print(bram_port_idx_d)
    print(diff_so_far)
    print(sub**2)
    print(index(dut.added.value, bram_port_idx_d, 2*WIDTH))
    if valid:
        assert index(dut.added.value, bram_port_idx_d, 2*WIDTH) == diff_so_far + sub**2, "expected addition result"
        assert index(dut.write_addr_d.value, bram_port_idx_d, D_ADDR_WIDTH) == read_addr_d, "wrong diff BRAM write address"
    assert index(dut.wen_d.value, bram_port_idx_d, 1) == valid, "wrong diff BRAM write enable"


@cocotb.test()
async def test_yin(dut):
    cocotb.start_soon(Clock(dut.clk_in, 10, units="ns").start())
    cocotb.start_soon(send_window(dut))


    dut.rst_in.value = 1
    await ClockCycles(dut.clk_in, 2)
    dut.rst_in.value = 0

    sample_in = 3
    sample_read = 2

    for _ in range(sample_in+1):
        await RisingEdge(dut.valid_in)

    await FallingEdge(dut.clk_in) # Receive the sample_in here

    await FallingEdge(dut.clk_in)
    assert dut.current_sample.value == random_window[sample_in], "not loading current sample"
    await ClockCycles(dut.clk_in, (sample_read // 4)*2, rising=False)
    await test_sample_pipeline(dut, sample_read, sample_in)


def main():
    """Simulate the counter using the Python runner."""
    sim = os.getenv("SIM", "icarus")
    proj_path = Path(__file__).resolve().parent.parent
    sys.path.append(str(proj_path / "sim" / "model"))
    sources = [
        proj_path / "hdl" / "yin.sv",
        proj_path / "hdl" / "xilinx_true_dual_port_read_first_1_clock_ram.v"
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
