import numpy as np
import wave
import librosa
import soundfile as sf
from pathlib import Path

import os
import sys

import cocotb
from cocotb.clock import Clock
from cocotb.runner import get_runner
from cocotb.triggers import ClockCycles, FallingEdge, ReadOnly, RisingEdge

WINDOW_SIZE = 2048  # Change if your module uses a different size
SAMPLE_RATE = 44100


# Helper Functions
async def reset(dut, cycles=2):
    """Reset the DUT."""
    dut.rst_in.value = 1
    await ClockCycles(dut.clk_in, cycles)
    dut.rst_in.value = 0


async def process_window(dut, window, period):
    """Process a single window of audio through the PSOLA module."""
    await FallingEdge(dut.clk_in)
    for i in range(WINDOW_SIZE):
        dut.signal[i].value = window[i]
    dut.period.value = period
    dut.new_signal.value = 1
    await FallingEdge(dut.clk_in)
    dut.new_signal.value = 0

    # Wait for the done signal
    while not dut.done.value:
        await RisingEdge(dut.clk_in)

    # Collect output
    output_window_len = dut.output_window_len.value.integer
    output = [int(dut.out[i].value) / (2**20) for i in range(output_window_len)]
    return output


@cocotb.test()
async def test_psola(dut):
    """Test the PSOLA module."""
    # Start the clock
    cocotb.start_soon(Clock(dut.clk_in, 10, units="ns").start())
    # Reset the DUT
    await reset(dut)

    BASE_PATH = Path(__file__).resolve().parent.parent
    print("BASE PATH", BASE_PATH)

    AUDIO_PATH = BASE_PATH / "test_data" / "aladdin-new.wav"
    PERIODS_PATH = BASE_PATH / "test_data" / "aladdin-new-windows.txt"

    # Load the audio file and periods from YIN
    input_wave, _ = librosa.load(AUDIO_PATH, sr=SAMPLE_RATE)
    with open(PERIODS_PATH, "r") as file:
        periods = [int(SAMPLE_RATE / float(line.strip())) for line in file]
    input_wave = input_wave[: len(periods) * WINDOW_SIZE]

    # Split audio into windows
    windows = np.array_split(input_wave, len(periods))

    # Process each window
    processed_audio = []
    for window, period in zip(windows, periods):
        # Zero-pad if the window is smaller than WINDOW_SIZE

        print(window)
        fp_window = [int(x * (2**20)) for x in window]

        print([hex(val) for val in fp_window])
        print(period)

        output_window = await process_window(dut, fp_window, period)
        processed_audio.extend(output_window)

    # Save the processed audio
    processed_audio = np.array(processed_audio, dtype=np.int16)
    sf.write("cocotb_psola_output.wav", processed_audio, SAMPLE_RATE)

    dut._log.info("Processed audio saved to cocotb_psola_output.wav")


def main():
    """Simulate the counter using the Python runner."""
    sim = os.getenv("SIM", "icarus")
    proj_path = Path(__file__).resolve().parent.parent
    sys.path.append(str(proj_path / "sim" / "model"))
    sources = [proj_path / "hdl" / "psola.sv"]
    sources += [
        proj_path / "hdl" / "searcher.sv",
        proj_path / "hdl" / "xilinx_single_port_ram_read_first.sv",
        proj_path / "hdl" / "fp_div.sv",
    ]
    build_test_args = ["-Wall"]
    parameters = {"WINDOW_SIZE": WINDOW_SIZE}
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
        test_module="test_psola_no_bram",
        test_args=run_test_args,
        waves=True,
    )


if __name__ == "__main__":
    main()
