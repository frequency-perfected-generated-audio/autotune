import os
import subprocess
import sys
from pathlib import Path

import cocotb
import numpy as np
from cocotb.clock import Clock
from cocotb.runner import get_runner
from cocotb.triggers import ClockCycles, FallingEdge, ReadOnly, RisingEdge
from scipy.io import wavfile

WINDOW_SIZE = 2048
SAMPLING_RATE = 44100
TOPLEVEL = (
    subprocess.run(["git", "rev-parse", "--show-toplevel"], capture_output=True)
    .stdout.decode("utf-8")
    .strip()
)

_, signal = wavfile.read(f"{TOPLEVEL}/test_data/aladdin-new.wav")
signal = signal.view(dtype=np.uint16) ^ 0x8000

with open(f"{TOPLEVEL}/test_data/aladdin-new-windows.txt", "r") as f:
    periods = [round(float(line.strip())) for line in f]

LARGEST_PERIOD = int("0x384", 16)
SMALLEST_PERIOD = int("0x17", 16)
def get_closest_period(period):
    with open(f"{TOPLEVEL}/test_data/semitones.mem", "r") as f:
        periods = np.array([int(l.strip(), 16) for l in f.readlines()])
    return periods[np.argmin(np.abs(periods - period))]

FP_WIDTH = 32
FRACTION_WIDTH = 11
def to_fp(value):
    accum = 0
    for x in range(FP_WIDTH-1, -1, -1):
        digit = int(value / (2**(x - FRACTION_WIDTH)))
        accum += 2**x * digit
        value -= 2**(x - FRACTION_WIDTH) * digit

    return int(hex(accum), 16)

def window_val(period, offset):
    return offset * to_fp(1/period) if offset <= period else to_fp(2) - offset * to_fp(1/period)

WAITING = 0
DIVIDING = 1
DOING_PSOLA = 2

READ1 = 0
READ2 = 1
VALUE_CALC1 = 2
VALUE_CALC2 = 3
WRITE = 4


# Call 1 cycle after sending tau_in
async def receive_tau(dut, period, signal):
    await ClockCycles(dut.clk_in, 1, rising=False)
    dut.tau_valid_in.value = 0
    assert dut.phase == DIVIDING, "dut not going into dividing phase after valid tau"

    # Trust fp div for now

    # Testing searched value
    await RisingEdge(dut.shifted_tau_valid)
    # takes us to falling edge of valid shift cycle, then one cycle beyond to see
    # the result of the register write
    await ClockCycles(dut.clk_in, 2, rising=False) 
    closest_period_exp = get_closest_period(period)
    closest_period_act = int(dut.shifted_tau.value)
    assert (
        closest_period_exp == closest_period_act
    ), f"Expected nearest period {closest_period_exp}, got {closest_period_act} for {period}"

    inv_tau_found = dut.tau_inv_done.value
    while not inv_tau_found:
        await ClockCycles(dut.clk_in, 1, rising=False)
        inv_tau_found = dut.tau_inv_done.value
    await ClockCycles(dut.clk_in, 1, rising=False)
    assert dut.phase == DOING_PSOLA, "dut not going into psola after div/search"

    processed = [0 for i in range(WINDOW_SIZE)]

    i = 0
    j = 0
    offset = 0
    while i < WINDOW_SIZE - period:
        # Addr logic
        actual_i = int(dut.i.value)
        assert actual_i == i, f"Expected i {i}, got {actual_i}"

        actual_j = int(dut.j.value)
        assert actual_j == j, f"Expected j {j}, got {actual_j}"

        upper_bound_offset = min(2 * period, WINDOW_SIZE - i)
        actual_ub = dut.max_offset.value
        assert actual_ub == upper_bound_offset, f"Expected offset upper bound {upper_bound_offset}, got {actual_ub}"

        while offset < upper_bound_offset:
            actual_offset = dut.offset.value
            assert (
                offset == actual_offset
            ), f"Expected offset {offset}, got {actual_offset}"

            actual_window = int(dut.window_coeff.value)
            exp_window = window_val(period, offset)
           #assert (
           #    actual_window == exp_window
           #), f"Expected window {exp_window}, got {actual_window}"
            # FELIX FELIX FELIX
            assert (
                abs(actual_window - exp_window) <= 1
            ), f"Expected window {exp_window}, got {actual_window}"
            assert dut.psola_phase.value == READ1, "not starting with READ1"

            await ClockCycles(dut.clk_in, 1, rising=False)
            assert dut.psola_phase.value == READ2, "not transitioning into READ2"

            await ClockCycles(dut.clk_in, 1, rising=False)
            assert dut.psola_phase.value == VALUE_CALC1, "not transitioning into VALUE_CALC1"

            # Reading values from bram
            actual_data_i = int(dut.data_i.value)
            actual_data_j = int(dut.data_j_out.value)
            assert actual_data_i == signal[i+offset], f"Expected signal value {signal[i]}, got {actual_data_i}"
            assert actual_data_j == processed[j+offset], f"Expected in-progress value {processed[j]}, got {actual_data_j}"

            await ClockCycles(dut.clk_in, 1, rising=False)
            assert dut.psola_phase.value == VALUE_CALC2, "not transitioning into VALUE_CALC2"

            # Reading values from bram
            actual_windowed = int(dut.data_i_windowed.value)
            exp_windowed = int(signal[i+offset]) * exp_window if (i + offset >= period) else int(signal[i+offset]) * to_fp(1)
            #if actual_window != exp_window:
            #    print(f"Expected windowed value {exp_windowed}, got {actual_windowed} with {exp_window=}, {actual_window=}")
            #else:
            assert actual_windowed == exp_windowed, f"Expected windowed value {exp_windowed}, got {actual_windowed}"

            await ClockCycles(dut.clk_in, 1, rising=False)
            assert dut.psola_phase.value == WRITE, "not transitioning into WRITE"
            processed[j+offset] += exp_windowed
            actual_sum = dut.data_j_in.value
            assert actual_sum == processed[j+offset], f"Expected write value {processed[j]}, got {actual_sum}"

            await ClockCycles(dut.clk_in, 1, rising=False)
            offset += 1

        i += period
        j += closest_period_exp
        offset = 0

        if i >= WINDOW_SIZE - period:
            assert dut.phase.value == WAITING, "not transitioning back to WAITING after offset cycle"
            break


async def feed_samples(dut, window_idx):
     for sample in signal[window_idx*WINDOW_SIZE:WINDOW_SIZE*(window_idx+1)]:
        await FallingEdge(dut.clk_in)
        dut.sample_in.value = int(sample)
        dut.sample_valid_in.value = 1
        await ClockCycles(dut.clk_in, 1, rising=False)
        dut.sample_valid_in.value = 0
        await ClockCycles(dut.clk_in, 4)


@cocotb.test()
async def test_psola(dut):
    cocotb.start_soon(Clock(dut.clk_in, 10, units="ns").start())

    dut.rst_in.value = 1
    await ClockCycles(dut.clk_in, 2)
    dut.rst_in.value = 0

    #await ClockCycles(dut.clk_in, 50000)

    # Testing diff portion
    for window_idx, tau_in in enumerate(periods[:3]):
        await feed_samples(dut, window_idx)
        await ClockCycles(dut.clk_in, 1, rising=False)
        dut.tau_valid_in.value = 1
        dut.tau_in.value = tau_in
        #await ClockCycles(dut.clk_in, 50000)
        await receive_tau(dut, tau_in, signal[window_idx*WINDOW_SIZE:WINDOW_SIZE*(window_idx+1)])


def main():
    """Simulate the counter using the Python runner."""
    sim = os.getenv("SIM", "icarus")
    proj_path = Path(__file__).resolve().parent.parent
    sys.path.append(str(proj_path / "sim" / "model"))
    sources = [
        proj_path / "hdl" / "psola_rewrite.sv",
        proj_path / "hdl" / "searcher.sv",
        proj_path / "hdl" / "xilinx_single_port_ram_read_first.sv",
        proj_path / "hdl" / "xilinx_true_dual_port_read_first_1_clock_ram.v",
        proj_path / "hdl" / "fp_div.sv",
        proj_path / "hdl" / "pipeline.sv",
    ]
    build_test_args = ["-Wall"]
    parameters = {"WINDOW_SIZE": WINDOW_SIZE}
    sys.path.append(str(proj_path / "sim"))
    runner = get_runner(sim)
    runner.build(
        sources=sources,
        hdl_toplevel="psola_rewrite",
        always=True,
        build_args=build_test_args,
        parameters=parameters,
        timescale=("1ns", "1ps"),
        waves=True,
    )
    run_test_args = []
    runner.test(
        hdl_toplevel="psola_rewrite",
        test_module="test_psola_shruti",
        test_args=run_test_args,
        waves=True,
    )


if __name__ == "__main__":
    main()
