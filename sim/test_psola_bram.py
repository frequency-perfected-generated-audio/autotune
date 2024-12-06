import os
import sys
import wave
from pathlib import Path

import cocotb
import librosa
import numpy as np
import soundfile as sf
from cocotb.clock import Clock
from cocotb.runner import get_runner
from cocotb.triggers import ClockCycles, FallingEdge, ReadOnly, RisingEdge
from matplotlib import pyplot as plt

WINDOW_SIZE = 2048  # Change if your module uses a different size
SAMPLE_RATE = 44100


# Helper Functions
async def reset(dut, cycles=2):
    """Reset the DUT."""
    dut.rst_in.value = 1
    await ClockCycles(dut.clk_in, cycles)
    dut.rst_in.value = 0
    await ClockCycles(dut.clk_in, cycles)


async def process_window(dut, next_window, tau_in):
    """Process a single window of audio through the PSOLA module."""
    await FallingEdge(dut.clk_in)
    dut.tau_in.value = 50  # tau_in
    dut.tau_valid_in.value = 1
    await FallingEdge(dut.clk_in)
    dut.tau_valid_in.value = 0
    await ClockCycles(dut.clk_in, 2)

    out = []
    cycle = 0
    while dut.read_done.value.integer == 0 or dut.output_done.value.integer == 0:
        # Streaming in next window
        if cycle % 3 == 0 and cycle < 3 * WINDOW_SIZE:
            dut.sample_in.value = next_window[cycle // 3]
            dut.addr_in.value = cycle // 3
            dut.sample_valid_in.value = 1
        else:
            dut.sample_valid_in.value = 0

        if dut.valid_out_piped.value.integer == 1:
            out.append(dut.out_val.value.signed_integer / (2**20))

        await ClockCycles(dut.clk_in, 1)
        cycle += 1

    # Collect output
    dut._log.info(f"PSOLA produced window of length {len(out)}")
    # window_len_out = dut.window_len_out.value.integer
    # dut._log.info(f"PSOLA produced window of length {window_len_out}")

    return out


@cocotb.test()
async def test_psola(dut):
    """Test the PSOLA module."""
    # Start the clock
    cocotb.start_soon(Clock(dut.clk_in, 10, units="ns").start())
    # Reset the DUT
    await reset(dut, cycles=5)

    BASE_PATH = Path(__file__).resolve().parent.parent

    # AUDIO_PATH = BASE_PATH / "test_data" / "aladdin-new.wav"
    # tau_inS_PATH = BASE_PATH / "test_data" / "aladdin-new-windows.txt"

    AUDIO_PATH = BASE_PATH / "test_data" / "slide.wav"
    tau_inS_PATH = BASE_PATH / "test_data" / "slide-windows.txt"

    # Load the audio file and tau_ins from YIN
    input_wave, _ = librosa.load(AUDIO_PATH, sr=SAMPLE_RATE)
    with open(tau_inS_PATH, "r") as file:
        tau_ins = [int(SAMPLE_RATE / float(line.strip())) for line in file]

    tau_ins = [50] + tau_ins[:-1]

    input_wave = input_wave[: len(tau_ins) * WINDOW_SIZE]

    # Split audio into windows
    windows = np.array_split(input_wave, len(tau_ins))

    # Process each window
    processed_signal = []
    for window, tau_in in zip(windows, tau_ins):
        # Zero-pad if the window is smaller than WINDOW_SIZE

        fp_window = [int(x * (2**10)) for x in window]

        output_window = await process_window(dut, fp_window, tau_in)
        processed_signal.extend(output_window)

    # Save the processed audio
    processed_signal = np.array(processed_signal, dtype=np.int32)
    sf.write("cocotb_psola_bram_output.wav", processed_signal, SAMPLE_RATE)

    # Plot the original signal
    plt.figure(figsize=(14, 7))
    plt.subplot(2, 1, 1)
    plt.plot(input_wave, label="Original Signal")
    plt.title("Original Signal")
    plt.xlabel("Sample")
    plt.ylabel("Amplitude")
    plt.legend()

    # Plot the processed signal
    plt.subplot(2, 1, 2)
    plt.plot(processed_signal, label="Processed Signal", color="orange")
    plt.title("Processed Signal")
    plt.xlabel("Sample")
    plt.ylabel("Amplitude")
    plt.legend()

    plt.tight_layout()

    plt.savefig("waveform_plots_psola_bram.png")
    plt.show()

    dut._log.info("Processed audio saved to cocotb_psola_bram_output.wav")


def main():
    """Simulate the counter using the Python runner."""
    sim = os.getenv("SIM", "icarus")
    proj_path = Path(__file__).resolve().parent.parent
    sys.path.append(str(proj_path / "sim" / "model"))
    sources = [proj_path / "hdl" / "bram_wrapper.sv"]
    sources += [
        proj_path / "hdl" / "psola.sv",
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
        hdl_toplevel="bram_wrapper",
        always=True,
        build_args=build_test_args,
        parameters=parameters,
        timescale=("1ns", "1ps"),
        waves=True,
    )
    run_test_args = []
    runner.test(
        hdl_toplevel="bram_wrapper",
        test_module="test_psola_bram",
        test_args=run_test_args,
        waves=True,
    )


if __name__ == "__main__":
    main()
