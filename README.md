# Frequency Perfect Generated Audio (FPGA)

A real-time autotuning system for the human voice implemented on an FPGA. The system processes 16-bit, 44.1KHz audio and outputs autotuned audio with ~0.1s latency. By optimizing Yin autocorrelation for pitch detection and PSOLA for pitch correction, this project achieves efficient, high-quality real-time performance.

Autotuning traditionally requires computationally expensive signal processing. This project implements hardware-optimized Yin and PSOLA algorithms to achieve low-latency, high-quality pitch correction. Yin detects the fundamental frequency using a difference function and cumulative mean normalization, while PSOLA adjusts pitch by overlapping and interpolating signal segments. The design pipelines computations across audio windows and optimizes FPGA resource usage with sequential operations, shared BRAMs, and DSP blocks. These hardware choices enable efficient, modular processing with minimal latency.
