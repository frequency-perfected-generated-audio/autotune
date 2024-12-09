import os
import sys
from pathlib import Path

import cocotb
import matplotlib.pyplot as plt
import numpy as np
from cocotb.clock import Clock
from cocotb.runner import get_runner
from cocotb.triggers import ClockCycles, FallingEdge, ReadOnly, RisingEdge
from scipy.io import wavfile

SAMPLE_RATE = 44100
WINDOW_SIZE = 2048
FRACTION_BITS = 14
SAMP_PLAY_DURATION = 10

out = []


async def logger(dut):
    count = 0
    while True:
        if dut.audio_valid_out.value == 1:
            x = dut.audio_out.value.integer / (2**FRACTION_BITS) - 32768
            # dut._log.info(f"{count=} {x=}")
            out.append(x)
            count += 1
        await ClockCycles(dut.clk_in, 1, rising=False)


@cocotb.test()
async def test_bufferizer(dut):
    def info(s):
        dut._log.info(s)

    info("Starting...")
    cocotb.start_soon(Clock(dut.clk_in, 10, units="ns").start())

    BASE_PATH = Path(__file__).resolve().parent.parent

    AUDIO_PATH = BASE_PATH / "test_data" / "slide.wav"
    tau_inS_PATH = BASE_PATH / "test_data" / "slide-windows.txt"

    # Load the audio file and tau_ins from YIN
    # input_wave, _ = librosa.load(AUDIO_PATH, sr=SAMPLE_RATE)
    _, input_wave = wavfile.read(AUDIO_PATH)
    input_wave = input_wave.view(dtype=np.uint16) ^ 0x8000

    with open(tau_inS_PATH, "r") as file:
        tau_ins = [int(SAMPLE_RATE / float(line.strip())) for line in file]

    tau_ins = [50] + tau_ins[:-1]

    input_wave = input_wave[: len(tau_ins) * WINDOW_SIZE]

    dut.rst_in.value = 1
    await ClockCycles(dut.clk_in, 5, rising=False)
    dut.rst_in.value = 0
    await ClockCycles(dut.clk_in, 5, rising=False)

    cocotb.start_soon(logger(dut))

    for i, samp in enumerate(input_wave[:20000]):
        await FallingEdge(dut.clk_in)
        dut.sample_in.value = int(samp)
        dut.sample_valid_in.value = 1
        if i > 2048 and i % 2048 == 20:
            dut._log.info(f"{tau_ins[i // 2048 - 1]=} {len(out)=}")
            dut.taumin_in.value = tau_ins[i // 2048 - 1]
            dut.taumin_valid_in.value = 1
        await ClockCycles(dut.clk_in, 1, rising=False)
        if i % 2048 == 20:
            dut.taumin_valid_in.value = 0
        dut.sample_valid_in.value = 0
        await ClockCycles(dut.clk_in, SAMP_PLAY_DURATION - 1)

    processed_signal = np.array(out)
    # # sf.write("cocotb_psola_bram_output.wav", processed_signal, SAMPLE_RATE)
    wavfile.write(
        "cocotb_psola_bram_output.wav", SAMPLE_RATE, processed_signal.astype(np.int16)
    )

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
    # plt.show()

    dut._log.info("Processed audio saved to cocotb_psola_bram_output.wav")


def main():
    """Simulate the counter using the Python runner."""
    sim = os.getenv("SIM", "icarus")
    proj_path = Path(__file__).resolve().parent.parent
    sys.path.append(str(proj_path / "sim" / "model"))
    sources = [proj_path / "hdl" / "bufferizer.sv"]
    sources += [
        proj_path / "hdl" / "bram_wrapper.sv",
        proj_path / "hdl" / "psola.sv",
        proj_path / "hdl" / "searcher.sv",
        proj_path / "hdl" / "xilinx_single_port_ram_read_first.sv",
        proj_path / "hdl" / "xilinx_true_dual_port_read_first_1_clock_ram.v",
        proj_path / "hdl" / "fp_div.sv",
        proj_path / "hdl" / "pipeline.sv",
        proj_path / "hdl" / "ring_buffer.sv",
    ]
    build_test_args = ["-Wall"]
    parameters = {"SAMP_PLAY_DURATION": SAMP_PLAY_DURATION}
    sys.path.append(str(proj_path / "sim"))
    runner = get_runner(sim)
    runner.build(
        sources=sources,
        hdl_toplevel="bufferizer",
        always=True,
        build_args=build_test_args,
        parameters=parameters,
        timescale=("1ns", "1ps"),
        waves=True,
    )
    run_test_args = []
    runner.test(
        hdl_toplevel="bufferizer",
        test_module="test_bufferizer",
        test_args=run_test_args,
        waves=True,
    )


if __name__ == "__main__":
    main()
