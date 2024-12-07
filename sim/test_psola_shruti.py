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
import wave
from array import array

WINDOW_SIZE = 2048
SAMPLING_RATE = 44100

with wave.open("/home/shrutsiv/Documents/MIT/Fall_2024/6.205/project/autotune/test_data/aladdin-new.wav") as f:
    signal = array('H', f.readframes(WINDOW_SIZE)).tolist()

with open("/home/shrutsiv/Documents/MIT/Fall_2024/6.205/project/autotune/test_data/aladdin-new-windows.txt", "r") as file:
    periods = [round(float(line.strip())) for line in file]

#signal = signal[: len(periods) * WINDOW_SIZE]


def get_closest_period(period):
    A4 = round(SAMPLING_RATE/440)
    semitone_ratio = 2 ** (1 / 12)
    closest_semitone = round(12 * np.log2(A4/period))
    return int(period * (semitone_ratio**closest_semitone) / A4)

def window_val(period, offset):
    return offset // period if offset <= period else 1 - (offset - period) // period

# Call 1 cycle after sending tau_in
async def receive_tau(dut, period):
    await ClockCycles(dut.clk_in, 1, rising=False)
    dut.tau_valid_in.value = 0
    assert dut.phase == 1, "dut not going into phase 1 after valid tau"

    # I'll trust that div works for now

    # Testing searched value
    await RisingEdge(dut.search_valid_out)
    await ClockCycles(dut.clk_in, 1, rising=False)
    closest_period_exp = get_closest_period(period)
    closest_period_act = dut.shifted_tau_in.value
    assert closest_period_exp == closest_period_act, f"Expected nearest period {closest_period_exp}, got {closest_period_act} for {period}"

    inv_tau_found = dut.inv_tau_in_found.value
    while not inv_tau_found:
        await ClockCycles(dut.clk_in, 1, rising=False)
        inv_tau_found = dut.inv_tau_in_found.value
    await ClockCycles(dut.clk_in, 1, rising=False)
    assert dut.phase == 2, "dut not going into phase 2 after div/search"

    processed = [0 for i in range(closest_period_exp)]

    i = 0
    j = 0
    # Wait for pipeline to load
    await ClockCycles(dut.clk_in, 2, rising=False)
    offset = 2
    while i < WINDOW_SIZE - period:
        # Addr logic
        upper_bound_offset = min(2*period, WINDOW_SIZE-i)
        while offset < upper_bound_offset:
            actual_offset = dut.offset.value
            assert offset == actual_offset, f"Expected offset {offset}, got {actual_offset}"
            offset += 1
            await ClockCycles(dut.clk_in, 1, rising=False)

            # Receiving data from bram
            offset_pipe = offset-2
            signal_act = dut.signal_val.value
            assert signal_act == signal[i+offset_pipe], f"Expected in-progress val {signal[i+offset_pipe]}, got {signal_act}"
            in_progress_act = dut.curr_processed_val.value
            assert in_progress_act == processed[j+offset_pipe], f"Expected in-progress val {processed[j+offset_pipe]}, got {in_progress_act}"

        await ClockCycles(dut.clk_in, 1, rising=False)
        actual_offset = dut.offset.value
        assert 0 == actual_offset, f"Expected offset 0, got {actual_offset}"

        # Mem logic + window func stuff TODO
        i += period
        j += closest_period_exp
        await ClockCycles(dut.clk_in, 2, rising=False)
        offset = 2

@cocotb.test()
async def test_psola(dut):
    cocotb.start_soon(Clock(dut.clk_in, 10, units="ns").start())


    dut.rst_in.value = 1
    await ClockCycles(dut.clk_in, 2)
    dut.rst_in.value = 0

    # Testing diff portion
    for tau_in in periods[:1]:
        await ClockCycles(dut.clk_in, 1, rising=False)
        dut.tau_valid_in.value = 1
        dut.tau_in.value = tau_in
        await receive_tau(dut, tau_in)

def main():
    """Simulate the counter using the Python runner."""
    sim = os.getenv("SIM", "icarus")
    proj_path = Path(__file__).resolve().parent.parent
    sys.path.append(str(proj_path / "sim" / "model"))
    sources = [
        proj_path / "hdl" / "psola.sv",
        proj_path / "hdl" / "searcher.sv",
        proj_path / "hdl" / "xilinx_single_port_ram_read_first.sv",
        proj_path / "hdl" / "xilinx_true_dual_port_read_first_1_clock_ram.v",
        proj_path / "hdl" / "fp_div.sv",
        proj_path / "hdl" / "pipeline.sv"
    ]
    build_test_args = ["-Wall"]
    parameters = {"WINDOW_SIZE" : WINDOW_SIZE}
    sys.path.append(str(proj_path / "sim"))
    runner = get_runner(sim)
    runner.build(
        sources=sources,
        hdl_toplevel="psola",
        always=True,
        build_args=build_test_args,
        parameters=parameters,
        timescale=("1ns", "1ps"),
        waves=True,
    )
    run_test_args = []
    runner.test(
        hdl_toplevel="psola",
        test_module="test_psola_shruti",
        test_args=run_test_args,
        waves=True,
    )


if __name__ == "__main__":
    main()
