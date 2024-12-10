from scipy.io import wavfile
import numpy as np
import os
import sys
from pathlib import Path

import cocotb
from cocotb.clock import Clock
from cocotb.runner import get_runner
from cocotb.triggers import ClockCycles, FallingEdge, ReadOnly, RisingEdge
from cocotb.binary import BinaryValue

DATA_WIDTH = 16

FP_WIDTH = 50
FRACTION_WIDTH = 16
def to_fp(value):
    accum = 0
    for x in range(FP_WIDTH-1, -1, -1):
        digit = int(value / (2**(x - FRACTION_WIDTH)))
        accum += 2**x * digit
        value -= 2**(x - FRACTION_WIDTH) * digit

    return int(hex(accum), 16)

def from_fp(value):
    accum = 0
    for x in range(FRACTION_WIDTH):
        accum += 2**(-1*(FRACTION_WIDTH-x)) * ((value >> x) & 0x1)

    for x in range(FP_WIDTH-FRACTION_WIDTH):
        accum += 2**x * ((value >> (x+FRACTION_WIDTH)) & 0x1)

    return accum

def fp_appx(value):
    was_neg = value < 0
    value = to_fp(value)
    if value < 0:
        value =  ~value+1
    value = from_fp(value)
    return -value if was_neg else value


AUDIO_PATH = "/home/shrutsiv/Documents/MIT/Fall_2024/6.205/project/autotune/sim/output-2304.wav"
COEFFS_PATH = "/home/shrutsiv/Documents/MIT/Fall_2024/6.205/project/autotune/sim/filtered_coeffs.txt"
with open(COEFFS_PATH, "r") as f:
    raw_coeffs = [float(f.strip()) for f in f.readlines()]
    b = [fp_appx(bval) for bval in raw_coeffs[:3]]
    a = [fp_appx(aval) for aval in raw_coeffs[3:6]]

    b_fp = [to_fp(bval) for bval in raw_coeffs[:3]]
    a_fp = [to_fp(aval) for aval in raw_coeffs[3:6]]
    print(b_fp, a_fp)

SAMPLING_FREQ = 44100 

_, input_wave = wavfile.read(AUDIO_PATH)
input_wave = input_wave.view(dtype=np.uint16) ^ 0x8000

def bpf(y, a_coeffs, b_coeffs, fp=True):
    new_y = [0 for _ in range(len(y))]
    for index, y_val in enumerate(y):
        y_0 = int(y[index])
        y_1 = int(y[index-1])
        y_2 = int(y[index-2])

        if index == 0:
            new_y[index] = (b_coeffs[0] * y_0) # 34 and 6
        elif index == 1:
            if fp:
                new_y[index] = b_coeffs[0] * y_0 + b_coeffs[1] * y_1 - ((a_coeffs[1] * new_y[index-1]) >> FRACTION_WIDTH)
            else:
                new_y[index] = b_coeffs[0] * y_0 + b_coeffs[1] * y_1 - a_coeffs[1] * new_y[index-1]
        else:
            if fp:
                new_y[index] = b_coeffs[0] * y_0 + b_coeffs[1] * y_1 - ((a_coeffs[1] * new_y[index-1]) >> FRACTION_WIDTH) + b_coeffs[2] * y_2 - ((a_coeffs[2] * new_y[index-2]) >> FRACTION_WIDTH)
            else:
                new_y[index] = b_coeffs[0] * y_0 + b_coeffs[1] * y_1 - a_coeffs[1] * new_y[index-1] + b_coeffs[2] * y_2 - a_coeffs[2] * new_y[index-2]
    return new_y


#new_y_fp = bpf(input_wave, a_fp, b_fp)
#new_y = bpf(input_wave, a, b, fp=False)
#output_wave = [o >> FRACTION_WIDTH for o in new_y_fp]
#output_wave = np.array(output_wave)
#wavfile.write("calculated_filter.wav", SAMPLING_FREQ, output_wave.astype(np.int16))
#sys.exit(0)

TIME_BW_SAMPLES = 9

in_samples = []
out_samples = []
def next_step(in_progress_val, index, coeff):
    global in_samples, out_samples
    if coeff == 0:
        return b_fp[0] * int(in_samples[index])
    elif index < coeff:
        return in_progress_val
    else:
        return in_progress_val + (b_fp[coeff] * int(in_samples[index-coeff])) - ((a_fp[coeff] * out_samples[index-coeff]) >> FRACTION_WIDTH)

@cocotb.test()
async def test_filter(dut):
    global in_samples, out_samples
    print("Starting...")
    cocotb.start_soon(Clock(dut.clk_in, 10, units="ns").start())

    dut.rst_in = 1
    await ClockCycles(dut.clk_in, 2)
    dut.rst_in = 0
    await ClockCycles(dut.clk_in, 1)

    in_samples = input_wave
    for index, sample in enumerate(in_samples):
        await ClockCycles(dut.clk_in, 1, rising=False)
        dut.sample_in.value = int(sample)
        dut.sample_valid_in.value = 1
        await ClockCycles(dut.clk_in, 1, rising=False)
        dut.sample_valid_in.value = 0

        in_progress = next_step(0, index, 0)
        #assert dut.sample_out.value.signed_integer  == int(in_progress), "wrong stage 0 value"

        await ClockCycles(dut.clk_in, 1, rising=False)
        in_progress = next_step(in_progress, index, 1)
        #assert dut.sample_out.value.signed_integer == int(in_progress), "wrong stage 1 value"

        await ClockCycles(dut.clk_in, 1, rising=False)
        in_progress = next_step(in_progress, index, 2)
        #assert dut.sample_out.value.signed_integer == int(in_progress), "wrong stage 2 value"
        assert dut.sample_valid_out.value == 1, "not going valid"

        out_samples.append(in_progress)

    out_samples = [y >> 20 for y in out_samples]
    output_wave = np.array(out_samples)
    wavfile.write("calculated_filter.wav", SAMPLING_FREQ, output_wave.astype(np.int16))

def main():
    """Simulate the counter using the Python runner."""
    sim = os.getenv("SIM", "icarus")
    proj_path = Path(__file__).resolve().parent.parent
    sys.path.append(str(proj_path / "sim" / "model"))
    sources = [
        proj_path / "hdl" / "filter.sv"
    ]
    build_test_args = ["-Wall"]
    parameters = {"DATA_WIDTH" : DATA_WIDTH }
    sys.path.append(str(proj_path / "sim"))
    runner = get_runner(sim)
    runner.build(
        sources=sources,
        hdl_toplevel="filter",
        always=True,
        build_args=build_test_args,
        parameters=parameters,
        timescale=("1ns", "1ps"),
        waves=True,
    )
    run_test_args = []
    runner.test(
        hdl_toplevel="filter",
        test_module="test_filter",
        test_args=run_test_args,
        waves=True,
    )

if __name__ == "__main__":
    main()
