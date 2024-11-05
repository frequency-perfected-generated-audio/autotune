import os
import sys
from pathlib import Path

import cocotb
from cocotb.clock import Clock
from cocotb.runner import get_runner
from cocotb.triggers import ClockCycles, FallingEdge, ReadOnly, RisingEdge

import random
from fxpmath import Fxp

async def reset(dut, cycles):
    dut.rst_in.value = 1
    await ClockCycles(dut.clk_in, cycles)
    dut.rst_in.value = 0

WIDTH = 32
FRACTION_WIDTH = 10
NUM_STAGES = 7

DIVISOR_WIDTH = 2*WIDTH + FRACTION_WIDTH
DIVIDEND_WIDTH = WIDTH + FRACTION_WIDTH

BITS_PER_STAGE = ((DIVIDEND_WIDTH-1) // NUM_STAGES) + 1
STAGE_OVERFLOW = DIVIDEND_WIDTH - (NUM_STAGES-1) * BITS_PER_STAGE;

NUM_TESTS=10

tests = []
x = 0
while x < NUM_TESTS:
    dividend = random.randrange(0, 2**(WIDTH)-1)
    divisor = random.randrange(1, 2**(WIDTH)-1)
    quotient = dividend / divisor
    
    if quotient < (2**(WIDTH-FRACTION_WIDTH)):
        tests.append((dividend, divisor, quotient))
        x += 1

def from_fp(value):
    accum = 0
    for x in range(FRACTION_WIDTH):
        accum += 2**(-1*(FRACTION_WIDTH-x)) * ((value >> x) & 0x1)

    for x in range(WIDTH-FRACTION_WIDTH):
        accum += 2**x * ((value >> (x+FRACTION_WIDTH)) & 0x1)

    return accum

def to_fp(value):
    accum = 0
    for x in range(WIDTH-1, -1, -1):
        digit = int(value / (2**(x - FRACTION_WIDTH)))
        accum += 2**x * digit
        value -= 2**(x - FRACTION_WIDTH) * digit

    return hex(accum)

@cocotb.test()
async def test_fp_div(dut):
    print("Starting...")
    cocotb.start_soon(Clock(dut.clk_in, 10, units="ns").start())

    await reset(dut, 2)

    for dividend, divisor, quotient in tests:
        await FallingEdge(dut.clk_in)
        dut.valid_in.value = 1
        dut.dividend_in.value = dividend
        dut.divisor_in.value = divisor

        await FallingEdge(dut.clk_in)
        dut.valid_in.value = 0
        assert dut.busy.value == 1, "not busy after valid input"

        await ClockCycles(dut.clk_in, NUM_STAGES - 2, rising=False)
        assert dut.valid_out.value == 1, "not valid after N cycles"

        expected = to_fp(quotient)
        got = hex(dut.quotient_out.value)

        assert got == expected, f"expected {expected}, got {got}"

def main():
    """Simulate the counter using the Python runner."""
    sim = os.getenv("SIM", "icarus")
    proj_path = Path(__file__).resolve().parent.parent
    sys.path.append(str(proj_path / "sim" / "model"))
    sources = [
        proj_path / "hdl" / "fp_div.sv"
    ]
    build_test_args = ["-Wall"]
    parameters = {"WIDTH" : WIDTH, "FRACTION_WIDTH" : FRACTION_WIDTH, "NUM_STAGES" : NUM_STAGES }
    sys.path.append(str(proj_path / "sim"))
    runner = get_runner(sim)
    runner.build(
        sources=sources,
        hdl_toplevel="fp_div",
        always=True,
        build_args=build_test_args,
        parameters=parameters,
        timescale=("1ns", "1ps"),
        waves=True,
    )
    run_test_args = []
    runner.test(
        hdl_toplevel="fp_div",
        test_module="test_fp_div",
        test_args=run_test_args,
        waves=True,
    )


if __name__ == "__main__":
    main()
